<?php

declare(strict_types=1);

/*
| Écran Paramètres de la PWA — les libellés d'INTERFACE qui lui sont propres.
|
| ## Pourquoi ce fichier existe, et pourquoi il est si court
|
| `lang/fr/pwa.php` porte déjà tout le contenu de cet écran : titres de section,
| badges d'état, textes de refus. Ce qui lui manquait, c'est le vocabulaire des
| GESTES d'écriture — la PWA était en lecture seule quand ce contenu a été
| écrit, et le geste n'existait pas (PA-159, 28/08/2026).
|
| ⚠ Trois libellés seulement, et aucun ne duplique une clé existante. Les
| libellés des CHAMPS, eux, ne sont toujours pas ici : ils viennent du registre
| serveur (`RegistreParametres`), source unique partagée avec l'API Flutter.
| Les recopier ferait deux listes, qui divergeraient.
|
| ## Une clé de `pwa.php` est PÉRIMÉE et n'est plus rendue
|
| `pwa.parametres.refus_enregistrer` affirme « la consultation web est en
| lecture seule ». C'était vrai à l'écriture, c'est faux depuis PA-159 : cet
| écran enregistre. Elle n'est pas rendue par la vue, et sa suppression est
| signalée au propriétaire de `pwa.php` — publier un motif de refus qui a cessé
| d'être vrai transforme une décision en oubli (PA-144).
*/

return [
    'modifier' => 'Modifier',
    'enregistrer' => 'Enregistrer',

    // Le type `booleen` du registre stocke « true » / « false » ; l'écran, lui,
    // pose la question en français. La VALEUR reste celle que le service
    // normalise — les deux ne se confondent nulle part.
    'oui' => 'Oui',
    'non' => 'Non',
];
