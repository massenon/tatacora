<?php

declare(strict_types=1);

/*
| Exporte, en JSON, les paramètres INITIAUX d'une base vierge du SERVEUR
| (`ParametresEtablissementSeeder::PARAMETRES`) — pour que les tests Flutter
| confrontent `parametresEtablissementInitiaux` à la SOURCE, jamais à une liste
| recopiée (piège 12, 15/10/2026).
|
| Aucune base, aucun démarrage de l'application : la constante est lue par
| l'autoloader de Composer, le seeder n'est PAS exécuté.
|
| Usage : php tool/parametres/exporter_parametres_initiaux.php
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use Database\Seeders\ParametresEtablissementSeeder;

$parametres = [];

foreach (ParametresEtablissementSeeder::PARAMETRES as [$cle, $valeur, $description]) {
    $parametres[] = [
        'cle' => $cle,
        'valeur' => $valeur,
        'description' => $description,
    ];
}

echo json_encode(['parametres' => $parametres], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
