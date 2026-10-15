<?php

declare(strict_types=1);

/*
| L'outillage de l'essai de bout en bout du MOTEUR D'ENVOI (lot F2a,
| 15/10/2026) contre un VRAI serveur (`php artisan serve` sur `tatacora_test`,
| test `synchronisation_serveur_reel_test.dart`).
|
| Contrairement a `valider_charge.php`, le serveur de l'essai ECRIT pour de
| bon (il n'y a pas de transaction a annuler autour d'une requete HTTP). Ce
| script encadre donc l'essai :
|
|   preparer  : prend un INSTANTANE de toutes les tables de `tatacora_test`
|               (somme de controle + lignes), puis seme les roles, le
|               referentiel comptable, ferme les caisses restees ouvertes et
|               cree un compte `gerant` (identifiant et mot de passe choisis
|               par le test, jamais livres avec le code) ;
|   relire    : rend les lignes ecrites par le serveur pour une liste
|               d'elements, et des comptes par table (pour prouver l'absence
|               de doublon au rejeu) ;
|   restaurer : remet a l'identique toute table dont la somme de controle a
|               change depuis l'instantane, puis supprime l'instantane.
|
| Un instantane laisse par un essai interrompu est RESTAURE avant d'en
| prendre un nouveau : la base revient toujours a son etat d'avant.
|
| Il REFUSE toute autre base que `tatacora_test`.
|
| Entree (stdin, JSON) : { "action": "...", ... } — voir chaque action.
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$entree = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($entree) || ! isset($entree['action'])) {
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

use App\Domain\Caisse\Models\SessionCaisse;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . BASE_AUTORISEE . " \u{bb}.\n");
    exit(1);
}

/** @return list<string> */
function tables(): array
{
    return array_map(
        static fn (object $l): string => (string) array_values((array) $l)[0],
        DB::select("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'"),
    );
}

/** @return array<string, string> */
function sommes(): array
{
    $sommes = [];

    foreach (tables() as $t) {
        $ligne = DB::selectOne('CHECKSUM TABLE `' . $t . '`');
        $sommes[$t] = (string) ((array) $ligne)['Checksum'];
    }

    return $sommes;
}

/** @return list<string> les tables remises a l'identique */
function restaurer(string $chemin): array
{
    if (! is_file($chemin)) {
        return [];
    }

    $instantane = json_decode((string) file_get_contents($chemin), true, 512, JSON_THROW_ON_ERROR);
    $actuelles = sommes();
    $restaurees = [];

    DB::statement('SET FOREIGN_KEY_CHECKS = 0');

    try {
        foreach ($actuelles as $t => $somme) {
            if (! array_key_exists($t, $instantane['sommes'])) {
                continue;
            }

            if ($instantane['sommes'][$t] === $somme) {
                continue;
            }

            DB::table($t)->delete();

            foreach (array_chunk($instantane['lignes'][$t], 200) as $paquet) {
                DB::table($t)->insert($paquet);
            }

            $restaurees[] = $t;
        }
    } finally {
        DB::statement('SET FOREIGN_KEY_CHECKS = 1');
    }

    unlink($chemin);

    return $restaurees;
}

$action = (string) $entree['action'];

switch ($action) {
    case 'preparer':
        $chemin = (string) $entree['instantane'];
        $anciennes = restaurer($chemin);

        $lignes = [];

        foreach (tables() as $t) {
            $lignes[$t] = array_map(static fn (object $l): array => (array) $l, DB::table($t)->get()->all());
        }

        file_put_contents($chemin, json_encode(['sommes' => sommes(), 'lignes' => $lignes], JSON_THROW_ON_ERROR));

        (new RolePermissionSeeder())->run();
        (new ComptabiliteReferentielSeeder())->run();

        // Une caisse laissee ouverte ferait refuser l'ouverture du poste.
        SessionCaisse::query()->whereNull('date_cloture')->update(['date_cloture' => now()]);

        $gerant = User::create([
            'login' => (string) $entree['login'],
            'mot_de_passe_hash' => Hash::make((string) $entree['mot_de_passe']),
            'role_id' => Role::where('libelle', 'gerant')->firstOrFail()->id,
            'statut' => 'actif',
        ]);

        echo json_encode([
            'base' => $base,
            'utilisateur_id' => $gerant->id,
            'instantane_precedent_restaure' => $anciennes,
        ], JSON_UNESCAPED_UNICODE);

        break;

    case 'relire':
        $lignes = [];

        foreach ($entree['elements'] as $e) {
            $ligne = DB::table((string) $e['table'])->where('id', (string) $e['id'])->first();
            $lignes[$e['table'] . ':' . $e['id']] = $ligne === null ? null : (array) $ligne;
        }

        $comptes = [];

        foreach ($entree['comptes'] as $t) {
            $comptes[$t] = DB::table((string) $t)->count();
        }

        echo json_encode([
            'lignes' => $lignes,
            'comptes' => $comptes,
            'jetons_du_poste' => DB::table('personal_access_tokens')
                ->where('name', (string) $entree['poste_id'])
                ->count(),
        ], JSON_UNESCAPED_UNICODE);

        break;

    case 'restaurer':
        echo json_encode(['restaurees' => restaurer((string) $entree['instantane'])], JSON_UNESCAPED_UNICODE);

        break;

    default:
        fwrite(STDERR, "Action inconnue : {$action}\n");
        exit(4);
}
