<?php

declare(strict_types=1);

/**
 * Écran PWA « Dépense courante » (M10) — libellés et messages.
 *
 * Fichier distinct de `lang/fr/depenses.php`, qui sert le DOMAINE : ses
 * messages nomment un refus comptable et sont partagés avec l'API. Ceux-ci
 * n'existent que pour l'écran, et ce sont les mots du maître
 * `prototype_v2/pages/depenses.html` — au mot près, y compris la casse. Les
 * mélanger aurait rendu les deux registres illisibles, et surtout : corriger
 * un libellé d'écran ne doit jamais toucher un message que l'API renvoie.
 *
 * ⚠ Aucun de ces libellés ne se réécrit « pour faire mieux ». Article 1.05 de
 * `docs/DIRECTIVE_CONFORMITE_100.md` : changer un libellé, même pour un
 * synonyme, est interdit.
 */
return [

    // --- En-tête de page (depenses.html l.26-39) -------------------------

    'titre' => 'Dépense courante',

    'sous_titre_avant' => "Les charges d'exploitation ",
    'sous_titre_fort' => 'décaissées directement',
    'sous_titre_apres' => ' — le marché du matin, un transport, un dépannage. Elles '
        ."n'ont ni bon de commande ni délai de règlement : une dépense suivie auprès "
        ."d'un fournisseur relève de ",
    'sous_titre_lien' => 'Approvisionnement',
    'sous_titre_fin' => '. Confondre les deux ferait apparaître en dettes fournisseurs '
        .'des sommes déjà sorties de la caisse.',

    'nouvelle_depense' => 'Nouvelle Dépense',

    // --- Indicateurs (depenses.html l.49, depenses.js l.79-92) -----------

    'kpis_bascule' => 'Indicateurs de la période',
    /*
     * L'aide de l'accordéon (03/09/2026). La bande se replie désormais à
     * TOUTES les largeurs : la bascule existait mais était `sm:hidden`,
     * si bien qu'au-delà de 640 px les six cartes restaient dépliées et
     * que le bouton lui-même disparaissait — sur le poste du Gérant,
     * précisément, où la hauteur de tableau compte le plus.
     */
    'kpis_aide' => 'Repliez la bande pour gagner de la hauteur de tableau.',

    'kpi_total' => 'Total décaissé',
    'kpi_total_detail' => ':nombre dépense(s)',
    'kpi_moyenne' => 'Dépense moyenne',
    'kpi_moyenne_detail' => 'sur la période filtrée',
    'kpi_marche' => 'Marché',
    'kpi_marche_detail' => 'denrées',
    'kpi_services' => 'Services',
    'kpi_services_detail' => 'charges externes',
    'kpi_caisse' => 'Caisse',
    'kpi_caisse_detail' => 'espèces',
    'kpi_sans_ecriture' => 'Sans écriture',
    'kpi_sans_ecriture_a_faire' => 'à régulariser',
    'kpi_sans_ecriture_ok' => 'tout est comptabilisé',

    // --- Filtres (depenses.html l.58-67, depenses.js l.53-58) ------------

    'recherche' => 'Libellé, nature, compte…',
    'du' => 'À partir du',
    'au' => "Jusqu'au",
    'toute_tresorerie' => 'Toute trésorerie',
    'toute_categorie' => 'Toute catégorie',
    'reinitialiser' => 'Réinitialiser',
    'export_pdf' => 'Export PDF',
    'export_excel' => 'Export Excel',

    // --- Tableau (depenses.html l.73-79) ---------------------------------

    'col_date' => 'Date',
    'col_libelle' => 'Libellé',
    'col_nature' => 'Nature',
    'col_charge' => 'Charge (SYSCOHADA)',
    'col_tresorerie' => 'Trésorerie',
    'col_montant' => 'Montant',
    'col_pieces' => 'Pièces',

    // État vide — les DEUX phrases du maître (depenses.js l.107-111). Elles
    // appellent des gestes opposés : saisir, ou élargir le filtre.
    'vide' => 'Aucune dépense enregistrée. Le bouton « Nouvelle Dépense » ouvre la saisie.',
    'vide_filtre' => 'Aucune dépense ne correspond à ces filtres.',
    'tout_afficher' => 'Tout afficher',

    'recu' => 'reçu',
    'sans_recu' => 'sans reçu',
    'non_comptabilisee' => 'non comptabilisée',

    // --- Rattrapage comptable --------------------------------------------
    //
    // Absent du maître : le prototype garde en mémoire un `ecriture_refus`
    // qu'il AFFICHE sans jamais offrir de le reprendre. Ici, la reprise
    // existe (`DepenseService::comptabiliser()`), et une dépense sans
    // écriture manque au compte de résultat tant que personne ne la reprend.

    'rattrapage_bandeau' => ':nombre dépense(s) ne portent aucune écriture comptable : '
        .'elles manquent au grand livre, à la balance et au compte de résultat tant '
        .'que la pièce n\'a pas été passée.',
    'rattrapage_action' => 'Comptabiliser',
    'rattrapage_centre' => 'Centre de coût de la pièce (obligatoire pour comptabiliser)',
    'rattrapage_centre_choisir' => 'Choisir un centre',
    'rattrapage_fait' => 'Dépense :numero comptabilisée.',

    // --- Modale de saisie (depenses.html l.95-166) -----------------------

    'modale_titre' => 'Nouvelle Dépense',
    'modale_intro' => "Enregistrez une charge d'exploitation de trésorerie directe.",

    'champ_date' => 'Date de la transaction',
    'champ_montant' => 'Montant décaissé (FCFA)',
    'champ_montant_invite' => 'ex. 12 500',
    'champ_libelle' => 'Libellé de la dépense',
    'champ_libelle_invite' => 'ex. Marché du matin — légumes',
    'champ_compte' => 'Catégorie des charges (SYSCOHADA)',
    'champ_tresorerie' => 'Compte de trésorerie',
    'champ_centre' => 'Centre de coût',
    'centre_defaut_du_compte' => 'Défaut du compte',
    'champ_tresorerie_aide' => "D'où l'argent est sorti.",
    'champ_nature' => 'Catégorie de dépenses',
    'champ_recu' => 'Reçu / facture (photo)',
    'champ_recu_aide' => "L'image est réduite avant enregistrement. Le navigateur ne peut en "
        .'conserver qu\'une douzaine : au-delà, tout le registre cesserait d\'être enregistré.',
    'choisir' => '— Choisir —',
    'enregistrer' => 'Enregistrer la dépense',

    'enregistree' => 'Dépense de :montant enregistrée.',

    // --- Lignes d'achat — DÉCISION DU PRODUCT OWNER DU 31/08/2026 ---------
    //
    // ⚠ Ces libellés ne viennent PAS du maître, et c'est assumé : sa modale
    // est mono-ligne (`depenses.html` l.104-150). Le Product Owner a tranché
    // au-dessus d'elle — « une dépense globale peut contenir une ou plusieurs
    // lignes de libellé d'achats ou autre avec son prix ; on peut éditer et
    // supprimer dans la même modale ». L'écart est donc dans l'autre sens : la
    // PWA fait PLUS que la maquette. Voir l'entête de
    // `app/Pwa/Livewire/Depenses/Depenses.php`.
    //
    // Les libellés du maître, eux, restent tous rendus : « Montant décaissé
    // (FCFA) » nomme désormais le total en lecture seule — c'est bien le
    // montant qui sort de la caisse —, et « Catégorie des charges (SYSCOHADA) »
    // titre la colonne des comptes.

    'lignes_titre' => 'Lignes de la dépense',
    'lignes_aide' => 'Une dépense peut porter plusieurs achats. Chaque ligne a son '
        .'libellé, son compte de charge et son prix.',
    'ligne_ajouter' => '+ Ajouter une ligne',
    'ligne_retirer' => 'Retirer cette ligne',
    'col_ligne_libelle' => 'Libellé',
    'col_ligne_montant' => 'Prix',
    'total_aide' => 'Total général des lignes, recalculé à chaque saisie. Il ne se '
        .'saisit pas : le montant écrit en comptabilité est celui que le serveur '
        .'recalcule à l\'enregistrement.',

    'lignes_requises' => 'Une dépense porte au moins une ligne.',
    'ligne_libelle_requis' => 'Ligne :position : le libellé de l\'achat est obligatoire.',
    'ligne_libelle_long' => 'Ligne :position : le libellé dépasse 255 caractères.',
    'ligne_compte_requis' => 'Ligne :position : choisissez la catégorie de charges.',
    'ligne_compte_inconnu' => 'Ligne :position : ce compte n\'existe pas au plan comptable.',
    'ligne_montant_requis' => 'Ligne :position : le prix est obligatoire.',
    'ligne_montant_positif' => 'Ligne :position : un prix à zéro ne s\'enregistre pas. '
        .'Retirez la ligne, ou saisissez son montant.',

    // --- Export ----------------------------------------------------------

    'export_titre' => 'Exporter — Dépenses',
    'export_vide' => 'La liste filtrée est vide : il n\'y a rien à exporter. '
        .'Élargissez la période ou retirez un filtre.',
    'export_fichier' => 'etat_depenses',
    'export_document' => 'État des dépenses courantes',
    'export_col_comptabilisation' => 'Comptabilisation',
    'export_comptabilisee' => 'comptabilisée',
    'export_non_comptabilisee' => 'non comptabilisée',
    'filtre_tout' => 'Registre entier, aucun filtre appliqué',
    'filtre_recherche' => 'recherche « :terme »',
    'filtre_du' => 'à partir du :date',
    'filtre_au' => "jusqu'au :date",
    'filtre_tresorerie' => 'trésorerie « :libelle »',
    'filtre_famille' => 'catégorie « :libelle »',

    // --- Refus déclarés (Article 8) --------------------------------------
];
