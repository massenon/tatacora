<?php

declare(strict_types=1);

/*
| Exporte les fichiers de langue du SERVEUR dont M4 reprend des phrases, tels
| quels, en JSON — pour que les tests Flutter les confrontent a leur source, mot
| pour mot (09/10/2026). Aucune base, aucun demarrage de l'application.
|
| Sortie : { "restaurant": <lang/fr/restaurant.php>,
|            "carte_pwa": <lang/fr/carte_pwa.php> }
|
| Usage : php tool/restaurant/exporter_langue.php
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false
    || ! is_file($api . '/lang/fr/restaurant.php')
    || ! is_file($api . '/lang/fr/carte_pwa.php')) {
    fwrite(STDERR, "tatacora-api/lang/fr/{restaurant,carte_pwa}.php introuvable.\n");
    exit(2);
}

echo json_encode([
    'restaurant' => require $api . '/lang/fr/restaurant.php',
    'carte_pwa' => require $api . '/lang/fr/carte_pwa.php',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
