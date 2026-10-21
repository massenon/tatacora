<?php

declare(strict_types=1);

/*
| Rejoue des ECRITURES VALIDEES par les VRAIS services du serveur
| (`BalanceGeneraleService`, `CompteResultatService`, `BilanService`), pour que
| le test Flutter compare, au centime, ce que le poste calcule du MEME jeu
| (21/10/2026, « compte de resultat et bilan sur le poste »).
|
| Le script travaille sur `tatacora_test` (il REFUSE toute autre base), seme le
| referentiel par le VRAI `ComptabiliteReferentielSeeder`, ecrit les lignes en
| SQL direct (elles sont deja validees : ce sont celles que le poste recoit),
| puis ANNULE tout (rollback). Si MySQL est injoignable, il echoue.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15",
|     "exercices": [ {"annee": 2030, "statut": "ouvert"|"en_cloture"|"cloture"} ],
|     "ecritures": [ {"annee": 2031, "journal": "VTE", "compte": "7061",
|                      "debit": "0.00", "credit": "1500.00", "date": "2031-06-15"} ],
|     "annees": [2031, 2030] }
| Sortie (stdout, JSON) :
|   { "cascade": [ {code, libelle, sens, prefixes, composants} ],
|     "rubriques": { immobilisations_brutes: [...], ... },
|     "etats": { "2031": { "balance": {...}, "resultat": {...}, "bilan": {...} } } }
|
| Usage : php tool/etats/rejouer_etats_financiers.php < jeu.json
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$jeu = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($jeu) || ! isset($jeu['ecritures'], $jeu['exercices'], $jeu['annees'], $jeu['aujourdhui'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

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
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Services\CompteResultatService;
use App\Domain\Comptabilite\Support\RubriquesSyscohada;
use App\Domain\Comptabilite\Support\SoldesIntermediairesGestion;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . BASE_AUTORISEE . " \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow($jeu['aujourdhui'] . ' 10:00:00');

$statuts = ['validee'];
$sortie = [];

DB::beginTransaction();

try {
    (new ComptabiliteReferentielSeeder())->run();

    $exerciceIds = [];

    foreach ($jeu['exercices'] as $e) {
        $annee = (int) $e['annee'];
        $exercice = ExerciceComptable::firstOrCreate(
            ['annee' => $annee],
            ['date_debut' => "{$annee}-01-01", 'date_fin' => "{$annee}-12-31", 'statut' => 'ouvert'],
        );
        $exercice->forceFill(['statut' => $e['statut']])->save();
        $exerciceIds[$annee] = (string) $exercice->id;
    }

    $centre = (string) CentreCout::query()->firstOrFail()->id;
    $maintenant = now();

    foreach ($jeu['ecritures'] as $l) {
        DB::table('ecritures_comptables')->insert([
            'id' => (string) Str::uuid(),
            'exercice_id' => $exerciceIds[(int) $l['annee']],
            'journal_id' => (string) JournalComptable::where('code', $l['journal'])->firstOrFail()->id,
            'compte_id' => (string) CompteComptable::where('numero_compte', $l['compte'])->firstOrFail()->id,
            'centre_id' => $centre,
            'date_ecriture' => $l['date'],
            'libelle' => 'Jeu d\'essai',
            'debit' => $l['debit'],
            'credit' => $l['credit'],
            'statut' => 'validee',
            'created_at' => $maintenant,
            'updated_at' => $maintenant,
        ]);
    }

    $balances = $app->make(BalanceGeneraleService::class);
    $resultats = $app->make(CompteResultatService::class);
    $bilans = $app->make(BilanService::class);

    $etats = [];

    foreach ($jeu['annees'] as $annee) {
        $id = $exerciceIds[(int) $annee];
        $b = $balances->genererPourExercice($id, $statuts, 'validee');
        $r = $resultats->genererPourExercice($id, $statuts, 'validee');
        $bi = $bilans->genererPourExercice($id, $statuts, 'validee');

        $etats[(string) $annee] = [
            'balance' => [
                'a_nouveaux_provisoires_de' => $b->aNouveauxProvisoiresDe,
                'lignes' => array_map(static fn ($l): array => [
                    'numero_compte' => $l->numeroCompte,
                    'libelle' => $l->libelle,
                    'classe' => $l->classe,
                    'debit' => $l->totalDebit,
                    'credit' => $l->totalCredit,
                ], $b->lignes),
            ],
            'resultat' => [
                'lignes' => array_map(static fn ($l): array => [
                    'code' => $l->code, 'montant' => $l->montant,
                ], $r->lignes),
                'avant_impot' => $r->resultatAvantImpot,
                'impot' => $r->impotComptabilise,
                'net' => $r->resultatNet,
                'impot_non_comptabilise' => $r->impotNonComptabilise,
            ],
            'bilan' => [
                'actif' => array_map(static fn ($p): array => [
                    'code' => $p->code, 'brut' => $p->brut, 'amortissement' => $p->amortissement, 'net' => $p->net,
                ], $bi->actif),
                'passif' => array_map(static fn ($p): array => [
                    'code' => $p->code, 'brut' => $p->brut, 'amortissement' => $p->amortissement, 'net' => $p->net,
                ], $bi->passif),
                'hors_rubrique' => $bi->comptesHorsRubrique,
                'total_actif_brut' => $bi->totalActifBrut,
                'total_actif_amortissement' => $bi->totalActifAmortissement,
                'total_actif' => $bi->totalActif,
                'total_passif' => $bi->totalPassif,
                'equilibre' => $bi->equilibre,
                'ecart' => $bi->ecart,
                'resultat_exercice' => $bi->resultatExercice,
                'impot_non_comptabilise' => $bi->impotNonComptabilise,
            ],
        ];
    }

    $sortie = [
        'cascade' => SoldesIntermediairesGestion::CASCADE,
        'rubriques' => [
            'immobilisations_brutes' => RubriquesSyscohada::IMMOBILISATIONS_BRUTES,
            'amortissements' => RubriquesSyscohada::AMORTISSEMENTS,
            'stocks' => RubriquesSyscohada::STOCKS,
            'creances' => RubriquesSyscohada::CREANCES,
            'tresorerie_actif' => RubriquesSyscohada::TRESORERIE_ACTIF,
            'capital' => RubriquesSyscohada::CAPITAL,
            'resultat_reporte' => RubriquesSyscohada::RESULTAT_REPORTE,
            'dettes_circulantes' => RubriquesSyscohada::DETTES_CIRCULANTES,
            'tresorerie_passif' => RubriquesSyscohada::TRESORERIE_PASSIF,
        ],
        'plan' => CompteComptable::query()
            ->whereIn('numero_compte', ['131', '139'])
            ->get(['numero_compte', 'libelle', 'classe'])
            ->mapWithKeys(static fn ($c): array => [(string) $c->numero_compte => [
                'libelle' => (string) $c->libelle, 'classe' => (string) $c->classe,
            ]])->all(),
        'etats' => $etats,
    ];
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
