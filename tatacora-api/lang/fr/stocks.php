<?php

declare(strict_types=1);

/*
 * Messages du domaine Stocks (M6).
 */

return [
    'rupture' => 'Stock insuffisant : :disponible disponible, :demande demandé. '
        // Article 8 (02/09/2026) : la reference RG-06 vit ici, jamais a l'ecran.
        . 'Une validation explicite est requise pour forcer la sortie.',
    'point_introuvable' => 'Point de stockage inconnu : la réception ne peut pas être imputée.',
    'point_type_absent' => 'Aucun point de stockage de type « :type » n\'est défini. '
        // Article 8 (02/09/2026) : la reference RG-05 vit ici, jamais a l'ecran.
        . 'La sortie de stock ne peut pas être imputée.',

    /*
     * Etat des stocks (M14 / EF-M14-02) — libelles imprimes sur un document
     * remis a des tiers.
     */
    'etat' => [
        'libelle_global' => 'État des stocks — tous points de stockage',
        'libelle_point' => 'État des stocks — :point',
        'arrete_au' => 'Arrêté au :date',

        'kpi_references' => 'Références',
        'kpi_critiques' => 'Sous seuil',
        'kpi_valeur' => 'Valeur du stock (CMP)',

        'col_article' => 'Article',
        'col_categorie' => 'Catégorie',
        'col_unite' => 'Unité',
        'col_quantite' => 'Quantité',
        'col_seuil' => 'Seuil',
        'col_statut' => 'Statut',
        'col_valeur' => 'Valeur',

        'sous_seuil' => 'Sous seuil',
        'normal' => 'Normal',
    ],

    /*
     * Valorisation et inventaire (EF-M6-05).
     */
    'quantite_negative' => 'Une quantité ne peut pas être négative.',
    'cout_negatif' => "Un coût d'achat ne peut pas être négatif : il ferait baisser le coût moyen "
        . 'pondéré et sous-évaluerait le stock au bilan.',
    'inventaire_incomplet' => ":nombre article(s) n'ont pas été comptés. Clôturer maintenant "
        . 'régulariserait une partie du stock en laissant le reste inchangé, sans que rien ne le signale.',
    'motif_regularisation' => 'Régularisation inventaire :inventaire — écart de :ecart',

    /*
     * Validation de l'API M6. Chaque message dit CE QUI est refusé et
     * POURQUOI : un refus muet renvoie l'utilisateur a essayer la meme chose.
     */
    'validation' => [
        'type_inconnu' => 'Type de mouvement inconnu. Un écart d\'inventaire ne se saisit pas ici : '
            . 'il naît de la clôture d\'un comptage, qui seule le rend opposable.',
        'quantite_positive' => 'La quantité doit être strictement positive : '
            . 'une saisie à zéro n\'est pas un mouvement.',
        'motif_obligatoire' => 'Le motif est obligatoire : un mouvement sans raison identifiée '
            . 'rend l\'historique de stock inopposable lors d\'un inventaire.',
        'article_inexistant' => 'Article inconnu du référentiel.',
        'point_inexistant' => 'Point de stockage inconnu : le mouvement ne peut pas être imputé.',
        'cout_reserve_entree' => 'Un coût unitaire ne se renseigne que sur une entrée : '
            . 'une sortie est valorisée au coût moyen pondéré du moment et ne le modifie pas.',
        'rupture_sur_sortie' => 'La validation de rupture ne concerne que les sorties et les pertes : '
            . 'une entrée de stock ne peut pas être en rupture.',
        'identifiant_non_accepte' => 'Un mouvement de stock ne reçoit pas d\'identifiant du client : '
            . 'il est attribué à l\'enregistrement.',
        'identifiant_non_modifiable' => 'L\'identifiant d\'un article ne se modifie pas.',
        'identifiant_deja_pris' => 'Cet identifiant est déjà utilisé par un autre article.',
        'valeur_calculee' => 'Cette valeur est calculée depuis les mouvements de stock : '
            . 'elle s\'affiche, elle ne se saisit pas. La soumettre n\'aurait aucun effet '
            . 'et laisserait croire le contraire.',
        'libelle_obligatoire' => 'Le libellé de l\'article est obligatoire.',
        'unite_obligatoire' => 'L\'unité de mesure est obligatoire : sans elle, une quantité ne veut rien dire.',
        'seuil_obligatoire' => 'Le seuil d\'alerte est obligatoire : sans lui, aucune rupture ne sera signalée.',
        // PA-161 (a) — le registre des modes de suivi est FERMÉ (`Article::SUIVIS`).
        'suivi_inconnu' => 'Mode de suivi inconnu : un article est en suivi permanent (gros stock) '
            . 'ou en achat journalier (petit stock), il n\'y a pas de troisième cas. Une valeur hors '
            . 'registre le ferait disparaître de tous les filtres sans qu\'aucun message ne l\'annonce.',
        'etat_inconnu' => 'Filtre d\'état inconnu. Un filtre incompris serait ignoré, '
            . 'et la liste entière s\'afficherait sous un intitulé qui promet le contraire.',
        'periode_obligatoire' => 'Une fiche de stock porte sur une période : '
            . 'les dates de début et de fin sont obligatoires.',
        'periode_inversee' => 'La date de fin ne peut pas précéder la date de début.',
        'page_trop_grande' => 'Au plus :max éléments par page.',
        // Points de stockage créés hors connexion (lot S2, 15/10/2026).
        'point_libelle_obligatoire' => 'Le libellé du point de stockage est obligatoire.',
        'point_type_inconnu' => 'Type de point inconnu : un point est un magasin, une cuisine, un bar '
            . 'ou un garage. Un type hors registre ferait disparaître le point de toute recherche par type.',
        'point_identifiant_deja_pris' => 'Cet identifiant est déjà utilisé par un autre point de stockage.',
    ],
];
