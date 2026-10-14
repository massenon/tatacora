<?php

declare(strict_types=1);

/*
 * Messages du domaine Rh (M13).
 */

return [

    'archivage' => [
        // Directive PO du 02/09/2026 : supprimer = archiver (statut « parti »).
        'deja_parti' => ':nom est déjà archivé (statut « parti »).',
    ],
    // --- Planning (EF-M13-02, RG-13)
    'planning_chevauchement' => 'Cet employé est déjà planifié sur un créneau qui recouvre '
        // Article 8 (02/09/2026) : la reference RG-13 vit ici, jamais a l'ecran.
        . 'celui-ci.',
    'employe_hors_effectif' => 'Cet employé n\'est pas en poste (:statut) : il ne peut pas être planifié.',
    'employe_en_conge' => 'Cet employé est en congé validé le :date.',

    // --- Congés (EF-M13-04, RG-14)
    'conge_deja_traite' => 'Cette demande a déjà été validée ou refusée.',
    // Article 8 (02/09/2026) : la reference RG-14 vit ici, jamais a l'ecran.
    'preavis_insuffisant' => 'Préavis insuffisant : :reel jour(s) au lieu des :exige exigés.',
    'couverture_insuffisante' => 'Couverture de service compromise : :restants employé(s) resteraient '
        // Article 8 (02/09/2026) : la reference RG-14 vit ici, jamais a l'ecran.
        . 'en poste pour un minimum de :minimum.',
    'parametre_absent' => 'Le paramètre « :cle » n\'est pas configuré. '
        // Article 8 (02/09/2026) : la reference RG-14 vit ici, jamais a l'ecran.
        . 'Aucune validation de congé n\'est possible tant qu\'un Administrateur ne l\'a pas renseigné.',

    // --- Paie (EF-M13-07)
    'taux_absent' => 'Le taux « :cle » n\'est pas paramétré. Aucun calcul de paie n\'est effectué '
        . 'tant qu\'il n\'est pas renseigné — un bulletin faux est une déclaration sociale erronée.',
    'bareme_its_non_confirme' => 'Revenu imposable de :revenu F, au-delà du plafond confirmé de :plafond F. '
        . 'La structure du barème ITS au-delà de ce seuil n\'est pas tranchée : deux sources divergent '
        . '(taux unique de 30 % contre palier supplémentaire à 40 %). Le calcul est refusé plutôt '
        // Article 8 (02/09/2026) : la reference PA-53 vit ici, jamais a l'ecran.
        . 'qu\'extrapolé — à faire confirmer auprès de la DGI.',
];
