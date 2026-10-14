<?php

declare(strict_types=1);

/*
 * Libellés des DEUX écrans M7 de la PWA — `prototype_v2/pages/m7-achats.html`
 * et `prototype_v2/pages/m7-approvisionnement.html`.
 *
 * ## Pourquoi un second fichier à côté de `pwa.achats` et `pwa.appro`
 *
 * `lang/fr/pwa.php` porte déjà les libellés du maître pour ces deux pages
 * (colonnes, onglets, états vides, indicateurs) : ils sont repris tels quels
 * par les vues, jamais recopiés ici — deux listes finiraient par diverger.
 *
 * Ce fichier porte ce que le régime CRUD (PA-159, 28/08/2026) a ajouté et que
 * `pwa.php` ne pouvait pas contenir : les libellés des formulaires d'écriture,
 * et les refus RÉÉCRITS. Les clés `pwa.achats.refus_*` et `pwa.appro.refus_*`
 * datent de la lecture seule stricte : leurs motifs (« la consultation web est
 * en lecture seule ») ont CESSÉ D'ÊTRE VRAIS le 28/08/2026, et un motif périmé
 * transforme une décision en oubli — c'est arrivé trois fois dans ce dépôt
 * (PA-107, PA-120, PA-144). Elles ne sont donc plus employées par ces deux
 * écrans ; ce qui reste refusé l'est ici, avec sa raison RELUE ET DATÉE.
 *
 * @see EF-M7-01 Référentiel fournisseurs
 * @see EF-M7-02 Émission de commandes d'achat
 * @see EF-M7-03 Réception et entrée de stock (RG-10)
 */

return [

    /*
     * ------------------------------------------------------------------
     * Le tableau générique du maître (`assets/js/crud-ui.js`)
     * ------------------------------------------------------------------
     * Les deux phrases de l'état vide vivent déjà en `pwa.achats.vide_titre`
     * et `vide_detail` : elles ne sont pas redites ici.
     */
    'tableau' => [
        'selection_tout' => 'Tout sélectionner',
        'selection_ligne' => 'Sélectionner cette ligne',
        'affichage' => 'Affichage de :debut-:fin sur :total',
        'page' => 'Page :page / :pages',
        'precedent' => '← Précédent',
        'suivant' => 'Suivant →',
        'selectionnes' => ':nombre sélectionné(s)',
    ],

    /*
     * ------------------------------------------------------------------
     * M7 — Fournisseurs & Achats
     * ------------------------------------------------------------------
     */
    'achats' => [
        'ajouter' => 'Ajouter fournisseur',
        'exporter' => 'Exporter',
        // maître — `crud-ui.js` l.25 (bouton « Actualiser », icône seule).
        'actualiser' => 'Actualiser',
        // maître — `crud-engine.js` l.117 : « Ajouter ${entiteLabelSingulier} »
        // avec `entiteLabelSingulier: "commande d'achat"` (m7-achats.html
        // l.256). Ce bouton mène vers Approvisionnement — voir le docblock
        // de `Achats` : aucune commande ne peut se créer ici.
        'ajouter_commande' => 'Ajouter commande d\'achat',

        // `m7-approvisionnement.html` l.159-160 et l.225-226 : DEUX boutons,
        // jamais un « Exporter » fusionné (audit navigateur du 01/09/2026).
        'export_excel' => 'Export Excel',
        'export_pdf' => 'Export PDF',

        // La modale « Détail — <nom> » du maître (`crud-ui.js` l.107-121) et
        // ses DEUX boutons : « Fermer » et « Modifier ». Le second est le
        // chemin normal vers l'édition depuis une consultation.
        'detail_voir' => 'Voir le détail',
        'detail_titre' => 'Détail — :element',
        'detail_fermer' => 'Fermer',
        'detail_modifier' => 'Modifier',

        // Le formulaire du maître (`m7-achats.html` l.133-183) : cinq champs,
        // dans son ordre, avec ses libellés et ses invites.
        'form_nouveau' => 'Nouveau fournisseur',
        'form_edition' => 'Modifier le fournisseur',
        'form_sous_titre' => 'Le fournisseur est une vraie clé étrangère des commandes d\'achat : '
            . 'il se choisit dans cette liste, il ne se saisit jamais en texte libre.',
        'form_raison_sociale' => 'Raison sociale',
        'form_raison_sociale_invite' => 'Ex. Grand Marché Natitingou SARL',
        'form_contact' => 'Contact (téléphone)',
        'form_contact_invite' => '01 90 12 34 56',
        'form_categorie' => 'Catégorie fournie',
        'form_conditions' => 'Conditions de paiement',
        'form_evaluation' => 'Évaluation',
        'form_non_renseigne' => 'Non renseigné',
        'form_enregistrer' => 'Enregistrer',

        'cree' => 'Fournisseur « :nom » enregistré.',
        'modifie' => 'Fournisseur « :nom » mis à jour.',
    ],

    /*
     * ------------------------------------------------------------------
     * M7 — Approvisionnement
     * ------------------------------------------------------------------
     */
    'appro' => [
        /*
         * Trois libellés de colonne que `pwa.appro` ne porte pas : le maître
         * les écrit dans l'entête de ses EXPORTS (`m7-approvisionnement.html`
         * l.367 et l.534), là où ses tableaux à l'écran, eux, n'ont pas de
         * ligne d'entête du tout. Ce sont ses mots, repris tels quels.
         */
        'col_reste_du' => 'Reste dû',
        'col_numero_commande' => 'N° commande',
        'col_anciennete' => 'Ancienneté',

        'commander_selection' => 'Commander la sélection',
        'receptionner' => 'Réceptionner',
        'regler' => 'Régler',

        'form_commande' => 'Nouveau bon de commande',
        'form_commande_sous_titre' => ':nombre article(s) sélectionné(s)',
        'form_fournisseur' => 'Fournisseur',
        'form_quantite' => 'Qté',
        'form_prix_unitaire' => 'P.U.',
        'form_montant' => 'Montant',
        'form_total' => 'Total',
        'form_creer_commande' => 'Créer le bon de commande',

        'form_reception' => 'Réception :commande',
        'form_reception_sous_titre' => ':fournisseur — commandé le :date',
        'form_point' => 'Point de stockage',
        'form_commandee' => 'Commandé',
        'form_deja_recu' => 'Déjà reçu',
        'form_recu_maintenant' => 'Reçu maintenant',
        'form_valider_reception' => 'Valider la réception',
        'form_avertissement_double' => 'La réception génère l\'entrée de stock et met à jour le coût '
            . 'moyen pondéré au prix de cette commande. Ne saisissez pas le stock une seconde fois '
            . 'dans l\'écran Stocks : la quantité serait comptée deux fois.',

        'commande_creee' => 'Bon de commande créé pour :fournisseur.',
        'reception_enregistree' => 'Réception enregistrée (:conformite) — stock et coût moyen pondéré '
            . 'mis à jour.',

        'aucune_selection' => 'Sélectionnez au moins un article à commander.',
        'aucun_fournisseur' => 'Aucun fournisseur n\'est enregistré : une commande d\'achat porte une '
            . 'vraie clé étrangère vers le référentiel. Créez le fournisseur sur l\'écran '
            . '« Fournisseurs & Achats » d\'abord.',
        'aucun_point' => 'Aucun point de stockage n\'est enregistré : une réception doit dire OÙ la '
            . 'marchandise entre, sans quoi aucun mouvement de stock ne peut être écrit.',
        'prix_obligatoire' => 'Le prix unitaire est obligatoire et strictement positif : sans lui aucun '
            . 'montant de commande ne peut être calculé, ni aucun coût moyen pondéré mis à jour à la '
            . 'réception.',
        'quantite_obligatoire' => 'La quantité doit être strictement positive : une saisie à zéro n\'est '
            . 'pas une ligne de commande.',

        'prix_suggere' => 'Prix unitaire pré-rempli avec le coût moyen pondéré connu de l\'article — '
            . 'c\'est une valorisation d\'achats passés, PAS un tarif négocié. Corrigez-le avec le prix '
            . 'du fournisseur avant de valider.',
        'quantite_suggeree' => 'Quantité suggérée : de quoi remonter au DOUBLE du seuil, jamais au seuil '
            . 'pile — recommander à l\'exact ferait repasser l\'article sous alerte à la première sortie.',
        // ⚠ « Cette liste porte sur leur MONTANT COMMANDÉ » a cessé d'être
        // vrai le 02/09/2026 (PA-165) : `ReglementFournisseurService` calcule
        // désormais un « Réglé » et un « Reste dû » réels — voir
        // `col_regle`/`col_reste_du`, lus depuis le Service, jamais soustraits
        // localement.
        'dettes_portee' => 'Cette liste porte sur les commandes non clôturées. « Réglé » et « Reste dû » '
            . 'viennent des règlements réellement enregistrés. La colonne « Ancienneté » mesure l\'âge du '
            . 'bon de commande, pas le retard d\'un paiement.',

        // ---- Modale « Régler » — PA-165 (02/09/2026), ReglementFournisseurService ----
        'form_reglement' => 'Régler — :fournisseur',
        'form_reglement_sous_titre' => 'Commande :commande — reste dû :reste',
        'form_montant_regle' => 'Montant réglé (FCFA)',
        'form_tresorerie' => 'Trésorerie',
        'form_valider_reglement' => 'Enregistrer le règlement',
        'reglement_enregistre' => 'Règlement de :montant enregistré pour :fournisseur.',
        'reglement_commande_soldee' => 'Cette commande est déjà intégralement réglée.',
        'tresorerie_caisse' => 'Caisse',
        'tresorerie_momo' => 'Mobile Money',
        'tresorerie_banque' => 'Banque',
    ],

    /*
     * ------------------------------------------------------------------
     * Exports — PA-119 : un export porte sur CE QUI EST AFFICHÉ, et il DIT
     * son filtre. Une liste vide se refuse, elle ne produit pas une page
     * blanche.
     * ------------------------------------------------------------------
     */
    'export' => [
        'titre_fournisseurs' => 'Exporter — Fournisseurs',
        'titre_commandes' => 'Exporter — Commandes d\'achat',
        'titre_appro' => 'Exporter — Approvisionnement',
        'sous_titre_filtre' => 'Le document portera exactement les :nombre ligne(s) affichées, filtres '
            . 'compris.',
        'sous_titre_selection' => 'Le document portera exactement les :nombre ligne(s) sélectionnées.',
        'vide' => 'Rien à exporter : la liste affichée est vide.',
        'fichier_fournisseurs' => 'fournisseurs',
        'fichier_commandes' => 'commandes_achat',
        'fichier_appro' => 'approvisionnement',
        // Titres portés par l'en-tête RG-19 du document (PA-194) — ceux que
        // les gabarits écrivaient en dur.
        'document_commandes' => 'Commandes d\'achat',
        'document_fournisseurs' => 'Fournisseurs',
        'document_appro' => 'Approvisionnement',
        'periode_appro' => 'Onglet « :onglet »',
    ],

    /*
     * ARCHIVAGE DU RÉFÉRENTIEL FOURNISSEURS — demande du Product Owner du
     * 03/09/2026. « Supprimer » est le mot du maître (`crud-ui.js` l.100 et
     * l.136) ; le geste, lui, ARCHIVE : `ReferentielFournisseurService` pose
     * `actif = false`, et aucun `delete()` n'existe dans ce dépôt.
     */
    'archivage' => [
        'bouton_ligne' => 'Supprimer',
        'bouton_lot' => 'Supprimer',
        'bouton_restaurer' => 'Restaurer',
        'badge' => 'Archivé',
        'verrou' => 'Engagé dans :nombre commande(s) d\'achat en cours : la réception à venir a besoin '
            . 'de ce fournisseur au sélecteur.',
        'succes' => '{1} Fournisseur archivé — il reste restaurable.|[2,*] :nombre fournisseurs archivés — '
            . 'ils restent restaurables.',
        'restaure' => 'Fournisseur « :nom » restauré : il revient au sélecteur des commandes.',
    ],
];
