<?php

declare(strict_types=1);

/*
| Exporte, en JSON, le catalogue des états du SERVEUR (M14) tel que le code PHP
| l'écrit — pour que les tests Flutter confrontent la copie locale à la SOURCE,
| jamais à une liste recopiée (10/10/2026).
|
| Ce que l'on lit, et comment :
|
|  - le REGISTRE FERMÉ : le bloc `REGISTRE` de `CatalogueEtatsService`, code
|    par code, dans l'ordre où le serveur le sert ;
|  - pour chaque classe d'état : le module (`module()`), la clé de langue du
|    libellé (`libelle()`), celle de la période (`periode()`, la dernière
|    clé : c'est la branche « sans filtre » de `calculer([])`), les clés des
|    KPI (celles qui précèdent un `=>` ou un `)]`) et celles des en-têtes
|    (le tableau `entetes:`), toutes RÉSOLUES dans les fichiers de langue ;
|  - les fichiers de langue eux-mêmes, pour les phrases propres à un état
|    (statuts, « Oui » / « Non », « Sous seuil »…).
|
| Aucune base, aucun démarrage de l'application : les états sont des classes
| dont on lit le texte, pas le comportement. Les calculs, eux, sont confrontés
| ailleurs (stocks, occupation, paie : `tool/stocks`, `tool/tableau_de_bord`).
|
| Usage : php tool/etats/exporter_registre.php
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/app/Domain/Etats/Services/CatalogueEtatsService.php')) {
    fwrite(STDERR, "tatacora-api/app/Domain/Etats/Services/CatalogueEtatsService.php introuvable.\n");
    exit(2);
}

$langues = [];
foreach (['etats_m14', 'stocks', 'vehicules', 'tableaux_de_bord'] as $fichier) {
    $chemin = $api . '/lang/fr/' . $fichier . '.php';
    if (! is_file($chemin)) {
        fwrite(STDERR, "lang/fr/$fichier.php introuvable.\n");
        exit(2);
    }
    $langues[$fichier] = require $chemin;
}

/** Résout `fichier.a.b.c` dans les tableaux de langue ; `null` si absent. */
function resoudre(array $langues, string $cle): ?string
{
    $parties = explode('.', $cle);
    $fichier = array_shift($parties);
    $noeud = $langues[$fichier] ?? null;
    foreach ($parties as $p) {
        if (! is_array($noeud) || ! array_key_exists($p, $noeud)) {
            return null;
        }
        $noeud = $noeud[$p];
    }

    return is_string($noeud) ? $noeud : null;
}

/** Les clés `__('...')` ou `__("...")` d'un extrait, dans l'ordre. */
function cles(string $extrait): array
{
    preg_match_all('/__\(\s*([\'"])([^\'"]+)\1/', $extrait, $m);

    return $m[2];
}

/** Le corps d'une méthode, accolades appariées. */
function corps(string $source, string $methode): string
{
    if (! preg_match('/function\s+' . preg_quote($methode, '/') . '\s*\(/', $source, $m, PREG_OFFSET_CAPTURE)) {
        return '';
    }
    $debut = strpos($source, '{', $m[0][1]);
    $niveau = 0;
    for ($i = $debut, $n = strlen($source); $i < $n; $i++) {
        if ($source[$i] === '{') {
            $niveau++;
        } elseif ($source[$i] === '}') {
            $niveau--;
            if ($niveau === 0) {
                return substr($source, $debut, $i - $debut + 1);
            }
        }
    }

    return '';
}

/** Le contenu du `[` qui suit `marqueur`, crochets appariés. */
function tableau(string $source, string $marqueur): string
{
    $p = strpos($source, $marqueur);
    if ($p === false) {
        return '';
    }
    $debut = strpos($source, '[', $p);
    $niveau = 0;
    for ($i = $debut, $n = strlen($source); $i < $n; $i++) {
        if ($source[$i] === '[') {
            $niveau++;
        } elseif ($source[$i] === ']') {
            $niveau--;
            if ($niveau === 0) {
                return substr($source, $debut + 1, $i - $debut - 1);
            }
        }
    }

    return '';
}

$catalogue = file_get_contents($api . '/app/Domain/Etats/Services/CatalogueEtatsService.php');

// `use App\Domain\Stocks\Etats\EtatStocks;` -> classe courte => chemin.
preg_match_all('/^use\s+(App\\\\[^;]+\\\\(Etat\w+));/m', $catalogue, $uses, PREG_SET_ORDER);
$fichiers = [];
foreach ($uses as $u) {
    $fichiers[$u[2]] = $api . '/app/' . str_replace('\\', '/', substr($u[1], 4)) . '.php';
}

$registre = tableau($catalogue, 'private const REGISTRE');
preg_match_all('/[\'"]([a-z\-]+)[\'"]\s*=>\s*(Etat\w+)::class/', $registre, $paires, PREG_SET_ORDER);

$etats = [];
foreach ($paires as $p) {
    [, $code, $classe] = $p;
    $chemin = $fichiers[$classe] ?? null;
    if ($chemin === null || ! is_file($chemin)) {
        fwrite(STDERR, "Fichier de l'état $classe introuvable.\n");
        exit(3);
    }
    $source = file_get_contents($chemin);

    preg_match('/function\s+module\s*\([^)]*\)\s*:\s*string\s*\{\s*return\s*[\'"](M\d+)[\'"]/', $source, $mod);

    $clesLibelle = cles(corps($source, 'libelle'));
    $clesPeriode = cles(corps($source, 'periode'));
    $calculer = corps($source, 'calculer');

    // KPI : `__('...') =>` ou `$kpis[__('...')] =`. Les en-têtes sont
    // `__('...'),` : jamais suivis de `=>`.
    preg_match_all('/__\(\s*([\'"])([^\'"]+)\1\s*\)\s*(?:=>|\]\s*=)/', $calculer, $k);
    $kpis = array_values(array_unique($k[2]));

    $entetes = cles(tableau($calculer, 'entetes'));

    $resoudre = static fn (array $liste): array => array_map(
        static fn (string $c): array => ['cle' => $c, 'texte' => resoudre($langues, $c)],
        $liste,
    );

    $etats[] = [
        'code' => $code,
        'classe' => $classe,
        'module' => $mod[1] ?? null,
        // Le PREMIER libellé : la branche « sans exercice » de la balance, le
        // libellé global des stocks.
        'libelle' => $resoudre(array_slice($clesLibelle, 0, 1))[0] ?? null,
        // La DERNIÈRE clé de la période : la branche de `calculer([])`.
        'periode' => $resoudre($clesPeriode === [] ? [] : [end($clesPeriode)])[0] ?? null,
        'kpis' => $resoudre($kpis),
        'entetes' => $resoudre($entetes),
    ];
}

// Les phrases de l'écran (`pwa.etats.*`) : titre, compteur, accueil, état vide.
$pwa = require $api . '/lang/fr/pwa.php';

echo json_encode([
    'etats' => $etats,
    'langue' => $langues,
    'pwa_etats' => $pwa['etats'] ?? null,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
