<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI composant `ImportExport`, l'onglet « Restaurer » (27/10/2026,
| lot A4 du poste) : le registre DÉRIVÉ des unités d'hébergement et des
| véhicules `hors_service` (`RegistreArchivesService`), le geste
| `restaurerArchive`, le filtre et la recherche. Le serveur est l'ancrage des
| règles que le poste réplique, jamais une liste recopiée.
|
| Entrée (stdin, JSON) : { "monde": {...}, "ops": [...] }
|   monde.unites    [{numero, archivee: bool}]
|   monde.vehicules [{immatriculation, archive: bool}]
|   ops: {"op":"vue","filtre":"restaurables|toutes|restaurees","recherche":"…"}
|        {"op":"restaurer","type":"unite_hebergement|vehicule","ref":"<numero|immat>"}
|        {"op":"libelles"}
| Sortie (stdout, JSON) : { "resultats": [ ... un par opération ... ] }
|
| Le script travaille sur `tatacora_test` (il REFUSE toute autre base, sauf une
| base d'essai PRIVÉE `tatacora_<nom>_test` donnée par `TATACORA_BASE_ESSAI`),
| puis ANNULE tout (rollback).
| Usage : php tool/transverse/rejouer_archives.php < scenario.json
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

use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Shared\ImportExport\Services\RegistreArchivesService;
use App\Shared\Rbac\Models\Role;
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

    $admin = User::create([
        'login' => 'admin.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
        'statut' => 'actif',
    ]);

    $categorie = (string) Str::uuid();
    DB::table('categories_hebergement')->insert([
        'id' => $categorie, 'libelle' => 'Standard', 'capacite_max' => 2, 'tarif_base' => '10000.00',
        'created_at' => now(), 'updated_at' => now(),
    ]);

    $ids = ['unite_hebergement' => [], 'vehicule' => []];

    foreach ($monde['unites'] ?? [] as $u) {
        $ids['unite_hebergement'][$u['numero']] = (string) Str::uuid();
        DB::table('unites_hebergement')->insert([
            'id' => $ids['unite_hebergement'][$u['numero']], 'categorie_id' => $categorie, 'numero' => $u['numero'],
            'statut' => $u['archivee'] ? 'hors_service' : 'libre',
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    foreach ($monde['vehicules'] ?? [] as $v) {
        $ids['vehicule'][$v['immatriculation']] = (string) Str::uuid();
        DB::table('vehicules')->insert([
            'id' => $ids['vehicule'][$v['immatriculation']], 'categorie' => 'voiture',
            'immatriculation' => $v['immatriculation'], 'tarif_jour' => '20000.00', 'annee' => 2020,
            'statut' => $v['archive'] ? 'hors_service' : 'disponible',
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    $resume = static function (array $entrees): array {
        return array_map(static fn (array $e): array => [
            'type' => $e['type'],
            'libelle' => $e['libelle'],
            'module' => $e['module'],
            'restaure' => $e['restaure'],
            'a_une_date' => $e['archive_le'] !== null,
            'par_present' => $e['archive_par'] !== null,
        ], $entrees);
    };

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'vue':
                    $c = Livewire::actingAs($admin)->test(ImportExport::class)
                        ->set('onglet', 'restaurer')
                        ->set('filtreArchives', $op['filtre'])
                        ->set('rechercheArchives', $op['recherche']);
                    $resultats[] = [
                        'lignes' => $resume($c->viewData('archives')),
                        'nombre_restaurables' => $c->viewData('nombreRestaurables'),
                    ];
                    break;

                case 'restaurer':
                    $c = Livewire::actingAs($admin)->test(ImportExport::class)
                        ->call('restaurerArchive', $op['type'], $ids[$op['type']][$op['ref']] ?? (string) Str::uuid());
                    $resultats[] = [
                        'erreur' => $c->errors()->get('archives')[0] ?? null,
                        'succes' => session('pwa-succes'),
                        'statut_apres' => $op['type'] === 'unite_hebergement'
                            ? UniteHebergement::query()->where('numero', $op['ref'])->value('statut')
                            : Vehicule::query()->where('immatriculation', $op['ref'])->value('statut'),
                    ];
                    break;

                case 'libelles':
                    $resultats[] = ['mots' => [
                        'restaurer_titre' => __('pwa.import_export.restaurer_titre'),
                        'restaurer_texte' => __('pwa.import_export.restaurer_texte'),
                        'recherche_archives' => __('pwa.import_export.recherche_archives'),
                        'filtre_restaurables' => __('pwa.import_export.filtre_restaurables'),
                        'filtre_toutes' => __('pwa.import_export.filtre_toutes'),
                        'filtre_restaurees' => __('pwa.import_export.filtre_restaurees'),
                        'col_element' => __('pwa.import_export.col_element'),
                        'col_module' => __('pwa.import_export.col_module'),
                        'col_archive_le' => __('pwa.import_export.col_archive_le'),
                        'col_par' => __('pwa.import_export.col_par'),
                        'col_action' => __('pwa.import_export.col_action'),
                        'archives_vide' => __('pwa.import_export.archives_vide'),
                        'action_restaurer' => __('pwa.import_export.action_restaurer'),
                        'badge_restaure' => __('pwa.import_export.badge_restaure'),
                        'archive_restauree' => __('pwa.import_export.archive_restauree', ['element' => ':element']),
                    ], 'types' => RegistreArchivesService::TYPES];
                    break;

                default:
                    fwrite(STDERR, "Operation inconnue : {$op['op']}\n");
                    exit(5);
            }
        } catch (Throwable $e) {
            $resultats[] = [
                'refus' => (new ReflectionClass($e))->getShortName(),
                'message' => $e->getMessage(),
            ];
        }
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
