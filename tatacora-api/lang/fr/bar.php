<?php

declare(strict_types=1);

/*
 * Messages du domaine Bar (M5).
 */

return [
    'vente_vide' => 'Une vente doit comporter au moins une ligne.',
    'quantite_minimale' => 'La quantité vendue doit être au moins 1.',
    'motif_vente' => 'Vente bar — :boisson ×:quantite',

    'validation' => [
        'article_obligatoire' => 'Une boisson doit être liée à un article du stock, '
            . 'sinon sa vente ne décrémenterait rien.',
        'article_inexistant' => "Cet article n'existe pas dans le référentiel Stocks.",
        'categorie_inconnue' => 'Catégorie inconnue : locale, maison ou importée.',
    ],
];
