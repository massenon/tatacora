<?php

declare(strict_types=1);

/*
 * Messages du domaine Tourisme (M9).
 */

return [
    'capacite_depassee' => 'Départ complet : :demandes participants demandés pour :restantes place(s) '
        . 'encore disponible(s) (capacité du circuit : :capacite).',
    'participants_minimum' => 'Une réservation doit compter au moins un participant.',
    'guide_deja_existant' => 'Un guide nommé « :nom » existe déjà au référentiel.',
    'guide_deja_affecte' => 'Ce guide assure déjà un autre circuit le :date.',
    'guide_du_depart_impose' => 'Ce départ est déjà conduit par un autre guide. Reprenez le guide en place, ou réaffectez le départ entier.',
    'affectation_impossible' => 'Une prestation annulée ou clôturée ne peut plus changer de guide.',
    'cloture_apres_annulation' => 'Une prestation annulée ne peut pas être clôturée.',
    'annulation_apres_cloture' => 'Une prestation clôturée ne peut plus être annulée. '
        . 'Corrigez-la par un avoir si elle a été facturée.',

    'validation' => [
        'circuit_inexistant' => "Ce circuit n'existe pas au catalogue.",
        'client_inexistant' => "Ce client n'existe pas dans le référentiel.",
        'guide_inexistant' => "Ce guide n'existe pas dans le référentiel.",
    ],

    /*
     * Etat des departs (M14 / EF-M14-02).
     */
    'etat' => [
        'libelle' => 'Départs touristiques',
        'arrete_au' => 'Arrêté au :date',

        'kpi_departs' => 'Départs',
        'kpi_participants' => 'Participants',
        'kpi_recette' => 'Recette prévisionnelle',

        'col_date' => 'Date',
        'col_circuit' => 'Circuit',
        'col_zone' => 'Zone',
        'col_participants' => 'Participants',
        'col_capacite' => 'Capacité',
        'col_guide' => 'Guide',
        'col_statut' => 'Statut',
        'col_montant' => 'Montant',
    ],

    /*
    |---------------------------------------------------------------------------
    | Ecran PWA M9 — maitre : `prototype_v2/pages/m9-tourisme-departs.html`
    |---------------------------------------------------------------------------
    |
    | Meme regle qu'en M8 : les libelles sont ceux du maitre au mot pres, et
    | tout refus est RENDU A L'ECRAN avec sa raison datee.
    |
    | Le vocabulaire suit le schema : on REAFFECTE un guide, on ne l'affecte
    | pas — `reservations_tour.guide_id` est NOT NULL, un depart en a
    | forcement deja un (PA-51).
    |
    */
    'pwa' => [
        'titre' => 'Tourisme',
        'sous_titre' => 'Circuits, départs, guides et capacités. La capacité est contrôlée <strong>cumulée '
            . 'sur le départ</strong> — jamais réservation par réservation. Un départ ne peut pas exister '
            . 'sans guide.',

        'du' => 'du',
        'au' => 'au',
        // Les boutons « Excel » / « PDF » du maître (`m9-tourisme-departs.html`
        // l.40-41) sont fusionnés en un seul « Exporter » (`pwa.export.bouton`)
        // — dérogation PO du 01/09/2026, rappelée le 02/09/2026 ; voir
        // `DerogationsMaquette` (export_bouton_unique).
        'export_titre' => 'Exporter le rapport Tourisme',

        'kpi_departs' => 'Départs planifiés',
        'kpi_departs_detail' => ':nombre complet(s)',
        'kpi_places' => 'Places vendues',
        'kpi_places_detail' => 'Capacité offerte',
        'kpi_remplissage' => 'Taux de remplissage',
        'kpi_remplissage_detail' => 'Sur la période',
        'kpi_ca' => 'Chiffre d\'affaires',
        'kpi_ca_detail' => 'Réservations confirmées',
        'kpi_reste' => 'Reste à encaisser',
        'kpi_reste_detail' => 'Soldes clients',
        'kpi_duree' => 'Durée indéterminée',
        'kpi_duree_detail' => 'Véhicule sous-bloqué',

        'onglet_departs' => 'Départs planifiés',
        'onglet_reservations' => 'Réservations',
        'onglet_catalogue' => 'Catalogue',

        'recherche' => 'Circuit, client, guide, n°…',
        // maitre — m9-tourisme-departs.html l.61 : le libelle par defaut du
        // select « prestation » (01/09/2026), reste identique au maitre bien
        // que le filtre porte desormais sur la prestation, pas sur le type
        // (voir Departs::$prestationId).
        'type_tous' => 'Circuits et excursions',
        'remplissage_tous' => 'Tous les départs',
        'remplissage_disponible' => 'Places disponibles',
        'remplissage_complet' => 'Complets',
        'remplissage_vide' => 'Aucune réservation',
        'statut_planifie' => 'Planifiés',
        'statut_tous' => 'Tous',
        'statut_annule' => 'Annulés',

        'action_reservation' => '+ Réservation',
        'action_prestation' => '+ Prestation',

        // --- Onglet Departs ---------------------------------------------
        'departs_titre' => 'Départs planifiés',
        'departs_vide' => 'Aucun départ ne correspond à ces critères.',
        'depart_sans_reservation' => "Ce départ n'a aucune réservation active : il n'existe que par elles, "
            . "il n'y a donc rien à annuler ni à réaffecter.",
        // Article 8 (02/09/2026) : la référence PA-119 vit ici, en
        // commentaire — jamais dans le message affiché.
        'export_vide' => 'Aucune ligne à exporter sur ce filtre — un document vide se lirait comme un registre vérifié.',
        'col_numero' => 'N°',
        'col_circuit' => 'Circuit',
        'col_depart' => 'Départ',
        'col_guide' => 'Guide',
        'col_vehicule' => 'Véhicule',
        'col_remplissage' => 'Remplissage',
        'col_prix' => 'Prix / pers.',
        'col_ca' => 'CA',
        'col_etat' => 'État',
        // Colonnes du DOCUMENT d'export du maître, onglet Départs
        // (`m9-tourisme-departs.js` l.494, `etatCourant()`) — rendues par
        // l'état imprimable de la vue, jamais par le tableau d'écran.
        'col_capacite' => 'Capacité',
        'col_vendues' => 'Vendues',
        'col_restantes' => 'Restantes',
        'doc_titre_departs' => 'Départs planifiés',
        'etat_planifie' => 'Planifié',
        'complet' => 'Complet',
        'places_restantes' => ':nombre place(s)',
        'depart_annule' => 'Annulé',
        'reserver' => 'Réserver',
        'guide' => 'Guide',
        'annuler' => 'Annuler',
        'total_departs' => 'TOTAL — :nombre départ(s)',
        'bandeau_capacite_titre' => 'La capacité vient du circuit, pas d\'une saisie.',
        // Article 8 (02/09/2026, passage navigateur) : plus aucun nom de
        // colonne, code PA/EF ni balise <code> dans un texte affiché — la
        // référence technique vit ici, en commentaire (capacité :
        // circuits.capacite_max, EF-M9-04, PA-51 ; durée : circuits.duree).
        'bandeau_capacite_texte' => 'Elle est lue de la fiche du circuit et contrôlée '
            . '<strong>cumulée sur le départ</strong> par le système : trois groupes de 5 sur un '
            . 'circuit à 12 places sont refusés au troisième.',
        'bandeau_duree_titre' => ':nombre départ(s) à durée indéterminée.',
        'bandeau_duree_texte' => 'La durée de ce circuit est un <strong>texte libre</strong> au '
            . 'catalogue : « Plusieurs jours » n\'est pas une durée exploitable. Le véhicule n\'est alors '
            . 'immobilisé que sur le <strong>jour de départ</strong>, et non sur la durée réelle du circuit.',

        // --- Onglet Reservations -----------------------------------------
        'reservations_titre' => 'Réservations',
        'reservations_vide' => 'Aucune réservation ne correspond.',
        'col_client' => 'Client',
        'col_personnes' => 'Pers.',
        'col_montant' => 'Montant',
        'col_acompte' => 'Acompte',
        'col_reste' => 'Reste dû',
        'total_reservations' => 'TOTAL',
        'reservation_annulee' => 'Annulée',
        // Colonnes du DOCUMENT d'export du maître, onglet Réservations
        // (`m9-tourisme-departs.js` l.472, `etatCourant()`) : le document
        // écrit « Téléphone » et « Personnes » en toutes lettres là où le
        // tableau d'écran les abrège (« Pers. ») ou les glisse sous la
        // colonne Client.
        'col_telephone' => 'Téléphone',
        'col_personnes_document' => 'Personnes',
        'doc_titre_reservations' => 'Réservations tourisme',
        'etat_reservee' => 'Réservée',
        'etat_en_cours' => 'En cours',
        'etat_terminee' => 'Terminée',

        // --- Onglet Catalogue --------------------------------------------
        'catalogue_titre' => 'Catalogue — tarifs opposables au client',
        'catalogue_vide' => 'Aucune prestation ne correspond.',
        'col_prestation' => 'Prestation',
        'col_type' => 'Type',
        'col_duree' => 'Durée',
        'col_zone_theme' => 'Zone / thème',
        'col_prix_catalogue' => 'Prix',
        'col_indicatif' => 'Indicatif €',
        'col_departs_planifies' => 'Départs planifiés',
        'type_valeur_circuit' => 'Circuit',
        // Colonnes du DOCUMENT d'export du maître, onglet Catalogue
        // (`m9-tourisme-departs.js` l.483, `etatCourant()`) : le document
        // sépare « Zone » et « Thème » que le tableau d'écran réunit, et
        // écrit « Prix FCFA » / « Indicatif EUR » en toutes lettres.
        'col_zone' => 'Zone',
        'col_theme' => 'Thème',
        'col_prix_fcfa' => 'Prix FCFA',
        'col_indicatif_eur' => 'Indicatif EUR',
        'col_page_catalogue' => 'Page catalogue',
        'doc_titre_catalogue' => 'Catalogue tourisme',
        'planifier' => 'Planifier',
        'editer' => 'Éditer',
        'places_vendues' => ':nombre place(s) vendue(s)',

        // --- Modale « Réserver des places » -------------------------------
        'modale_resa_titre' => 'Réserver des places',
        'modale_resa_sous_titre' => ':circuit — départ du :date',
        'bloc_capacite' => 'Capacité',
        'bloc_vendues' => 'Déjà vendues',
        'bloc_restantes' => 'Restantes',
        'champ_prestation' => 'Prestation',
        'champ_date_depart' => 'Date de départ',
        'champ_guide' => 'Guide',
        'champ_client' => 'Client',
        'champ_nb_personnes' => 'Nombre de personnes',
        'bouton_reserver' => 'Réserver',
        'note_cumul' => 'Le contrôle porte sur le <strong>cumul des places vendues</strong> sur ce départ, '
            . 'pas sur cette seule réservation : trois groupes de 5 sur un circuit à 12 places sont refusés '
            . 'au troisième.',
        'note_guide_du_depart' => 'Un départ a <strong>un</strong> guide : celui de sa première réservation. Les groupes suivants le reprennent — sinon chacun arriverait avec le sien. En changer relève de « Réaffecter le guide », qui porte sur le départ entier (UC-39).',
        'note_guide_obligatoire' => 'Le guide est <strong>obligatoire dès la création</strong> : une '
            . 'prestation ne peut pas exister sans lui. La réaffectation se fait ensuite depuis la liste '
            . 'des départs.',
        'client_aucun' => 'Aucun client au référentiel — créez-le d\'abord depuis « Clients & Créances ».',
        'guide_aucun' => 'Aucun guide au référentiel — une réservation ne peut pas être prise sans lui.',
        'bouton_ajouter_guide' => 'Ajouter',
        'theme_autre' => 'Autre',
        'prestation_aucune' => 'Aucune prestation au catalogue.',

        // --- Modale « Réaffecter le guide » -------------------------------
        'modale_guide_titre' => 'Réaffecter le guide',
        'modale_guide_sous_titre' => ':circuit — :date',
        'guide_actuel' => 'Guide actuellement affecté :',
        'champ_nouveau_guide' => 'Nouveau guide',
        'bouton_reaffecter' => 'Réaffecter',
        // Article 8 (02/09/2026) : la référence technique (guide_id NOT NULL,
        // PA-51) vit ici, jamais à l'écran.
        'note_reaffectation' => 'Il s\'agit d\'une <strong>ré</strong>affectation : un départ ne peut pas '
            . 'exister sans guide, celui-ci a donc forcément déjà le sien.',

        // --- Modale « Prestation » (catalogue) ----------------------------
        'modale_circuit_titre_creation' => 'Nouvelle prestation au catalogue',
        'modale_circuit_titre_edition' => 'Éditer la prestation',
        'modale_circuit_sous_titre' => 'Catalogue des circuits.',
        'champ_nom' => 'Intitulé',
        'champ_theme' => 'Thème',
        'champ_zone' => 'Zone',
        'champ_duree' => 'Durée',
        'invite_duree' => 'Ex. 3 jours / 2 nuits',
        'champ_prix' => 'Prix par personne',
        'champ_capacite' => 'Capacité maximale',
        'bouton_enregistrer' => 'Enregistrer',

        // --- Archivage ----------------------------------------------------
        'verrou' => 'Élément engagé dans :nombre opération(s) : :apercu. Il ne peut pas être archivé — '
            . 'la ligne correspondante deviendrait illisible.',
        'verrou_reservation' => 'Réservation de :client (:personnes pers.) le :date',
        'archiver_reservation' => 'Voulez-vous annuler la réservation :element ?',
        'archiver_depart' => 'Voulez-vous annuler le départ :element ?',
        'depart_places_vendues' => ':nombre place(s) déjà vendue(s) : les réservations seront annulées. '
            . 'Les clients concernés devront être prévenus et remboursés.',
        'reservation_faite' => 'Réservation de :personnes place(s) enregistrée pour :client.',
        'reservation_annulee_faite' => 'Réservation annulée, places libérées.',
        'depart_annule_faite' => 'Départ annulé — :nombre réservation(s) passée(s) en annulation.',
        'guide_reaffecte' => 'Guide réaffecté à :nombre réservation(s) du départ.',
        // --- Modale « Ajouter un guide touristique » ----------------------
        'modale_guide_creation_titre' => 'Ajouter un guide touristique',
        'modale_guide_creation_sous_titre' => 'Le guide rejoint le référentiel et se sélectionne dans la réservation.',
        'champ_guide_nom' => 'Nom du guide',
        'champ_guide_certification' => 'Certification',
        'champ_guide_zone' => 'Zone de compétence',
        'champ_guide_tarif' => 'Tarif journalier',
        'invite_guide_zone' => 'Ex. Nord Bénin',
        'bouton_ajouter_le_guide' => 'Ajouter le guide',
        'guide_cree' => 'Guide « :nom » ajouté au référentiel.',
        'circuit_enregistre' => 'Prestation « :nom » enregistrée au catalogue.',
    ],
];
