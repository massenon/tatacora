<?php

declare(strict_types=1);

/*
 * Messages du domaine CRM (M3).
 */

return [
    'doublon_potentiel' => 'Un client au téléphone identique existe déjà (:nom). '
        // Article 8 (02/09/2026) : la reference RG-18 vit ici, jamais a l'ecran.
        . 'Vérifiez avant de créer un doublon — cet avertissement ne bloque pas l\'enregistrement.',

    'validation' => [
        'nom_requis' => 'Le nom du client est obligatoire.',
        'telephone_requis' => 'Le téléphone est obligatoire — c\'est le principal moyen '
            . 'de retrouver une fiche existante.',
        'type_requis' => 'Le type de client est obligatoire.',
        'type_invalide' => 'Type de client inconnu : particulier, groupe, agence ou structure.',
    ],

    // Relances (PA-165)
    'relance_canal_inconnu' => 'Le canal de relance « :canal » n\'existe pas au registre.',
    'relance_client_inconnu' => 'Ce client n\'existe pas dans le référentiel.',
    'relance_montant_invalide' => 'Le montant réclamé doit être un nombre positif ou nul.',

    /*
     * ARCHIVAGE DU RÉFÉRENTIEL CLIENTS — demande du Product Owner du
     * 03/09/2026. « Supprimer » est le mot du maître (`crud-ui.js` l.100 et
     * l.136) ; le geste, lui, ARCHIVE : `ReferentielClientService` pose
     * `actif = false`. RG-18 pose une fiche client UNIQUE : elle doit
     * survivre à la fin de la relation commerciale, sinon toute réservation,
     * facture ou location qui la cite deviendrait illisible.
     */
    'archivage' => [
        'bouton_ligne' => 'Supprimer',
        'bouton_lot' => 'Supprimer',
        'bouton_restaurer' => 'Restaurer',
        'badge' => 'Archivé',
        'selection_ligne' => 'Sélectionner ce client',
        'selectionnes' => ':nombre sélectionné(s)',
        'verrou_sejour' => 'Il a :nombre séjour(s) en cours ou à venir : la réception a besoin de ce '
            . 'client au sélecteur jusqu\'au départ.',
        'verrou_location' => 'Il a :nombre location(s) de véhicule non terminée(s).',
        'verrou_circuit' => 'Il a :nombre réservation(s) de circuit à venir.',
        'verrou_creance' => 'Il porte :nombre facture(s) non soldée(s) : l\'archiver le retirerait de '
            . 'l\'écran où l\'on décide de le relancer.',
        'succes' => '{1} Client archivé — il reste restaurable.|[2,*] :nombre clients archivés — '
            . 'ils restent restaurables.',
        'restaure' => 'Client « :nom » restauré.',
    ],
];
