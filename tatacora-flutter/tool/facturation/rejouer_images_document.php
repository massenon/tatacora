<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI moteur de synchronisation du serveur, le dépôt et le retrait de la
| signature et du cachet des documents A4 faits DEPUIS UN POSTE (11/11/2026, décision du PO),
| et rend ce que la descente `GET /sync/apparence-documents` livrerait ensuite aux postes.
| Le test `signature_cachet_contre_serveur_test.dart` pousse les opérations EXACTES que la file
| du poste a enfilées.
|
| Entrée (stdin, JSON) :
|   { "operations": [ {uuid_operation, table, type, entite_id, payload, horodatage_client} ],
|     "prealable": { "signature": "<base64>|null", "cachet": "<base64>|null" } }
|   `prealable` : images déposées AU SERVEUR (comme le web) avant les opérations.
| Sortie (stdout, JSON) :
|   { "resultats": [ {statut, motif, ...} ],
|     "descente": { "signature": {empreinte, octets_base64}|null, "cachet": ... } }
|
| Garde-fous : base `tatacora_test` seulement (ou la base PRIVÉE `tatacora_<nom>_test` de
| `TATACORA_BASE_ESSAI`) ; le disque `public` est détourné vers un dossier temporaire, effacé
| ensuite ; la transaction est annulée.
| Usage : php tool/facturation/rejouer_images_document.php < scenario.json
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

if (! is_array($scenario) || ! isset($scenario['operations'])) {
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

use App\Models\User;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Services\SynchronisationService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

$tmp = sys_get_temp_dir() . '/tatacora_images_' . Str::random(8);
mkdir($tmp, 0777, true);
config(['filesystems.disks.public.root' => $tmp]);
Storage::forgetDisk('public');

$sortie = [];
DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    // Le compte du jeton d'appairage est un BARMAN : aucun module PARAM, et le serveur ne juge pas.
    $barman = User::create([
        'login' => 'img.' . Str::random(8),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'barman')->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    $apparence = app(ApparenceEtablissementService::class);

    foreach (($scenario['prealable'] ?? []) as $nature => $base64) {
        if (is_string($base64)) {
            $apparence->enregistrerImageDocument((string) $nature, (string) base64_decode($base64, true));
        }
    }

    Auth::login($barman);
    $resultats = app(SynchronisationService::class)
        ->traiterLot('poste-essai', $scenario['operations'], (string) $barman->id)['resultats'];

    $sortie['resultats'] = $resultats;
    $sortie['descente'] = [];

    foreach (ApparenceEtablissementService::IMAGES_DOCUMENT as $nature) {
        $octets = $apparence->octetsImageDocument($nature);
        $sortie['descente'][$nature] = $octets === null ? null : [
            'empreinte' => $apparence->empreinteImageDocument($nature),
            'octets_base64' => base64_encode($octets),
        ];
    }
} finally {
    Auth::logout();
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
    Storage::deleteDirectory('');
    @array_map('unlink', glob($tmp . '/*/*') ?: []);
    @array_map('rmdir', glob($tmp . '/*') ?: []);
    @rmdir($tmp);
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
