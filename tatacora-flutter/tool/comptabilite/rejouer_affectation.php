<?php

declare(strict_types=1);

/*
| Rejoue une AFFECTATION DU RESULTAT par les VRAIS services du serveur
| (`AffectationResultatService`, `ClotureExerciceService`, `BilanService`,
| `BalanceGeneraleService`), pour que le test Flutter compare, champ a champ, ce
| que `AffectationResultatLocale` fait du MEME scenario (09/11/2026, demande du
| PO : « ajoute l'affectation du resultat », web ET poste).
|
| La base N'EST PAS un double : l'observer RG-11, les contraintes, les cles
| etrangeres et le verrou de sequence sont ceux du serveur. Le script travaille
| sur `tatacora_test` — ou sur la base d'essai nommee par la variable
| d'environnement TATACORA_BASE_ESSAI (un nom qui FINIT par `_test`, jamais une
| base de travail ; ex. `TATACORA_BASE_ESSAI=tatacora_affect_test`) —, seme le
| referentiel par le VRAI `ComptabiliteReferentielSeeder` et les roles, puis
| ANNULE tout (rollback). Si MySQL est injoignable, il echoue : il ne se contente
| pas de sauter.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15",
|     "forme_juridique": "sarl",            // facultatif : sans lui, l'entreprise individuelle (defaut)
|     "exercices": [ {"annee": 2030, "statut": "ouvert"} ],
|     "cles_messages": ["comptabilite.affectation_deja_passee", ...],
|     "evenements": [
|       {"t": "piece", "journal": "OD", "date": "2030-03-05", "valide": true, "ref": "reglement",
|        "libelle": "...", "lignes": [{"compte": "5711", "debit": "100.00", "centre": "Bar"}]},
|       {"t": "contrepasser_piece", "ref": "reglement"},   // annule une piece posee plus haut
|       {"t": "forme", "valeur": "entreprise_individuelle|sarl|sa"},   // le parametre `forme_juridique`
|       {"t": "horloge", "date": "2031-05-10"},   // le « jour » de la suite (contre-passation)
|       {"t": "geste", "action": "demarrer|reprendre|cloturer|rouvrir",
|        "annee": 2030, "motif": "...", "role": "comptable|administrateur"},
|       {"t": "affecter", "annee": 2030, "date": "2031-04-30", "role": "comptable",
|        "ventilation": {"reserve_legale": "7000.00", "report_a_nouveau": "63000.00"}},
|       {"t": "contrepasser_affectation", "annee": 2030, "motif": "...", "reference": "...", "role": "..."},
|       {"t": "etat_affectation", "annee": 2030},
|       {"t": "flux_affectations", "role": "comptable|administrateur"},   // ce que le serveur DESCEND
|       {"t": "bilan", "annee": 2031}, {"t": "balance", "annee": 2031},
|       {"t": "etat", "annee": 2031}, {"t": "instantane"} ] }
| Sortie (stdout, JSON) :
|   { "resultats": [ ... un resultat par evenement ... ],
|     "constantes": {...}, "rubriques": {...}, "messages": {...} }
|
| Usage : TATACORA_BASE_ESSAI=tatacora_test php tool/comptabilite/rejouer_affectation.php < scenario.json
*/

$baseAutorisee = (string) (getenv('TATACORA_BASE_ESSAI') ?: 'tatacora_test');

if (! str_ends_with($baseAutorisee, '_test')) {
    fwrite(STDERR, "Refus : la base d'essai doit finir par _test (« {$baseAutorisee} »).\n");
    exit(1);
}

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['evenements'], $scenario['aujourdhui'], $scenario['exercices'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

// La base est choisie AVANT l'amorcage : le fichier `.env` ne l'emporte pas sur
// une variable deja posee.
putenv('DB_DATABASE=' . $baseAutorisee);
$_ENV['DB_DATABASE'] = $baseAutorisee;
$_SERVER['DB_DATABASE'] = $baseAutorisee;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\AffectationResultatService;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Support\FormeJuridique;
use App\Domain\Comptabilite\Support\RubriquesSyscohada;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Domain\Comptabilite\Services\EtatClotureService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseAutorisee) {
    fwrite(STDERR, "Refus : la base active est « {$base} », pas « {$baseAutorisee} ».\n");
    exit(1);
}

Carbon::setTestNow($scenario['aujourdhui'] . ' 10:00:00');
Storage::fake('local');

$passer = $app->make(PasserEcritureService::class);
$service = $app->make(ClotureExerciceService::class);
$etat = $app->make(EtatClotureService::class);
$balances = $app->make(BalanceGeneraleService::class);
$affectations = $app->make(AffectationResultatService::class);
$bilans = $app->make(BilanService::class);
$ecritures = $app->make(EcritureComptableService::class);

$resultats = [];
$sortie = [];
$piecesPosees = [];

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    (new ComptabiliteReferentielSeeder())->run();

    $utilisateur = static function (string $role): User {
        return User::create([
            'login' => $role . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    };
    $comptable = $utilisateur('comptable');
    $autre = $utilisateur('administrateur');
    Auth::setUser($comptable);

    // La FORME JURIDIQUE de depart (facultative) : sans elle, l'entreprise individuelle, le
    // defaut du Gite. Les scenarios de societe la posent ici pour ne pas decaler leurs indices.
    if (isset($scenario['forme_juridique'])) {
        ParametreSysteme::query()->updateOrCreate(['cle' => FormeJuridique::CLE], ['valeur' => (string) $scenario['forme_juridique']]);
    }

    foreach ($scenario['exercices'] as $e) {
        $annee = (int) $e['annee'];
        $exercice = ExerciceComptable::firstOrCreate(
            ['annee' => $annee],
            ['date_debut' => "{$annee}-01-01", 'date_fin' => "{$annee}-12-31", 'statut' => 'ouvert'],
        );
        $exercice->forceFill(['statut' => $e['statut']])->save();
    }

    $centreId = static fn (?string $libelle): ?string => $libelle === null
        ? null
        : (string) CentreCout::where('libelle', $libelle)->firstOrFail()->id;

    $statuts = static fn (): array => ExerciceComptable::query()->orderBy('annee')->pluck('statut', 'annee')
        ->mapWithKeys(static fn (string $s, int|string $a): array => [(string) $a => $s])->all();

    $lignes = static function (string $exerciceId): array {
        $ecritures = EcritureComptable::query()
            ->where('exercice_id', $exerciceId)
            ->with(['journal', 'compte', 'centre'])
            ->get();

        return $ecritures->map(static fn (EcritureComptable $e): array => [
            'journal' => $e->journal->code,
            'numero_piece' => $e->numero_piece,
            'date' => $e->date_ecriture->format('Y-m-d'),
            'compte' => $e->compte->numero_compte,
            'centre' => $e->centre->libelle,
            'libelle' => $e->libelle,
            'debit' => (string) $e->debit,
            'credit' => (string) $e->credit,
            'statut' => $e->statut,
            'contrepasse' => $e->ecriture_contrepassee_id !== null,
        ])->all();
    };

    foreach ($scenario['evenements'] as $ev) {
        try {
            switch ($ev['t']) {
                case 'piece':
                    $ligneDemandees = [];
                    foreach ($ev['lignes'] as $l) {
                        $ligne = ['compte' => $l['compte']];
                        foreach (['debit', 'credit', 'libelle'] as $cle) {
                            if (array_key_exists($cle, $l)) {
                                $ligne[$cle] = $l[$cle];
                            }
                        }
                        if (($l['centre'] ?? null) !== null) {
                            $ligne['centre_id'] = $centreId($l['centre']);
                        }
                        $ligneDemandees[] = $ligne;
                    }
                    $donnees = [
                        'journal' => $ev['journal'],
                        'date' => $ev['date'],
                        'libelle' => $ev['libelle'],
                        'lignes' => $ligneDemandees,
                        'statuts_exercice_admis' => $ev['statuts_admis'] ?? ['ouvert'],
                    ];
                    $posee = ($ev['valide'] ?? true) ? $passer->passerEtValider($donnees) : $passer->passer($donnees);
                    if (isset($ev['ref'])) {
                        $piecesPosees[(string) $ev['ref']] = $posee;
                    }
                    $resultats[] = ['ok' => true];
                    break;

                case 'contrepasser_piece':
                    // Annule (contre-passe) une piece posee plus haut sous son `ref`.
                    $passer->contrepasserPiece($piecesPosees[(string) $ev['ref']], (string) ($ev['motif'] ?? 'Annulation'));
                    $resultats[] = ['ok' => true];
                    break;

                case 'forme':
                    // Le parametre `forme_juridique`, pose tel quel (la garde « affectation active »
                    // du changement de forme est celle du service d'enregistrement, testee cote PHP).
                    ParametreSysteme::query()->updateOrCreate(['cle' => FormeJuridique::CLE], ['valeur' => (string) $ev['valeur']]);
                    $resultats[] = ['ok' => true, 'forme' => FormeJuridique::courante()->value];
                    break;

                case 'horloge':
                    Carbon::setTestNow($ev['date'] . ' 10:00:00');
                    $resultats[] = ['ok' => true];
                    break;

                case 'valider_brouillons':
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $brouillons = EcritureComptable::query()
                        ->where('exercice_id', $exercice->id)->where('statut', 'brouillon')
                        ->get()->groupBy('numero_piece');
                    foreach ($brouillons as $piece) {
                        $ecritures->valider($piece);
                    }
                    $resultats[] = ['ok' => true];
                    break;

                case 'geste':
                    $auteur = ($ev['role'] ?? 'comptable') === 'comptable' ? $comptable : $autre;
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $apres = match ($ev['action']) {
                        'demarrer' => $service->demarrer($exercice, $auteur),
                        'reprendre' => $service->reprendreSaisie($exercice, $auteur),
                        'cloturer' => $service->cloturer($exercice, $auteur)->exercice,
                        'rouvrir' => $service->rouvrir($exercice, $auteur, (string) ($ev['motif'] ?? '')),
                    };
                    $cloture = $service->clotureActive($apres->id);
                    $resultats[] = [
                        'ok' => true,
                        'statut' => $apres->statut,
                        'cloture' => $cloture === null ? null : [
                            'piece_cloture' => $cloture->piece_cloture,
                            'piece_a_nouveaux' => $cloture->piece_a_nouveaux,
                            'resultat' => (string) $cloture->resultat,
                        ],
                        'statuts' => $statuts(),
                    ];
                    break;

                case 'etat':
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $e = $etat->genererPourExercice($exercice, ['validee', 'brouillon']);
                    $resultats[] = [
                        'ok' => true,
                        'blocages' => [...$e->blocagesStructurels, ...$e->blocagesDeDonnees],
                        'avertissements' => $e->avertissements,
                        'conditions_reunies' => $e->conditionsVerifiablesReunies,
                        'resultat_a_reporter' => $e->resultatAReporter,
                        'compte_destination' => $e->compteDeDestination,
                        'statut' => $e->statutExercice,
                    ];
                    break;

                case 'balance':
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $b = $balances->genererPourExercice($exercice->id, ['validee']);
                    $resultats[] = [
                        'ok' => true,
                        'a_nouveaux_provisoires_de' => $b->aNouveauxProvisoiresDe,
                        'equilibree' => $b->equilibree,
                        'lignes' => array_map(static fn ($l): array => [
                            'numero_compte' => $l->numeroCompte,
                            'libelle' => $l->libelle,
                            'classe' => $l->classe,
                            'debit' => $l->totalDebit,
                            'credit' => $l->totalCredit,
                        ], $b->lignes),
                    ];
                    break;

                case 'ouverture':
                    // Les soldes d'OUVERTURE (le report a nouveau), lus la ou ils sont.
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $o = $balances->soldesOuverture($exercice->id);
                    $soldes = $o['soldes'];
                    ksort($soldes, SORT_STRING);
                    $resultats[] = [
                        'ok' => true,
                        'soldes' => array_filter(
                            array_map(static fn (string $net): string => $net, $soldes),
                            static fn (string $net): bool => bccomp($net, '0', 2) !== 0,
                        ),
                        'provisoire' => $o['provisoire'],
                        'annee' => $o['annee'],
                        'connu' => $o['connu'],
                    ];
                    break;

                case 'affecter':
                    $auteur = ($ev['role'] ?? 'comptable') === 'comptable' ? $comptable : $autre;
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $a = $affectations->affecter($exercice, $ev['ventilation'], (string) $ev['date'], $auteur);
                    $resultats[] = [
                        'ok' => true,
                        'piece' => $a->piece_affectation,
                        'resultat' => (string) $a->resultat,
                        'reserve_legale' => (string) $a->reserve_legale,
                        'autres_reserves' => (string) $a->autres_reserves,
                        'dividendes' => (string) $a->dividendes,
                        'report_crediteur' => (string) $a->report_a_nouveau_crediteur,
                        'report_debiteur' => (string) $a->report_a_nouveau_debiteur,
                        'compte_exploitant' => (string) $a->compte_exploitant,
                        'forme' => $a->forme_juridique,
                    ];
                    break;

                case 'contrepasser_affectation':
                    $auteur = ($ev['role'] ?? 'comptable') === 'comptable' ? $comptable : $autre;
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $a = $affectations->contrepasser($exercice, $auteur, (string) ($ev['motif'] ?? ''), $ev['reference'] ?? null);
                    $resultats[] = [
                        'ok' => true,
                        'piece' => $a->piece_affectation,
                        'motif' => $a->motif_contrepassation,
                        'reference' => $a->reference_decision_contrepassation,
                        'date' => Carbon::now()->toDateString(),
                    ];
                    break;

                case 'flux_affectations':
                    // CE QUE LE SERVEUR DESCEND aux postes (09/11/2026, « une affectation passee au
                    // web DOIT apparaitre sur le poste ») : le VRAI `CatalogueDescendantService`,
                    // lu depuis le debut pour le compte indique, les elements de la table
                    // `affectations_resultat` seuls. L'horizon de 5 s du flux est franchi par
                    // l'horloge de l'essai, jamais par un contournement du service.
                    $lecteur = ($ev['role'] ?? 'comptable') === 'comptable' ? $comptable : $autre;
                    $avant = Carbon::now();
                    Carbon::setTestNow($avant->copy()->addSeconds(CatalogueDescendantService::HORIZON_SECONDES + 5));
                    $catalogue = $app->make(CatalogueDescendantService::class);
                    $curseur = null;
                    $elements = [];
                    do {
                        $page = $catalogue->page($lecteur, 'poste-essai-affectation', $curseur, 500);
                        foreach ($page['elements'] as $element) {
                            if ($element['table'] === 'affectations_resultat') {
                                $elements[] = $element;
                            }
                        }
                        $curseur = $page['curseur'];
                    } while (! $page['complet']);
                    Carbon::setTestNow($avant);
                    $resultats[] = [
                        'ok' => true,
                        'elements' => $elements,
                        'non_lisibles' => in_array('affectations_resultat', $page['non_lisibles'], true),
                    ];
                    break;

                case 'etat_affectation':
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $e = $affectations->etat($exercice, ($ev['role'] ?? 'comptable') === 'comptable' ? $comptable : $autre);
                    $resultats[] = $e === null ? ['ok' => true, 'carte' => false] : [
                        'ok' => true,
                        'carte' => true,
                        'annee' => $e['annee'],
                        'annee_affectation' => $e['anneeAffectation'],
                        'resultat' => $e['resultat'],
                        'est_benefice' => $e['estBenefice'],
                        'compte_resultat' => $e['compteResultat'],
                        'affectable' => $e['affectable'],
                        'active_piece' => $e['active']?->piece_affectation,
                        'date_par_defaut' => $e['dateParDefaut'],
                        'proposition' => $e['proposition'],
                        'reserve_legale_proposee' => $e['reserveLegalePropose'],
                        'plafond_atteint' => $e['plafondReserveLegaleAtteint'],
                        'peut_affecter' => $e['peutAffecter'],
                        'forme' => $e['forme'],
                        'est_societe' => $e['estSociete'],
                        'postes' => $e['postes'],
                        'poste_du_reste' => $e['posteDuReste'],
                        'alertes' => $e['alertes'],
                        'avertissements' => $e['avertissements'],
                    ];
                    break;

                case 'bilan':
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $b = $bilans->genererPourExercice($exercice->id, ['validee']);
                    $resultats[] = [
                        'ok' => true,
                        'equilibre' => $b->equilibre,
                        'ecart' => $b->ecart,
                        'total_actif' => $b->totalActif,
                        'total_passif' => $b->totalPassif,
                        'resultat_exercice' => $b->resultatExercice,
                        'resultat_reporte' => $b->resultatReporte,
                        'hors_rubrique' => array_map(static fn (array $c): string => $c['numero_compte'], $b->comptesHorsRubrique),
                        'passif' => array_map(static fn ($p): array => ['code' => $p->code, 'net' => $p->net], $b->passif),
                    ];
                    break;

                case 'instantane':
                    $exercices = ExerciceComptable::query()->orderBy('annee')->get();
                    $resultats[] = [
                        'ok' => true,
                        'statuts' => $statuts(),
                        'lignes' => $exercices->mapWithKeys(static fn (ExerciceComptable $e): array => [
                            (string) $e->annee => $lignes($e->id),
                        ])->all(),
                        'clotures' => ClotureExercice::query()->with('exercice')->orderBy('cloturee_le')->get()
                            ->map(static fn (ClotureExercice $c): array => [
                                'annee' => (int) $c->exercice->annee,
                                'piece_cloture' => $c->piece_cloture,
                                'piece_a_nouveaux' => $c->piece_a_nouveaux,
                                'resultat' => (string) $c->resultat,
                                'active' => $c->estActive(),
                                'motif' => $c->motif_reouverture,
                            ])->all(),
                    ];
                    break;

                default:
                    throw new InvalidArgumentException('Evenement inconnu : ' . $ev['t']);
            }
        } catch (RuntimeException $refus) {
            $resultats[] = ['refus' => $refus::class, 'message' => $refus->getMessage()];
        }
    }

    $sortie = [
        'resultats' => $resultats,
        'constantes' => [
            'journal' => AffectationResultatService::JOURNAL,
            'role' => AffectationResultatService::ROLE,
            'motif_min' => AffectationResultatService::MOTIF_LONGUEUR_MIN,
            'postes' => AffectationResultatService::POSTES,
            'postes_benefice' => AffectationResultatService::POSTES_BENEFICE,
            'postes_perte' => AffectationResultatService::POSTES_PERTE,
            'postes_benefice_ei' => AffectationResultatService::POSTES_BENEFICE_EI,
            'postes_perte_ei' => AffectationResultatService::POSTES_PERTE_EI,
            'prefixes_capitaux_propres' => AffectationResultatService::PREFIXES_CAPITAUX_PROPRES,
            'prefixes_pertes_anterieures' => AffectationResultatService::PREFIXES_PERTES_ANTERIEURES,
            'prefixes_reserves_non_distribuables' => AffectationResultatService::PREFIXES_RESERVES_NON_DISTRIBUABLES,
            'reference_longueur_max' => AffectationResultatService::REFERENCE_LONGUEUR_MAX,
            'formes' => FormeJuridique::valeurs(),
            'taux_reserve_legale' => AffectationResultatService::TAUX_RESERVE_LEGALE,
            'plafond_reserve_legale' => AffectationResultatService::PLAFOND_RESERVE_LEGALE,
            'centre' => ClotureExerciceService::CENTRE_DE_CLOTURE,
        ],
        'rubriques' => [
            // Le capital SOCIAL de l'affectation (101 seul) : `RubriquesSyscohada::CAPITAL` couvre
            // desormais tout le groupe 10, compte de l'exploitant compris (bilan).
            'capital' => AffectationResultatService::PREFIXES_CAPITAL_SOCIAL,
            'reserves' => RubriquesSyscohada::RESERVES,
            'report_a_nouveau' => RubriquesSyscohada::REPORT_A_NOUVEAU,
            'resultat_reporte' => RubriquesSyscohada::RESULTAT_REPORTE,
            'dettes_circulantes' => RubriquesSyscohada::DETTES_CIRCULANTES,
            'dettes_associes' => RubriquesSyscohada::DETTES_ASSOCIES,
        ],
        'messages' => collect($scenario['cles_messages'] ?? [])
            ->mapWithKeys(static fn (string $cle): array => [$cle => (string) trans($cle)])->all(),
    ];
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
    Storage::disk('local')->deleteDirectory('');
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
