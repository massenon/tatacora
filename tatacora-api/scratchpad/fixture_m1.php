<?php

declare(strict_types=1);

require __DIR__.'/../vendor/autoload.php';

$app = require_once __DIR__.'/../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

const LOGIN = 'it_desktop_d1';
const MOT_DE_PASSE = 'D1-desktop-2026!';
const NUMERO_UNITE = 'IT-BNG-01';

$nettoyage = in_array('--nettoyer', $argv, true);

if ($nettoyage) {
    $utilisateur = DB::table('utilisateurs')->where('login', LOGIN)->first();
    $unite = DB::table('unites_hebergement')->where('numero', NUMERO_UNITE)->first();

    if ($unite !== null) {
        DB::table('reservations')->where('unite_id', $unite->id)->delete();
    }
    if ($utilisateur !== null) {
        DB::table('deduplication_synchronisation')->where('utilisateur_id', $utilisateur->id)->delete();
        DB::table('personal_access_tokens')->where('tokenable_id', $utilisateur->id)->delete();
        DB::table('journal_audit')->where('utilisateur_id', $utilisateur->id)->delete();
        DB::table('journal_securite')->where('utilisateur_id', $utilisateur->id)->delete();
    }
    DB::table('sessions_synchronisation')->where('poste_id', 'like', 'poste-%')->delete();
    if ($unite !== null) {
        DB::table('unites_hebergement')->where('id', $unite->id)->delete();
        DB::table('categories_hebergement')->where('libelle', 'IT Bungalow')->delete();
    }
    DB::table('clients')->where('nom', 'IT Client')->delete();
    if ($utilisateur !== null) {
        DB::table('utilisateurs')->where('id', $utilisateur->id)->delete();
    }

    echo "Jeu d'essai retire.\n";
    exit(0);
}

$baseUrl = rtrim(getenv('BASE_URL') ?: 'http://127.0.0.1:8010', '/');
$sortie = getenv('FIXTURE_SORTIE') ?: __DIR__.'/fixture.json';

/*
 * Aucun role n'est cree : `receptionniste` porte deja C sur M1 et M3.
 * Fabriquer un role de test ferait diverger le jeu d'essai de la matrice
 * reelle, et le parcours ne prouverait plus rien du RBAC de production.
 */
$roleId = DB::table('roles')->where('libelle', 'receptionniste')->value('id');
if ($roleId === null) {
    fwrite(STDERR, "Role 'receptionniste' absent : lancer php artisan db:seed.\n");
    exit(1);
}

$utilisateurId = DB::table('utilisateurs')->where('login', LOGIN)->value('id');
if ($utilisateurId === null) {
    $utilisateurId = (string) Str::uuid();
    DB::table('utilisateurs')->insert([
        'id' => $utilisateurId,
        'login' => LOGIN,
        'mot_de_passe_hash' => Hash::make(MOT_DE_PASSE),
        'role_id' => $roleId,
        'statut' => 'actif',
        'created_at' => now(),
        'updated_at' => now(),
    ]);
} else {
    DB::table('utilisateurs')->where('id', $utilisateurId)->update([
        'mot_de_passe_hash' => Hash::make(MOT_DE_PASSE),
        'role_id' => $roleId,
        'statut' => 'actif',
    ]);
}

$categorieId = DB::table('categories_hebergement')->where('libelle', 'IT Bungalow')->value('id');
if ($categorieId === null) {
    $categorieId = (string) Str::uuid();
    DB::table('categories_hebergement')->insert([
        'id' => $categorieId,
        'libelle' => 'IT Bungalow',
        'capacite_max' => 2,
        'tarif_base' => 28000,
        'created_at' => now(),
        'updated_at' => now(),
    ]);
}

$uniteId = DB::table('unites_hebergement')->where('numero', NUMERO_UNITE)->value('id');
if ($uniteId === null) {
    $uniteId = (string) Str::uuid();
    DB::table('unites_hebergement')->insert([
        'id' => $uniteId,
        'categorie_id' => $categorieId,
        'numero' => NUMERO_UNITE,
        'statut' => 'libre',
        'created_at' => now(),
        'updated_at' => now(),
    ]);
}

$clientId = DB::table('clients')->where('nom', 'IT Client')->value('id');
if ($clientId === null) {
    $clientId = (string) Str::uuid();
    DB::table('clients')->insert([
        'id' => $clientId,
        'nom' => 'IT Client',
        'telephone' => '+229 01 00 00 00 99',
        'type_client' => 'particulier',
        'date_creation' => now(),
        'created_at' => now(),
        'updated_at' => now(),
    ]);
}

/*
 * Les jetons passent par le VRAI point d'entree HTTP, jamais par
 * `createToken()` en memoire : c'est le seul moyen de constater que le backend
 * repond, que PA-54 tient, et que le nom de poste porte par le jeton est bien
 * celui que le client annoncera dans son lot.
 */
function connexion(string $baseUrl, string $poste): string
{
    $corps = json_encode([
        'identifiant' => LOGIN,
        'mot_de_passe' => MOT_DE_PASSE,
        'poste' => $poste,
    ], JSON_THROW_ON_ERROR);

    $ch = curl_init($baseUrl.'/api/v1/login');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $corps,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => ['Accept: application/json', 'Content-Type: application/json'],
        CURLOPT_TIMEOUT => 15,
    ]);
    $reponse = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $erreur = curl_error($ch);
    curl_close($ch);

    if ($reponse === false || $code !== 200) {
        fwrite(STDERR, "Connexion refusee pour {$poste} (HTTP {$code}) {$erreur} : ".(string) $reponse."\n");
        exit(1);
    }

    $donnees = json_decode((string) $reponse, true, 512, JSON_THROW_ON_ERROR);

    return $donnees['token'];
}

$jetonA = connexion($baseUrl, 'poste-A');
$jetonB = connexion($baseUrl, 'poste-B');

$fixture = [
    'base_url' => $baseUrl.'/api/v1',
    // `token` reste present : le test VM Dart du Sprint 1 le lit encore.
    'token' => $jetonA,
    'poste_a' => 'poste-A',
    'token_a' => $jetonA,
    'poste_b' => 'poste-B',
    'token_b' => $jetonB,
    'utilisateur_id' => $utilisateurId,
    'categorie_id' => $categorieId,
    'unite_id' => $uniteId,
    'unite_numero' => NUMERO_UNITE,
    'client_id' => $clientId,
];

file_put_contents($sortie, json_encode($fixture, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));

echo "Jeu d'essai ecrit dans {$sortie}\n";
foreach (['unite_id', 'client_id', 'categorie_id', 'utilisateur_id'] as $cle) {
    echo str_pad($cle, 16).$fixture[$cle]."\n";
}
