<?php

declare(strict_types=1);

/*
| PARITÉ serveur / poste des règles COMMUNES de la facturation normalisée
| (07/11/2026) : le mode, ses libellés, la lecture d'une valeur inconnue, l'IFU
| de 13 chiffres, les statuts de normalisation. Le poste confronte son Dart à
| CETTE sortie — rejouée contre le vrai PHP, jamais recopiée dans un test.
|
| Aucune base, aucun démarrage de l'application : des enums et des fonctions
| pures, que l'autoloader de Composer charge.
|
| Usage : php tool/facturation/rejouer_regles_communes.php
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\ReglagesMecef;
use App\Domain\Facturation\Services\StatutNormalisation;
use App\Domain\Facturation\Support\IfuClient;

$echantillonsMode = ['boitier', 'BOITIER', ' emecef ', 'desactive', '', 'nimportequoi', 'e-mecef', 'Boîtier'];
$echantillonsIfu = [
    '3202612345678', '0202011344660', '320261234567', '32026123456789', '32026123456A8',
    '', ' 3202612345678', '3202612345678 ', '３２０２６１２３４５６７８', "3202612345678\n",
];

// IFU du CLIENT (07/11/2026) : facultatif, 13 chiffres s'il est rempli ; nettoyage des séparateurs.
$echantillonsIfuClient = [
    '', '   ', '3201910768821', '3201 9107 68821', '3201.9107.68821', '3201-9107-68821', '320191076882',
    '32019107688211', '32019107688AB', '３２０１９１０７６８８２１', "3201910768821\n", '3201910768821x',
];

// Les phrases communes au web et au poste (lang/fr/facturation.php), résolues par le vrai PHP.
$phrases = require $api . '/lang/fr/facturation.php';

echo json_encode([
    'ifu_client_valide' => array_combine(
        $echantillonsIfuClient,
        array_map(static fn (string $v): bool => IfuClient::valide($v), $echantillonsIfuClient),
    ),
    'ifu_client_nettoye' => array_combine(
        $echantillonsIfuClient,
        array_map(static fn (string $v): ?string => IfuClient::nettoyer($v), $echantillonsIfuClient),
    ),
    'phrases' => [
        'ifu_label' => $phrases['ifu_client']['label'],
        'ifu_nom_label' => $phrases['ifu_client']['nom_label'],
        'ifu_aide' => $phrases['ifu_client']['aide'],
        'ifu_invalide' => $phrases['ifu_client']['invalide'],
        'ifu_retenir' => $phrases['ifu_client']['retenir'],
        'ifu_nom_divers' => $phrases['ifu_client']['nom_divers'],
        'normaliser_maintenant' => $phrases['mode']['normaliser_maintenant'],
        'avoir_en_ligne' => $phrases['avoir_en_ligne'],
    ],
    'cle_mode' => ModeFacturation::CLE,
    'modes' => array_map(
        static fn (ModeFacturation $m): array => ['valeur' => $m->value, 'libelle' => $m->libelle()],
        ModeFacturation::cases(),
    ),
    'mode_depuis' => array_combine(
        $echantillonsMode,
        array_map(static fn (string $v): string => ModeFacturation::depuis($v)->value, $echantillonsMode),
    ),
    'ifu_valide' => array_combine(
        $echantillonsIfu,
        array_map(static fn (string $v): bool => ReglagesMecef::ifuValide($v), $echantillonsIfu),
    ),
    'statuts' => array_map(
        static fn (StatutNormalisation $s): array => [
            'valeur' => $s->value,
            'libelle' => $s->libelle(),
            'rejouable' => $s->rejouable(),
        ],
        StatutNormalisation::cases(),
    ),
    'urls' => ['defaut' => ReglagesMecef::URL_API_PAR_DEFAUT],
    // Les CINQ réglages réservés aux Administrateurs (mode, API, opérateur ×2, forme juridique) : le poste
    // les écrit depuis le 09/11/2026 (décision du PO), le serveur en réserve l'écriture au compte
    // administrateur du jeton d'appairage. Les neuf réglages des documents n'en font PAS partie.
    'cles_administrateur' => \App\Shared\Sync\Gestionnaires\GestionnaireParametres::CLES_ADMINISTRATEUR,
    'cles_documents' => \App\Domain\Facturation\Services\ReglagesDocuments::CLES,
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
