<?php

declare(strict_types=1);

/*
| Rejoue, en PHP, les calculs de stock du SERVEUR sur des cas donnes — pour que
| les tests Flutter confrontent les fonctions pures de `calcul_stock.dart` a la
| SOURCE, jamais a une formule recopiee (09/10/2026).
|
| Aucune base, aucun demarrage de l'application : `moyennePonderee()` est pure,
| et `deriveCoutMoyenPondere()` ne lit que deux attributs du modele.
|
| Entree (stdin, JSON) :
|   { "cmp": [["10.00","1000.0000","5.00","1250.5000"], ...],
|     "derive": [["1106.2500","1000.0000"], ...] }
| Sortie (stdout, JSON) :
|   { "cmp": ["1083.5000", ...], "derive": [11, ...], "rupture": "<phrase>" }
|
| Usage : php tool/stocks/exporter_calculs.php < cas.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Domain\Stocks\Services\ValorisationStockService;

$cas = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($cas)) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

$valorisation = new ValorisationStockService(new StockTheoriqueService());

$cmp = [];
foreach ($cas['cmp'] ?? [] as [$qAvant, $cmpAvant, $qEntree, $cout]) {
    $cmp[] = $valorisation->moyennePonderee($qAvant, $cmpAvant, $qEntree, $cout);
}

$derive = [];
foreach ($cas['derive'] ?? [] as [$cmpCourant, $prix]) {
    $article = new Article();
    $article->setRawAttributes([
        'cout_moyen_pondere' => $cmpCourant,
        'prix_achat' => $prix,
    ]);
    $derive[] = $article->deriveCoutMoyenPondere();
}

$langue = require $api . '/lang/fr/stocks.php';
$languePwa = require $api . '/lang/fr/stocks_pwa.php';

echo json_encode([
    'cmp' => $cmp,
    'derive' => $derive,
    'rupture' => $langue['rupture'],
    'validation' => $langue['validation'],
    'cout_negatif' => $langue['cout_negatif'],
    'refus_journalier' => $languePwa['mouvement']['refus_journalier'],
    'motif_ouverture' => $languePwa['article']['stock_ouverture_motif'],
    // 21/10/2026 : l'archivage d'un article et l'inventaire physique.
    'archivage' => $languePwa['archivage'],
    'inventaires' => $languePwa['inventaires'],
    'quantite_negative' => $langue['quantite_negative'],
    'inventaire_incomplet' => $langue['inventaire_incomplet'],
    'motif_regularisation' => $langue['motif_regularisation'],
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
