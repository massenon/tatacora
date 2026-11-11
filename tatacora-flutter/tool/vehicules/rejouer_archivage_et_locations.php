<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI serveur, la règle UNIQUE d'archivage d'un véhicule
| (`ParcVehiculeService::contratsEngages` : `date_fin >= aujourd'hui` ET
| `statut != annule`) et l'état M14 « Locations » (`EtatLocations` : contrats
| annulés exclus), pour le test de parité du poste (PRD corrections, B1/B2).
|
| Sortie (stdout, JSON) :
|   engages     { fin_hier, fin_aujourdhui, fin_demain, annule } : nombre de
|               contrats engageant le véhicule de chaque cas
|   etat        { nombre, montant, lignes, periode, entetes } : l'état « Locations »
|               du même jeu, case « Inclure les contrats annulés » DÉCOCHÉE
|   etat_inclus  la même forme, case COCHÉE (`inclure_annules` = 1) : `cellules`
|               porte les lignes entières (annulé listé à part, montant vide,
|               statut), `kpis` les totaux (identiques à `etat` : un annulé n'est
|               jamais compté)
|
| Horloge posée au 21/10/2026. La base N'EST PAS un double : le script REFUSE
| toute base autre que `tatacora_test` (ou une base d'essai PRIVÉE
| `tatacora_<nom>_test` donnée par `TATACORA_BASE_ESSAI`), puis ANNULE tout.
| Usage : php tool/vehicules/rejouer_archivage_et_locations.php
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
use App\Domain\Vehicules\Etats\EtatLocations;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ParcVehiculeService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow('2026-10-21 10:00:00');

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    $client = Client::create(['nom' => 'KORA', 'telephone' => '97000001', 'type_client' => 'particulier']);
    $parc = app(ParcVehiculeService::class);

    // Un véhicule par cas (RG-08 : pas de chevauchement sur un même véhicule).
    $cas = [
        'fin_hier' => ['2026-10-18', '2026-10-20', 'actif'],
        'fin_aujourdhui' => ['2026-10-19', '2026-10-21', 'actif'],
        'fin_demain' => ['2026-10-19', '2026-10-22', 'actif'],
        'annule' => ['2026-10-25', '2026-10-28', 'annule'],
    ];

    $sortie = ['engages' => []];
    $n = 0;

    foreach ($cas as $nom => [$debut, $fin, $statut]) {
        $n++;
        $vehicule = Vehicule::create([
            'immatriculation' => 'BJ-' . $n, 'categorie' => 'voiture', 'annee' => 2020,
            'tarif_jour' => '10000', 'statut' => 'disponible',
        ]);
        $contrat = ContratLocation::create([
            'vehicule_id' => $vehicule->id, 'client_id' => $client->id,
            'date_debut' => $debut, 'date_fin' => $fin,
        ]);
        $contrat->forceFill(['statut' => $statut])->save();
        $sortie['engages'][$nom] = $parc->contratsEngages($vehicule)->count();
    }

    $etat = (new EtatLocations())->calculer([]);
    $valeurs = array_values($etat->kpis);
    $sortie['etat'] = [
        'nombre' => $valeurs[0],
        'montant' => $valeurs[1],
        'lignes' => array_map(static fn (array $l): string => (string) $l[1], $etat->lignes),
    ];

    $inclus = (new EtatLocations())->calculer(['inclure_annules' => '1']);
    $valeursInclus = array_values($inclus->kpis);
    $sortie['etat_inclus'] = [
        'nombre' => $valeursInclus[0],
        'montant' => $valeursInclus[1],
        'lignes' => array_map(static fn (array $l): string => (string) $l[1], $inclus->lignes),
        'periode' => (new EtatLocations())->periode(['inclure_annules' => '1']),
        'entetes' => $inclus->entetes,
        'cellules' => $inclus->lignes,
    ];
    $sortie['etat']['periode'] = (new EtatLocations())->periode([]);
    $sortie['etat']['entetes'] = $etat->entetes;
    $sortie['etat']['cellules'] = $etat->lignes;

    echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}
