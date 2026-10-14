<?php

declare(strict_types=1);

/*
 * Libelles des DEUX ecrans M6 de la PWA — « Gestion des Stocks »
 * (`prototype_v2/pages/m6-stocks.html`) et « Inventaires & Fiches de stock »
 * (`prototype_v2/pages/m6-inventaires.html`).
 *
 * ## Pourquoi un fichier separe de `lang/fr/stocks.php`
 *
 * `stocks.php` porte les messages du DOMAINE : refus de service, validation de
 * l'API, intitules imprimes sur un etat remis a un tiers. Ce fichier-ci porte
 * les mots de DEUX ECRANS, et il en porte beaucoup — titres de colonne,
 * invites, aides de champ, refus nommes. Les melanger aurait fait grossir un
 * fichier lu par l'API, le moteur d'etats et le client Flutter.
 *
 * ## Les libelles viennent du maitre, au mot pres
 *
 * Chaque chaine visible est celle de la maquette validee par le client. Une
 * reformulation est un ecart de gabarit (`t-trois-sources.js` §2 et §4), au
 * meme titre qu'une classe changee. Quand un libelle s'ecarte, il porte un
 * commentaire disant lequel et pourquoi.
 */

return [

    /*
     * ------------------------------------------------------------------
     * Ecran « Gestion des Stocks » — m6-stocks.html
     * ------------------------------------------------------------------
     */
    'liste' => [
        'titre' => 'Gestion des Stocks',
        'titre_page' => 'Gestion des Stocks — TATACORA AFRIQUE',

        // maitre — m6-stocks.html l.28-31
        'sous_titre' => 'Référentiel valorisé au coût moyen pondéré — le stock affiché est',
        'sous_titre_fort' => 'calculé depuis les mouvements',
        'sous_titre_fin' => ', il ne se saisit jamais.',

        // maitre — l.34-36
        'lien_inventaires' => 'Inventaires & fiches',
        'lien_approvisionnement' => 'Approvisionnement',
        'nouvel_article' => '+ Nouvel article',

        // maitre — l.47-66
        'rechercher' => 'Rechercher un article…',
        'toutes_categories' => 'Toutes catégories',
        'tous_points' => 'Tous les points',
        'tous_etats' => 'Tous les états',
        'etat_sous_seuil' => 'Sous seuil',
        'etat_rupture' => 'En rupture',

        // maitre — l.52-56 : le filtre « Tous les suivis ».
        'tous_suivis' => 'Tous les suivis',
        'suivi_permanent' => 'Gros stock (permanent)',
        'suivi_journalier' => 'Petit stock (journalier)',

        // maitre — l.230-233 : le badge de la colonne « Suivi », et la mention
        // qui remplace le stock d'un article dont le stock n'est pas tenu.
        'badge_permanent' => 'Permanent',
        'badge_journalier' => 'Journalier',
        'stock_non_suivi' => 'non suivi',

        /*
         * PA-161 (a) — « — » AVEC sa raison, jamais un zero plausible.
         *
         * Un article cree avant le 02/09/2026 n'a ni point de rattachement ni
         * prix d'achat : les deux naissent d'une reception. Ecrire « Magasin
         * general » ou « 0 F » a leur place affirmerait un fait que personne
         * n'a etabli. L'infobulle dit lequel manque, article par article — un
         * motif global aurait dit que la colonne n'existe pas, ce qui est faux.
         */
        'jamais_receptionne' => 'Jamais réceptionné : ni point de rattachement, ni prix d\'achat. '
            . 'Les deux se posent à la première entrée de stock.',
        'importer' => 'Importer',
        'modele' => 'Modèle',
        'excel' => 'Excel',
        'pdf' => 'PDF',

        // maitre — l.185-186
        'nombre_articles' => ':nombre article(s)',
        'stock_non_modifiable' => 'Stock calculé — non modifiable ici',

        // maitre — l.192-201 : la casse est celle du maitre, `uppercase` fait
        // le rendu. Une majuscule ecrite en dur ressortirait telle quelle dans
        // le CSV et le PDF, ou aucune feuille de style ne s'applique.
        'col_article' => 'Article',
        'col_categorie' => 'Catégorie',
        // 02/09/2026 — garde G5 : le maitre nomme « Unité » en colonne de son
        // etat exporte (l.464), entre Catégorie et Point.
        'col_unite' => 'Unité',
        'col_point' => 'Point',
        'col_suivi' => 'Suivi',
        'col_stock' => 'Stock',
        'col_seuil' => 'Seuil',
        'col_valeur_achat' => 'Valeur d\'achat',
        'col_cmp' => 'CMP',
        'col_valeur_stock' => 'Valeur stock',
        'col_actions' => 'Actions',

        // maitre — l.242-244
        'action_fiche' => 'Fiche',
        'action_mouvement' => 'Mouvement',
        'action_modifier' => 'Modifier',

        // maitre — l.170-174 (les cinq cartes d'indicateurs)
        'kpi_references' => 'Références',
        'kpi_references_detail' => ':permanents suivies · :journaliers journalières',
        'kpi_valeur' => 'Valeur du stock',
        'kpi_valeur_detail' => 'au coût moyen pondéré',
        'kpi_sous_seuil' => 'Sous seuil',
        'kpi_sous_seuil_detail' => 'à réapprovisionner',
        'kpi_mouvements' => 'Mouvements 30 j',
        'kpi_suivi' => 'Gros / petit stock',
        'kpi_suivi_detail' => 'suivi vs journalier',
        // maitre l.174 : `k.permanents + ' / ' + k.journaliers`.
        'kpi_suivi_valeur' => ':permanents / :journaliers',

        // Etat vide — `crud-ui.js` du maitre pose « Aucun résultat » et
        // « Essayez de modifier votre recherche ou vos filtres. ». La page
        // m6-stocks, elle, ecrit sa propre phrase (l.189), plus precise : elle
        // nomme l'objet manquant. C'est celle-ci qui est rendue en detail.
        'vide_titre' => 'Aucun résultat',
        'vide_detail' => 'Aucun article ne correspond à ces filtres.',
    ],

    /*
     * ⚠ LE BLOC `refus` A ETE RETIRE LE 02/09/2026, ET C'EST LE LIVRABLE.
     *
     * Il portait trois motifs affiches sous le tableau : « Point », « Suivi »
     * et « Valeur d'achat » ne sont pas alimentees, `articles` ne les porte
     * pas. Ils etaient exacts a l'ecriture ; PA-161 (a) a tranche et les trois
     * colonnes existent (`SHOW COLUMNS FROM articles` du 02/09/2026).
     *
     * Les garder aurait laisse a l'ecran une explication devenue fausse, ce
     * qui est PIRE qu'une colonne vide : le lecteur cesse de chercher pourquoi
     * la donnee manque, puisque l'ecran lui dit que c'est impossible (PA-144).
     *
     * Ce qui reste a dire est dit LIGNE PAR LIGNE, la ou la valeur manque
     * reellement : `liste.jamais_receptionne`, en infobulle sur le « — » d'un
     * article jamais receptionne. Un motif global aurait affirme que la
     * colonne n'existe pas ; l'infobulle dit que CET article-la n'a pas encore
     * de valeur, ce qui est vrai et actionnable.
     */

    /*
     * Modale « Nouvel article » / « Modifier l'article » — m6-stocks.html
     * l.296-374.
     */
    'article' => [
        'titre_creation' => 'Nouvel article',
        'titre_edition' => 'Modifier l\'article',
        'sous_titre_creation' => 'Le stock se constitue par mouvements, jamais par saisie directe.',
        'valider_creation' => 'Créer l\'article',
        'valider_edition' => 'Enregistrer',

        'nom' => 'Nom de l\'article',
        'nom_invite' => 'Ex. Riz local (sac 50 kg)',
        'categorie' => 'Catégorie',
        'unite' => 'Unité de mesure',
        'point' => 'Point de stockage',

        /*
         * ⚠ Cette aide disait « Il n'est pas attaché à l'article ». C'etait
         * vrai jusqu'au 02/09/2026 et faux depuis : `articles.point_stockage_id`
         * existe (PA-161 (a)). La phrase est reecrite plutot que laissee a
         * vieillir (PA-144), et elle garde la distinction qui compte — la
         * colonne dit OU L'ARTICLE EST RATTACHE, jamais ou se trouve son stock.
         */
        'point_aide' => 'Point de rattachement principal de l\'article, et point d\'imputation de '
            . 'son stock d\'ouverture. Il ne limite pas le stock : un article peut être détenu en '
            . 'plusieurs endroits, et le total se calcule point par point.',

        // maitre — l.312-315
        'suivi' => 'Mode de suivi',
        'suivi_permanent_option' => 'Gros stock — suivi permanent (sacs, cartons, viandes…)',
        'suivi_journalier_option' => 'Petit stock — acheté au jour le jour (tomates, laitue…)',
        'suivi_aide' => 'Le petit stock n\'est ni décrémenté à la vente, ni inventorié, ni alerté : '
            . 'seule la dépense d\'achat est constatée.',

        'valeur_achat' => 'Valeur d\'achat unitaire (FCFA)',
        'valeur_achat_invite' => 'Ex. 32000',
        'valeur_achat_aide' => 'Elle valorise le stock d\'ouverture et fixe le premier coût moyen '
            . 'pondéré. Sans elle, l\'article entre au bilan pour zéro et la variation de '
            . 'stock — donc le résultat — est fausse.',

        'seuil' => 'Seuil d\'alerte',
        // Article 8 (02/09/2026) : la reference RG-07 vit ici, jamais a l'ecran.
        'seuil_aide' => 'Un paramètre, pas un état : il déclenche l\'alerte de sous-stock.',

        'stock_ouverture' => 'Stock d\'ouverture',
        'stock_ouverture_aide' => 'Enregistré comme un MOUVEMENT d\'entrée, pas comme une '
            . 'colonne : c\'est ce qui le rend visible en fiche de stock.',

        /*
         * La valeur d'achat en MODIFICATION est en LECTURE SEULE, et c'est un
         * ecart assume avec le maitre (l.307-310, qui la rend editable).
         *
         * Elle est posee par l'entree de stock — seul geste qui l'etablit, et
         * le seul qui laisse une trace en fiche de stock. Offrir un champ ici
         * laisserait reecrire un prix d'achat apres coup, sans reception pour
         * l'appuyer, et l'ecart avec le cout moyen pondere — qui est
         * l'information utile de cette colonne — deviendrait arbitraire.
         */
        'recap_valeur_achat' => 'Valeur d\'achat (dernière entrée)',
        'recap_valeur_achat_absente' => 'aucune entrée valorisée',
        'recap_valeur_achat_note' => 'Elle est posée par l\'entrée de stock, seul geste qui '
            . 'l\'établit. La corriger ici réécrirait un prix d\'achat après coup, sans réception '
            . 'pour l\'appuyer.',

        'recap_stock' => 'Stock actuel (calculé)',
        'recap_cmp' => 'Coût moyen pondéré',
        'recap_valeur' => 'Valeur du stock',
        'recap_note' => 'Le stock ne se modifie pas ici : il se corrige par un mouvement ou un '
            . 'inventaire, qui en conserve la raison.',

        // Motif du mouvement d'entrée que le stock d'ouverture produit. Il est
        // écrit dans `mouvements_stock.motif` : il apparaît tel quel en fiche
        // de stock, et c'est ce qui rend l'ouverture rapprochable.
        'stock_ouverture_motif' => 'Stock d\'ouverture',

        'cree' => 'Article « :libelle » créé.',
        'modifie' => 'Article « :libelle » mis à jour.',

        /*
        |-----------------------------------------------------------------------
        | ENTRÉE DE STOCK DEPUIS LA FICHE ARTICLE — directive PO du 06/09/2026
        |-----------------------------------------------------------------------
        |
        | « Niveau stock, permettre de modifier le stock dans le modal Modifier
        | l'article. » Le geste manquait : le stock d'ouverture n'existait qu'à
        | la CRÉATION, et corriger un stock exigeait de fermer la fiche pour
        | rouvrir « Mouvement ».
        |
        | ⚠ Les libellés disent ENTRÉE, jamais « stock ». Le stock reste
        | l'agrégation des mouvements, rendue en lecture seule juste en dessous.
        | Un champ nommé « Stock » ferait croire qu'on écrase une valeur — la
        | deuxième des sept règles du projet prise à revers.
        */
        'entree_titre' => 'Faire entrer du stock',
        'entree_quantite' => 'Quantité à faire entrer',
        'entree_point' => 'Point de stockage qui reçoit',
        'entree_cout' => 'Coût unitaire de cette entrée (FCFA)',
        'entree_aide' => 'Ajoute au stock, sans jamais l’écraser : l’entrée est enregistrée comme '
            . 'un mouvement daté et signé, visible en fiche article. Laissez la quantité vide pour '
            . 'enregistrer la fiche sans toucher au stock. Sans coût unitaire, l’entrée ne valorise '
            . 'rien — zéro se lirait « reçu gratuitement » et fausserait le coût moyen pondéré.',
        'entree_motif' => 'Entrée depuis la fiche article',
        'entree_enregistree' => 'Entrée enregistrée : :quantite :unite sur « :libelle ».',
        'entree_point_requis' => 'Choisissez le point de stockage qui reçoit la marchandise : une '
            . 'quantité sans destination n’est pas une livraison.',
        'entree_refus_journalier' => 'L’article « :article » est suivi au jour le jour : il n’a pas '
            . 'de stock à tenir, et lui poser une entrée écrirait un solde que personne ne compte.',
        'entree_refus_role' => 'Faire entrer du stock depuis la fiche article est réservé à '
            . 'l’administrateur : l’entrée valorise la marchandise et déplace le coût moyen '
            . 'pondéré, qui alimente le bilan. Le bouton « Mouvement » de la ligne reste ouvert.',
        'introuvable' => 'Cet article n\'existe plus dans le référentiel.',
    ],

    /*
     * Modale « Mouvement de stock » — m6-stocks.html l.376-446.
     */
    'mouvement' => [
        'titre' => 'Mouvement de stock',
        'valider' => 'Enregistrer',

        'stock_actuel' => 'Stock actuel',
        'cmp' => 'CMP',

        'type' => 'Type de mouvement',
        'type_entree' => 'Entrée (réception, retour)',
        'type_sortie' => 'Sortie (consommation, vente)',
        'type_perte' => 'Perte (casse, péremption, vol)',

        'point' => 'Point de stockage',
        'quantite' => 'Quantité',

        'cout' => 'Coût d\'achat unitaire (FCFA)',
        'cout_aide' => 'Recalcule le coût moyen pondéré. Laisser vide pour un simple transfert '
            . 'entre points : déplacer une marchandise ne change pas son coût.',

        'motif' => 'Motif',
        'motif_invite' => 'Ex. Réception SODIS Bénin',

        'enregistre' => 'Mouvement enregistré.',

        // RG-06 — la rupture n'est pas une erreur definitive, c'est une demande
        // de confirmation aupres d'un utilisateur habilite (maitre l.425-440).
        'rupture_titre' => 'Stock insuffisant',
        'rupture_detail' => 'Forcer la sortie créera un stock négatif, tracé comme '
            . '« rupture forcée » dans la fiche de stock.',
        'rupture_confirmer' => 'Forcer la sortie',
        'rupture_enregistree' => 'Sortie forcée enregistrée et tracée.',

        'aucun_point' => 'Aucun point de stockage n\'est défini : un mouvement ne peut être '
            . 'imputé nulle part. Créez-en un avant de saisir une entrée.',

        /*
         * maitre — l.381, au mot pres. L'article est NOMME : « son stock n'est
         * pas suivi » sans dire lequel obligerait a deviner sur une liste de
         * vingt-cinq lignes.
         */
        'refus_journalier' => '« :article » est en suivi journalier : son stock n\'est pas suivi.',
    ],

    /*
     * Import CSV — m6-stocks.html l.477-502.
     */
    'import' => [
        'titre' => 'Importer des articles',
        'sous_titre' => 'Fichier CSV, une ligne par article. Le stock d\'ouverture entre comme '
            . 'un mouvement, jamais comme une colonne.',
        'fichier' => 'Fichier CSV',
        'colonnes' => 'Colonnes attendues, dans cet ordre : :colonnes',
        'valider' => 'Importer',
        'telecharger_modele' => 'Télécharger le modèle',

        'bilan' => ':crees article(s) importé(s).',
        'bilan_partiel' => ':crees importé(s), :refuses refusé(s).',
        'ligne_refusee' => 'ligne :numero — :nom : :raison',
        'fichier_illisible' => 'Le fichier n\'a pas pu être lu : il est vide, ou ce n\'est pas '
            . 'un CSV.',
        'entete_absente' => 'La première ligne doit être l\'en-tête du modèle. Téléchargez le '
            . 'modèle et repartez de lui.',
        'colonne_manquante' => 'colonne manquante',
    ],

    /*
     * ------------------------------------------------------------------
     * Ecran « Inventaires & Fiches de stock » — m6-inventaires.html
     * ------------------------------------------------------------------
     */
    'inventaires' => [
        'titre' => 'Inventaires & Fiches de stock',
        'titre_page' => 'Inventaires & Fiches de stock — TATACORA AFRIQUE',

        // maitre — l.28-31
        'sous_titre' => 'Stock initial, entrées, sorties et stock théorique sur une période — '
            . 'le stock est',
        'sous_titre_fort' => 'calculé',
        'sous_titre_fin' => ', jamais saisi.',

        // maitre — l.37-45
        'onglet_fiche' => 'Fiche de stock',
        'onglet_inventaire' => 'Inventaire physique',
        'onglet_historique' => 'Inventaires clôturés',

        // maitre — l.53-79
        'article' => 'Article',
        'point' => 'Point de stockage',
        'tous_points' => 'Tous les points',
        'du' => 'Du',
        'au' => 'Au',
        'periode_7' => '7 jours',
        'periode_30' => '30 jours',
        'periode_90' => '90 jours',
        'periode_mois' => 'Ce mois',
        'export_pdf' => 'Export PDF',
        'export_excel' => 'Export Excel',

        'aucun_article' => 'Aucun article',
        'aucun_article_detail' => 'Créez d\'abord un article dans l\'écran Stocks.',

        // maitre — l.211-215
        'incoherence' => 'Incohérence détectée.',
        'incoherence_detail' => 'Le solde progressif ne retombe pas sur le stock théorique. '
            . 'Un mouvement a été écrit hors du moteur de stock — ce document ne doit pas '
            . 'servir de justificatif.',

        // maitre — l.226-231 (les six cartes)
        'kpi_stock_initial' => 'Stock initial',
        'kpi_entrees' => 'Entrées',
        'kpi_sorties' => 'Sorties',
        'kpi_pertes' => 'Pertes',
        'kpi_regularisations' => 'Régularisations',
        'kpi_stock_theorique' => 'Stock théorique',

        // maitre — l.234-241
        'cmp' => 'CMP',
        'valeur_theorique' => 'Valeur du stock théorique',
        'point_courant' => 'Point',

        // maitre — l.245-269
        // Option « Tous les articles » du filtre de fiche de stock
        // (PO 06/09/2026). Les quantites ne sont JAMAIS totalisees —
        // kilos, casiers et portions ne s'additionnent pas ; seule la
        // valeur en francs a une unite commune.
        'tous_les_articles' => 'Tous les articles',
        'tous_aide' => "Chaque ligne garde l'unite et le solde de son propre article : les quantites d'articles differents ne s'additionnent pas.",
        'kpi_articles' => 'Articles au catalogue',
        'kpi_articles_mouvementes' => 'Articles mouvementes',
        'kpi_mouvements' => 'Mouvements sur la periode',
        'kpi_valeur' => 'Valeur du stock theorique',
        'incoherents_liste' => 'Articles concernes : :articles.',
        'detail_mouvements' => 'Détail des mouvements',
        'nombre_mouvements' => ':nombre mouvement(s)',
        'aucun_mouvement' => 'Aucun mouvement sur cette période.',
        'col_date' => 'Date',
        'col_type' => 'Type',
        'col_motif' => 'Motif',
        'col_entree' => 'Entrée',
        'col_sortie' => 'Sortie',
        'col_solde' => 'Solde',
        // 02/09/2026 — garde G5 : le maitre nomme cette colonne « Utilisateur »
        // dans son etat exporte (l.290) ; « Par » reste rendu par l'historique
        // (hist_col_par). Ancienne cle `col_par`, renommee avec son libelle.
        'col_utilisateur' => 'Utilisateur',

        'type_entree' => 'Entrée',
        'type_sortie' => 'Sortie',
        'type_perte' => 'Perte',
        'type_inventaire' => 'Inventaire',

        // maitre — l.394-412
        'aucun_inventaire' => 'Aucun inventaire en cours',
        'aucun_inventaire_detail' => 'Ouvrir un inventaire fige le stock théorique de chaque '
            . 'article à cet instant.',
        'lancer' => 'Lancer l\'inventaire',
        'lance' => 'Inventaire ouvert — :nombre article(s) à compter.',

        /*
         * ÉTAPE 1 — le tableau « Cycle d'inventaire par magasin ». Maitre :
         * m6-inventaires.html l.341-357 (`rendrePeriodicite()`).
         *
         * ⚠ Le maitre calcule une periodicite REGLABLE par magasin
         * (`StockEngine.PERIODICITES`, persistee en localStorage cote
         * prototype). Le schema serveur ne porte AUCUNE colonne de
         * periodicite : l'ajouter serait promettre un reglage que rien
         * n'exploite encore, l'exact defaut nomme par PA-59 (un indicateur
         * qui dit « tout va bien » — ou ici « c'est regle » — pendant que
         * rien n'a lieu). L'affichage est donc DERIVE, jamais parametrable :
         * chaque magasin rend le meme etat que le maitre rend LUI-MEME pour
         * un magasin sans periodicite definie (`etat()`, l.328).
         */
        'cycle_titre' => 'Cycle d’inventaire par magasin',
        'cycle_aide' => 'La périodicité signale une échéance ; elle n’empêche jamais de lancer un inventaire.',
        // 02/09/2026 — les QUATRE entetes sont ceux du maitre (l.353-356), au
        // caractere pres : il les ecrit SANS accents, et la garde G5 compare
        // sans les rapprocher. L'ancien « Dernier inventaire réel » (motive
        // par PA-150 : aucun statut de cloture au schema) est revenu au mot du
        // maitre par transcription litterale ; la reserve de PA-150 reste
        // vraie — la date affichee est celle du dernier inventaire ENREGISTRE
        // — et vit dans l'entete de la vue, pas dans un libelle divergent.
        'cycle_col_magasin' => 'Magasin',
        'cycle_col_periodicite' => 'Periodicite',
        'cycle_col_dernier' => 'Dernier inventaire cloture',
        'cycle_col_etat' => 'Etat',
        'cycle_non_definie' => 'non définie',
        'cycle_dernier_aucun' => 'aucun',

        // maitre — l.435-454
        'inventaire_du' => 'Inventaire du :date — :point',
        'tous_points_libelle' => 'tous points',
        'comptes' => ':comptes / :total article(s) comptés',
        'ecarts' => ':nombre écart(s)',
        'impact' => 'impact valorisé',
        'cloturer' => 'Clôturer et régulariser',

        // 02/09/2026 — garde G5 : « Unité » est une colonne de l'etat exporte
        // du comptage (maitre l.538), entre Article et Théorique.
        'col_unite_comptage' => 'Unité',
        'col_theorique' => 'Théorique',
        'col_compte' => 'Compté',
        'col_ecart' => 'Écart',
        'col_ecart_valorise' => 'Écart valorisé',
        'a_compter' => 'à compter',
        // 02/09/2026 — etat vide de la feuille de comptage (garde G5 : le
        // thead reste rendu, le corps dit qu'il n'y a rien). Couple generique
        // du maitre, `crud-ui.js` l.76-77.
        'comptage_vide_titre' => 'Aucun résultat',
        'comptage_vide_detail' => 'Essayez de modifier votre recherche ou vos filtres.',
        'enregistrer_comptage' => 'Enregistrer le comptage',
        'comptage_enregistre' => 'Comptage de « :article » enregistré.',

        // maitre — l.514-521
        'incomplet_titre' => 'Inventaire incomplet',
        'incomplet_detail' => 'Clôturer maintenant ne régularisera QUE les articles comptés ; '
            . 'les autres resteront à leur stock théorique actuel, sans que rien ne le signale '
            . 'par la suite.',
        'incomplet_confirmer' => 'Clôturer partiellement',
        'cloture' => 'Inventaire clôturé — :nombre régularisation(s), impact :impact.',

        // maitre — l.559-568
        'hist_col_date' => 'Date',
        'hist_col_point' => 'Point',
        'hist_col_articles' => 'Articles',
        'hist_col_regularises' => 'Régularisés',
        'hist_col_manquants' => 'Manquants',
        'hist_col_excedents' => 'Excédents',
        'hist_col_impact' => 'Impact net',
        'hist_col_par' => 'Par',
        'hist_vide' => 'Aucun inventaire clôturé',
        'hist_vide_detail' => 'Les inventaires clôturés et leurs régularisations apparaîtront ici.',

        'aucun_point_defini' => 'Aucun point de stockage n\'est défini : un inventaire porte sur '
            . 'un point, il ne peut pas être ouvert sans lui.',
    ],

    /*
     * Titres des deux modales d'export, passes a
     * `pwa.partials.modale-export` — il NOMME ce qui sera exporte.
     */
    'export' => [
        'titre_stocks' => 'Exporter — Articles en stock',
        'titre_fiche' => 'Exporter — Fiche de stock',
        'sous_titre_filtre' => 'Le document porte les filtres affichés : :filtres',
        'filtre_aucun' => 'aucun filtre, le référentiel entier',
        'liste_vide' => 'Rien à exporter : aucun article ne correspond aux filtres affichés.',
        // L'export de fiche porte sur UN article : son en-tete, ses
        // cumuls et son unite le sont (PO 06/09/2026).
        'fiche_tous_articles' => "Choisissez un article : le document de fiche de stock est etabli pour un seul article. Sous « Tous les articles », les quantites d'unites differentes ne peuvent pas etre totalisees.",
        'fiche_absente' => 'Sélectionnez un article avant d\'exporter.',
        // Titres portés par l'en-tête RG-19 du document (PA-194) — ceux que
        // les gabarits écrivaient en dur.
        'document_stocks' => 'État des stocks',
        'document_fiche' => 'Fiche de stock — :article',
        'document_inventaire' => 'Inventaire physique',
        'periode_inventaire' => ':point — inventaire du :date',
        'tous_points' => 'Tous points',
    ],

    /*
     * ARCHIVAGE DU RÉFÉRENTIEL ARTICLES — demande du Product Owner du
     * 03/09/2026. « Supprimer » est le mot du maître (`crud-ui.js` l.100 et
     * l.136) ; le geste, lui, ARCHIVE : `ReferentielArticleService` pose
     * `actif = false`, et aucun `delete()` n'existe dans ce dépôt.
     *
     * Les quatre verrous disent une CONSÉQUENCE, pas un code d'erreur : celui
     * qui lit doit savoir quoi faire pour débloquer.
     */
    'archivage' => [
        'bouton_ligne' => 'Supprimer',
        'bouton_lot' => 'Supprimer',
        'bouton_restaurer' => 'Restaurer',
        'badge' => 'Archivé',
        'selection_tout' => 'Tout sélectionner',
        'selection_ligne' => 'Sélectionner cette ligne',
        'selectionnes' => ':nombre sélectionné(s)',
        'verrou_stock' => 'Il reste :quantite en stock : archiver l\'article rendrait ces unités '
            . 'invisibles à l\'inventaire.',
        'verrou_commande' => 'Il figure sur :nombre commande(s) d\'achat en cours : la réception à venir '
            . 'a besoin de cet article au sélecteur.',
        'verrou_carte' => 'Il est vendu à la carte (:nombre entrée(s)) : le comptoir continuerait de le '
            . 'vendre et de décrémenter son stock. Retirez-le d\'abord de la carte.',
        'verrou_recette' => 'Il entre dans :nombre recette(s) : la déduction de stock cuisine le cherche '
            . 'par cette composition.',
        'succes' => '{1} Article archivé — il reste restaurable.|[2,*] :nombre articles archivés — '
            . 'ils restent restaurables.',
        'restaure' => 'Article « :libelle » restauré.',
    ],
];
