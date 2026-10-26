<?php

declare(strict_types=1);

/*
 * Messages du domaine Achats (M7).
 */

return [
    'commande_cloturee' => 'Cette commande est déjà clôturée : une réception supplémentaire '
        . 'créerait une entrée de stock sans commande en face.',
    'reception_vide' => 'Une réception doit porter sur au moins un article.',
    'cloture_impossible' => 'Cette commande ne peut pas être clôturée : la réception n\'est pas conforme '
        // Article 8 (02/09/2026) : la reference RG-10 vit ici, jamais a l'ecran.
        . 'à la tolérance configurée. Enregistrez la réception complémentaire '
        . 'ou faites acter l\'écart par un responsable.',
    'tolerance_absente' => 'La tolérance de réception n\'est pas configurée. '
        . 'Aucune conformité ne peut être évaluée tant qu\'un Administrateur ne l\'a pas renseignée.',
    'motif_reception' => 'Réception commande :commande — bon :bon',
    'envoi_impossible' => 'Seule une commande en brouillon peut être émise : une commande déjà émise, '
        . 'réceptionnée ou clôturée ne se réémet pas.',

    'rapprochement' => [
        'facture_absente' => 'Facture fournisseur non fournie : le rapprochement ne porte que sur '
            // Article 8 (02/09/2026) : la reference PA-40 vit ici, jamais a l'ecran.
            . 'commande et réception. Le troisième volet reste à vérifier manuellement.',
        'reconstitution' => 'Quantités reçues reconstituées depuis les mouvements de stock, '
            . 'faute de lignes de bon de réception.',
    ],

    /*
     * Validation de l'API M7. Chaque message dit CE QUI est refusé et POURQUOI :
     * un refus muet renvoie l'utilisateur essayer exactement la même chose.
     */
    'validation' => [
        'fournisseur_inexistant' => 'Fournisseur inconnu du référentiel. Un fournisseur se choisit dans la '
            . 'liste, il ne se saisit pas en texte libre : le rapprochement à trois voies suppose une '
            . 'relation exacte.',
        'raison_sociale_obligatoire' => 'La raison sociale est obligatoire.',
        'evaluation_inconnue' => 'Évaluation inconnue. Le registre est fermé : excellent, bon, moyen, a_revoir.',
        'lignes_obligatoires' => 'Une commande d\'achat porte au moins une ligne : une commande vide n\'a '
            . 'rien à réceptionner et fausserait le rapprochement.',
        'article_inexistant' => 'Article inconnu du référentiel.',
        'article_en_double' => 'Le même article figure deux fois. Les quantités commandées sont relues '
            . 'article par article : la seconde ligne écraserait la première, et le rapprochement '
            . 'comparerait le reçu à une quantité commandée sous-évaluée.',
        'quantite_positive' => 'La quantité doit être strictement positive : une saisie à zéro n\'est pas '
            . 'une ligne de commande.',
        'prix_obligatoire' => 'Le prix unitaire est obligatoire : sans lui aucun montant de commande ne '
            . 'peut être calculé, ni aucun coût moyen pondéré mis à jour à la réception.',
        'statut_non_saisissable' => 'Ce statut ne se saisit pas à la création. Réceptionnée, réceptionnée '
            . 'partiellement et clôturée sont produits par une réception réelle, qui seule génère '
            . 'l\'entrée de stock correspondante.',
        'statut_inconnu' => 'Statut de commande inconnu. Un filtre incompris serait ignoré, et la liste '
            . 'entière s\'afficherait sous un intitulé qui promet le contraire.',
        'conformite_inconnue' => 'Filtre de conformité inconnu. Un filtre incompris serait ignoré, et la '
            . 'liste entière s\'afficherait sous un intitulé qui promet le contraire.',
        'identifiant_non_accepte' => 'Une commande d\'achat ne reçoit pas d\'identifiant du client : cette '
            . 'table n\'est pas synchronisable et aucun mécanisme de rejeu n\'existe. En accepter un '
            . 'laisserait croire à une idempotence qui n\'a pas lieu.',
        'valeur_calculee' => 'Cette valeur est calculée depuis les lignes de la commande : elle '
            . 's\'affiche, elle ne se saisit pas. La soumettre n\'aurait aucun effet et laisserait '
            . 'croire le contraire.',
        'reception_lignes_obligatoires' => 'Une réception porte sur au moins un article reçu.',
        'point_inexistant' => 'Point de stockage inconnu : l\'entrée de stock ne peut pas être imputée.',
        'page_trop_grande' => 'Au plus :max éléments par page.',
    ],

    // Règlements fournisseur (PA-165) — trois refus locaux.
    'reglement_tresorerie_inconnue' => 'La trésorerie « :code » n\'existe pas au registre.',
    'reglement_montant_invalide' => 'Le montant réglé doit être supérieur à zéro.',
    'reglement_superieur_au_reste' => 'Le montant dépasse le reste dû (:reste F). Un trop-payé ne s\'enregistre pas : réglez le reste dû exact.',

    // Annulation d'un règlement (PA-168)
    'reglement_deja_annule' => 'Ce règlement est déjà annulé.',
    'reglement_motif_requis' => 'Un motif est obligatoire pour annuler un règlement.',
    'reglement_piece_introuvable' => 'La pièce comptable de ce règlement est introuvable ou déséquilibrée (:libelle) : l\'annulation est refusée plutôt que de contre-passer à moitié.',
];
