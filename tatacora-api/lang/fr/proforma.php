<?php

declare(strict_types=1);

/*
| Facture proforma — messages destinés à l'utilisateur (PO, 07/11/2026).
*/

return [
    'client_requis' => 'Le nom du client est obligatoire.',
    'lignes_requises' => 'Ajoutez au moins une ligne à la proforma.',
    'ligne_invalide' => 'Chaque ligne exige une désignation, une quantité entière et un prix unitaire en francs entiers.',
    'ifu_invalide' => 'L’IFU du client doit compter exactement 13 chiffres.',
    'non_modifiable' => 'Cette proforma est :statut : elle n’est plus modifiable.',
    'motif_requis' => 'Le motif d’annulation est obligatoire.',
    'deja_convertie' => 'Cette proforma est déjà convertie en facture.',
    'annulee' => 'Cette proforma est annulée : elle ne peut pas être convertie.',
    'brouillon_a_convertir' => 'Émettez d’abord la proforma : un brouillon ne se convertit pas en facture.',
    'introuvable' => 'Proforma introuvable.',
    'montant_trop_grand' => 'Le montant de la proforma dépasse la limite admise.',

    'statut' => [
        'brouillon' => 'Brouillon',
        'emise' => 'Émise',
        'convertie' => 'Convertie',
        'annulee' => 'Annulée',
        'expiree' => 'Expirée',
    ],

    'flux' => [
        'libre' => 'Saisie libre',
        'location' => 'Location de véhicule',
        'tourisme' => 'Tourisme',
        'hebergement' => 'Hébergement',
        'evenement' => 'Événement',
    ],

    // PDF A4
    'titre' => 'FACTURE PROFORMA',
    'reference' => 'Réf.',
    'client' => 'Client',
    'ifu' => 'IFU',
    'telephone' => 'Tel',
    'objet' => 'Objet',
    'designation' => 'DÉSIGNATION',
    'quantite' => 'Quantité',
    'prix_unitaire' => 'Prix unitaire (FCFA)',
    'montant' => 'Montant (FCFA)',
    'total' => 'TOTAL',
    'arrete' => 'Arrêté la présente FACTURE PROFORMA à la somme de :',
    'valable_jusqu_au' => 'Valable jusqu’au :date',
    'brouillon_mention' => 'BROUILLON — non numérotée',
    'facebook' => 'Facebook',
    'email' => 'E-mail',
    'rccm' => 'N°RCCM',
    'qtier' => 'Qtier',
];
