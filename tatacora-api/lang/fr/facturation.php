<?php

declare(strict_types=1);

/*
 * Messages du domaine Facturation (M2).
 */

return [
    'immuable' => 'La facture :numero est certifiée : elle ne peut plus être modifiée '
        // Article 8 (02/09/2026) : la reference RG-03 vit ici, jamais a l'ecran.
        . 'ni supprimée. Émettez un avoir pour la corriger.',
    // Article 8 (02/09/2026) : la reference RG-03 vit ici, jamais a l'ecran.
    'immuable_sans_numero' => 'Cette facture ne peut être ni modifiée ni supprimée. '
        . 'La seule correction possible est l\'émission d\'un avoir.',
    'avoir_sur_non_certifiee' => 'Un avoir ne se rattache qu\'à une facture certifiée : '
        . 'une facture brouillon se corrige directement.',
    // Article 8 (02/09/2026) : la reference RG-03 vit ici, jamais a l'ecran.
    'ligne_sur_certifiee' => 'Aucune ligne ne peut être ajoutée à une facture certifiée.',
    'deja_certifiee' => 'Cette facture est déjà certifiée : la recertifier écraserait son NIM.',
    'avoir_montant_excessif' => 'Le montant de l\'avoir ne peut pas dépasser celui de la facture.',
    'libelle_avoir' => 'Avoir sur facture :numero',

    // Encaissement (PA-165) — quatre refus locaux, tous corrigibles sur place.
    'encaissement_facture_non_figee' => 'Cette facture n\'est pas encore figée : émettez-la avant d\'encaisser.',
    'encaissement_mode_inconnu' => 'Le mode de paiement « :mode » n\'existe pas au registre.',
    'encaissement_montant_invalide' => 'Le montant encaissé doit être supérieur à zéro.',
    'encaissement_superieur_au_reste' => 'Le montant dépasse le reste dû (:reste F). Un trop-perçu ne s\'enregistre pas : encaissez le reste dû exact.',
    'encaissement_caisse_fermee' => 'Aucune session de caisse n\'est ouverte : ouvrez la caisse avant d\'encaisser.',

    // Annulation d'un encaissement (PA-168)
    'paiement_deja_annule' => 'Cet encaissement est déjà annulé.',
    'paiement_motif_requis' => 'Un motif est obligatoire pour annuler un encaissement.',
    'paiement_piece_introuvable' => 'La pièce comptable de cet encaissement est introuvable ou déséquilibrée (:libelle) : l\'annulation est refusée plutôt que de contre-passer à moitié.',
];
