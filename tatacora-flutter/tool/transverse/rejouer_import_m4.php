<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI `ControleImportService` et la VRAIE définition
| `ReferentielsImport` du serveur, l'import du module M4 « Carte du restaurant »
| (28/10/2026) : la colonne « Catégorie » (liste fermée des dix clés de la carte,
| `CarteRestaurant::CATEGORIES`), obligatoire, et la façon dont le contrôle la
| juge. Le serveur est l'ancrage de la colonne que le poste réplique, jamais une
| liste recopiée.
|
| Entrée (stdin, JSON) : { "tableaux": [ [ [en-tête...], [ligne...], ... ], ... ] }
| Sortie (stdout, JSON) :
|   { "colonnes": [ {champ, libelle, requis, type, valeurs, reference, exemple} ],
|     "rapports": [ {ok, erreurs: [{ligne, colonne, message}], avertissements, categories: [...]} ] }
|
| Le script travaille sur `tatacora_test` (il REFUSE toute autre base, sauf une
| base d'essai PRIVÉE `tatacora_<nom>_test` donnée par `TATACORA_BASE_ESSAI`),
| puis ANNULE tout (rollback).
| Usage : php tool/transverse/rejouer_import_m4.php < scenario.json
*/

const BASE_AUTORISEE = 'tatacora_test';

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

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['tableaux'])) {
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

use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Shared\ImportExport\Data\ReferentielsImport;
use App\Shared\ImportExport\Services\ControleImportService;
use Illuminate\Support\Facades\DB;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

DB::beginTransaction();

try {
    // Les références que la colonne « Menu » / « Fiche recette » résout.
    app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Menu local', 'type' => 'local']);
    app(ReferentielRecetteService::class)->creer(['libelle' => 'Poulet DG']);

    $module = ReferentielsImport::parCle('m4-restaurant');

    if ($module === null) {
        fwrite(STDERR, "Module m4-restaurant introuvable.\n");
        exit(4);
    }

    $colonnes = array_map(static fn ($c): array => [
        'champ' => $c->champ, 'libelle' => $c->libelle, 'requis' => $c->requis, 'type' => $c->type,
        'valeurs' => $c->valeurs, 'reference' => $c->reference, 'exemple' => $c->exemple,
    ], $module->colonnes);

    $rapports = [];

    foreach ($scenario['tableaux'] as $tableau) {
        $r = app(ControleImportService::class)->controler($module, $tableau);
        $rapports[] = [
            'ok' => $r->ok,
            'erreurs' => $r->erreurs,
            'avertissements' => $r->avertissements,
            'categories' => array_map(static fn (array $l): mixed => $l['categorie'] ?? null, $r->lignes),
        ];
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['colonnes' => $colonnes, 'rapports' => $rapports], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
