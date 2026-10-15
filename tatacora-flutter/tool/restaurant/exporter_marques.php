<?php

declare(strict_types=1);

/*
| Rejoue, en PHP, la deduction de « corrige a la main » du SERVEUR sur des cas
| donnes — pour que les tests Flutter confrontent `prixCorrigeMainApres()` a la
| SOURCE, jamais a une regle recopiee (09/10/2026).
|
| Le code execute est le VRAI : `MarquesDePrix::completer()`, applique a un
| `Plat` dont les attributs sont poses a la main. Aucune base.
|
| Entree (stdin, JSON) :
|   { "cas": [{"provisoire":true,"corrige":false,"prix":"1000.00","soumis":"1200"}, ...] }
| Sortie (stdout, JSON) : pour chaque cas, la valeur de `prix_corrige_main` APRES
| l'enregistrement (la marque posee par le service, sinon celle d'avant).
|
| Usage : php tool/restaurant/exporter_marques.php < cas.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Domain\Carte\MarquesDePrix;
use App\Domain\Restaurant\Models\Plat;

$entree = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($entree)) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

$sortie = [];

foreach ($entree['cas'] ?? [] as $cas) {
    $plat = new Plat();
    $plat->setRawAttributes([
        'prix_provisoire' => $cas['provisoire'] ? 1 : 0,
        'prix_corrige_main' => $cas['corrige'] ? 1 : 0,
        'prix_vente' => $cas['prix'],
    ]);

    $donnees = MarquesDePrix::completer($plat, ['prix_vente' => $cas['soumis']]);

    $sortie[] = array_key_exists(MarquesDePrix::CORRIGE_MAIN, $donnees)
        ? (bool) $donnees[MarquesDePrix::CORRIGE_MAIN]
        : (bool) $cas['corrige'];
}

echo json_encode($sortie);
