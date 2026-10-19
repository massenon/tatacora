<?php

declare(strict_types=1);

namespace App\Shared\Sync\Support;

use Illuminate\Http\Request;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * Le `poste_id` déclaré doit être celui du jeton (PA-66) — un auteur, deux
 * lecteurs : `POST /api/v1/sync` et `GET /api/v1/referentiels` (15/10/2026).
 *
 * ## Pourquoi la provenance compte, dans les deux sens
 *
 * À la montée, le `poste_id` commande la classification des conflits (RG-17) :
 * un client qui annonce un autre poste que le sien fait passer ses écritures
 * pour celles d'un tiers. À la descente, il choisit les CORRESPONDANCES
 * renvoyées : annoncer le poste d'un autre ferait lire ses fusions — des
 * UUID locaux qui n'existent pas ici, et qui révéleraient ce que ce poste a
 * saisi hors connexion.
 *
 * ## La vérification n'a lieu que si le jeton PORTE un poste
 *
 * En production c'est toujours le cas : `createToken($poste)` est le seul
 * chemin d'émission, et `$poste` vaut au pire `'inconnu'`. Un jeton sans nom
 * ne se rencontre qu'en test — `Sanctum::actingAs()` fabrique un **mock
 * Mockery** dont `name` vaut `false`, ce qui passe `filled()` mais n'est
 * évidemment pas un nom de poste. D'où le contrôle de type explicite plutôt
 * qu'un simple test de présence ; `(string) false` vaut `''`, ce qui exprime
 * exactement la situation — aucun poste déclaré.
 *
 * C'est le même piège que PA-54 : `actingAs` court-circuite le garde, donc
 * un test qui l'emploierait ne prouverait rien. Les tests dédiés empruntent
 * un jeton RÉEL.
 */
final class PosteDuJeton
{
    public static function concorde(Request $requete, string $posteDeclare): bool
    {
        $jeton = $requete->user()?->currentAccessToken();
        $postePorte = $jeton instanceof PersonalAccessToken ? (string) $jeton->name : '';

        return $postePorte === '' || $postePorte === $posteDeclare;
    }
}
