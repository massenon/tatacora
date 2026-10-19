<?php

declare(strict_types=1);

/*
| Rejoue `bcadd($v, '0', 2)` — la normalisation de montant de
| `PasserEcritureService::montant()` — sur des chaines, pour que le test Flutter
| confronte `centimesDepuisChaine` / `chaineDepuisCentimes` a la SOURCE
| (10/10/2026, lot 1 de M10). Aucune base, aucun demarrage de l'application.
|
| Entree (stdin, JSON) : { "montants": ["12500", "10.999", "-3.5", "abc", ...] }
| Sortie (stdout, JSON) : { "montants": ["12500.00", "10.99", "-3.50", null, ...] }
|   `null` quand bcmath refuse la chaine (ValueError).
|
| Usage : php tool/comptabilite/exporter_montants.php < cas.json
*/

$cas = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($cas) || ! isset($cas['montants'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

$sortie = [];
foreach ($cas['montants'] as $valeur) {
    try {
        $sortie[] = bcadd((string) $valeur, '0', 2);
    } catch (Throwable) {
        $sortie[] = null;
    }
}

echo json_encode(['montants' => $sortie], JSON_UNESCAPED_UNICODE);
