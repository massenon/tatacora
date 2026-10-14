<?php

declare(strict_types=1);

/*
 * Messages du domaine Vehicules (M8).
 */

return [
    // Article 8 (02/09/2026) : la reference RG-08 vit ici, jamais a l'ecran.
    'chevauchement' => 'Ce véhicule est déjà loué sur cette période.',

    // Article 8 (02/09/2026) : la référence RG-09 vit ici, jamais à l'écran.
    'piece_identite_requise' => "Une pièce d'identité est obligatoire pour toute location.",
    'permis_requis' => 'Un permis de conduire est obligatoire pour la catégorie « :categorie ».',
    'non_louable' => 'Ce véhicule est indisponible (:statut) : il ne peut pas être loué.',

    'validation' => [
        'vehicule_inexistant' => "Ce véhicule n'existe pas dans le parc.",
        'client_inexistant' => "Ce client n'existe pas dans le référentiel.",
        'guide_inexistant' => "Ce guide n'existe pas dans le référentiel.",
        'fin_apres_debut' => 'La date de fin doit être postérieure à la date de début.',
    ],

    /*
     * Etat du parc (M14 / EF-M14-02) — libelles imprimes sur un document.
     */
    'etat' => [
        'libelle' => 'État du parc de véhicules',
        'arrete_au' => 'Arrêté au :date',

        'kpi_vehicules' => 'Véhicules',
        'kpi_louables' => 'Louables',
        'kpi_immobilises' => 'Immobilisés',
        'kpi_valeur_jour' => 'Tarif journalier cumulé',

        'col_immatriculation' => 'Immatriculation',
        'col_categorie' => 'Catégorie',
        'col_annee' => 'Année',
        'col_capacite' => 'Places',
        'col_tarif' => 'Tarif / jour',
        'col_statut' => 'Statut',
        'col_permis' => 'Permis requis',

        'permis_oui' => 'Oui',
        'permis_non' => 'Non',
    ],

    /*
    |---------------------------------------------------------------------------
    | Ecran PWA M8 — maitre : `prototype_v2/pages/m8-locations.html`
    |---------------------------------------------------------------------------
    |
    | Les libelles sont ceux du MAITRE, au mot pres, apostrophe typographique
    | comprise (« Piece d'identite » s'ecrit avec U+2019 comme au maitre). Les
    | recopier « a peu pres » suffit a faire diverger l'ecran et l'export, ou
    | aucune feuille de style ne rattrape la difference.
    |
    | Les cles `refus_*` sont RENDUES A L'ECRAN (bloc de refus), jamais un
    | commentaire : un motif de refus qu'on ne voit plus redevient un oubli
    | (PA-144). Chacune porte la date a laquelle sa raison a ete verifiee.
    |
    | Ces cles vivent ici et non dans `lang/fr/pwa.php` : ce lot ne touche pas
    | au fichier partage, qu'une autre vague tient en meme temps.
    |
    */
    'pwa' => [
        'titre' => 'Véhicules & Locations',
        'sous_titre' => 'Parc, contrats de location, planning et immobilisations. Un véhicule loué ou '
            . 'immobilisé pour entretien n\'est proposé nulle part ailleurs.',

        'du' => 'du',
        'au' => 'au',
        // Les boutons « Excel » / « PDF » du maître (`m8-locations.html`
        // l.40-41) sont fusionnés en un seul « Exporter » (`pwa.export.bouton`)
        // — dérogation PO du 01/09/2026, rappelée le 02/09/2026 ; voir
        // `DerogationsMaquette` (export_bouton_unique).
        'export_titre' => 'Exporter le rapport Véhicules & Locations',

        'kpi_parc' => 'Parc',
        'kpi_parc_immobilises' => ':nombre immobilisé(s)',
        'kpi_parc_aucun' => 'Aucune immobilisation',
        'kpi_contrats' => 'Contrats actifs',
        'kpi_contrats_detail' => ':nombre annulé(s)',
        'kpi_ca' => 'Chiffre d\'affaires',
        'kpi_ca_detail' => ':jours jour(s) loué(s)',
        'kpi_occupation' => 'Taux d\'occupation',
        'kpi_occupation_detail' => 'Sur la période',
        'kpi_reste' => 'Reste à encaisser',
        'kpi_reste_detail' => 'Soldes de location',
        'kpi_jours' => 'Jours loués',
        'kpi_jours_detail' => 'Toutes catégories',

        'onglet_parc' => 'Parc & disponibilité',
        'onglet_contrats' => 'Contrats',
        'onglet_planning' => 'Planning du parc',
        'onglet_immo' => 'Immobilisations',

        'recherche' => 'Véhicule, client, n° de contrat…',
        'toutes_categories' => 'Toutes catégories',

        // Libellés d'AFFICHAGE des catégories — l'enum du schéma reste la
        // valeur stockée. « voiture » se dit « Berline » depuis l'arbitrage
        // du seeder (sens inverse d'une correction de schéma) ; les autres
        // reprennent la casse du maître (import-export-engine.js l.124).
        // Une valeur hors registre est rendue EN CLAIR : elle doit se voir.
        'categorie_voiture' => 'Berline',
        'categorie_4x4' => '4x4',
        'categorie_pickup' => 'Pick-up',
        'categorie_moto' => 'Moto',
        'categorie_scooter' => 'Scooter',
        'categorie_velo' => 'Vélo',
        'categorie_bus' => 'Bus',
        'statut_actif' => 'Contrats actifs',
        'statut_tous' => 'Tous',
        'statut_annule' => 'Annulés',

        'action_immobiliser' => 'Immobiliser',
        'action_contrat' => '+ Contrat',
        'action_vehicule' => '+ Véhicule',

        // --- Onglet Parc -----------------------------------------------
        'parc_titre' => 'Parc — du :debut au :fin',
        'parc_vide' => 'Aucun véhicule ne correspond.',
        'col_vehicule' => 'Véhicule',
        'col_categorie' => 'Catégorie',
        'col_places' => 'Places',
        'col_permis' => 'Permis',
        'col_tarif' => 'Tarif / jour',
        // ⚠ Corrigé le 31/08/2026 — ET LE MAÎTRE SE CONTREDIT LUI-MÊME ICI.
        //
        // `m8-locations.js` nomme cette colonne DE DEUX FAÇONS : son tableau
        // à l'écran écrit `jours + ' jour(s)'` (l.67), donc « 14 jour(s) », et
        // son en-tête d'export écrit « Montant période » (l.414). Ce sont deux
        // noms pour la même colonne — celle qui vaut `tarif_jour × jours`.
        //
        // C'est le libellé d'EXPORT qui est retenu, et l'écart est délibéré :
        // un en-tête qui change de texte selon la fenêtre affichée devient
        // faux dès qu'il quitte l'écran, et aucune feuille de style ne
        // rattrape un en-tête faux dans un CSV remis au comptable. « 14
        // jour(s) » ne nomme d'ailleurs pas ce que la colonne contient — un
        // montant.
        //
        // Le nombre de jours reste accessible, mais en attribut `title` : il
        // informe au survol sans entrer dans le TEXTE de l'en-tête, donc sans
        // repartir dans un CSV ni redevenir un titre variable.
        'col_periode_parc' => 'Montant période',
        'col_periode_parc_precision' => 'sur :jours jour(s)',
        'col_disponibilite' => 'Disponibilité',
        'permis_exige' => 'exigé',
        'permis_dispense' => 'dispensé',
        'disponible' => 'Disponible',
        'engage' => 'Engagé',
        'hors_service' => 'Hors service',
        'louer' => 'Louer',
        'editer' => 'Éditer',
        'archiver' => 'Archiver',
        'remettre_en_service' => 'Remettre en service',

        'bandeau_permis_titre' => 'Tarifs « chauffeur inclus ».',
        'bandeau_permis_texte' => 'C\'est une caractéristique du tarif catalogue, pas une option facturée '
            // Article 8 (02/09/2026) : la reference RG-09 vit ici, jamais a l'ecran.
            . 'en plus. Le permis n\'est exigé que pour les catégories qui le requièrent.',

        // --- Onglet Contrats -------------------------------------------
        'contrats_titre' => 'Contrats de location',
        'contrats_vide' => 'Aucun contrat ne correspond à ces critères.',
        'col_numero' => 'N°',
        'col_client' => 'Client',
        'col_periode' => 'Période',
        'col_jours' => 'Jours',
        'col_montant' => 'Montant',
        'col_acompte' => 'Acompte',
        'col_reste' => 'Reste dû',
        'col_etat' => 'État',
        // Colonne du DOCUMENT d'export du maître, onglet Contrats
        // (`m8-locations.js` l.436, `etatCourant()`) : le document donne à la
        // pièce d'identité sa propre colonne, que le tableau d'écran glisse
        // sous la colonne Client.
        'col_piece' => 'Pièce',
        // Article 8 (02/09/2026) : la reference RG-09 vit ici, jamais a l'ecran.
        'sans_permis' => 'Sans permis',
        'permis_numero' => 'Permis :numero',
        'contrat_actif' => 'Actif',
        'contrat_annule' => 'Annulé',
        'solde' => 'Soldé',
        'annuler_contrat' => 'Annuler',
        'total_contrats' => 'TOTAL — :nombre contrat(s) actif(s)',

        // --- Onglet Planning -------------------------------------------
        'planning_titre' => 'Planning du parc — :jours jour(s)',
        'legende_libre' => 'libre',
        'legende_location' => 'location',
        'legende_immobilise' => 'immobilisé',

        // --- Onglet Immobilisations ------------------------------------
        'immo_titre' => 'Immobilisations du parc',
        'immo_vide' => 'Aucune immobilisation enregistrée.',
        'col_motif' => 'Motif',
        'col_du' => 'Du',
        'col_au' => 'Au',
        'col_commentaire' => 'Commentaire',
        'col_enregistre_par' => 'Enregistré par',
        'motif_entretien' => 'Entretien',
        'motif_carburation' => 'Carburation',
        'par_jour' => '/jour',

        // --- Modale « Nouveau contrat de location » --------------------
        'modale_contrat_titre' => 'Nouveau contrat de location',
        'modale_contrat_sous_titre' => 'RG-08 : le véhicule est verrouillé sur la période avant écriture.',
        'champ_vehicule' => 'Véhicule',
        'champ_depart' => 'Départ',
        'champ_restitution' => 'Restitution',
        'champ_client' => 'Client',
        'champ_telephone' => 'Téléphone',
        'champ_piece' => 'Pièce d’identité',
        'invite_piece' => 'N° CNI ou passeport',
        'champ_permis' => 'Permis de conduire',
        'invite_permis' => 'N° de permis',
        'champ_remise' => 'Remise (FCFA)',
        'champ_acompte' => 'Acompte reçu (FCFA)',
        'bouton_etablir' => 'Établir le contrat',
        'apercu_jours' => ':jours jour(s) × :tarif',
        'apercu_remise' => 'Remise',
        'apercu_acompte' => 'Acompte',
        'apercu_reste' => 'Reste à payer',
        'info_vehicule' => ':places place(s) · :categorie · chauffeur inclus',
        'info_permis_exige' => 'permis exigé',
        // Article 8 (02/09/2026) : la reference RG-09 vit ici, jamais a l'ecran.
        'info_permis_dispense' => 'dispensé de permis',
        'client_aucun' => 'Aucun client au référentiel M3 — créez-le d\'abord depuis « Clients & Créances ».',

        // --- Modale « Immobiliser un véhicule » ------------------------
        'modale_immo_titre' => 'Immobiliser un véhicule',
        'modale_immo_sous_titre' => 'Entretien ou carburation — EF-M8-05.',
        'champ_motif' => 'Motif',
        'champ_date' => 'Du',
        'champ_cout' => 'Coût (FCFA)',
        'bouton_immobiliser' => 'Immobiliser',

        // --- Modale « Véhicule » (hors maitre, addition assumee) -------
        'modale_vehicule_titre_creation' => 'Nouveau véhicule au parc',
        'modale_vehicule_titre_edition' => 'Éditer le véhicule',
        'modale_vehicule_sous_titre' => 'Référentiel du parc — EF-M8-01.',
        'champ_immatriculation' => 'Immatriculation',
        'invite_immatriculation' => 'Ex. AB 1234 RB',
        'champ_annee' => 'Année',
        'champ_transmission' => 'Transmission',
        'champ_capacite' => 'Places',
        'champ_tarif' => 'Tarif / jour (FCFA)',
        'bouton_enregistrer' => 'Enregistrer',

        // --- Archivage --------------------------------------------------
        'verrou' => 'Élément engagé dans :nombre opération(s) : :apercu. Il ne peut pas être archivé — '
            . 'la ligne correspondante deviendrait illisible.',
        'verrou_contrat' => 'Contrat :numero du :debut au :fin',
        'verrou_contrat_annule' => "Ce contrat est déjà annulé — il n'y a plus rien à archiver.",
        'archiver_vehicule' => 'Voulez-vous archiver le véhicule :element ?',
        'archiver_contrat' => 'Voulez-vous annuler le contrat :element ?',
        'archivage_vehicule_fait' => 'Véhicule :immatriculation retiré du parc actif — il reste consultable.',
        'archivage_contrat_fait' => 'Contrat :numero annulé — le véhicule redevient disponible.',
        'remise_en_service_faite' => 'Véhicule :immatriculation remis en service.',
        'contrat_etabli' => 'Contrat :numero établi — :montant pour :jours jour(s).',
        'vehicule_enregistre' => 'Véhicule :immatriculation enregistré.',
        'immobilisation_enregistree' => 'Véhicule :immatriculation immobilisé le :date.',
        'refus_lever_immobilisation' => 'Aucune action « Lever » n\'est proposée sur une immobilisation : '
            . '`entretiens_vehicule` n\'a ni `statut` ni date de fin, et la suppression est interdite sur '
            . 'une table transactionnelle (`BasePolicy::delete()` rend `false`). Un bouton qui effacerait '
            . 'la ligne ferait disparaître l\'entretien du journal du parc. La remise en service se fait '
            . 'sur le VÉHICULE, où le statut existe. Vérifié le 31/08/2026.',
    ],
];
