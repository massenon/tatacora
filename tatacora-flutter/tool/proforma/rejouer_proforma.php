<?php

declare(strict_types=1);

/*
| PARITÉ PHP / Dart de la facture proforma (PO, 07/11/2026).
|
| Rejoue, avec les classes du SERVEUR, les trois règles que le poste réimplémente en Dart :
|  - le montant en lettres (`MontantEnLettres`), sur la table du PO et sur une plage de montants ;
|  - la date longue et les milliers (`MiseEnPageProforma`) ;
|  - le numéro (`ProformaService::formaterNumero`).
| Le test Dart `proforma_contre_serveur_test.dart` lance ce script et compare chaque valeur à la sienne.
| Aucune base de données : les classes rejouées n'en ont pas besoin.
*/

require __DIR__.'/../../../tatacora-api/vendor/autoload.php';

use App\Domain\Facturation\Services\ProformaService;
use App\Domain\Facturation\Support\MiseEnPageProforma;
use App\Domain\Facturation\Support\MontantEnLettres;
use Illuminate\Support\Carbon;

$table = json_decode((string) file_get_contents(__DIR__.'/cas_montant_en_lettres.json'), true, 512, JSON_THROW_ON_ERROR);

$montants = array_column($table, 'montant');
// Plage dense (0..2200 : toutes les dizaines, centaines, 70/80/90) puis des bornes de milliers, millions, milliards.
foreach (range(0, 2200) as $n) {
    $montants[] = $n;
}
foreach ([10000, 16000, 17000, 70000, 71000, 80000, 81000, 90000, 99000, 100000, 101000, 180000, 200000, 201000,
    999999, 1000000, 1000001, 1080000, 2000000, 21000000, 71000000, 80000000, 81000000, 100000000, 180000000,
    200000000, 999999999, 1000000000, 2000000000, 80000000000, 999999999999] as $n) {
    $montants[] = $n;
}
mt_srand(20261107);
for ($i = 0; $i < 400; $i++) {
    $montants[] = mt_rand(0, 999999999);
}
$montants = array_values(array_unique($montants));
sort($montants);

$lettres = [];
foreach ($montants as $n) {
    $lettres[(string) $n] = MontantEnLettres::francsCfa($n);
}

$dates = [];
foreach (['2026-11-02', '2027-01-01', '2026-02-28', '2028-02-29', '2026-08-15', '2026-12-31'] as $d) {
    $dates[$d] = MiseEnPageProforma::dateLongue(Carbon::parse($d));
}

$milliers = [];
foreach ([0, 5, 999, 1000, 12345, 400000, 1234567, 99999999999] as $n) {
    $milliers[(string) $n] = MiseEnPageProforma::montant($n);
}

$numeros = [];
foreach ([[1, 'GCN', 2026], [45, 'GCN', 2026], [9999, 'ABC', 2027], [12345, 'X1', 2030]] as [$rang, $ref, $annee]) {
    $numeros["$rang|$ref|$annee"] = ProformaService::formaterNumero($rang, $ref, $annee);
}

echo json_encode(['lettres' => $lettres, 'dates' => $dates, 'milliers' => $milliers, 'numeros' => $numeros], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
