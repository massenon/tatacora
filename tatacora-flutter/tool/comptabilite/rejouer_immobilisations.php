<?php

declare(strict_types=1);

/*
| Rejoue des IMMOBILISATIONS par le VRAI `ImmobilisationService` du serveur
| (creer, planAmortissement, tableauPourExercice), pour que le test Flutter
| compare, au centime, ce que le poste calcule du MEME jeu (21/10/2026,
| « immobilisations sur le poste »).
|
| Le script travaille sur `tatacora_test` (il REFUSE toute autre base), seme le
| referentiel par le VRAI `ComptabiliteReferentielSeeder` (comptes 231, 244…),
| puis ANNULE tout (rollback). Si MySQL est injoignable, il echoue.
|
| Entree (stdin, JSON) :
|   { "biens": [ {"libelle": "...", "valeur": "1200000.00", "duree": 5,
|                 "date": "2026-03-20", "compte": "231"|null} ],
|     "annees": [2026, 2027],
|     "recherches": ["prado"],
|     "refus": [ { donnees passees telles quelles a creer() } ] }
| Sortie (stdout, JSON) :
|   { "biens": [ {code, plan: {lignes: [...], total}} ],
|     "tableaux": { "2026": {lignes, totaux} },
|     "recherches": { "prado": [codes...] },
|     "refus": [ message... ] }
|
| Usage : php tool/comptabilite/rejouer_immobilisations.php < jeu.json
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$jeu = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($jeu) || ! isset($jeu['biens'], $jeu['annees'])) {
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

use App\Domain\Comptabilite\Services\ImmobilisationService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . BASE_AUTORISEE . " \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow('2026-10-21 10:00:00');

$ligne = static fn ($l): array => [
    'annee' => $l->annee,
    'base' => $l->base,
    'dotation' => $l->dotation,
    'cumul' => $l->cumul,
    'vnc' => $l->vnc,
    'prorata' => $l->prorata,
];

$sortie = ['biens' => [], 'tableaux' => [], 'recherches' => [], 'refus' => []];

DB::beginTransaction();

try {
    (new ComptabiliteReferentielSeeder())->run();

    /** @var ImmobilisationService $service */
    $service = $app->make(ImmobilisationService::class);

    foreach ($jeu['biens'] as $b) {
        $i = $service->creer([
            'libelle' => $b['libelle'],
            'valeur_origine' => $b['valeur'],
            'duree_annees' => $b['duree'],
            'date_mise_service' => $b['date'],
            'compte_immobilisation' => $b['compte'] ?? null,
        ]);
        $plan = $service->planAmortissement($i->refresh());
        $sortie['biens'][] = [
            'id' => $i->id,
            'code' => $i->code,
            'plan' => ['lignes' => array_map($ligne, $plan->lignes), 'total' => $plan->total],
        ];
    }

    foreach ($jeu['annees'] as $annee) {
        $t = $service->tableauPourExercice((int) $annee);
        $sortie['tableaux'][(string) $annee] = [
            'lignes' => array_map(static fn ($l): array => [
                'code' => $l->immobilisation->code,
                'brut' => $l->brut,
                'dotation' => $l->dotation,
                'cumul' => $l->cumul,
                'vnc' => $l->vnc,
            ], $t->lignes),
            'totaux' => [
                'brut' => $t->totalBrut,
                'dotation' => $t->totalDotation,
                'cumul' => $t->totalCumul,
                'vnc' => $t->totalVnc,
            ],
        ];
    }

    foreach ($jeu['recherches'] ?? [] as $q) {
        $t = $service->tableauPourExercice((int) $jeu['annees'][0], (string) $q);
        $sortie['recherches'][(string) $q] = array_map(static fn ($l): string => $l->immobilisation->code, $t->lignes);
    }

    foreach ($jeu['refus'] ?? [] as $donnees) {
        try {
            $service->creer($donnees);
            $sortie['refus'][] = null;
        } catch (RuntimeException $e) {
            $sortie['refus'][] = $e->getMessage();
        }
    }
} finally {
    DB::rollBack();
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
