<?php

declare(strict_types=1);

/*
| Rejoue le GRAND LIVRE et l'ANALYTIQUE par les VRAIS services du serveur
| (`GrandLivreService`, `AnalytiqueService`, et `BalanceGeneraleService::
| soldesOuverture`), pour que le test Flutter compare, au centime, ce que le
| poste calcule du MEME jeu (26/10/2026, « tous les modules sans serveur »).
|
| Le script travaille sur `tatacora_test` (il REFUSE toute autre base), seme le
| referentiel par le VRAI `ComptabiliteReferentielSeeder`, ecrit les lignes en
| SQL direct, puis ANNULE tout (rollback). MySQL injoignable : il echoue.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15",
|     "exercices": [ {"annee": 2030, "statut": "ouvert"|"en_cloture"|"cloture"} ],
|     "centres": [ {"libelle": "Hebergement"} ],
|     "ecritures": [ {"annee": 2031, "journal": "VTE", "compte": "7061",
|                      "centre": "Hebergement", "debit": "0.00",
|                      "credit": "1500.00", "date": "2031-06-15",
|                      "statut": "validee"|"brouillon"} ],
|     "grands_livres": [ {"annee": 2031, "compte": "7061", "filtre": "toutes"|"validee"|"brouillon"} ],
|     "analytiques": [ {"annee": 2031, "filtre": "toutes"} ] }
| Sortie (stdout, JSON) : { "grands_livres": [...], "analytiques": [...] }
|
| Usage : php tool/comptabilite/rejouer_grand_livre_analytique.php < jeu.json
*/

const BASE_AUTORISEE = 'tatacora_test';

// Une base d'ESSAI privee (`TATACORA_BASE_ESSAI=tatacora_<nom>_test`) peut
// remplacer `tatacora_test` : elle doit finir par `test`, la base de
// developpement reste refusee.
$baseEssai = (static function (): string {
    $voulue = getenv('TATACORA_BASE_ESSAI');

    return is_string($voulue) && preg_match('/^tatacora_[a-z0-9_]*test$/', $voulue) === 1
        ? $voulue
        : BASE_AUTORISEE;
})();

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$jeu = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($jeu) || ! isset($jeu['ecritures'], $jeu['exercices'], $jeu['aujourdhui'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

putenv('DB_DATABASE=' . $baseEssai);
$_ENV['DB_DATABASE'] = $baseEssai;
$_SERVER['DB_DATABASE'] = $baseEssai;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\Services\AnalytiqueService;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Domain\Comptabilite\Services\GrandLivreService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . $baseEssai . " \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow($jeu['aujourdhui'] . ' 10:00:00');

$statutsDe = static fn (string $filtre): array => match ($filtre) {
    'validee' => ['validee'],
    'brouillon' => ['brouillon'],
    default => ['brouillon', 'validee'],
};

$sortie = ['grands_livres' => [], 'analytiques' => []];

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

    $centres = [];

    foreach ($jeu['centres'] ?? [] as $c) {
        $centres[$c['libelle']] = (string) CentreCout::firstOrCreate(
            ['libelle' => $c['libelle']],
            ['type' => $c['type'] ?? 'operationnel'],
        )->id;
    }

    $maintenant = now();

    foreach ($jeu['ecritures'] as $i => $l) {
        DB::table('ecritures_comptables')->insert([
            'id' => (string) Str::uuid(),
            'exercice_id' => $exerciceIds[(int) $l['annee']],
            'journal_id' => (string) JournalComptable::where('code', $l['journal'])->firstOrFail()->id,
            'compte_id' => (string) CompteComptable::where('numero_compte', $l['compte'])->firstOrFail()->id,
            'centre_id' => $centres[$l['centre']],
            'date_ecriture' => $l['date'],
            'libelle' => 'Ligne ' . $i,
            'debit' => $l['debit'],
            'credit' => $l['credit'],
            'statut' => $l['statut'],
            'created_at' => $maintenant,
            'updated_at' => $maintenant,
        ]);
    }

    $livres = $app->make(GrandLivreService::class);
    $analytiques = $app->make(AnalytiqueService::class);

    foreach ($jeu['grands_livres'] ?? [] as $q) {
        $compte = CompteComptable::where('numero_compte', $q['compte'])->firstOrFail();
        $g = $livres->genererPourCompte(
            $exerciceIds[(int) $q['annee']],
            $compte,
            $statutsDe($q['filtre']),
            $q['filtre'],
        );
        $sortie['grands_livres'][] = [
            'annee' => (int) $q['annee'],
            'compte' => $q['compte'],
            'filtre' => $q['filtre'],
            'lignes' => array_map(static fn ($l): array => [
                'libelle' => (string) $l->ecriture->libelle,
                'debit' => (string) $l->ecriture->debit,
                'credit' => (string) $l->ecriture->credit,
                'solde' => $l->soldeProgressif,
            ], $g->lignes),
            'solde_mouvements' => $g->soldeMouvements,
            'solde_ouverture' => $g->soldeOuverture,
            'solde_cloture' => $g->soldeCloture,
            'ouverture_provisoire' => $g->ouvertureProvisoire,
            'annee_ouverture' => $g->anneeOuverture,
            'comptes_mouvementes' => $livres->comptesMouvementes(
                $exerciceIds[(int) $q['annee']],
                $statutsDe($q['filtre']),
            )->map(static fn ($c): string => (string) $c->numero_compte)->all(),
        ];
    }

    foreach ($jeu['analytiques'] ?? [] as $q) {
        $a = $analytiques->genererPourExercice(
            $exerciceIds[(int) $q['annee']],
            $statutsDe($q['filtre']),
            $q['filtre'],
        );
        $sortie['analytiques'][] = [
            'annee' => (int) $q['annee'],
            'filtre' => $q['filtre'],
            'centres' => array_map(static fn ($c): array => [
                'libelle' => $c->libelle,
                'type' => $c->type,
                'produits' => $c->produits,
                'charges' => $c->charges,
                'resultat' => $c->resultat,
                'taux' => $c->tauxMarge,
                'lignes' => $c->nombreLignes,
            ], $a->centres),
            'total_produits' => $a->totalProduits,
            'total_charges' => $a->totalCharges,
            'total_resultat' => $a->totalResultat,
        ];
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
