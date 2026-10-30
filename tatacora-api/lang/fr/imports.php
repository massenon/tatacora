<?php

declare(strict_types=1);

/*
|--------------------------------------------------------------------------
| Import de référentiels par module — écran Import & Export (PARAM)
|--------------------------------------------------------------------------
|
| Maître : `prototype_v2/pages/import-export.html` (onglet 1) et
| `prototype_v2/assets/js/import-export-engine.js` §1-2 (02/09/2026).
|
| Les COLONNES déclarées ici divergent du maître partout où son prototype
| inventait des champs que le schéma serveur ne porte pas (ville/pays sur
| `clients`, désignation sur `vehicules`, statut importable sur
| `unites_hebergement`…) : la déclaration suit le SCHÉMA RÉEL et les
| services de domaine qui écrivent — jamais une liste plausible recopiée.
| Chaque divergence est notée dans `ReferentielsImport`.
|
*/

return [

    // ------------------------------------------------------------ contrôle
    'controle' => [
        'fichier_vide' => 'Fichier vide.',
        'module_inconnu' => 'Module inconnu.',
        'entete_absente' => 'La ligne d\'en-tête est absente ou illisible.',
        'colonne_manquante' => 'Ligne 1 : colonne obligatoire « :libelle » absente de l\'en-tête. Colonnes trouvées : :trouvees. Repartez du modèle .xlsx téléchargé.',
        'aucune_entete' => '(aucune)',
        'ligne_exemple_ignoree' => 'Ligne d\'exemple du modèle (« (exemple) ») — ignorée.',
        'colonne_inconnue' => 'Colonne « :libelle » non reconnue — elle sera ignorée.',
        'valeur_obligatoire' => 'valeur obligatoire absente',
        'texte_trop_long' => '« :colonne » ne peut pas dépasser :maximum caractères',
        'valeur_hors_liste' => 'valeur « :valeur » hors liste (attendu : :attendu)',
        'valeur_non_numerique' => 'valeur « :valeur » n\'est pas un nombre',
        'montant_negatif' => 'montant négatif (:valeur)',
        'reference_inconnue' => 'aucun enregistrement « :valeur » au référentiel :referentiel — la fiche se crée depuis son propre écran, jamais en silence depuis un import',
        'doublon_fichier' => 'Doublon dans le fichier : « :valeur » apparaît plusieurs fois.',
        'doublon_existant' => '« :valeur » existe déjà — la ligne sera ajoutée en doublon si vous poursuivez.',
        'doublon_existant_bloquant' => '« :valeur » existe déjà, et cette colonne est unique en base : la ligne serait refusée à l\'import.',
        'aucune_ligne' => 'Aucune ligne à importer.',
        'refus_service' => 'Ligne :ligne (« :element ») refusée par le module : :raison',
        'import_fait' => ':nombre ligne(s) importée(s) dans :module.',
    ],

    // Lecture des fichiers déposés (`TableurService`) — un message par cause.
    'fichier' => [
        'vide' => 'Le fichier est vide.',
        'illisible' => 'Le fichier n\'a pas pu être lu.',
        'xls_ancien' => 'Ce fichier est un ancien classeur .xls. Ouvrez-le dans Excel et enregistrez-le au format « Classeur Excel (.xlsx) », ou repartez du modèle .xlsx téléchargé.',
        'xlsx_illisible' => 'Le classeur .xlsx est illisible ou protégé. Repartez du modèle .xlsx téléchargé, ou enregistrez-le de nouveau depuis Excel.',
        'trop_long' => 'Le fichier compte plus de :maximum lignes : découpez-le en plusieurs fichiers.',
    ],

    // Le classeur .xlsx servi comme modèle (feuilles « Modèle » et « Aide »).
    'xlsx' => [
        'aide_titre' => 'Import — :module',
        'aide_consigne' => 'Remplissez la feuille « Modèle », une ligne par fiche. Ne changez ni l\'ordre ni le nom des en-têtes de la ligne 1.',
        'aide_exemple' => 'La ligne grisée de la feuille « Modèle », marquée « (exemple) », n\'est pas importée : supprimez-la ou remplacez-la par vos données.',
        'aide_colonne' => 'Colonne',
        'aide_obligatoire' => 'Obligatoire',
        'aide_format' => 'Format',
        'aide_valeurs' => 'Valeurs admises',
        'aide_exemple_colonne' => 'Exemple',
        'oui' => 'Oui',
        'non' => 'Non',
        'liste_titre' => 'Valeur hors liste',
        'liste_erreur' => 'Valeurs admises : :valeurs',
        'format_liste' => 'Une valeur de la liste',
        'nom_fichier' => 'modele_import_:cle.xlsx',
        'nom_fichier_gite' => 'modele_import_:cle_carte_gite_chez_noel.xlsx',
    ],

    // Rendu de la colonne « VALEURS ATTENDUES » quand la colonne n'a pas de
    // liste fermée — mêmes mots que le maître (`import-export.html` l.430-434).
    'types' => [
        'texte' => 'Texte libre',
        'nombre' => 'Nombre entier',
        'montant' => 'Montant en FCFA',
        'reference' => 'Libellé exact d\'une fiche existante',
    ],
    'exemple_prefixe' => 'ex. :exemple',

    // -------------------------------------------------------- les modules
    'm3_clients' => [
        'nom' => 'Clients',
        'description' => 'Fiches clients : particuliers, groupes, agences et structures.',
        'colonnes' => [
            'nom' => ['libelle' => 'Nom / Raison sociale', 'exemple' => 'Agence Bénin Tour'],
            'prenom' => ['libelle' => 'Prénom', 'exemple' => 'Pascaline'],
            'type_client' => ['libelle' => 'Type de client', 'exemple' => 'agence'],
            'telephone' => ['libelle' => 'Téléphone', 'exemple' => '+229 01 97 00 00 00'],
            'email' => ['libelle' => 'Email', 'exemple' => 'contact@exemple.bj'],
        ],
    ],

    'm1_hebergement' => [
        'nom' => 'Unités d\'hébergement',
        'description' => 'Bungalows, chambres et tentes du gîte. Chaque unité rejoint une catégorie existante, qui porte le tarif ; une unité importée entre au parc libre.',
        'colonnes' => [
            'numero' => ['libelle' => 'Numéro d\'unité', 'exemple' => 'BNG-03'],
            'categorie' => ['libelle' => 'Catégorie', 'exemple' => 'Bungalow'],
        ],
    ],

    'm5_bar' => [
        'nom' => 'Carte du bar',
        // Article 8 (02/09/2026) : la reference RG-05 vit ici, jamais a l'ecran.
        'description' => 'Boissons proposées au bar et au point de vente. Chaque boisson se rattache à un article de stock existant.',
        'colonnes' => [
            'libelle' => ['libelle' => 'Nom de la boisson', 'exemple' => 'Bière Béninoise 66 cl'],
            'categorie' => ['libelle' => 'Catégorie', 'exemple' => 'locale'],
            'prix_vente' => ['libelle' => 'Prix de vente (FCFA)', 'exemple' => '1200'],
            'article' => ['libelle' => 'Article de stock lié', 'exemple' => 'Béninoise 66 cl'],
        ],
    ],

    'm4_restaurant' => [
        'nom' => 'Carte du restaurant',
        'description' => 'Plats proposés au restaurant. Menu et fiche recette sont facultatifs : un plat sans menu entre dans « Carte du restaurant », un plat sans fiche reçoit une fiche vide du même nom (le stock consommé s\'y ajoute ensuite) et se vend sans mouvement de stock tant qu\'elle est vide. La description est facultative (500 caractères au plus). Un prix vide donne un plat « sur commande » à 0 FCFA, prix provisoire.',
        'colonnes' => [
            'libelle' => ['libelle' => 'Nom du plat', 'exemple' => 'Poulet DG'],
            'categorie' => ['libelle' => 'Catégorie', 'exemple' => 'plats'],
            'prix_vente' => ['libelle' => 'Prix de vente (FCFA)', 'exemple' => '4500'],
            'menu' => ['libelle' => 'Menu', 'exemple' => 'Menu local'],
            'recette' => ['libelle' => 'Fiche recette', 'exemple' => 'Poulet DG'],
            'description' => ['libelle' => 'Description', 'exemple' => 'Poulet, plantain mûr, poivron, tomate'],
        ],
    ],

    'm6_stocks' => [
        'nom' => 'Articles de stock',
        'description' => 'Articles suivis en stock, avec leur seuil d\'alerte. Le stock initial se saisit ensuite par un mouvement d\'entrée, jamais par l\'import.',
        'colonnes' => [
            'libelle' => ['libelle' => 'Désignation de l\'article', 'exemple' => 'Riz local (sac 25 kg)'],
            'categorie' => ['libelle' => 'Catégorie', 'exemple' => 'Denrées'],
            'unite_mesure' => ['libelle' => 'Unité de mesure', 'exemple' => 'sac'],
            'seuil_alerte' => ['libelle' => 'Seuil d\'alerte', 'exemple' => '5'],
            'point_stockage' => ['libelle' => 'Point de stockage', 'exemple' => 'Magasin général'],
        ],
    ],

    'm7_achats' => [
        'nom' => 'Fournisseurs',
        'description' => 'Fournisseurs référencés pour les commandes.',
        'colonnes' => [
            'raison_sociale' => ['libelle' => 'Raison sociale', 'exemple' => 'Bénin Boissons Distribution'],
            'contact' => ['libelle' => 'Contact', 'exemple' => '+229 01 21 30 40 50'],
            'categorie' => ['libelle' => 'Catégorie', 'exemple' => 'Boissons'],
            'conditions_paiement' => ['libelle' => 'Conditions de paiement', 'exemple' => '30 jours'],
            'evaluation' => ['libelle' => 'Évaluation', 'exemple' => 'bon'],
        ],
    ],

    'm8_vehicules' => [
        'nom' => 'Parc de véhicules',
        'description' => 'Véhicules du parc proposés à la location. Un véhicule importé entre au parc disponible.',
        'colonnes' => [
            'immatriculation' => ['libelle' => 'Immatriculation', 'exemple' => 'AB 1234 RB'],
            'categorie' => ['libelle' => 'Catégorie', 'exemple' => '4x4'],
            'annee' => ['libelle' => 'Année', 'exemple' => '2022'],
            'capacite' => ['libelle' => 'Nombre de places', 'exemple' => '5'],
            'transmission' => ['libelle' => 'Transmission', 'exemple' => 'Manuelle'],
            'tarif_jour' => ['libelle' => 'Tarif journalier (FCFA)', 'exemple' => '45000'],
        ],
    ],

    'm9_tourisme' => [
        'nom' => 'Circuits touristiques',
        'description' => 'Circuits et excursions proposés aux clients.',
        'colonnes' => [
            'nom' => ['libelle' => 'Nom du circuit', 'exemple' => 'Circuit Parc National de la Pendjari'],
            'theme' => ['libelle' => 'Thème', 'exemple' => 'nature'],
            'zone' => ['libelle' => 'Zone', 'exemple' => 'Atacora'],
            'duree' => ['libelle' => 'Durée', 'exemple' => '2 jours'],
            'prix' => ['libelle' => 'Prix par participant (FCFA)', 'exemple' => '125000'],
            'capacite_max' => ['libelle' => 'Capacité maximale', 'exemple' => '12'],
        ],
    ],
];
