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
    // Décision PO du 15/10/2026 : une modification dont la cible est inconnue
    // est traitée comme une création (perdue en route) si elle est complète.
    'modification_inconnue_incomplete' => 'Modification impossible : l\'élément n\'existe pas sur le serveur (sa création '
        . 'n\'a pas été reçue), et la modification ne porte pas tout ce qu\'il faut pour le créer : :raison',
    'archivage_non_disponible' => 'Cet élément ne s\'archive pas : seuls les articles, les unités d\'hébergement et les '
        . 'fournisseurs se rangent. La modification n\'a pas été appliquée.',
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

    // Documents (lot S3, décisions PO du 15/10/2026). Chaque refus dit quoi
    // faire : le poste l'affiche à côté du document refusé.
    'caisse' => [
        'champ_non_modifiable' => 'Une clôture de caisse ne transmet que la date de clôture et les montants comptés '
            . '(champ(s) refusé(s) : :champs). Le fond et l\'ouverture d\'un tiroir ne se réécrivent pas.',
    ],
    'factures' => [
        'reservation_inconnue' => 'Facture refusée : la réservation n\'est pas connue du serveur (pas encore reçue, ou refusée).',
        'motif_absent' => 'Annulation saisie sur un poste',
    ],
    'annulation_autre_poste' => 'Annulation refusée : ce document a été saisi sur un autre poste (ou au serveur). '
        . 'Seuls l\'administration et le comptable peuvent l\'annuler.',
    'reservations' => [
        'champ_non_modifiable' => 'Une réservation ne se modifie que par son annulation (avec ses conditions) ou par son '
            . 'déplacement (chambre, dates) — champ(s) refusé(s) : :champs.',
        'annulee' => 'Déplacement refusé : la réservation est annulée.',
    ],
    'ventes_modification' => [
        'champ_non_modifiable' => 'Une vente ne se modifie que par son annulation (statut annulee + motif).',
    ],
    'commandes' => [
        'statut_inconnu' => 'Commande : seuls l\'envoi (envoyee) et la clôture (cloturee) se synchronisent.',
    ],
    'tables' => [
        'espace_invalide' => 'Table refusée : l\'espace « :espace » n\'existe pas (ou n\'a pas de tables).',
        'champ_non_modifiable' => 'Une table ne se modifie que par son numéro, ses places et son activation '
            . '(champ(s) refusé(s) : :champs).',
        'inconnue' => 'Table refusée : la table n\'est pas connue du serveur (pas encore reçue, ou refusée).',
        'occupee' => 'Table :libelle déjà occupée par un autre poste (ou à la PWA) : encaissez ou libérez '
            . 'la table là-bas avant de l\'ouvrir ici.',
    ],
    'reglements' => [
        'commande_inconnue' => 'Règlement refusé : la commande n\'est pas connue du serveur (pas encore reçue, ou refusée).',
    ],
    'vehicules' => [
        'champ_non_modifiable' => 'Un véhicule ne se modifie que par sa catégorie, son immatriculation, son tarif '
            . 'et son statut (champ(s) refusé(s) : :champs).',
        'statut_non_synchronisable' => 'Statut « :statut » refusé : « loué » se déduit des contrats.',
        'inconnu' => 'Contrat refusé : le véhicule n\'est pas connu du serveur (pas encore reçu, ou refusé).',
        'client_inconnu' => 'Contrat refusé : le client n\'est pas connu du serveur (pas encore reçu, ou refusé).',
    ],
    'rh' => [
        'service_inconnu' => 'Employé refusé : le service « :libelle » n\'existe pas au serveur.',
        'employe_inconnu' => 'Bulletin refusé : l\'employé n\'est pas connu du serveur (pas encore reçu, ou refusé).',
        'champ_non_modifiable' => 'Champ(s) d\'employé non synchronisable(s) : :champs.',
    ],
    'paiements' => [
        'facture_inconnue' => 'Encaissement refusé : la facture n\'est pas connue du serveur (pas encore reçue, ou refusée).',
    ],
    'sejours' => [
        'reservation_inconnue' => 'Séjour refusé : la réservation n\'est pas connue du serveur (pas encore reçue, ou refusée).',
        'instant_illisible' => 'Séjour refusé : l\'heure « :valeur » est illisible.',
    ],
    'ventes' => [
        'note_chambre_incoherente' => 'Vente refusée : une vente sur séjour se porte sur la note de chambre, et la note de chambre n\'existe qu\'au séjour.',
        'reservation_inconnue' => 'Vente sur note de chambre refusée : la réservation n\'est pas connue du serveur (pas encore reçue, ou refusée).',
        'note_chambre_hors_perimetre' => 'Les consommations portées sur la note de chambre ne se synchronisent pas encore : '
            . 'la clôture du séjour émet la facture, qui relève d\'un lot ultérieur. Clôturez ce séjour depuis l\'écran en ligne.',
        'total_incoherent' => 'Le total de la vente (:annonce F) ne correspond pas à la somme de ses lignes (:lignes F) : '
            . 'le document est incohérent, le serveur ne peut pas savoir lequel des deux a été encaissé.',
    ],
    'depenses' => [
        'centre_introuvable' => 'Le centre de coût « :centre » est introuvable sur le serveur. La dépense n\'est pas '
            . 'enregistrée : l\'imputer à un autre centre fausserait l\'analytique (RG-12). Mettez à jour le référentiel du poste.',
    ],
    'receptions' => [
        'commande_inconnue' => 'La commande de ce bon de réception est inconnue du serveur : synchronisez la commande '
            . 'avant ses réceptions (elle a peut-être été refusée — voir son motif).',
    ],

    // Erreurs de PROGRAMMATION (LogicException) : elles remontent en 500 pour
    // rejeu, jamais a l'ecran comme un refus — mais restent en langue (06 §4.4).
    'interne' => [
        'hors_registre' => 'Table « :table » hors registre de synchronisation.',
        'table_incoherente' => 'Le gestionnaire :gestionnaire déclare la table « :declaree », enregistré sous « :cle ».',
        'modification_non_declaree' => 'La table « :table » ne synchronise aucune modification : le moteur n\'aurait pas dû appeler modifier().',
    ],
];
