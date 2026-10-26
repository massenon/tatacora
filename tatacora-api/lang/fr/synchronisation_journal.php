<?php

declare(strict_types=1);

/*
 * Les journaux de la synchronisation, lus à l'écran « Postes & Appairage »
 * (onglets « Réception » et « Envoi ») : ce que le serveur reçoit des postes,
 * ce qu'il met à leur disposition, et — pour chaque échec — sa cause en
 * français, avec ce qu'il faut faire.
 *
 * Aucun code interne ni nom de table brute n'est rendu : les tables ont un
 * libellé métier (`tables`), les motifs une phrase (`motifs`).
 */

return [
    'issues' => [
        'acceptee' => 'Acceptée',
        'fusionnee' => 'Fusionnée',
        'dupliquee' => 'Déjà reçue',
        'signalee' => 'Acceptée avec signalement',
        'conservee' => 'Version du serveur conservée',
        'conflit' => 'Conflit à trancher',
        'rejetee' => 'Rejetée',
        'erreur' => 'Erreur du serveur',
    ],

    'types' => [
        'creation' => 'Création',
        'modification' => 'Modification',
    ],

    'traitements' => [
        'a_traiter' => 'À traiter',
        'corrige' => 'Corrigée, à relancer',
        'relance' => 'Relancée et acceptée',
        'ignore' => 'Ignorée',
    ],

    'tables' => [
        'reservations' => 'Réservation',
        'sejours' => 'Séjour',
        'clients' => 'Client',
        'relances_clients' => 'Relance de client',
        'fournisseurs' => 'Fournisseur',
        'points_stockage' => 'Point de stockage',
        'articles' => 'Article',
        'cartes_boisson' => 'Boisson de la carte',
        'menus' => 'Menu',
        'recettes' => 'Fiche technique',
        'plats' => 'Plat',
        'indisponibilites_carte' => 'Retrait de la carte',
        'categories_hebergement' => 'Catégorie d\'hébergement',
        'unites_hebergement' => 'Unité d\'hébergement',
        'commandes_achat' => 'Commande d\'achat',
        'bons_reception' => 'Bon de réception',
        'reglements_fournisseur' => 'Règlement fournisseur',
        'sessions_caisse' => 'Session de caisse',
        'tables_salle' => 'Table de salle',
        'paniers' => 'Panier de table',
        'ventes' => 'Vente',
        'depenses' => 'Dépense',
        'factures' => 'Facture',
        'paiements' => 'Paiement de facture',
        'circuits' => 'Circuit',
        'guides' => 'Guide',
        'reservations_tour' => 'Réservation de circuit',
        'vehicules' => 'Véhicule',
        'contrats_location' => 'Contrat de location',
        'entretiens_vehicule' => 'Entretien de véhicule',
        'employes' => 'Employé',
        'bulletins_paie' => 'Bulletin de paie',
        'plannings' => 'Planning',
        'conges' => 'Congé',
        'parametres_systeme' => 'Paramètre du système',
        'roles' => 'Rôle',
        'mouvements_stock' => 'Mouvement de stock',
        'modeles_notification' => 'Modèle de notification',
        'immobilisations' => 'Immobilisation',
        'canaux_reservation' => 'Canal de réservation',
        'inventaires' => 'Inventaire',
        'avoirs' => 'Avoir',
        'services' => 'Service',
        'centres_cout' => 'Centre de coût',
        'exercices_comptables' => 'Exercice comptable',
        'ecritures_comptables' => 'Écriture comptable',
    ],

    // Le motif d'un rejet : `phrase` est le titre court, `cause` explique
    // pourquoi et ce qu'il faut faire. `:module`, `:table`, `:detail` sont
    // remplacés au moment de l'enregistrement.
    'motifs' => [
        'table_non_synchronisable' => [
            'phrase' => 'Type de donnée non accepté par le serveur',
            'cause' => 'Le poste a envoyé des données de type « :table », que le serveur n\'accepte pas de recevoir. '
                . 'Mettez le poste à jour ; cette opération ne peut pas être rejouée.',
        ],
        'compte_inactif' => [
            'phrase' => 'Compte du poste inactif',
            'cause' => 'Le compte qui a saisi cette opération sur le poste est suspendu, désactivé ou supprimé. '
                . 'Réactivez-le, puis relancez l\'opération.',
        ],
        'droit_manquant' => [
            'phrase' => 'Droit manquant',
            'cause' => 'Le compte qui a saisi cette opération n\'a pas le droit d\'écrire dans le module « :module ». '
                . 'Accordez ce droit à son rôle (Rôles & Permissions), puis relancez l\'opération.',
        ],
        'modification_non_synchronisable' => [
            'phrase' => 'Modification impossible hors connexion',
            'cause' => 'Ce type d\'enregistrement ne se modifie pas depuis un poste. Faites la modification depuis '
                . 'l\'écran en ligne du serveur, puis ignorez cette opération.',
        ],
        'date_metier_invalide' => [
            'phrase' => 'Date du document illisible',
            'cause' => 'La date portée par le document n\'est pas une date valide. Corrigez-la dans la charge reçue, '
                . 'puis relancez.',
        ],
        'chevauchement' => [
            'phrase' => 'Chevauchement avec un autre enregistrement',
            'cause' => 'Cet enregistrement entre en conflit avec un autre déjà présent (même ressource, mêmes dates). '
                . 'Libérez l\'autre enregistrement ou modifiez les dates dans la charge reçue, puis relancez.',
        ],
        'donnees_invalides' => [
            'phrase' => 'Données invalides',
            'cause' => 'Une ou plusieurs valeurs du document ne respectent pas les règles de saisie : :detail '
                . 'Corrigez-les dans la charge reçue, puis relancez.',
        ],
        'entite_existante' => [
            'phrase' => 'Création sur un identifiant déjà utilisé',
            'cause' => 'Le poste annonce une création, mais un enregistrement portant le même identifiant existe déjà '
                . 'sur le serveur. Vérifiez qu\'il ne s\'agit pas d\'un doublon, puis ignorez cette opération.',
        ],
        'entite_inconnue' => [
            'phrase' => 'Enregistrement inconnu du serveur',
            'cause' => 'Le poste modifie un enregistrement que le serveur ne connaît pas : sa création n\'a pas été '
                . 'reçue, ou a été refusée. Retrouvez la création de cet enregistrement dans la liste, '
                . 'corrigez-la, puis relancez les deux opérations dans l\'ordre.',
        ],
        'stock_insuffisant' => [
            'phrase' => 'Stock insuffisant',
            'cause' => 'Le stock du serveur ne couvre pas cette sortie. Enregistrez l\'entrée de stock manquante, '
                . 'puis relancez l\'opération.',
        ],
        'recette_manquante' => [
            'phrase' => 'Fiche technique manquante',
            'cause' => 'Un plat de ce document n\'a pas de fiche technique sur le serveur. Complétez la fiche du '
                . 'plat, puis relancez l\'opération.',
        ],
        'refus_caisse' => [
            'phrase' => 'Refus de la caisse',
            'cause' => 'La règle de la caisse refuse cette opération (session, point de vente ou montant). '
                . 'Vérifiez la session de caisse concernée, puis relancez ou ignorez l\'opération.',
        ],
        'piece_immuable' => [
            'phrase' => 'Pièce déjà figée',
            'cause' => 'La pièce visée est validée ou certifiée : elle ne peut plus être modifiée. '
                . 'Passez par une contre-passation ou un avoir, puis ignorez cette opération.',
        ],
        'regle_metier' => [
            'phrase' => 'Refusée par une règle de gestion',
            'cause' => 'Une règle de gestion du serveur refuse cette opération : « :detail » '
                . 'Corrigez la charge reçue si la valeur en cause est modifiable, puis relancez.',
        ],
        'conflit_financier' => [
            'phrase' => 'Modification concurrente sur une donnée financière',
            'cause' => 'Le serveur et le poste ont modifié la même donnée financière : aucune résolution '
                . 'automatique n\'est permise. Un responsable doit trancher, puis marquer l\'opération comme traitée.',
        ],
        'version_serveur_conservee' => [
            'phrase' => 'Version du serveur conservée',
            'cause' => 'Une saisie plus récente existait déjà sur le serveur : la modification du poste, plus ancienne, '
                . 'n\'a pas été appliquée. Rien à faire sauf si la modification du poste devait l\'emporter.',
        ],
        'erreur_serveur' => [
            'phrase' => 'Erreur imprévue du serveur',
            'cause' => 'Le serveur a rencontré une erreur imprévue en traitant cette opération. Le poste la renverra '
                . 'automatiquement ; si l\'erreur persiste, signalez-la à l\'éditeur.',
        ],
        'rejeu' => [
            'phrase' => 'Opération déjà reçue',
            'cause' => 'Le poste a renvoyé une opération que le serveur avait déjà traitée : le résultat d\'origine '
                . 'a été rendu, rien n\'a été écrit une seconde fois.',
        ],
        'document_deja_enregistre' => [
            'phrase' => 'Document déjà enregistré',
            'cause' => 'Ce document existait déjà sur le serveur sous le même identifiant : il n\'a pas été enregistré '
                . 'une seconde fois.',
        ],
        'fusion' => [
            'phrase' => 'Fusionné avec un enregistrement existant',
            'cause' => 'Un enregistrement équivalent existait déjà sur le serveur : celui du poste y a été rattaché, '
                . 'sans doublon.',
        ],
    ],

    // Les écarts signalés en acceptant un document.
    'anomalies' => [
        'ecart_prix' => 'Écart de prix avec le catalogue du serveur',
        'vente_en_rupture' => 'Vente enregistrée alors que le stock du serveur était épuisé',
        'vente_session_inconnue' => 'Vente rattachée à une caisse que le serveur ne connaît pas',
        'vente_session_cloturee' => 'Vente rattachée à une caisse déjà clôturée sur le serveur',
        'ecart_theorique_caisse' => 'Écart entre le théorique de caisse du poste et celui du serveur',
        'ecart_conformite_reception' => 'Conformité de la réception jugée autrement par le serveur',
        'plat_sans_composition' => 'Plat vendu sans composition : aucune sortie de stock sur le serveur',
        'cloture_session_inconnue' => 'Clôture d\'une caisse que le serveur ne connaît pas',
        'guide_sans_tarif' => 'Guide créé sans tarif journalier : enregistré à 0, tarif à saisir',
        'vehicule_sans_annee' => 'Véhicule créé sans année ni capacité : à compléter',
        'mouvement_rupture_serveur' => 'Sortie de stock que le stock du serveur ne couvrait pas',
        'bulletin_ecart_net' => 'Bulletin recalculé avec un net différent de celui du poste',
        'paiement_facture_non_certifiee' => 'Encaissement d\'une facture non certifiée',
        'paiement_session_inconnue' => 'Encaissement d\'une caisse inconnue du serveur',
    ],

    // Les libellés des champs de la charge, pour le formulaire de correction.
    'champs' => [
        'libelle' => 'Libellé',
        'nom' => 'Nom',
        'prenom' => 'Prénom',
        'montant' => 'Montant',
        'montant_total' => 'Montant total',
        'montant_cloture' => 'Montant annoncé par le poste',
        'prix_unitaire' => 'Prix unitaire',
        'prix_vente' => 'Prix de vente',
        'quantite' => 'Quantité',
        'date' => 'Date',
        'cloture_le' => 'Clôturée le',
        'date_reception' => 'Date de réception',
        'date_arrivee' => 'Arrivée',
        'date_depart' => 'Départ',
        'client_nom' => 'Nom du client',
        'mode_paiement' => 'Mode de paiement',
        'point_vente' => 'Point de vente',
        'remise_type' => 'Type de remise',
        'remise_valeur' => 'Valeur de la remise',
        'motif' => 'Motif',
        'statut' => 'Statut',
        'notes' => 'Notes',
        'telephone' => 'Téléphone',
        'email' => 'Adresse e-mail',
        'type_vente' => 'Type de vente',
        'table' => 'Table',
        'lignes' => 'Lignes',
        'categorie' => 'Catégorie',
        'description' => 'Description',
        'fournisseur' => 'Fournisseur',
        'immatriculation' => 'Immatriculation',
        'seuil_alerte' => 'Seuil d\'alerte',
    ],

    // L'écran « Postes & Appairage » — onglets Réception et Envoi.
    'ecran' => [
        'onglet_postes' => 'Postes',
        'onglet_reception' => 'Réception',
        'onglet_envoi' => 'Envoi',
        'actualiser' => 'Actualiser',
        'jamais' => '—',
        'acces_refuse' => 'Ces journaux sont réservés aux Administrateurs et au Comptable.',

        'reception_titre' => 'Ce que le serveur a reçu des postes',
        'reception_intro' => 'Chaque opération envoyée par un poste est consignée ici avec son issue et, pour un échec, '
            . 'sa cause. Corrigez la donnée en cause, puis relancez : l\'opération est rejouée par le même chemin que '
            . 'la synchronisation, sans doublon.',
        'compteur_total' => 'Opérations reçues',
        'compteur_acceptees' => 'Acceptées',
        'compteur_a_traiter' => 'À traiter',
        'compteur_rejetees' => 'Rejetées',
        'compteur_rejeux' => 'Déjà reçues',
        'compteur_signalees' => 'Signalées',

        'filtre_poste' => 'Poste',
        'filtre_table' => 'Donnée',
        'filtre_issue' => 'Issue',
        'filtre_periode' => 'Période',
        'filtre_a_traiter' => 'À traiter seulement',
        'tous_postes' => 'Tous les postes',
        'toutes_donnees' => 'Toutes les données',
        'toutes_issues' => 'Toutes les issues',
        'periode_aujourdhui' => 'Aujourd\'hui',
        'periode_7j' => '7 derniers jours',
        'periode_30j' => '30 derniers jours',
        'periode_toutes' => 'Tout l\'historique',

        'col_recu_le' => 'Reçue le',
        'col_envoyee_le' => 'Envoyée par le poste le',
        'col_poste' => 'Poste',
        'col_utilisateur' => 'Utilisateur',
        'col_donnee' => 'Donnée',
        'col_type' => 'Type',
        'col_issue' => 'Issue',
        'col_motif' => 'Motif',
        'col_tentatives' => 'Envois',
        'col_actions' => 'Actions',
        'aucune_operation' => 'Aucune opération reçue pour ces critères.',
        'detail' => 'Détail',
        'fermer' => 'Fermer',

        'detail_titre' => 'Opération reçue du poste « :poste »',
        'detail_cause' => 'Cause',
        'detail_motif_poste' => 'Phrase rendue au poste',
        'detail_charge' => 'Charge reçue',
        'detail_corrigee' => 'Charge corrigée',
        'detail_erreurs' => 'Valeurs refusées',
        'detail_signalements' => 'Signalements',
        'detail_traitement' => 'Prise en charge',
        'detail_traite_par' => 'Par :nom le :date',
        'detail_motif_traitement' => 'Motif : :motif',
        'detail_recu' => 'Reçue le :date, envoyée par le poste le :envoyee',
        'detail_envois' => 'Reçue :n fois, dernière tentative le :date',
        'detail_entite' => 'Identifiant de l\'enregistrement',
        'detail_conflits' => 'Enregistrements en conflit',

        'corriger' => 'Corriger',
        'relancer' => 'Relancer',
        'ignorer' => 'Marquer comme traité',
        'corriger_titre' => 'Corriger la charge reçue',
        'corriger_aide' => 'Modifiez les valeurs en cause. La correction est vérifiée par les règles de gestion du '
            . 'module concerné avant d\'être enregistrée ; elle est tracée à votre nom. Les identifiants ne se modifient pas.',
        'corriger_enregistrer' => 'Vérifier et enregistrer',
        'corriger_annuler' => 'Annuler',
        'corriger_valide' => 'Correction enregistrée : la charge respecte les règles. Relancez l\'opération pour l\'appliquer.',
        'corriger_refusee' => 'Correction refusée : :motif',
        'corriger_aucun_champ' => 'Aucune valeur n\'a été modifiée.',
        'champ_lecture_seule' => 'non modifiable',
        'ligne_numero' => 'Ligne :n',

        'relance_reussie' => 'Opération rejouée avec succès : :issue.',
        'relance_echouee' => 'L\'opération a été rejouée mais reste en échec : :motif',
        'relance_deja_aboutie' => 'Cette opération a déjà abouti : il n\'y a rien à relancer.',
        'relance_impossible' => 'Cette opération n\'est pas en échec : il n\'y a rien à relancer.',
        'relance_charge_absente' => 'La charge de cette opération n\'a pas été conservée : elle ne peut pas être rejouée.',

        'ignorer_titre' => 'Marquer comme traité',
        'ignorer_aide' => 'L\'opération ne sera pas rejouée. Indiquez pourquoi (par exemple : saisie refaite sur le serveur) : '
            . 'le motif est conservé avec votre nom.',
        'ignorer_motif' => 'Motif',
        'ignorer_confirmer' => 'Marquer comme traité',
        'ignorer_motif_requis' => 'Indiquez le motif : il est conservé avec votre nom.',
        'ignorer_fait' => 'Opération marquée comme traitée.',

        'refus_droit' => 'Vous n\'avez pas le droit d\'écrire dans le module « :module » : l\'action est refusée.',
        'refus_role' => 'Cette action est réservée aux Administrateurs et au Comptable.',
        'refus_admin' => 'Cette action est réservée aux Administrateurs.',
        'refus_inconnue' => 'Cette opération n\'existe plus dans le journal.',
        'refus_non_modifiable' => 'Cette opération a déjà été prise en charge.',

        'envoi_titre' => 'Ce que le serveur a mis à disposition des postes',
        'envoi_intro' => 'Chaque poste télécharge le catalogue et les documents des autres postes par pages, depuis un '
            . 'curseur qu\'il conserve. Cet onglet montre, poste par poste, ce qu\'il a reçu et ce qui l\'attend.',
        'envoi_col_poste' => 'Poste',
        'envoi_col_passage' => 'Dernier passage',
        'envoi_col_etat' => 'État du téléchargement',
        'envoi_col_livres' => 'Éléments livrés',
        'envoi_col_droits' => 'Non livrés (droits)',
        'envoi_col_refus' => 'Refus « données réinitialisées »',
        'envoi_col_actions' => 'Actions',
        'envoi_aucun_poste' => 'Aucun poste n\'a encore téléchargé le catalogue.',
        'envoi_complet' => 'À jour',
        'envoi_en_cours' => 'Téléchargement en cours',
        'envoi_redescente_demandee' => 'Redescente demandée le :date',
        'envoi_redescente_faite' => 'Redescendu depuis le début le :date',
        'envoi_voir' => 'Voir le détail',
        'envoi_detail_titre' => 'Poste « :poste » : ce qu\'il a reçu',
        'envoi_detail_col_donnee' => 'Donnée',
        'envoi_detail_col_livres' => 'Livrés',
        'envoi_detail_col_dernier' => 'Dernière livraison',
        'envoi_detail_col_restants' => 'Restent à livrer',
        'envoi_detail_col_droits' => 'Non livrés faute de droit',
        'envoi_detail_aucune' => 'Rien n\'a encore été livré à ce poste.',
        'envoi_dernier_curseur' => 'Dernier curseur rendu au poste : :curseur',
        'envoi_aucun_curseur' => 'Aucun curseur rendu : le poste repart du début.',
        'envoi_perime_le' => 'Dernier refus le :date (:n au total) : le poste a travaillé sur des données d\'avant une réinitialisation.',
        'envoi_aucun_refus' => 'Aucun refus.',
        'redescendre' => 'Redescendre depuis le début',
        'redescendre_titre' => 'Redescendre depuis le début le poste « :poste » ?',
        'redescendre_texte' => 'Au prochain passage du poste, le serveur ignorera son curseur et lui livrera de nouveau '
            . 'tout le catalogue et tous les documents. Rien n\'est supprimé sur le poste ; les éléments déjà présents '
            . 'sont simplement remplacés par la version du serveur.',
        'redescendre_confirmer' => 'Redescendre depuis le début',
        'redescendre_fait' => 'Redescente demandée pour le poste « :poste » : il repartira du début à son prochain passage.',
        'redescendre_deja' => 'Une redescente est déjà demandée pour le poste « :poste ».',
        'poste_inconnu' => 'Ce poste n\'est pas connu du serveur.',
    ],
];
