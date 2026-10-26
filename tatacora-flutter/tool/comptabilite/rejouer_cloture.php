<?php

declare(strict_types=1);

/*
| Rejoue une CLOTURE ANNUELLE SYSCOHADA par les VRAIS services du serveur
| (`ClotureExerciceService`, `EtatClotureService`, `BalanceGeneraleService`,
| `ArchiveClotureService`), pour que le test Flutter compare, champ a champ, ce
| que `ClotureExerciceLocale` fait du MEME scenario (26/10/2026, « la cloture
| annuelle SYSCOHADA doit etre implementee en poste et web »).
|
| La base N'EST PAS un double : l'observer RG-11, les contraintes, les cles
| etrangeres et le verrou de sequence sont ceux du serveur. Le script travaille
| sur `tatacora_test` — ou sur la base d'essai nommee par la variable
| d'environnement TATACORA_BASE_ESSAI (un nom qui FINIT par `_test`, jamais une
| base de travail) —, seme le referentiel par le VRAI `ComptabiliteReferentielSeeder`
| et les roles, puis ANNULE tout (rollback). L'archive est ecrite sur un disque
| FACTICE (`Storage::fake`), jamais sur celui du serveur. Si MySQL est
| injoignable, il echoue : il ne se contente pas de sauter.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15",
|     "exercices": [ {"annee": 2030, "statut": "ouvert"} ],
|     "cles_messages": ["comptabilite.cloture_ordre", ...],
|     "evenements": [
|       {"t": "piece", "journal": "VTE", "date": "2030-03-05", "valide": true,
|        "libelle": "Vente", "lignes": [{"compte": "5711", "debit": "100.00", "centre": "Bar"}]},
|       {"t": "geste", "action": "demarrer|reprendre|cloturer|rouvrir",
|        "annee": 2030, "motif": "...", "role": "comptable|administrateur"},
|       {"t": "valider_brouillons", "annee": 2031},
|       {"t": "etat", "annee": 2030}, {"t": "balance", "annee": 2031}, {"t": "ouverture", "annee": 2031},
|       {"t": "archive", "annee": 2030}, {"t": "instantane"} ] }
| Sortie (stdout, JSON) :
|   { "resultats": [ ... un resultat par evenement ... ],
|     "constantes": {...}, "journaux": {...}, "messages": {...} }
|
| Usage : TATACORA_BASE_ESSAI=tatacora_test php tool/comptabilite/rejouer_cloture.php < scenario.json
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
use App\Domain\Comptabilite\Services\ArchiveClotureService;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Domain\Comptabilite\Services\EtatClotureService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
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
$archives = $app->make(ArchiveClotureService::class);
$ecritures = $app->make(EcritureComptableService::class);

$resultats = [];
$sortie = [];

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
                    ($ev['valide'] ?? true) ? $passer->passerEtValider($donnees) : $passer->passer($donnees);
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

                case 'archive':
                    $exercice = ExerciceComptable::where('annee', (int) $ev['annee'])->firstOrFail();
                    $cloture = $service->clotureActive($exercice->id) ?? throw new RuntimeException('Aucune cloture active.');
                    $archives->archiver($cloture, $comptable);
                    $cloture->refresh();
                    $disque = Storage::disk('local');
                    $dossier = (string) $cloture->archive_chemin;
                    $manifeste = json_decode((string) $disque->get($dossier . '/manifeste.json'), true);
                    $resultats[] = [
                        'ok' => true,
                        'verifiee' => $archives->verifier($cloture),
                        'ecritures_csv' => base64_encode((string) $disque->get($dossier . '/ecritures.csv')),
                        'balance_csv' => base64_encode((string) $disque->get($dossier . '/balance.csv')),
                        'fichiers' => array_keys($manifeste['fichiers']),
                        'cles_manifeste' => array_keys($manifeste),
                        'cles_cloture' => array_keys($manifeste['cloture']),
                        'referentiel' => $manifeste['referentiel'],
                        'algorithme' => $manifeste['algorithme'],
                        'empreinte_longueur' => strlen((string) $cloture->archive_empreinte),
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

    $reflexion = new ReflectionClass(ClotureExerciceService::class);

    $sortie = [
        'resultats' => $resultats,
        'constantes' => [
            'journal_cloture' => ClotureExerciceService::JOURNAL_CLOTURE,
            'journal_a_nouveaux' => ClotureExerciceService::JOURNAL_A_NOUVEAUX,
            'journaux_reserves' => ClotureExerciceService::JOURNAUX_RESERVES,
            'centre' => ClotureExerciceService::CENTRE_DE_CLOTURE,
            'role_reouverture' => ClotureExerciceService::ROLE_REOUVERTURE,
            'motif_min' => ClotureExerciceService::MOTIF_LONGUEUR_MIN,
            'classes_gestion' => ClotureExerciceService::CLASSES_GESTION,
            'classes_bilan' => ClotureExerciceService::CLASSES_BILAN,
            'colonnes_ecritures' => ArchiveClotureService::COLONNES_ECRITURES,
            'colonnes_balance' => ArchiveClotureService::COLONNES_BALANCE,
            'fichiers' => [
                ArchiveClotureService::FICHIER_ECRITURES,
                ArchiveClotureService::FICHIER_BALANCE,
                ArchiveClotureService::FICHIER_ETATS,
                ArchiveClotureService::FICHIER_MANIFESTE,
            ],
            'constantes_connues' => count($reflexion->getConstants()),
        ],
        'journaux' => DB::table('journaux_comptables')->whereIn('code', ['AN', 'CL'])->pluck('libelle', 'code')->all(),
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
