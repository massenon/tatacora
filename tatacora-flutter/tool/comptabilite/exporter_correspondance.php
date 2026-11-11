<?php

declare(strict_types=1);

/*
| Exporte, depuis le SERVEUR, la correspondance rôle -> compte comptable que le
| poste réplique (26/10/2026, décision du PO : les comptes se modifient sur le
| poste et sur le web) : les rôles (groupe, libellé, aide, préfixes de compte
| admis, clé de paramètre, compte par défaut) et les gabarits de langue de
| l'écran « Correspondance des comptes » (`lang/fr/comptes_correspondance.php`).
| Le test Flutter confronte chaque bloc à son équivalent Dart : jamais deux
| listes qui divergent.
|
| Aucune base, aucun démarrage de l'application : les classes lues ne font que
| porter des constantes, que l'autoloader de Composer charge.
|
| Sortie (stdout, JSON) :
|   { "retour_hub": "Retour au Hub Comptabilité",
|     "roles": [{"role","groupe","libelle","aide","prefixes","cle","defaut"}...],
|     "groupes": ["produits", ...],
|     "gabarits": {"compte_absent": "...", ...} }
|
| Usage : php tool/comptabilite/exporter_correspondance.php
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Domain\Comptabilite\Support\RolesCorrespondance;

$roles = [];

foreach (RolesCorrespondance::ROLES as $role => $d) {
    $roles[] = [
        'role' => $role,
        'groupe' => $d['groupe'],
        'libelle' => $d['libelle'],
        'aide' => $d['aide'],
        'prefixes' => $d['prefixes'],
        'cle' => CorrespondanceComptesService::cle($role),
        'defaut' => RolesCorrespondance::defaut($role),
    ];
}

// Le lien de retour de l'en-tete des ecrans M10 (`pwa.comptabilite.retour_hub`).
$pwa = require $api . '/lang/fr/pwa.php';

echo json_encode([
    'retour_hub' => $pwa['comptabilite']['retour_hub'],
    'roles' => $roles,
    'groupes' => RolesCorrespondance::GROUPES,
    'gabarits' => require $api . '/lang/fr/comptes_correspondance.php',
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
