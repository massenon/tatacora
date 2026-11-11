<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI serveur, l'ANNULATION d'un contrat de location et ses
| conséquences (26/10/2026) : le serveur est l'ancrage des règles que le poste
| réplique (`VehiculeDao.annulerContrat`, `_contratsEnConflit`,
| `ArchivageClients.verrous`), jamais des phrases ou des règles recopiées.
|
| Sortie (stdout, JSON) :
|   chevauchement_avant      la phrase du refus RG-08 tant que le contrat est actif
|   annulation               "ok" quand `ContratLocationService::annuler` passe
|   statut_apres             le statut posé
|   disponible_apres         le véhicule est-il libre sur la plage après annulation ?
|   second_contrat_apres     "ok" : un contrat sur la même plage est accepté
|   double_annulation        la phrase quand on annule un contrat déjà annulé
|   archivage_vehicule_*     ParcVehiculeService::contratsEngages : nombre avant / après
|   verrous_client_*         ReferentielClientService::verrous : motifs avant / après
|   phrases                  la question de la modale, le succès et le verrou de la vue
|
| Dates : l'horloge est posée au 21/10/2026 ; le contrat court du 25 au 28.
| La base N'EST PAS un double : le script travaille sur `tatacora_test` (il REFUSE
| toute autre base, sauf une base d'essai PRIVÉE `tatacora_<nom>_test` donnée par
| `TATACORA_BASE_ESSAI`), puis ANNULE tout (rollback).
| Usage : php tool/vehicules/rejouer_annulation_contrat.php
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

putenv('DB_DATABASE=' . $baseEssai);
$_ENV['DB_DATABASE'] = $baseEssai;
$_SERVER['DB_DATABASE'] = $baseEssai;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\ReferentielClientService;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ContratLocationService;
use App\Domain\Vehicules\Services\ParcVehiculeService;
use App\Models\User;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow('2026-10-21 10:00:00');

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    $gerant = User::create([
        'login' => 'annulation.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'gerant')->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    Auth::login($gerant);

    $client = Client::create(['nom' => 'KORA', 'telephone' => '97000001', 'type_client' => 'particulier']);
    $vehicule = Vehicule::create([
        'immatriculation' => 'BJ-1', 'categorie' => 'voiture', 'annee' => 2020,
        'tarif_jour' => '25000', 'statut' => 'disponible',
    ]);

    $service = app(ContratLocationService::class);
    $parc = app(ParcVehiculeService::class);
    $clients = app(ReferentielClientService::class);

    $creer = static fn (string $debut, string $fin): ContratLocation => $service->creer([
        'vehicule_id' => $vehicule->id, 'client_id' => $client->id,
        'date_debut' => $debut, 'date_fin' => $fin,
        'piece_identite' => 'CNI-1', 'permis_conduire' => 'P-1',
    ]);

    $sortie = [];
    $contrat = $creer('2026-10-25', '2026-10-28');
    $contrat->forceFill(['statut' => 'actif'])->save();

    $sortie['engages_avant'] = $parc->contratsEngages($vehicule)->count();
    $sortie['verrous_client_avant'] = $clients->verrous($client);

    try {
        $creer('2026-10-26', '2026-10-27');
        $sortie['chevauchement_avant'] = null;
    } catch (ChevauchementDetecteException $e) {
        $sortie['chevauchement_avant'] = $e->getMessage();
    }

    $service->annuler($contrat);
    $sortie['annulation'] = 'ok';
    $sortie['statut_apres'] = $contrat->fresh()->statut;
    $sortie['disponible_apres'] = $service->estDisponible($vehicule->id, '2026-10-25', '2026-10-28');

    $second = $creer('2026-10-26', '2026-10-27');
    $sortie['second_contrat_apres'] = $second->exists ? 'ok' : 'ko';

    try {
        $service->annuler($contrat->fresh());
        $sortie['double_annulation'] = null;
    } catch (RuntimeException $e) {
        $sortie['double_annulation'] = $e->getMessage();
    }

    // Le second contrat est actif et court encore : il engage. Annulé, plus rien.
    $second->forceFill(['statut' => 'actif'])->save();
    $sortie['engages_apres_un_actif'] = $parc->contratsEngages($vehicule)->count();
    $service->annuler($second->fresh());
    $sortie['engages_apres_annulation'] = $parc->contratsEngages($vehicule)->count();
    $sortie['verrous_client_apres'] = $clients->verrous($client->fresh());
    $sortie['rows_conservees'] = ContratLocation::query()->count();

    // Les phrases de la vue (modale d'archivage, message de succès, verrou), telles
    // que le serveur les rend pour l'élément « AB 1234 RB ».
    $sortie['phrases'] = [
        'question' => __('vehicules.pwa.archiver_contrat', ['element' => 'AB 1234 RB']),
        'succes' => __('vehicules.pwa.archivage_contrat_fait', ['numero' => 'AB 1234 RB']),
        'deja_annule' => __('vehicules.pwa.verrou_contrat_annule'),
    ];

    echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}
