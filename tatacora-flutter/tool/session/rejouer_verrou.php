<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI composant `VerrouSession` du serveur, ce que fait
| `deverrouiller()` (27/10/2026, lot A1 du poste) : le serveur est l'ancrage de
| la règle que le poste réplique (cinq essais par fenêtre de 60 secondes, le
| bon mot de passe n'y change rien une fois la limite atteinte, un succès remet
| le compteur à zéro), jamais une liste recopiée.
|
| Entrée (stdin, JSON) : { "ops": [ ... ] }
|   {"op":"utilisateur","ref":"u"}
|   {"op":"deverrouiller","user":"u","mot_de_passe":"..."}
|   {"op":"libelles"}   (les mots `pwa.verrou.*`, le seuil, la clé de limitation)
| Sortie (stdout, JSON) : { "resultats": [ ... un par opération ... ] }
|   deverrouiller : { "erreur": "<message sous le champ>"|null, "deverrouille": bool }
|
| Le mot de passe correct de tout utilisateur créé ici est MOT_DE_PASSE_CORRECT.
| La base N'EST PAS un double : le script travaille sur `tatacora_test` (il REFUSE
| toute autre base, sauf une base d'essai PRIVÉE `tatacora_<nom>_test` donnée par
| `TATACORA_BASE_ESSAI`), puis ANNULE tout (rollback) et efface les compteurs.
| Usage : php tool/session/rejouer_verrou.php < scenario.json
*/

const BASE_AUTORISEE = 'tatacora_test';
const MOT_DE_PASSE_CORRECT = 'mot-de-passe-correct';

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
use App\Pwa\Livewire\Transverse\VerrouSession;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Livewire\Livewire;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

/** @var array<string, User> $utilisateurs */
$utilisateurs = [];
$resultats = [];

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'utilisateur':
                    $utilisateurs[$op['ref']] = User::create([
                        'login' => $op['ref'] . '.' . Str::random(6),
                        'mot_de_passe_hash' => Hash::make(MOT_DE_PASSE_CORRECT),
                        'role_id' => Role::where('libelle', 'receptionniste')->firstOrFail()->id,
                        'statut' => 'actif',
                    ]);
                    RateLimiter::clear('verrou-session|' . $utilisateurs[$op['ref']]->id);
                    $resultats[] = ['ok' => true];
                    break;

                case 'deverrouiller':
                    $u = $utilisateurs[$op['user']];
                    $c = Livewire::actingAs($u)->test(VerrouSession::class)
                        ->set('motDePasse', $op['mot_de_passe'] === 'CORRECT' ? MOT_DE_PASSE_CORRECT : $op['mot_de_passe'])
                        ->call('deverrouiller');

                    $messages = $c->errors()->get('motDePasse');
                    $deverrouille = true;
                    try {
                        $c->assertDispatched('session-deverrouillee');
                    } catch (Throwable) {
                        $deverrouille = false;
                    }

                    $resultats[] = [
                        'erreur' => $messages[0] ?? null,
                        'deverrouille' => $deverrouille,
                        // Le champ est vidé après CHAQUE essai, échec compris.
                        'champ_vide' => $c->get('motDePasse') === '',
                    ];
                    break;

                case 'libelles':
                    $resultats[] = ['libelles' => [
                        'titre' => __('pwa.verrou.titre'),
                        'message' => __('pwa.verrou.message'),
                        'sous_message' => __('pwa.verrou.sous_message'),
                        'mot_de_passe' => __('pwa.verrou.mot_de_passe'),
                        'deverrouiller' => __('pwa.verrou.deverrouiller'),
                        'erreur' => __('pwa.verrou.erreur'),
                        'trop_de_tentatives' => __('pwa.verrou.trop_de_tentatives', ['secondes' => ':secondes']),
                        'afficher_mot_de_passe' => __('pwa.connexion.afficher_mot_de_passe'),
                        'masquer_mot_de_passe' => __('pwa.connexion.masquer_mot_de_passe'),
                        'inactivite_secondes' => VerrouSession::INACTIVITE_SECONDES,
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
            ];
        }
    }
} finally {
    foreach ($utilisateurs as $u) {
        RateLimiter::clear('verrou-session|' . $u->id);
    }
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
