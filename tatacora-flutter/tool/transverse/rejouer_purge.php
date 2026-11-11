<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI composant `ImportExport` et le VRAI `RegistreArchivesService`,
| la PURGE définitive d'une unité d'hébergement ou d'un véhicule archivé (28/10/2026,
| lot A5 du poste) : le bouton « Purger » (`ouvrirPurge` puis `purgerArchive`,
| réservé au super_admin), ses verrous (non archivé, engagé, cité par un
| enregistrement passé) et ses phrases. Le serveur est l'ancrage des règles que le
| poste réplique, jamais une liste recopiée.
|
| Entrée (stdin, JSON) : { "monde": {...}, "ops": [...] }
|   monde.unites    [{numero, archivee, reservations: [{debut, fin, statut}]}]
|   monde.vehicules [{immatriculation, archive, contrats: [{debut, fin, annule, numero}],
|                     entretiens: n}]
|   (debut / fin : décalage en JOURS par rapport à aujourd'hui)
|   ops: {"op":"composant","type":"unite_hebergement|vehicule","ref":"<numero|immat>","role":"super_admin|administrateur"}
|          -> ouvrirPurge puis purgerArchive, comme le clic
|        {"op":"service","type":"…","ref":"…"}   -> RegistreArchivesService::purger
|        {"op":"libelles"}
| Sortie (stdout, JSON) : { "resultats": [ ... un par opération ... ] }
|
| Le script travaille sur `tatacora_test` (il REFUSE toute autre base, sauf une
| base d'essai PRIVÉE `tatacora_<nom>_test` donnée par `TATACORA_BASE_ESSAI`),
| puis ANNULE tout (rollback).
| Usage : php tool/transverse/rejouer_purge.php < scenario.json
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

if (! is_array($scenario) || ! isset($scenario['ops'], $scenario['monde'])) {
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

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Shared\ImportExport\Services\RegistreArchivesService;
use App\Shared\Rbac\Models\Role;
use Carbon\CarbonImmutable;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

$monde = $scenario['monde'];
$resultats = [];

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    $compte = static fn (string $role): User => User::create([
        'login' => $role . '.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    $comptes = ['super_admin' => $compte('super_admin'), 'administrateur' => $compte('administrateur')];

    $categorie = (string) Str::uuid();
    DB::table('categories_hebergement')->insert([
        'id' => $categorie, 'libelle' => 'Standard', 'capacite_max' => 2, 'tarif_base' => '10000.00',
        'created_at' => now(), 'updated_at' => now(),
    ]);
    $client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'particulier']);
    $jour = static fn (int $decalage): string => CarbonImmutable::today()->addDays($decalage)->toDateString();

    $ids = ['unite_hebergement' => [], 'vehicule' => []];

    foreach ($monde['unites'] ?? [] as $u) {
        $unite = UniteHebergement::create([
            'numero' => $u['numero'], 'categorie_id' => $categorie,
            'statut' => $u['archivee'] ? 'hors_service' : 'libre',
        ]);
        $ids['unite_hebergement'][$u['numero']] = $unite->id;

        foreach ($u['reservations'] ?? [] as $r) {
            Reservation::create([
                'client_id' => $client->id, 'unite_id' => $unite->id,
                'date_arrivee' => $jour($r['debut']), 'date_depart' => $jour($r['fin']), 'statut' => $r['statut'],
            ]);
        }
    }

    foreach ($monde['vehicules'] ?? [] as $v) {
        $vehicule = Vehicule::create([
            'categorie' => 'voiture', 'immatriculation' => $v['immatriculation'], 'tarif_jour' => '20000.00',
            'annee' => 2020, 'statut' => $v['archive'] ? 'hors_service' : 'disponible',
        ]);
        $ids['vehicule'][$v['immatriculation']] = $vehicule->id;

        foreach ($v['contrats'] ?? [] as $c) {
            $contrat = ContratLocation::create([
                'vehicule_id' => $vehicule->id, 'client_id' => $client->id,
                'date_debut' => $jour($c['debut']), 'date_fin' => $jour($c['fin']),
                'piece_identite' => 'CNI', 'permis_conduire' => 'P',
            ]);
            $contrat->forceFill(['numero' => $c['numero'], 'statut' => ($c['annule'] ?? false) ? 'annule' : 'actif'])->save();
        }

        for ($i = 0; $i < ($v['entretiens'] ?? 0); $i++) {
            DB::table('entretiens_vehicule')->insert([
                'id' => (string) Str::uuid(), 'vehicule_id' => $vehicule->id, 'type' => 'entretien',
                'date' => $jour(-30), 'cout' => '15000.00', 'created_at' => now(), 'updated_at' => now(),
            ]);
        }
    }

    $existe = static function (string $type, string $ref) use ($ids): bool {
        $id = $ids[$type][$ref] ?? null;

        return $id !== null && ($type === 'unite_hebergement'
            ? UniteHebergement::query()->whereKey($id)->exists()
            : Vehicule::query()->whereKey($id)->exists());
    };

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'composant':
                    session()->forget('pwa-succes');
                    $c = Livewire::actingAs($comptes[$op['role']])->test(ImportExport::class)
                        ->set('onglet', 'restaurer')
                        ->call('ouvrirPurge', $op['type'], $ids[$op['type']][$op['ref']] ?? (string) Str::uuid())
                        ->call('purgerArchive');
                    $resultats[] = [
                        'erreur' => $c->errors()->get('purge')[0] ?? null,
                        'succes' => session('pwa-succes'),
                        'existe_apres' => $existe($op['type'], $op['ref']),
                    ];
                    break;

                case 'service':
                    try {
                        $libelle = app(RegistreArchivesService::class)->purger($op['type'], $ids[$op['type']][$op['ref']] ?? (string) Str::uuid());
                        $resultats[] = ['erreur' => null, 'libelle' => $libelle, 'existe_apres' => $existe($op['type'], $op['ref'])];
                    } catch (RuntimeException $e) {
                        $resultats[] = ['erreur' => $e->getMessage(), 'existe_apres' => $existe($op['type'], $op['ref'])];
                    }
                    break;

                case 'libelles':
                    $resultats[] = ['mots' => [
                        'action_purger' => __('pwa.import_export.action_purger'),
                        'purge_titre' => __('pwa.import_export.purge_titre'),
                        'purge_message' => __('pwa.import_export.purge_message'),
                        'purge_detail' => __('pwa.import_export.purge_detail'),
                        'purge_confirmer' => __('pwa.import_export.purge_confirmer'),
                        'archive_purgee' => __('pwa.import_export.archive_purgee', ['element' => ':element']),
                        'purge_refusee_non_archive' => __('pwa.import_export.purge_refusee_non_archive'),
                        'purge_refusee_referencee' => __('pwa.import_export.purge_refusee_referencee'),
                    ]];
                    break;

                default:
                    fwrite(STDERR, "Operation inconnue : {$op['op']}\n");
                    exit(5);
            }
        } catch (Throwable $e) {
            $resultats[] = [
                'refus' => (new ReflectionClass($e))->getShortName(),
                'message' => $e->getMessage(),
                'existe_apres' => isset($op['type'], $op['ref']) ? $existe($op['type'], $op['ref']) : null,
            ];
        }
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
