<?php

declare(strict_types=1);

/*
 * Comptes réels (PA-167) — le pont config entre le `.env` du serveur et
 * `ComptesReelsSeeder`.
 *
 * ## Pourquoi ce fichier existe, alors que le seeder lisait `env()`
 *
 * `php artisan config:cache` — recommandé sur le cPanel de production — rend
 * `env()` NUL partout hors de `config/` : le seeder aurait alors refusé les
 * trois comptes en accusant un `.env` pourtant correct. C'est le défaut
 * exact que la règle larastan `noEnvCallsOutsideOfConfig` existe pour
 * empêcher. Les valeurs transitent donc par ici, et le seeder lit
 * `config('comptes_reels...')`.
 *
 * AUCUN mot de passe n'a de valeur par défaut : une variable absente rend
 * une chaîne vide, et le seeder refuse TOUT sans rien écrire.
 */
return [

    'mots_de_passe' => [
        'rodrigue' => env('COMPTE_RODRIGUE_MOT_DE_PASSE', ''),
        'bienvenu' => env('COMPTE_BIENVENU_MOT_DE_PASSE', ''),
        'noel' => env('COMPTE_NOEL_MOT_DE_PASSE', ''),
        'super_admin' => env('COMPTE_SUPER_ADMIN_MOT_DE_PASSE', ''),
    ],

    // Rôle par compte — vide : le seeder applique son défaut documenté
    // (rodrigue = administrateur, bienvenu = gerant, noel = administrateur,
    // décision PO du 01/09/2026).
    'roles' => [
        'rodrigue' => env('COMPTE_RODRIGUE_ROLE', ''),
        'bienvenu' => env('COMPTE_BIENVENU_ROLE', ''),
        'noel' => env('COMPTE_NOEL_ROLE', ''),
        'super_admin' => env('COMPTE_SUPER_ADMIN_ROLE', ''),
    ],
];
