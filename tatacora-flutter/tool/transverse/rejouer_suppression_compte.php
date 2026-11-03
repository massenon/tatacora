<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI `SuppressionCompteService` du serveur, la règle d'autorité
| de « Supprimer un compte » (décision du PO du 03/11/2026) : qui peut supprimer
| (un super administrateur), qui peut l'être (un compte non administrateur), jamais
| soi-même. Le poste (`ComptesUtilisateursDao.supprimerCompte`) réplique cette
| règle ; le test `suppression_compte_contre_serveur_test.dart` compare les deux,
| cas par cas — jamais une liste recopiée.
|
| Entrée (stdin, JSON) : { "ops": [ ... ] }
|   {"op":"compte","ref":"x","role":"barman"}
|   {"op":"supprimer","auteur":"x","cible":"y"}
|   {"op":"libelles"}   (les phrases `pwa.comptes.*` de la suppression)
| Sortie (stdout, JSON) : { "resultats": [ ... un par opération ... ] }
|   supprimer : { "refus": "<phrase>"|null, "supprime": bool }
|
| La base N'EST PAS un double : le script travaille sur `tatacora_test` (il REFUSE
| toute autre base, sauf une base d'essai PRIVÉE `tatacora_<nom>_test` donnée par
| `TATACORA_BASE_ESSAI`), puis ANNULE tout (rollback).
| Usage : php tool/transverse/rejouer_suppression_compte.php < scenario.json
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

if (! is_array($scenario) || ! isset($scenario['ops'])) {
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
use App\Shared\Auth\Services\SuppressionCompteService;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est " . $base . ", pas " . $baseEssai . ".\n");
    exit(1);
}

/** @var array<string, User> $comptes */
$comptes = [];
$resultats = [];

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    $service = app(SuppressionCompteService::class);

    foreach ($scenario['ops'] as $op) {
        switch ($op['op']) {
            case 'compte':
                $comptes[$op['ref']] = User::create([
                    'login' => $op['ref'] . '.' . Str::random(6),
                    'mot_de_passe_hash' => Hash::make('mot-de-passe-correct'),
                    'role_id' => Role::where('libelle', $op['role'])->firstOrFail()->id,
                    'statut' => 'actif',
                ]);
                $resultats[] = ['ok' => true];
                break;

            case 'supprimer':
                $cible = $comptes[$op['cible']];
                $refus = null;
                try {
                    $service->supprimer($comptes[$op['auteur']], $cible->id, null);
                } catch (RuntimeException $e) {
                    $refus = $e->getMessage();
                }
                $resultats[] = [
                    'refus' => $refus,
                    'supprime' => User::withTrashed()->find($cible->id)?->supprime_le !== null,
                ];
                break;

            case 'libelles':
                $resultats[] = ['libelles' => [
                    'droit' => __('pwa.comptes.refus_suppression_droit'),
                    'soi_meme' => __('pwa.comptes.refus_suppression_soi_meme'),
                    'administrateur' => __('pwa.comptes.refus_suppression_administrateur'),
                    'introuvable' => __('pwa.comptes.refus_introuvable'),
                ]];
                break;

            default:
                fwrite(STDERR, "Operation inconnue : " . $op['op'] . "\n");
                exit(5);
        }
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
