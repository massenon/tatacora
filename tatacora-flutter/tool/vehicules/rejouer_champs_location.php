<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI moteur de synchronisation du serveur, les champs que le poste
| porte depuis la v41 (27/10/2026, lot L3) : année, places et transmission d'un
| véhicule, remise / acompte / montant figé / N° `LOC-` d'un contrat, catégorie d'un
| plat. Le serveur est l'ancrage des bornes et des PHRASES que le poste réplique
| (`VehiculeDao`, `RestaurantDao`), jamais des textes recopiés.
|
| Sortie (stdout, JSON) :
|   annee_max          l'an prochain, borne haute de l'année d'un véhicule
|   refus              nom du cas => la phrase du serveur (motif de l'opération rejetée)
|   vehicule_ok        ce que le serveur a rangé pour un véhicule complet
|   contrat_ok         montant net, acompte, reste dû, N° pour remise + acompte
|   contrat_gratuit    remise = brut (bornes incluses)
|   categories         les dix clés du registre fermé de la carte (et categories_libelles)
|   plat_ok            la catégorie rangée
|
| La base N'EST PAS un double : le script travaille sur `tatacora_test` (il REFUSE
| toute autre base, sauf une base d'essai PRIVÉE `tatacora_<nom>_test` donnée par
| `TATACORA_BASE_ESSAI`), puis ANNULE tout (rollback).
| Usage : php tool/vehicules/rejouer_champs_location.php
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
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Pwa\Livewire\Restaurant\CarteRestaurant;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Services\SynchronisationService;
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

Carbon::setTestNow('2026-10-27 10:00:00');

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    $admin = User::create([
        'login' => 'champs.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    Auth::login($admin);

    $service = $app->make(SynchronisationService::class);

    /** Pousse UNE opération et rend son résultat. */
    $pousser = static function (string $table, string $type, string $id, array $payload) use ($service, $admin): array {
        $lot = [[
            'uuid_operation' => (string) Str::uuid(), 'table' => $table, 'type' => $type, 'entite_id' => $id,
            'payload' => $payload, 'horodatage_client' => '2026-10-27T10:00:00+00:00',
        ]];

        return $service->traiterLot('poste-essai', $lot, (string) $admin->id)['resultats'][0];
    };

    $motif = static fn (array $r): ?string => ($r['statut'] ?? null) === 'rejete' ? (string) ($r['motif'] ?? '') : null;
    $sortie = ['annee_max' => (int) date('Y') + 1, 'refus' => []];

    // ------------------------------------------------------------ véhicule
    $vehiculeId = (string) Str::uuid();
    $complet = [
        'immatriculation' => 'BJ-L3', 'categorie' => 'voiture', 'tarif_jour' => 25000,
        'annee' => 2021, 'capacite' => 5, 'transmission' => 'Manuelle',
    ];
    $r = $pousser('vehicules', 'creation', $vehiculeId, $complet);
    $v = Vehicule::findOrFail($vehiculeId);
    $sortie['vehicule_ok'] = [
        'statut_op' => $r['statut'], 'annee' => (int) $v->annee, 'capacite' => (int) $v->capacite,
        'transmission' => $v->transmission, 'tarif_jour' => (string) $v->tarif_jour,
    ];

    foreach ([
        'annee_trop_ancienne' => ['annee' => 1949],
        'annee_trop_recente' => ['annee' => $sortie['annee_max'] + 1],
        'annee_texte' => ['annee' => 'abc'],
        'annee_nulle' => ['annee' => null],
        'places_zero' => ['capacite' => 0],
        'places_cent' => ['capacite' => 100],
        'places_texte' => ['capacite' => 'abc'],
        'places_nulles' => ['capacite' => null],
        'transmission_longue' => ['transmission' => str_repeat('x', 256)],
    ] as $cas => $champs) {
        $sortie['refus']['modif_' . $cas] = $motif($pousser('vehicules', 'modification', $vehiculeId, $champs));
    }

    // À la création aussi : une année hors bornes est refusée.
    $sortie['refus']['creation_annee_trop_ancienne'] = $motif($pousser('vehicules', 'creation', (string) Str::uuid(), [
        ...$complet, 'immatriculation' => 'BJ-L3B', 'annee' => 1949,
    ]));

    // ------------------------------------------------------------- contrat
    $client = Client::create(['nom' => 'KORA', 'telephone' => '97000001', 'type_client' => 'particulier']);
    $contrat = static fn (array $plus, string $debut = '2026-11-01', string $fin = '2026-11-04', ?string $vehicule = null): array => [
        'vehicule_id' => $vehicule ?? $vehiculeId, 'client_id' => $client->id, 'date_debut' => $debut, 'date_fin' => $fin,
        'piece_identite' => 'CNI-1', 'permis_conduire' => 'P-1', ...$plus,
    ];

    // 3 jours x 25 000 = 75 000 brut.
    $sortie['refus']['remise_superieure_au_brut'] = $motif($pousser('contrats_location', 'creation', (string) Str::uuid(), $contrat(['remise' => 75001])));
    $sortie['refus']['acompte_superieur_au_net'] = $motif($pousser('contrats_location', 'creation', (string) Str::uuid(), $contrat(['remise' => 5000, 'acompte' => 70001])));
    $sortie['refus']['remise_negative'] = $motif($pousser('contrats_location', 'creation', (string) Str::uuid(), $contrat(['remise' => -1])));
    $sortie['refus']['acompte_negatif'] = $motif($pousser('contrats_location', 'creation', (string) Str::uuid(), $contrat(['acompte' => -1])));

    $lire = static function (string $id): array {
        $c = DB::table('contrats_location')->where('id', $id)->first();

        return [
            'montant' => (string) $c->montant, 'acompte' => (string) $c->acompte,
            'reste_a_payer' => (string) $c->reste_a_payer, 'numero' => (string) $c->numero, 'statut' => (string) $c->statut,
        ];
    };

    $a = (string) Str::uuid();
    $r = $pousser('contrats_location', 'creation', $a, $contrat(['remise' => 5000, 'acompte' => 20000]));
    $sortie['contrat_ok'] = [...$lire($a), 'statut_op' => $r['statut'], 'numero_accuse' => $r['numero'] ?? null, 'montant_accuse' => $r['montant'] ?? null];

    $b = (string) Str::uuid();
    $r = $pousser('contrats_location', 'creation', $b, $contrat(['remise' => 75000, 'acompte' => 0], '2026-12-01', '2026-12-04'));
    $sortie['contrat_gratuit'] = [...$lire($b), 'statut_op' => $r['statut']];

    // ---------------------------------------------------------------- plat
    $menu = app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Carte', 'type' => 'local']);
    $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Riz gras']);
    $plat = static fn (array $plus): array => [
        'libelle' => 'Plat ' . Str::random(4), 'menu_id' => $menu->id, 'recette_id' => $fiche->id, 'prix_vente' => 1000, ...$plus,
    ];
    $sortie['categories'] = array_keys(CarteRestaurant::CATEGORIES);
    $sortie['categories_libelles'] = CarteRestaurant::CATEGORIES;
    $sortie['refus']['categorie_inconnue'] = $motif($pousser('plats', 'creation', (string) Str::uuid(), $plat(['categorie' => 'Plats'])));
    $platId = (string) Str::uuid();
    $r = $pousser('plats', 'creation', $platId, $plat(['categorie' => 'sandwicherie']));
    $sortie['plat_ok'] = ['statut_op' => $r['statut'], 'categorie' => DB::table('plats')->where('id', $platId)->value('categorie')];
    $sortie['refus']['categorie_modif_inconnue'] = $motif($pousser('plats', 'modification', $platId, ['categorie' => 'inconnue']));
    $sortie['refus']['categorie_modif_nulle'] = $motif($pousser('plats', 'modification', $platId, ['categorie' => null]));

    echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}
