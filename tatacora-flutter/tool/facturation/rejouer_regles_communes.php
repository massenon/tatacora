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

$echantillonsMode = ['boitier', 'BOITIER', ' emecef ', 'desactive', '', 'nimportequoi', 'e-mecef', 'Boîtier'];
$echantillonsIfu = [
    '3202612345678', '0202011344660', '320261234567', '32026123456789', '32026123456A8',
    '', ' 3202612345678', '3202612345678 ', '３２０２６１２３４５６７８', "3202612345678\n",
];

echo json_encode([
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
    'cles_administrateur' => ReglagesMecef::CLES_ADMINISTRATEUR,
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
