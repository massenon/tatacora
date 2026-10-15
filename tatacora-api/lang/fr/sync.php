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

    // Registre de gestionnaires (décision PO du 15/10/2026) — le TYPE annoncé
    // doit correspondre à l'état serveur, et une table qui ne synchronise pas
    // ses modifications le dit, plutôt que d'écrire en brut.
    'modification_non_synchronisable' => 'Modification non synchronisable : cet enregistrement ne se modifie pas '
        . 'hors connexion. Faites la modification depuis l\'écran en ligne.',
    'modification_entite_inconnue' => 'Modification impossible : l\'enregistrement visé n\'existe pas sur le serveur. '
        . 'Sa création n\'a peut-être pas encore été synchronisée, ou a été refusée.',
    'creation_entite_existante' => 'Création refusée : un enregistrement portant cet identifiant existe déjà sur le serveur.',
    'date_metier_invalide' => 'La date du document est illisible : elle doit être une date valide.',
    'archive_valeur_invalide' => 'L\'état d\'archivage transmis est illisible : il doit valoir vrai ou faux.',

    // Téléchargement du catalogue par les postes (décision PO du 15/10/2026).
    'referentiels' => [
        'curseur_invalide' => 'Le curseur de téléchargement est illisible : reprenez le téléchargement depuis le début '
            . '(sans curseur). Aucun élément ne sera perdu, certains seront simplement reçus une seconde fois.',
        'limite_trop_grande' => 'Une page du catalogue compte au plus :max éléments : suivez le curseur pour la suite.',
        'compte_inactif' => 'Ce compte n\'est pas actif : le catalogue ne peut pas être téléchargé.',
    ],

    // Erreurs de PROGRAMMATION (LogicException) : elles remontent en 500 pour
    // rejeu, jamais a l'ecran comme un refus — mais restent en langue (06 §4.4).
    'interne' => [
        'hors_registre' => 'Table « :table » hors registre de synchronisation.',
        'table_incoherente' => 'Le gestionnaire :gestionnaire déclare la table « :declaree », enregistré sous « :cle ».',
        'modification_non_declaree' => 'La table « :table » ne synchronise aucune modification : le moteur n\'aurait pas dû appeler modifier().',
    ],
];
