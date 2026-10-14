<?php

declare(strict_types=1);

/*
 * Messages du domaine Hebergement (M1).
 */

return [
    // Article 8 (02/09/2026) : la reference RG-01 vit ici, jamais a l'ecran.
    'chevauchement' => 'Cette unité est déjà réservée sur cette période.',

    // PA-115, portée serveur : rouvrir une réservation annulée la ferait
    // revivre sans que son statut change.
    // Article 8 (02/09/2026) : la reference RG-02 vit ici, jamais a l'ecran.
    'annulee_non_modifiable' => 'Une réservation annulée ne se modifie pas.',

    'validation' => [
        'client_inexistant' => "Ce client n'existe pas dans le référentiel.",
        'unite_inexistante' => "Cette unité d'hébergement n'existe pas.",
        'depart_apres_arrivee' => "La date de départ doit être postérieure à la date d'arrivée.",
    ],

    // Lignes de services de la fiche (PA-163). Le refus est TOTAL : une
    // seule ligne fausse refuse la fiche entière — un repli silencieux
    // transformerait une faute de saisie en donnée fausse.
    'ligne_service_inconnu' => 'Le service « :service » n\'existe pas sur une fiche de réservation.',
    'ligne_source_inconnue' => 'Un élément choisi pour le service « :service » n\'existe plus au catalogue. Rouvrez la liste et choisissez à nouveau.',
    'ligne_quantite_invalide' => 'La quantité d\'une ligne de service doit être supérieure à zéro.',

    // Annulation avec commission et remboursement (EF-M1-06).
    'annulation_montant_total_inconnu' => 'Le montant total de cette réservation est inconnu (aucun tarif n\'a été figé à sa création) : le calcul de la commission est refusé plutôt qu\'approximé.',
    'annulation_taux_invalide' => 'Le taux d\'annulation doit être compris entre 0 et 100 %.',
    'annulation_remboursement_negatif' => 'Le montant ou le pourcentage remboursé ne peut pas être négatif.',
    'annulation_mode_remboursement_inconnu' => 'Mode de saisie du remboursement inconnu : « :mode ».',
    'annulation_remboursement_superieur_acompte' => 'Le montant remboursé ne peut pas dépasser l\'acompte réellement encaissé.',
    'annulation_libelle_ecriture' => 'Remboursement annulation — :client',
    'annulation_ligne_ecriture_absente' => 'La pièce comptable du remboursement n\'a pas produit la ligne attendue.',
];
