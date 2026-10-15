<?php

declare(strict_types=1);

/*
| Rejoue un scenario de pieces comptables par les VRAIS services du serveur
| (`PasserEcritureService`, `EcritureComptableService`, `ExerciceComptableService`,
| `PlanComptableService`), pour que le test Flutter compare, champ a champ, ce
| que le moteur Dart fait du MEME scenario (10/10/2026, lot 1 de M10).
|
| Contrairement aux scripts voisins, la base N'EST PAS un double : l'observer
| RG-11, les contraintes CHECK, les cles etrangeres et le verrou de sequence
| sont ceux du serveur. Le script travaille sur `tatacora_test` (il REFUSE toute
| autre base), seme le referentiel par le VRAI `ComptabiliteReferentielSeeder`,
| puis ANNULE tout (rollback) : la base n'est pas modifiee. Si MySQL est
| injoignable, il echoue — il ne se contente pas de sauter.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15",
|     "ops": [ {"op": "passer", "ref": "p1", "valide": true, "journal": "VTE",
|               "date": "2031-03-04", "libelle": "Vente", "lignes": [
|                 {"compte": "5711", "debit": "12500.00", "centre": "Bar"}, ...]},
|              {"op": "valider", "ref": "p1"}, {"op": "contrepasser_piece", "ref": "p1"},
|              {"op": "contrepasser_ligne", "ref": "p1", "index": 0},
|              {"op": "modifier", "ref": "p1", "index": 0, "champs": {"libelle": "x"}},
|              {"op": "supprimer", "ref": "p1", "index": 0},
|              {"op": "ouvrir_exercice", "annee": 2031},
|              {"op": "poser_statut_exercice", "annee": 2031, "statut": "en_cloture"},
|              {"op": "cloturer_exercice", "annee": 2031},
|              {"op": "creer_compte", "numero": "6099", "libelle": "x", "nature": "charge"},
|              {"op": "comptes_de_charge"}, {"op": "dump_plan"}, {"op": "dump_exercices"} ] }
| Sortie (stdout, JSON) : { "resultats": [ ... un resultat par operation ... ] }
|   chaque resultat : { "ok": true, ... } ou { "refus": "<classe>", "message": "..." }.
|
| Usage : php tool/comptabilite/rejouer_scenario.php < scenario.json
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['ops'], $scenario['aujourdhui'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

// La base est choisie AVANT l'amorcage : le fichier `.env` ne l'emporte pas sur
// une variable deja posee.
putenv('DB_DATABASE=' . BASE_AUTORISEE);
$_ENV['DB_DATABASE'] = BASE_AUTORISEE;
$_SERVER['DB_DATABASE'] = BASE_AUTORISEE;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Domain\Comptabilite\Services\ExerciceComptableService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Models\User;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\QueryException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est « {$base} », pas « " . BASE_AUTORISEE . " ».\n");
    exit(1);
}

Carbon::setTestNow($scenario['aujourdhui'] . ' 10:00:00');

$passer = $app->make(PasserEcritureService::class);
$ecritures = $app->make(EcritureComptableService::class);
$exercices = $app->make(ExerciceComptableService::class);
$plan = $app->make(PlanComptableService::class);

/** @var array<string, list<string>> $pieces ref => identifiants, dans l'ordre d'ecriture */
$pieces = [];
/** @var array<string, string> $origine identifiant => "ref#index" */
$origine = [];
$resultats = [];

$decrire = static function (EcritureComptable $e) use (&$origine): array {
    $e->refresh();
    $e->loadMissing(['journal', 'compte', 'centre']);

    return [
        'numero_piece' => $e->numero_piece,
        'journal' => $e->journal->code,
        'date' => $e->date_ecriture->format('Y-m-d'),
        'compte' => $e->compte->numero_compte,
        'centre' => $e->centre->libelle,
        'libelle' => $e->libelle,
        'debit' => (string) $e->debit,
        'credit' => (string) $e->credit,
        'statut' => $e->statut,
        'contrepasse_de' => $e->ecriture_contrepassee_id === null
            ? null
            : ($origine[$e->ecriture_contrepassee_id] ?? '?'),
    ];
};

$enregistrer = static function (string $ref, Collection $lignes) use (&$pieces, &$origine): void {
    $pieces[$ref] = [];
    foreach ($lignes->values() as $i => $e) {
        $pieces[$ref][] = $e->id;
        $origine[$e->id] = $ref . '#' . $i;
    }
};

$modeles = static function (string $ref) use (&$pieces): Collection {
    return new Collection(array_map(
        static fn (string $id): EcritureComptable => EcritureComptable::findOrFail($id),
        $pieces[$ref],
    ));
};

$centreId = static function (?string $libelle): ?string {
    if ($libelle === null) {
        return null;
    }

    return (string) CentreCout::where('libelle', $libelle)->firstOrFail()->id;
};

DB::beginTransaction();

try {
    (new ComptabiliteReferentielSeeder())->run();

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'passer':
                    $lignes = [];
                    foreach ($op['lignes'] as $l) {
                        $ligne = ['compte' => $l['compte']];
                        foreach (['debit', 'credit', 'libelle'] as $cle) {
                            if (array_key_exists($cle, $l)) {
                                $ligne[$cle] = $l[$cle];
                            }
                        }
                        if (($l['centre'] ?? null) !== null) {
                            $ligne['centre_id'] = $centreId($l['centre']);
                        }
                        $lignes[] = $ligne;
                    }
                    $donnees = [
                        'journal' => $op['journal'],
                        'date' => $op['date'],
                        'libelle' => $op['libelle'],
                        'lignes' => $lignes,
                    ];
                    $ecrites = ($op['valide'] ?? false)
                        ? $passer->passerEtValider($donnees)
                        : $passer->passer($donnees);
                    $enregistrer($op['ref'], $ecrites);
                    $resultats[] = ['ok' => true, 'lignes' => $ecrites->map($decrire)->all()];
                    break;

                case 'valider':
                    $validees = $ecritures->valider($modeles($op['ref']));
                    $resultats[] = ['ok' => true, 'lignes' => $validees->map($decrire)->all()];
                    break;

                case 'contrepasser_piece':
                    $inverses = $passer->contrepasserPiece($modeles($op['ref']), $op['motif'] ?? null);
                    $enregistrer($op['ref'] . '/inverse', $inverses);
                    $resultats[] = ['ok' => true, 'lignes' => $inverses->map($decrire)->all()];
                    break;

                case 'contrepasser_piece_vide':
                    $passer->contrepasserPiece(new Collection());
                    $resultats[] = ['ok' => true, 'lignes' => []];
                    break;

                case 'contrepasser_ligne':
                    $ligne = EcritureComptable::findOrFail($pieces[$op['ref']][$op['index']]);
                    $inverse = $ecritures->contrepasser($ligne, $op['motif'] ?? null);
                    $origine[$inverse->id] = ($op['ref'] . '/ligne') . '#' . $op['index'];
                    $resultats[] = ['ok' => true, 'lignes' => [$decrire($inverse)]];
                    break;

                case 'modifier':
                    $ligne = EcritureComptable::findOrFail($pieces[$op['ref']][$op['index']]);
                    $ligne->update($op['champs']);
                    $resultats[] = ['ok' => true, 'lignes' => [$decrire($ligne)]];
                    break;

                case 'supprimer':
                    EcritureComptable::findOrFail($pieces[$op['ref']][$op['index']])->delete();
                    $resultats[] = ['ok' => true];
                    break;

                case 'ouvrir_exercice':
                    $e = $exercices->ouvrir((int) $op['annee']);
                    $resultats[] = ['ok' => true, 'exercice' => [
                        'annee' => (int) $e->annee,
                        'date_debut' => $e->date_debut->format('Y-m-d'),
                        'date_fin' => $e->date_fin->format('Y-m-d'),
                        'statut' => $e->statut,
                    ]];
                    break;

                case 'poser_statut_exercice':
                    ExerciceComptable::where('annee', (int) $op['annee'])->firstOrFail()
                        ->forceFill(['statut' => $op['statut']])->save();
                    $resultats[] = ['ok' => true];
                    break;

                case 'cloturer_exercice':
                    $exercice = ExerciceComptable::where('annee', (int) $op['annee'])->firstOrFail();
                    $auteur = User::factory()->create();
                    $e = $exercices->cloturer($exercice, $auteur);
                    $resultats[] = ['ok' => true, 'exercice' => [
                        'annee' => (int) $e->annee,
                        'statut' => $e->statut,
                        'date_cloture' => $e->date_cloture?->format('Y-m-d'),
                        'cloture_par_renseigne' => $e->utilisateur_cloture_id !== null,
                    ]];
                    break;

                case 'creer_compte':
                    $c = $plan->creerCompte($op['numero'], $op['libelle'], $op['nature']);
                    $resultats[] = ['ok' => true, 'compte' => [
                        'numero' => $c->numero_compte,
                        'libelle' => $c->libelle,
                        'classe' => $c->classe,
                        'nature' => $c->nature,
                    ]];
                    break;

                case 'dump_plan':
                    // Le plan TEL QUE LE SEEDER L'A ECRIT : numero, libelle, classe,
                    // nature et centre par defaut (libelle), dans l'ordre des numeros.
                    $centres = CentreCout::query()->pluck('libelle', 'id');
                    $resultats[] = ['ok' => true, 'plan' => App\Domain\Comptabilite\Models\CompteComptable::query()
                        ->orderBy('numero_compte')->get()
                        ->map(static fn ($c): array => [
                            $c->numero_compte,
                            $c->libelle,
                            $c->classe,
                            $c->nature,
                            $c->centre_cout_defaut_id === null ? null : $centres[$c->centre_cout_defaut_id],
                        ])->all()];
                    break;

                case 'dump_exercices':
                    $resultats[] = ['ok' => true, 'exercices' => ExerciceComptable::query()
                        ->orderBy('annee')->get()
                        ->map(static fn ($e): array => [(int) $e->annee, $e->statut])->all()];
                    break;

                case 'analytique':
                    // La marge par centre (`AnalytiqueService`, le calcul du
                    // graphique « Marge sur couts directs par activite » de
                    // l'accueil), les deux statuts comme `Accueil::margeParActivite`
                    // (13/10/2026).
                    $exercice = ExerciceComptable::where('annee', (int) $op['annee'])->firstOrFail();
                    $analytique = $app->make(\App\Domain\Comptabilite\Services\AnalytiqueService::class)
                        ->genererPourExercice($exercice->id, EcritureComptable::STATUTS);
                    $resultats[] = ['ok' => true, 'centres' => array_map(
                        static fn ($l): array => [
                            'libelle' => $l->libelle,
                            'produits' => $l->produits,
                            'charges' => $l->charges,
                            'resultat' => $l->resultat,
                            'lignes' => $l->nombreLignes,
                        ],
                        $analytique->centres,
                    )];
                    break;

                case 'comptes_de_charge':
                    $resultats[] = ['ok' => true, 'comptes' => $plan->comptesDeCharge()
                        ->map(static fn ($c): string => $c->numero_compte)->all()];
                    break;

                default:
                    fwrite(STDERR, "Operation inconnue : {$op['op']}\n");
                    exit(5);
            }
        } catch (QueryException) {
            // Contrainte de la base (CHECK, cle etrangere) : le serveur n'a
            // aucune phrase pour elle, seulement une erreur SQL.
            $resultats[] = ['refus' => 'contrainte_base'];
        } catch (Throwable $e) {
            $resultats[] = ['refus' => (new ReflectionClass($e))->getShortName(), 'message' => $e->getMessage()];
        }
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
