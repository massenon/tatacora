<?php

declare(strict_types=1);

/*
| Rejoue des ECRITURES VALIDEES par le VRAI `TafireService` du serveur (TAFIRE
| sur le resultat de N SEUL, 10/11/2026) : le test Flutter compare, au centime,
| TOUS les champs du TAFIRE du poste (cessions, emprunts, affectation du resultat
| de N-1, dividendes, trois flux). Meme entree que `rejouer_etats_financiers.php`.
|
| La base est celle de TATACORA_BASE_ESSAI (un nom qui FINIT par `_test`),
| `tatacora_test` par defaut ; tout est ANNULE (rollback).
|
| Usage : TATACORA_BASE_ESSAI=tatacora_<x>_test php tool/etats/rejouer_tafire.php < jeu.json
*/

$baseAutorisee = (string) (getenv('TATACORA_BASE_ESSAI') ?: 'tatacora_test');

if (! str_ends_with($baseAutorisee, '_test')) {
    fwrite(STDERR, "Refus : TATACORA_BASE_ESSAI doit finir par _test.\n");
    exit(1);
}

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

putenv('DB_DATABASE=' . $baseAutorisee);
$_ENV['DB_DATABASE'] = $baseAutorisee;
$_SERVER['DB_DATABASE'] = $baseAutorisee;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\Services\TafireService;
use App\Domain\Comptabilite\Support\RubriquesTafire;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseAutorisee) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . $baseAutorisee . " \u{bb}.\n");
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

    // Un exercice CLÔTURÉ dont l'année suivante porte des à-nouveaux a sa
    // clôture ENREGISTRÉE : c'est ce qui rend l'ouverture « connue » aux
    // yeux de `BalanceGeneraleService::soldesOuverture`.
    foreach ($jeu['exercices'] as $e) {
        if ($e['statut'] !== 'cloture') {
            continue;
        }

        $suivante = (int) $e['annee'] + 1;
        $aDesNouveaux = collect($jeu['ecritures'])->contains(
            static fn (array $l): bool => (int) $l['annee'] === $suivante && $l['journal'] === 'AN',
        );

        if ($aDesNouveaux) {
            DB::table('clotures_exercices')->insert([
                'id' => (string) Str::uuid(),
                'exercice_id' => $exerciceIds[(int) $e['annee']],
                'resultat' => '0.00',
                'cloturee_le' => $maintenant,
                'created_at' => $maintenant,
                'updated_at' => $maintenant,
            ]);
        }
    }

    $tafires = $app->make(TafireService::class);
    $etats = [];

    foreach ($jeu['annees'] as $annee) {
        $t = $tafires->genererPourExercice($exerciceIds[(int) $annee], $statuts, 'validee');

        $etats[(string) $annee] = [
            'resultat' => $t->resultatExercice,
            'dotations' => $t->dotationsAmortissements,
            'reprises' => $t->reprisesAmortissements,
            'vnc_cessions' => $t->valeurComptableCessions,
            'quote_part_subventions' => $t->quotePartSubventions,
            'cafg' => $t->capaciteAutofinancementGlobale,
            'produits_cessions' => $t->produitsCessions,
            'capital' => $t->augmentationCapital,
            'emprunts' => $t->variationEmprunts,
            'dettes_participations' => $t->variationDettesParticipations,
            'ressources' => $t->totalRessources,
            'acquisitions' => $t->acquisitionsImmobilisations,
            'autres_capitaux_propres' => $t->variationAutresCapitauxPropres,
            'dividendes_a_payer' => $t->variationDividendesAPayer,
            'dividendes_verses' => $t->dividendesVerses,
            'emplois' => $t->totalEmplois,
            'flux_exploitation' => $t->fluxExploitation,
            'flux_investissement' => $t->fluxInvestissement,
            'flux_financement' => $t->fluxFinancement,
            'stocks' => $t->variationStocks,
            'creances' => $t->variationCreances,
            'dettes' => $t->variationDettes,
            'bfr' => $t->variationBesoinFondsRoulement,
            'calculee' => $t->variationTresorerieCalculee,
            'reelle' => $t->variationTresorerieReelle,
            'ecart' => $t->ecart,
            'coherent' => $t->coherent,
        ];
    }

    $sortie = [
        'rubriques' => [
            'dotations' => RubriquesTafire::DOTATIONS,
            'reprises' => RubriquesTafire::REPRISES,
            'dotations_amortissements' => RubriquesTafire::DOTATIONS_AMORTISSEMENTS,
            'reprises_sur_immobilisations' => RubriquesTafire::REPRISES_SUR_IMMOBILISATIONS,
            'quote_part_subventions' => RubriquesTafire::QUOTE_PART_SUBVENTIONS,
            'valeur_comptable_cessions' => RubriquesTafire::VALEUR_COMPTABLE_CESSIONS,
            'produits_cessions' => RubriquesTafire::PRODUITS_CESSIONS,
            'apports_capital' => RubriquesTafire::APPORTS_CAPITAL,
            'autres_capitaux_propres' => RubriquesTafire::AUTRES_CAPITAUX_PROPRES,
            'dettes_financieres' => RubriquesTafire::DETTES_FINANCIERES,
            'dettes_participations' => RubriquesTafire::DETTES_PARTICIPATIONS,
            'dividendes_a_payer' => RubriquesTafire::DIVIDENDES_A_PAYER,
        ],
        'etats' => $etats,
    ];
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
