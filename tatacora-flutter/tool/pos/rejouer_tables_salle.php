<?php

declare(strict_types=1);

/*
| Les DROITS des tables de salle, CONTRE le vrai moteur du serveur (09/11/2026,
| bogue du PO : le barman du poste A, trois « Droit manquant » sur « Tables de
| salle » dans « À traiter »).
|
| Le poste enfile une `creation` de table (`assurerConnueDuServeur`) au premier
| geste d'USAGE qui la cite — prendre une table au point de vente avant d'avoir
| reçu la salle du serveur. Le serveur juge chaque opération sur le compte du
| JETON D'APPAIRAGE : ce script pousse des ETAPES, chacune sous le compte d'un
| RÔLE de la matrice (`RolePermissionSeeder::MATRICE`), au vrai
| `SynchronisationService::traiterLot`, sur une salle SEMÉE PAR LE VRAI seeder
| (`TablesSalleSeeder`, les treize tables du jeu initial) — le serveur qui a
| déjà sa salle, comme en exploitation.
|
| Entrée (stdin, JSON) :
|   { "poste_id": "poste-a",
|     "etapes": [ { "role": "barman", "operations": [ {uuid_operation, table, type,
|                                                      entite_id, payload,
|                                                      horodatage_client}, ... ] } ] }
| Sortie (stdout, JSON) :
|   { "etapes": [ { "resultats": [ ... ], "tables": <nombre de tables>,
|                   "paniers_ouverts": <nombre> } ] }
|
| Base : `tatacora_test`, ou la base PRIVÉE `TATACORA_BASE_ESSAI=tatacora_<nom>_test`
| (le nom doit finir par `test`). Tout est ANNULÉ à la fin (rollback).
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

$entree = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($entree) || ! isset($entree['poste_id'], $entree['etapes']) || ! is_array($entree['etapes'])) {
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

use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\TableSalle;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Http\Requests\SynchroniserRequest;
use App\Shared\Sync\Services\SynchronisationService;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\TablesSalleSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow('2026-11-09 20:00:00');

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    // Le serveur A DÉJÀ sa salle : le jeu initial, par le vrai seeder.
    if (TableSalle::query()->count() === 0) {
        (new TablesSalleSeeder())->run();
    }

    /** @var array<string, User> $comptes un compte par rôle */
    $comptes = [];
    $sortie = ['etapes' => []];

    foreach ($entree['etapes'] as $etape) {
        $role = (string) $etape['role'];
        $roleModele = Role::where('libelle', $role)->first();

        if ($roleModele === null) {
            fwrite(STDERR, "Role inconnu : {$role}\n");
            exit(4);
        }

        $compte = $comptes[$role] ??= User::create([
            'login' => 'jeton.' . $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $roleModele->id,
            'statut' => 'actif',
        ]);
        Auth::login($compte);

        $resultats = [];

        foreach (array_chunk($etape['operations'], 50) as $morceau) {
            $enveloppe = Validator::make(
                ['poste_id' => $entree['poste_id'], 'operations' => $morceau],
                (new SynchroniserRequest())->rules(),
            );

            if ($enveloppe->fails()) {
                fwrite(STDERR, 'Enveloppe refusee : ' . json_encode($enveloppe->errors()->toArray()) . "\n");
                exit(5);
            }

            $traite = $app->make(SynchronisationService::class)
                ->traiterLot((string) $entree['poste_id'], $morceau, (string) $compte->id);
            $resultats = [...$resultats, ...$traite['resultats']];
        }

        $sortie['etapes'][] = [
            'resultats' => $resultats,
            'tables' => TableSalle::query()->count(),
            'paniers_ouverts' => Panier::query()->where('statut', Panier::STATUT_OUVERT)->count(),
        ];
    }

    echo json_encode($sortie, JSON_UNESCAPED_UNICODE);
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}
