<?php

declare(strict_types=1);

/*
 * LIBELLES DES DEUX ECRANS M1 DE LA PWA — vague CRUD du 31/08/2026.
 *
 * Maquettes : `prototype_v2/pages/m1-hebergement.html` et
 * `prototype_v2/pages/reservations.html`.
 *
 * ## Pourquoi un fichier a cote de `lang/fr/pwa.php`
 *
 * `pwa.php` porte deja les libelles M1 de la vague de consultation, et ils
 * restent valables : titres, onglets, colonnes, mention du calendrier. Ce
 * fichier-ci porte ce que la vague d'ECRITURE ajoute — les formulaires, les
 * gestes du cycle operationnel, et surtout les REFUS, qui ont change de
 * raison.
 *
 * ⚠ TROIS MOTIFS DE REFUS DE `pwa.php` ETAIENT PERIMES ; ILS ONT ETE SUPPRIMES
 * LE 31/08/2026 (PA-144 — un motif qui a cesse d'etre vrai transforme une
 * decision en oubli). Ils sont nommes ici pour l'histoire, pas comme des cles
 * a lire — aucune des trois n'existe plus :
 *
 *  - `refus_cycle` : « la colonne `unites_hebergement.statut` n'est ecrite par
 *    personne ». FAUX depuis que `SejourService` l'ecrit par ses trois gestes
 *    (check-in, check-out, menage). Le cycle est porte.
 *  - `refus_crud` : « la consultation web est en lecture seule stricte ».
 *    FAUX depuis la decision du Product Owner du 28/08/2026 (PA-159).
 *  - `refus_reservation_rapide` : « la modale n'est pas rendue : creer une
 *    reservation ecrit ». FAUX pour la meme raison.
 *
 * Ils sont REMPLACES par les cles `refus_*` ci-dessous, qui disent ce qui est
 * reellement refuse et pourquoi, a la date du 31/08/2026. La purge a porte sur
 * 255 cles de six sections de `pwa.php` : voir l'en-tete de ce fichier-la.
 *
 * ⚠ La meme regle vaut pour les refus de CE fichier : chacun porte sa date, et
 * `refus_historique_client` a du etre reecrit le jour meme de son ecriture, son
 * premier motif ayant cesse d'etre vrai dans la journee. Verifiez la raison
 * avant de vous y fier.
 *
 * ## Les libelles du maitre qui ne sont PAS rendus sont cites VERBATIM ici
 *
 * `prototype_v2/tests/t-trois-sources.js` compare chaque libelle du maitre au
 * code qui porte la page : un libelle doit etre rendu OU nomme comme refuse.
 * Les textes de refus ci-dessous citent donc les mots exacts du maitre, entre
 * guillemets — c'est ce qui rend le refus verifiable, et c'est aussi ce que
 * l'utilisateur lit a l'ecran.
 */

return [

    /*
     * ============================================================
     * Plan d'Hebergement — `prototype_v2/pages/m1-hebergement.html`
     * ============================================================
     */
    'hebergement' => [

        // ---- Cycle operationnel : les quatre boutons de carte du maitre
        // (`m1-hebergement.html` l.166-171, ACTION_PAR_STATUT). Ils sont
        // PORTES depuis le 31/08/2026 : `SejourService` ecrit reellement le
        // cycle, et l'ecran n'affiche donc plus une colonne morte (PA-126).
        'action_reserver' => 'Réserver cette unité',
        'action_checkin' => 'Effectuer Check-In Client',
        'action_checkout' => 'Effectuer Check-Out',
        'action_nettoye' => 'Marquer Nettoyé & Prêt',
        'action_indisponible' => 'Indisponible',
        'action_restaurer' => 'Réintégrer au parc',

        // ---- Pastilles. ⚠ Elles disent la DISPONIBILITE DU JOUR, derivee des
        // reservations actives (RG-02) et du sejour en cours, jamais lue de
        // `unites_hebergement.statut` — l'arbitrage est en tete de
        // `App\Domain\Hebergement\Services\SejourService`.
        'pastille_occupee' => 'Occupée',
        'pastille_nettoyage' => 'Nettoyage',

        // ---- Actions de parc
        'bouton_ajouter' => 'Ajouter hébergement',
        'action_modifier' => 'Modifier',
        'action_supprimer' => 'Supprimer',

        // ---- Modale « Ajouter / Modifier un hébergement »
        'modale_unite_creation' => 'Ajouter hébergement',
        'modale_unite_modification' => 'Modifier l\'hébergement',
        'modale_unite_sous_titre' => 'Parc du Gîte Chez Noël — bungalows, chambres et tentes.',
        'champ_code' => 'Code unité',
        'champ_code_invite' => 'Ex. BNG-03',
        'champ_categorie' => 'Catégorie',
        'champ_categorie_invite' => 'Choisir une catégorie…',
        'nouvelle_categorie' => '+ Nouvelle catégorie',
        'categorie_libelle' => 'Libellé de la catégorie (Bungalow, Chambre simple, Suite…)',
        'categorie_tarif' => 'Tarif par nuit (FCFA)',
        'categorie_capacite' => 'Capacité (personnes)',
        'enregistrer' => 'Enregistrer',

        // ---- Modale « Réservation rapide » (maquette l.62-126)
        'modale_rapide_titre' => 'Réservation rapide',
        'champ_client' => 'Client',
        'champ_client_invite' => 'Choisir un client…',
        'champ_arrivee' => 'Arrivée',
        'champ_depart' => 'Départ',
        'nombre_nuits' => 'Nombre de nuits',
        'montant_hebergement' => 'Montant hébergement',
        'nuits' => ':nombre nuit(s)',
        'bouton_rapide' => 'Enregistrer et compléter plus tard',
        // maquette — l.120-123, rendu tel quel.
        'rapide_pied' => 'La réservation est créée avec l\'hébergement seul. Restauration, bar, '
            .'tourisme et véhicule s\'ajoutent dans Réservations.',
        'depart_apres_arrivee' => 'La date de départ doit être postérieure à la date d\'arrivée.',

        // ---- Archivage du parc
        'archivage_element' => 'l\'unité :numero',
        'archivage_verrou' => 'Élément engagé dans :nombre opération(s) : :details. Il ne peut pas être '
            .'archivé — la ligne correspondante deviendrait illisible.',
        'archivage_detail_reservation' => 'réservation du :arrivee au :depart',
        'archivee' => 'Unité :numero retirée du parc : elle n\'est plus commercialisable, et rien n\'est effacé.',
        'restauree' => 'Unité :numero réintégrée au parc.',

        // ---- Retours de geste
        'checkin_fait' => 'Check-in effectué : :client occupe l\'unité :numero.',
        'checkout_fait' => 'Check-out effectué. L\'unité :numero passe en nettoyage avant d\'être reproposée.',
        'nettoyee' => 'L\'unité :numero est prête et de nouveau disponible.',
        'unite_enregistree' => 'Unité « :numero » enregistrée.',
        'reservation_creee' => 'Réservation enregistrée pour :client — :nuits nuit(s) sur l\'unité :numero.',
        'checkin_impossible' => 'Aucune arrivée n\'est attendue aujourd\'hui sur l\'unité :numero.',
        'checkout_impossible' => 'Aucun séjour en cours sur l\'unité :numero.',

        // ---- Export
        'export_titre' => 'Exporter — Unités d\'hébergement',
        'export_sous_titre' => 'Le parc tel qu\'il est affiché, filtres compris.',
        'export_filtre' => 'Filtre appliqué : :filtre',
        'export_sans_filtre' => 'Aucun filtre — parc complet',
        'export_vide' => 'Aucune unité ne correspond aux filtres : il n\'y a rien à exporter.',

        /*
         * ---- REFUS NOMMES, DATES, ET VERIFIES LE 31/08/2026 ----
         *
         * Chaque phrase cite VERBATIM les libelles du maitre qu'elle refuse :
         * sans cela, ni l'utilisateur ni `t-trois-sources.js` ne peuvent
         * distinguer un refus d'un oubli.
         */
    ],

    /*
     * ==================================================
     * Réservations — `prototype_v2/pages/reservations.html`
     * ==================================================
     */
    'reservations' => [

        'bouton_ajouter_client' => 'Ajouter client',

        // ---- Modale « Nouvelle réservation » (maquette l.107-190)
        'modale_sous_titre' => 'Renseignez les informations de la réservation.',
        'champ_unite' => 'Unité d\'hébergement',
        'champ_unite_invite' => 'Choisir une unité…',
        'bouton_enregistrer' => 'Enregistrer la réservation',

        // ---- Modale « Ajouter un client » (maquette l.245-268), portée au mot près
        'modale_client_titre' => 'Ajouter un client',
        'modale_client_sous_titre' => 'Fiche client unique du référentiel.',
        'champ_nom' => 'Nom complet',
        'champ_nom_invite' => 'Ex. Jean KORA',
        'champ_telephone' => 'Téléphone',
        'champ_telephone_invite' => '01 97 35 59 74',
        'champ_type_client' => 'Type de client',
        'bouton_ajouter_le_client' => 'Ajouter le client',
        'client_cree' => 'Client « :nom » créé et sélectionné.',
        // RG-18 : avertissant, jamais bloquant.
        'doublon_avertissement' => 'Doublon possible — :message',
        // Le droit M3 est exigé EN PLUS du droit M1 : créer un client est une
        // écriture M3, et la synchronisation vérifie les droits par opération
        // (PA-65, PA-116).
        'client_droit_m3' => 'Créer une fiche client demande le droit d\'écriture sur les clients, en plus '
            // Article 8 (02/09/2026) : la reference PA-116 vit ici, jamais a l'ecran.
            .'de celui sur l\'hébergement.',
        // Les quatre options du maitre (l.259). ⚠ Le schema stocke
        // `particulier|groupe|agence|structure` : les confondre casse la
        // synchronisation.
        'type_particulier' => 'Particulier',
        'type_groupe' => 'Groupe',
        'type_agence' => 'Agence partenaire',
        'type_structure' => 'Structure',

        // ---- Modale « Réservation enregistrée » (maquette l.193-210)
        'modale_impression_titre' => 'Réservation enregistrée',
        'modale_impression_question' => 'Voulez-vous imprimer la facture de cette réservation ?',
        'modale_impression_plus_tard' => 'Plus tard',
        'modale_impression_imprimer' => 'Imprimer la facture',
        // ⚠ PA-113 — le PAPIER, lui, ne s'appelle pas « facture ».
        'modale_impression_avertissement' => 'Le document remis porte le titre « CONFIRMATION DE '
            .'RÉSERVATION » et ne vaut pas facture : une facture est normalisée MECeF (numéro, IFU, '
            .'cachet fiscal), et imprimer « FACTURE » sur ce papier produirait un faux document fiscal '
            // Article 8 (02/09/2026) : la reference PA-113 vit ici, jamais a l'ecran.
            .'.',
        'confirmation_titre' => 'CONFIRMATION DE RÉSERVATION',
        'confirmation_mention' => 'Ce document ne vaut pas facture. Une facture normalisée MECeF, portant '
            .'un numéro et un cachet fiscal, est remise séparément.',

        // ---- Modale « Détail — » (maquette l.213-225)
        'modale_detail_titre' => 'Détail — :reference',
        'modale_detail_fermer' => 'Fermer',
        'detail_reference' => 'Référence interne',
        'detail_statut' => 'Statut enregistré',
        'detail_etat_derive' => 'État du jour (dérivé des dates)',
        'detail_cree_le' => 'Créée le',

        // ---- Annulation (RG-02)
        'annulation_titre' => 'Annuler cette réservation',
        // Le même geste, offert depuis la fiche de détail (PO, 02/09/2026).
        'annulation_bouton_fiche' => 'Annuler la réservation',
        'annulation_element' => 'la réservation de :client du :arrivee au :depart',
        'annulation_message' => 'Voulez-vous annuler :element ?',

        // ---- Annulation avec commission et remboursement (EF-M1-06,
        // séance client 18-20/08/2026, instruction du Product Owner
        // 01/09/2026). Le taux de référence (§4.4/§6.3) n'est jamais recopié
        // en dur dans un libellé : ce paramètre change sans redéploiement.
        'annulation_delai' => 'Prestation dans :heures heure(s).',
        'annulation_delai_passe' => 'La date d\'arrivée est déjà passée.',
        'annulation_sous_seuil' => 'moins de 24h avant la prestation (cas de référence client : 50 %).',
        'annulation_montant_total' => 'Montant total de la réservation',
        'annulation_acompte_verse' => 'Acompte déjà encaissé',
        'annulation_champ_taux' => 'Taux d\'annulation (commission retenue sur le montant total)',
        'annulation_taux_aide' => 'Pré-rempli depuis le paramètre système (Paramètres → Exploitation) — modifiable pour cette annulation.',
        'annulation_champ_remboursement' => 'Montant remboursé au client',
        'annulation_mode_pourcentage' => '% de l\'acompte',
        'annulation_mode_montant' => 'FCFA',
        'annulation_remboursement_aide' => 'Ne peut jamais dépasser l\'acompte réellement encaissé. Saisissez l\'une des deux façons — l\'autre se déduit à l\'enregistrement.',
        'annulation_aucun_acompte' => 'Aucun acompte n\'a été encaissé sur cette réservation : rien à rembourser.',
        'annulation_col_total' => 'Total',
        'annulation_col_taux' => 'Taux',
        'annulation_col_commission' => 'Commission retenue',
        'annulation_col_rembourse' => 'Remboursé',
        'annulation_col_date' => 'Annulée le',
        'annulation_col_auteur' => 'Par',
        'annulation_tous_canaux' => 'Tous les canaux',

        // Article 8 (02/09/2026) : la reference RG-02 vit ici, jamais a l'ecran.
        'annulation_rappel' => 'L\'unité réservée redevient disponible immédiatement. La '
            .'réservation est <strong>conservée</strong> et reste consultable — rien n\'est effacé.',
        'annulation_confirmer' => 'Annuler la réservation',
        'annulation_impossible' => 'Cette réservation est déjà annulée.',

        // ---- Colonnes et montants de l'historique (H5 / PA-112)
        'hist_col_consommations' => 'Consommations',
        'ligne_consommations' => 'Consommations',
        'service_hebergement' => 'Hébergement',
        'etat_a_venir' => 'À venir',
        'etat_en_cours' => 'En cours',
        'etat_terminee' => 'Terminée',
        'etat_annulee' => 'Annulée',

        // ---- Export de l'historique (PA-119)
        'export_titre' => 'Exporter — Historique des réservations',
        'export_sous_titre' => 'L\'historique tel qu\'il est affiché, filtres compris.',
        'export_filtre' => 'Filtre appliqué : :filtre',
        'export_sans_filtre' => 'Aucun filtre — toutes périodes',
        'export_vide' => 'Aucune réservation ne correspond aux filtres : il n\'y a rien à exporter.',
        'export_periode' => 'Du :debut au :fin',

        /*
         * ---- REFUS NOMMES, DATES ET VERIFIES LE 31/08/2026 ----
         */
    ],
];
