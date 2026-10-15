<?php

// Script FACTICE des essais de `executerPhp` (R-B, D283). Il ne touche a
// AUCUNE base : il compte ses executions dans un fichier, puis reussit ou
// echoue selon le mode recu sur l'entree standard.
//
//   - `succes`        : rend {"execution": n} ;
//   - `echec_requete` : echoue comme une requete FAUSSE (pas de contention) ;
//   - `contention`    : echoue comme un interblocage MySQL tant que
//                       n <= `echecs`, puis reussit.

declare(strict_types=1);

$entree = json_decode((string) stream_get_contents(STDIN), true);
$compteur = (string) $entree['compteur'];
$n = (is_file($compteur) ? (int) file_get_contents($compteur) : 0) + 1;
file_put_contents($compteur, (string) $n);

$mode = (string) $entree['mode'];

if ($mode === 'echec_requete') {
    fwrite(STDERR, 'Illuminate\Database\QueryException: SQLSTATE[42S22]: Column not found: 1054 Unknown column x');
    exit(1);
}

if ($mode === 'contention' && $n <= (int) $entree['echecs']) {
    fwrite(STDERR, 'SQLSTATE[40001]: Serialization failure: 1213 Deadlock found when trying to get lock; try restarting transaction');
    exit(1);
}

echo json_encode(['execution' => $n]);
