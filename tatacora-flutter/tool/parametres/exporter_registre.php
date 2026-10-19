<?php

declare(strict_types=1);

/*
| Exporte, en JSON, le registre des paramètres du SERVEUR et son fichier de
| langue — pour que les tests Flutter confrontent la copie locale à la SOURCE,
| jamais à une liste recopiée (09/10/2026).
|
| Aucune base, aucun démarrage de l'application : le registre ne fait que
| référencer des constantes de classes, que l'autoloader de Composer charge.
|
| Usage : php tool/parametres/exporter_registre.php
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Shared\Parametres\Data\RegistreParametres;

$definitions = [];

foreach (RegistreParametres::definitions() as $d) {
    $definitions[] = [
        'cle' => $d->cle,
        'groupe' => $d->groupe,
        'libelle' => $d->libelle,
        'type' => $d->type,
        'regles' => $d->regles,
        'choix' => $d->choix,
        'aide' => $d->aide,
    ];
}

echo json_encode([
    'definitions' => $definitions,
    'motifs_secret' => RegistreParametres::MOTIFS_SECRET,
    'langue' => require $api . '/lang/fr/parametres.php',
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
