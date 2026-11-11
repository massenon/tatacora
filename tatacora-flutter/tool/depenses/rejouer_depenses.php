<?php

declare(strict_types=1);

/*
| Rejoue un scenario de DEPENSES par le VRAI `DepenseService` du serveur
| (enregistrer, comptabiliser), pour que le test Flutter compare, champ a champ,
| ce que `DepenseDao` fait du MEME scenario (10/10/2026, lot 3 de M10).
|
| La base N'EST PAS un double : l'observer RG-11, les contraintes CHECK, les
| cles etrangeres et le verrou de sequence sont ceux du serveur. Le script
| travaille sur `tatacora_test` (il REFUSE toute autre base), seme le
| referentiel par le VRAI `ComptabiliteReferentielSeeder`, puis ANNULE tout
| (rollback) : la base n'est pas modifiee. Si MySQL est injoignable, il echoue.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15",
|     "ops": [
|       {"op": "depense", "date": "2031-03-04", "tresorerie": "caisse",
|        "libelle": "Marche", "centre": "Restaurant"|null,
|        "lignes": [{"compte": "6011", "libelle": "Tomates", "montant": "8500",
|                    "nature": "Tomate", "famille": "Marché"}]},
|       {"op": "depense_ancienne", "ref": "a1", "date": ..., "tresorerie": ...,
|        "libelle": ..., "lignes": [...]},
|       {"op": "rattrapage", "ref": "a1", "centre": "Restaurant"|null},
|       {"op": "libelles"},
|       {"op": "poser_centre_defaut", "compte": "6052", "centre": "Structure"},
|       {"op": "ouvrir_exercice", "annee": 2032},
|       {"op": "poser_statut_exercice", "annee": 2032, "statut": "en_cloture"},
|       {"op": "parametre", "cle": "compte_caisse", "valeur": "5712"|null},
|       {"op": "compter"}, {"op": "tresoreries"} ] }
| Sortie (stdout, JSON) : { "resultats": [ ... un resultat par operation ... ] }
|   chaque resultat : { "ok": true, ... } ou { "refus": "<classe>", "message": "..." }.
|
| Usage : php tool/depenses/rejouer_depenses.php < scenario.json
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
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\ExerciceComptableService;
use App\Domain\Depenses\Models\Depense;
use App\Domain\Depenses\Models\LigneDepense;
use App\Domain\Depenses\Services\DepenseService;
use App\Models\User;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Illuminate\Database\QueryException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . BASE_AUTORISEE . " \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow($scenario['aujourdhui'] . ' 10:00:00');

$depenses = $app->make(DepenseService::class);
$exercices = $app->make(ExerciceComptableService::class);

// Le compte de depart : la base de test peut porter des lignes etrangeres a ce
// scenario ; seul le DELTA est compare.
$depart = [
    'depenses' => Depense::count(),
    'lignes_depense' => LigneDepense::count(),
    'ecritures' => EcritureComptable::count(),
];

/** @var array<string, string> $anciennes ref => identifiant de la depense heritee */
$anciennes = [];
$resultats = [];

$centreId = static function (?string $libelle): ?string {
    if ($libelle === null) {
        return null;
    }

    return (string) CentreCout::where('libelle', $libelle)->firstOrFail()->id;
};

$lignesDeClient = static function (array $lignes): array {
    return array_map(static fn (array $l): array => [
        'compte_charge' => $l['compte'],
        'libelle' => $l['libelle'],
        'montant' => $l['montant'],
        'nature' => $l['nature'],
        'famille' => $l['famille'],
    ], $lignes);
};

/**
 * La depense telle que le serveur la a ecrite, ET sa piece (lignes triees de
 * facon canonique : compte, debit, credit, libelle).
 */
$decrire = static function (Depense $d): array {
    $d->refresh();
    $d->load('lignes');

    $piece = [];
    $numero = null;

    if ($d->ecriture_id !== null) {
        $tresorerie = EcritureComptable::with(['journal', 'compte', 'centre'])->findOrFail($d->ecriture_id);
        $numero = $tresorerie->numero_piece;

        foreach (EcritureComptable::with(['journal', 'compte', 'centre'])->where('numero_piece', $numero)->get() as $e) {
            $piece[] = [
                'numero_piece' => $e->numero_piece,
                'journal' => $e->journal->code,
                'date' => $e->date_ecriture->format('Y-m-d'),
                'compte' => $e->compte->numero_compte,
                'centre' => $e->centre->libelle,
                'libelle' => $e->libelle,
                'debit' => (string) $e->debit,
                'credit' => (string) $e->credit,
                'statut' => $e->statut,
            ];
        }

        // Tri sur une CLE TEXTE comparee octet a octet : `<=>` sur des tableaux
        // comparerait "8500.00" et "0.00" comme des nombres.
        usort($piece, static fn (array $a, array $b): int => strcmp(
            implode('|', [$a['compte'], $a['debit'], $a['credit'], $a['libelle']]),
            implode('|', [$b['compte'], $b['debit'], $b['credit'], $b['libelle']]),
        ));
    }

    $lignes = [];

    foreach ($d->lignes as $l) {
        $lignes[] = [
            'compte_charge' => $l->compte_charge,
            'libelle' => $l->libelle,
            'nature' => $l->nature,
            'famille' => $l->famille,
            'montant' => (string) $l->montant,
        ];
    }

    usort($lignes, static fn (array $a, array $b): int => strcmp(
        implode('|', [$a['compte_charge'], $a['libelle'], $a['montant']]),
        implode('|', [$b['compte_charge'], $b['libelle'], $b['montant']]),
    ));

    return [
        'tresorerie' => $d->tresorerie,
        'compte_tresorerie' => $d->compte_tresorerie,
        'montant_total' => (string) $d->montant_total,
        'libelle' => $d->libelle,
        'date' => $d->date_transaction->format('Y-m-d'),
        'comptabilisee' => $d->estComptabilisee(),
        'numero_piece' => $numero,
        'ecriture_refus' => $d->ecriture_refus,
        'lignes' => $lignes,
        'piece' => $piece,
    ];
};

DB::beginTransaction();

try {
    (new ComptabiliteReferentielSeeder())->run();

    $auteur = User::factory()->create();
    $serie = 0;

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'depense':
                    $depense = $depenses->enregistrer([
                        'date_transaction' => $op['date'],
                        'tresorerie' => $op['tresorerie'],
                        'centre_id' => $centreId($op['centre'] ?? null),
                        'libelle' => $op['libelle'],
                        'lignes' => $lignesDeClient($op['lignes']),
                    ], $auteur);
                    $resultats[] = ['ok' => true, 'depense' => $decrire($depense)];
                    break;

                case 'depense_ancienne':
                    // Une depense telle que l'ancien service en produisait :
                    // ecrite, sans piece (comme le fait le test du serveur).
                    $serie++;
                    $total = '0.00';
                    foreach ($op['lignes'] as $l) {
                        $total = bcadd($total, $l['montant'], 2);
                    }
                    $heritee = Depense::create([
                        'numero' => 'DEP-2031-9' . str_pad((string) $serie, 4, '0', STR_PAD_LEFT),
                        'date_transaction' => $op['date'],
                        'tresorerie' => $op['tresorerie'],
                        'compte_tresorerie' => DepenseService::TRESORERIES[$op['tresorerie']]['compte'],
                        'montant_total' => $total,
                        'libelle' => $op['libelle'],
                        'utilisateur_id' => $auteur->id,
                    ]);
                    foreach ($op['lignes'] as $l) {
                        LigneDepense::create([
                            'depense_id' => $heritee->id,
                            'libelle' => $l['libelle'],
                            'compte_charge' => $l['compte'],
                            'nature' => $l['nature'],
                            'famille' => $l['famille'],
                            'montant' => $l['montant'],
                        ]);
                    }
                    $anciennes[$op['ref']] = (string) $heritee->id;
                    $resultats[] = ['ok' => true, 'depense' => $decrire($heritee)];
                    break;

                case 'rattrapage':
                    $heritee = Depense::findOrFail($anciennes[$op['ref']]);
                    try {
                        // Le centre est un parametre OBLIGATOIRE du geste
                        // (10/10/2026) : le VRAI service recoit ce que la vue lui
                        // passe, un identifiant ou la chaine vide.
                        $rattrapee = $depenses->comptabiliser(
                            $heritee,
                            (string) ($centreId($op['centre'] ?? null) ?? ''),
                        );
                        $resultats[] = ['ok' => true, 'depense' => $decrire($rattrapee)];
                    } catch (Throwable $e) {
                        // La raison est PERSISTEE sur la depense, hors transaction.
                        $resultats[] = [
                            'refus' => (new ReflectionClass($e))->getShortName(),
                            'message' => $e->getMessage(),
                            'depense' => $decrire($heritee),
                        ];
                    }
                    break;

                case 'parametre':
                    // La correspondance des comptes (26/10/2026) : une cle
                    // `compte_<role>` posee DIRECTEMENT en base — c'est la LECTURE
                    // au moment de passer la piece qu'on mesure, pas l'ecran.
                    // `null` retire la ligne : le defaut.
                    DB::table('parametres_systeme')->where('cle', $op['cle'])->delete();
                    if ($op['valeur'] !== null) {
                        DB::table('parametres_systeme')->insert([
                            'id' => (string) Str::uuid(),
                            'cle' => $op['cle'],
                            'valeur' => $op['valeur'],
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]);
                    }
                    $resultats[] = ['ok' => true];
                    break;

                case 'poser_centre_defaut':
                    CompteComptable::where('numero_compte', $op['compte'])->firstOrFail()
                        ->forceFill(['centre_cout_defaut_id' => $centreId($op['centre'])])->save();
                    $resultats[] = ['ok' => true];
                    break;

                case 'ouvrir_exercice':
                    $e = $exercices->ouvrir((int) $op['annee']);
                    $resultats[] = ['ok' => true, 'annee' => (int) $e->annee];
                    break;

                case 'poser_statut_exercice':
                    ExerciceComptable::where('annee', (int) $op['annee'])->firstOrFail()
                        ->forceFill(['statut' => $op['statut']])->save();
                    $resultats[] = ['ok' => true];
                    break;

                case 'compter':
                    $resultats[] = ['ok' => true, 'compte' => [
                        'depenses' => Depense::count() - $depart['depenses'],
                        'lignes_depense' => LigneDepense::count() - $depart['lignes_depense'],
                        'ecritures' => EcritureComptable::count() - $depart['ecritures'],
                    ]];
                    break;

                case 'libelles':
                    // Les libelles du bandeau de rattrapage, lus de lang/fr par le
                    // VRAI traducteur (jamais recopies a la main cote Dart).
                    $resultats[] = ['ok' => true, 'libelles' => [
                        'centre' => __('depenses_pwa.rattrapage_centre'),
                        'choisir' => __('depenses_pwa.rattrapage_centre_choisir'),
                        'action' => __('depenses_pwa.rattrapage_action'),
                        'bandeau' => __('depenses_pwa.rattrapage_bandeau', ['nombre' => ':nombre']),
                        'centre_absent' => __('depenses.centre_absent', ['numero' => ':numero']),
                    ]];
                    break;

                case 'tresoreries':
                    $resultats[] = ['ok' => true, 'tresoreries' => DepenseService::TRESORERIES];
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
