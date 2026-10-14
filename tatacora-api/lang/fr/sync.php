<?php

declare(strict_types=1);

/*
 * Messages du protocole de synchronisation hors connexion.
 *
 * Ces libelles remontent jusqu'a l'ecran du terminal Flutter : ils indiquent a
 * l'utilisateur pourquoi sa saisie hors connexion n'a pas ete acceptee.
 */

return [
    'table_non_synchronisable' => 'La table « :table » n\'est pas synchronisable. '
        . 'Accepter cette écriture contournerait les règles de gestion de son domaine.',
    'lot_trop_grand' => 'Un lot de synchronisation ne peut pas dépasser :max opérations : '
        . 'découpez en lots successifs.',
    'horodatage_obligatoire' => "L'horodatage client est obligatoire : sans lui, aucun conflit "
        . "ne peut être arbitré par antériorité.",
    'conflit_financier' => 'Modification concurrente sur une donnée financière : '
        // Article 8 (02/09/2026) : la reference RG-17 vit ici, jamais a l'ecran.
        . 'la résolution automatique est interdite. Un responsable doit trancher.',
    'conflit_horodatage' => 'Une saisie plus récente existe déjà côté serveur : '
        . 'votre modification hors connexion a été écartée.',
    'rejet_metier' => 'Opération refusée par une règle de gestion : :raison',
    'poste_non_reconnu' => 'Le poste déclaré ne correspond pas à celui de la session. Reconnectez-vous depuis ce poste.',
];
