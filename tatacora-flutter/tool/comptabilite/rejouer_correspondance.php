<?php

declare(strict_types=1);

/*
| Rejoue la VALIDATION et la LECTURE de la correspondance des comptes par les
| VRAIS services du serveur (26/10/2026, décision du PO : les comptes se
| modifient sur le poste et sur le web) : `EnregistrerParametreService` (le seul
| chemin d'écriture des paramètres, donc celui de l'écran web ET de la
| synchronisation d'un poste) et `CorrespondanceComptesService` (la lecture au
| moment de passer une pièce). Le test Flutter joue le MÊME scénario par
| `EnregistrerParametres` et `ComptabiliteDao.compteDuRole` du poste, et compare
| champ à champ : chaque refus (sa PHRASE), chaque compte retenu.
|
| Rien n'est modifié dans `tatacora-api`. Le script travaille sur `tatacora_test`
| (il REFUSE toute autre base), sème le référentiel comptable par le VRAI
| `ComptabiliteReferentielSeeder`, puis ANNULE tout (rollback). Si MySQL est
| injoignable, il échoue. Jamais deux processus PHP en parallèle sur cette base.
|
| Entrée (stdin, JSON) : { "aujourdhui": "2031-06-15", "ops": [ ... ] }
|   {"op":"enregistrer","valeurs":{"compte_caisse":"5712", ...}}
|        -> {"ok":true,"modifiees":["compte_caisse"]}  ou  {"refus":"<phrase>"}
|   {"op":"compte","role":"CAISSE"}   -> {"ok":true,"compte":"5712"}
|   {"op":"comptes_lus","role":"TVA_FACTUREE_PRESTATIONS"}
|        -> {"ok":true,"comptes":["4433","4432"]}
| Sortie (stdout, JSON) : { "resultats": [ ... un par opération ... ] }
|
| Usage : php tool/comptabilite/rejouer_correspondance.php < scenario.json
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['ops'], $scenario['aujourdhui'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

putenv('DB_DATABASE=' . BASE_AUTORISEE);
$_ENV['DB_DATABASE'] = BASE_AUTORISEE;
$_SERVER['DB_DATABASE'] = BASE_AUTORISEE;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Models\User;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . BASE_AUTORISEE . " \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow($scenario['aujourdhui'] . ' 10:00:00');

$resultats = [];

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    (new ComptabiliteReferentielSeeder())->run();

    Auth::setUser(User::create([
        'login' => 'admin.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
        'statut' => 'actif',
    ]));

    $ecriture = $app->make(EnregistrerParametreService::class);
    $comptes = $app->make(CorrespondanceComptesService::class);

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'enregistrer':
                    $modifiees = $ecriture->enregistrer($op['valeurs']);
                    $resultats[] = ['ok' => true, 'modifiees' => $modifiees];
                    break;

                case 'compte':
                    $resultats[] = ['ok' => true, 'compte' => $comptes->compte($op['role'])];
                    break;

                case 'comptes_lus':
                    $resultats[] = ['ok' => true, 'comptes' => $comptes->comptesLus($op['role'])];
                    break;

                default:
                    fwrite(STDERR, "Operation inconnue : {$op['op']}\n");
                    exit(5);
            }
        } catch (RuntimeException $e) {
            $resultats[] = ['refus' => $e->getMessage()];
        }
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
