<?php

declare(strict_types=1);

/*
 * Libelles des DEUX points de vente et du journal des ventes (PWA).
 *
 * Maitres : prototype_v2/pages/pos.html, prototype_v2/pages/pos-heberges.html
 * et prototype_v2/pages/historique-ventes.html.
 *
 * Les chaines reprises telles quelles du maitre portent le commentaire
 * « maitre » avec sa ligne : elles ne se reformulent pas au fil de l'eau,
 * c'est le texte que le client a valide des yeux. Les chaines PROPRES a la
 * PWA portent la raison de leur existence — presque toutes nomment un refus,
 * et un refus qui ne dit pas pourquoi se lit comme une panne.
 */

return [

    // =====================================================================
    // Communs aux deux points de vente
    // =====================================================================

    'commun' => [
        // maitre — pos.html l.56
        'rechercher' => 'Rechercher un article…',
        // maitre — pos.html l.469
        'catalogue_vide' => 'Aucun article ne correspond à cette recherche.',
        // maitre — pos.html l.494
        'prix_a_definir' => 'Prix à définir',
        // maitre — pos.html l.520
        'sans_prix' => '« :article » n\'a pas de prix à la carte. Renseignez-le avant de le vendre.',
        // maitre — rendreOnglets(), premiere pastille
        'categorie_tout' => 'Tout',

        /*
         * REMISE du panier — ajout hors maitre, directive PO du 02/09/2026 :
         * % ou FCFA sur les DEUX points de vente. Le montant et le net sont
         * derives par `Panier::remiseSur()` (auteur unique), et les refus de
         * bornes vivent dans `lang/fr/ventes.php`.
         */
        'remise' => 'Remise',
        'remise_aucune' => 'Aucune',
        'remise_valeur' => 'Valeur de la remise',
        'remise_appliquee' => 'Sur un total de :brut',
        'remise_sans_panier' => 'Aucun panier ouvert : ouvrez une vente avant d\'appliquer une remise.',

        /*
         * PROPRE a la PWA. Le maitre passe le prix et le libelle au clavier
         * (`data-ajouter` porte le montant dans le DOM) : ici l'ecran ne
         * transmet qu'un MODULE et une REFERENCE, et le serveur relit le
         * catalogue. Une reference inconnue est donc une erreur d'appel, pas
         * une saisie — elle se nomme au lieu de produire une ligne a zero.
         */
        'reference_inconnue' => 'Cet article n\'est plus au catalogue : il ne peut pas être ajouté au panier.',
    ],

    // =====================================================================
    // POS comptant — prototype_v2/pages/pos.html
    // =====================================================================

    'comptant' => [
        'titre_page' => 'Point de vente comptant — TATACORA AFRIQUE',

        // maitre — pos.html l.34-35
        'salle' => 'Salle',
        'salle_aide' => 'Une table par panier. Le comptoir n’en exige aucune.',
        // maitre — pos.html l.40-43
        'initiale_comptoir' => 'C',
        'vendre_au_comptoir' => 'Vendre au comptoir',
        'sans_table' => 'Sans table',
        // maitre — rendreSalle(), etats de table
        'etat_libre' => 'libre',
        'etat_ouverte' => 'ouverte',
        'etat_en_cours' => 'en cours',
        'etat_fermee' => 'fermée',
        'places' => ':nombre pl.',
        'espace_vide' => 'Aucune table dans cet espace.',

        // maitre — pos.html l.60-63
        'filtre_famille_aide' => 'Filtre d\'affichage du catalogue — il ne change ni la caisse, ni le panier',
        'famille_tout' => 'Tout',
        'famille_bar' => 'Bar',
        'famille_restaurant' => 'Restaurant',

        // maitre — pos.html l.488-503
        'point_orange_infobulle' => 'Vendable, mais ne décrémente aucun stock — fiche technique absente',
        'point_orange_legende' => 'Point orange : article vendable qui ne décrémente aucun stock, faute de fiche technique (EF-M4-02).',

        /*
         * AJOUT AU MAÎTRE (04/09/2026) — la marque « composition provisoire ».
         *
         * Elle n'est PAS le point orange, et c'est pour cela qu'elle a sa
         * propre forme : le point orange dit « rien ne sort du stock », celle-ci
         * dit « ce qui en sort est approximatif ». Les 82 fiches semées le
         * 04/09/2026 portent des quantités POSÉES pour débloquer le service,
         * jamais pesées — sans marque, elles seraient indiscernables d'une
         * fiche relevée en cuisine, et l'écart ne se verrait qu'à l'inventaire,
         * imputé à une perte physique qui n'a jamais eu lieu.
         *
         * Une lettre plutôt qu'un second point : deux pastilles de couleurs
         * voisines à la même place ne se distinguent pas au comptoir.
         */
        'composition_provisoire_marque' => 'P',
        'composition_provisoire_infobulle' => 'Fiche technique provisoire : le stock décrémenté par '
            . 'ce plat est approximatif — ses quantités ont été posées, jamais pesées.',
        'composition_provisoire_legende' => 'Marque P : la fiche technique du plat est provisoire, '
            . 'le stock décrémenté est approximatif. Elle se lève depuis Restaurant & Cuisine, '
            . 'onglet « Fiches techniques ».',

        // maitre — pos.html l.75-110
        'panier' => 'Panier',
        'panier_aucun' => 'Aucun panier ouvert',
        'panier_choisir' => 'Choisissez une table ou le comptoir dans la salle.',
        'panier_vide' => 'Panier vide',
        'panier_vide_aide' => 'Touchez un article pour l\'ajouter.',
        /*
         * PROPRE a la PWA — PA-161, 31/08/2026. Le panier est desormais une
         * TABLE : il survit au rechargement de la page, au changement de
         * navigateur et a la releve d'equipe. Ce qu'il ne fait PAS, et que la
         * phrase dit : partir vers un autre poste. `paniers` n'est pas au
         * registre `TABLES_SYNCHRONISABLES` ; ecrire « en attente de
         * synchronisation » annoncerait un depart qui n'aura jamais lieu
         * (PA-59/60/61).
         */
        'panier_sur_ce_poste' => 'Enregistré sur ce poste : le panier reste ouvert après un '
            .'changement d’équipe ou de navigateur. Il ne part vers aucun autre poste.',
        'articles' => ':nombre article(s)',
        'vider' => 'Vider',
        'abandonner' => 'Abandonner',
        'total' => 'Total',
        'mode_reglement' => 'Mode de règlement',
        'encaisser' => 'Encaisser',
        /*
         * PROPRE a la PWA. Le maitre n'attache pas de client a une vente au
         * comptant ; `ventes.client_id` est une vraie cle etrangere, et c'est
         * ce qui permet de porter une consommation sur la note d'un client
         * connu. Facultatif : une biere payee en especes n'a pas de client.
         */
        /*
         * ⚠ REPRIS le 02/09/2026 (directive PO) : le selecteur du referentiel
         * M3 a quitte le comptoir. Le champ est un TEXTE LIBRE facultatif —
         * une MENTION imprimee sur le ticket et la facture
         * (`ventes.client_mention`), jamais une cle etrangere : la vente au
         * comptant est anonyme par nature et ce nom n'alimente aucun registre
         * client. L'ancien commentaire (« vraie cle etrangere ») decrivait le
         * flux retire ; `ventes.client_id` reste au schema pour le POS des
         * clients heberges.
         */
        'client' => 'Client (facultatif)',
        'client_mention_aide' => 'Nom à imprimer sur le ticket — aucun compte client n\'est créé.',
        // `client_aucun` SUPPRIMEE le 02/09/2026 : elle n'etait le tiret que
        // du selecteur retire — plus aucun appelant. Une cle morte finit
        // citee comme si elle vivait.

        // Refus serveur du mode retire du selecteur (PO 02/09/2026).
        'refus_note_chambre_comptoir' => '« Porté sur la note de chambre » n\'existe pas au '
            .'comptoir : aucune chambre n\'y porte de note. Utilisez le point de vente des '
            .'clients hébergés.',

        // maitre — dialogue « Stock insuffisant » (RG-06)
        'rupture_titre' => 'Stock insuffisant',
        'rupture_aide' => 'Vendre quand même créera un stock négatif, tracé comme rupture forcée. '
            .'Le panier reste intact.',
        'rupture_confirmer' => 'Vendre quand même',

        /*
         * ECART DECLARE, DATE — 31/08/2026. Le maitre (pos.html l.504-510)
         * affiche un bandeau rouge listant les articles « au prix provisoire ».
         * Aucune colonne du schema ne porte cette notion : ni `cartes_boisson`
         * ni `plats` n'ont de drapeau de prix provisoire. Le rendre exigerait
         * de le DEVINER sur une donnee monetaire. Cette ligne dit qu'il n'est
         * pas rendu, plutot que de laisser croire que tous les prix sont
         * confirmes.
         */
        'sans_prix_provisoire' => 'Aucun prix n’est signalé comme provisoire : '
            .'le schéma ne porte pas cette information (31/08/2026).',
        // maitre — pos.html l.619
        'encaisser_sans_caisse' => 'Ouvrez la caisse pour encaisser',
        // maitre — pos.html l.596
        'retirer_ligne' => 'Retirer « :article » du panier',

        // maitre — rendreSession(), etat ouvert puis ferme
        'caisse_ouverte' => 'Caisse :point ouverte',
        'caisse_depuis' => 'depuis :heure',
        'caisse_fond' => 'Fond :montant',
        'caisse_ventes' => ':nombre vente(s)',
        'caisse_ca' => 'CA :montant',
        'caisse_encaisse' => 'Encaissé :montant',
        'caisse_en_note' => 'En note :montant',
        'caisse_aucune' => 'Aucune caisse ouverte',
        'caisse_aucune_aide' => 'Aucune vente n\'est possible tant que la caisse n\'est pas ouverte.',
        'ouvrir_caisse' => 'Ouvrir la caisse',
        'cloturer_caisse' => 'Clôturer la caisse',
        'journal_du_jour' => 'Journal du jour',

        // maitre — modaleJournal(), les quatre cartes dans l'ordre
        'journal_ca' => 'Chiffre d\'affaires',
        'journal_encaisse' => 'Encaissé',
        'journal_panier_moyen' => 'Panier moyen',
        'journal_articles' => 'Articles vendus',
        'journal_vide' => 'Aucune vente aujourd’hui.',
        'journal_annuler' => 'annuler',
        'journal_annulee' => 'annulée',

        // maitre — modaleTicket()
        'ticket_titre' => 'Vente encaissée',
        'ticket_imprimer' => 'Imprimer',
        // « Facture » tout court depuis le 02/09/2026 (directive PO,
        // modale « Vente encaissée ») : seuls restent « Ticket 80 mm » et
        // « Facture » — le bouton « Imprimer » du maitre est retire.
        'ticket_facture_a4' => 'Facture',
        // Ajout hors maitre — decision du Product Owner du 01/09/2026, en
        // attendant la validation de l'API MECeF par la Direction des
        // impots : une fenetre d'impression 80 mm dediee, distincte
        // d'« Imprimer » (qui imprime la page courante) et de « Facture A4 ».
        'ticket_thermique' => 'Ticket 80 mm',
        'ticket_porte_en_note' => 'Porté en note de chambre : ce montant n’est PAS dans le tiroir. '
            .'Il devient une créance, réglée au départ du client.',
        'ticket_stock' => ':nombre article(s) n’ont décrémenté aucun stock : :articles. '
            .'Leur fiche technique est absente.',

        // maitre — dialogue « Annuler cette vente »
        'annulation_titre' => 'Annuler cette vente',
        'annulation_message' => 'Les sorties de stock correspondantes seront compensées par un mouvement inverse.',
        'annulation_detail' => 'La vente reste au journal, marquée annulée : rien n’est effacé.',
        'annulation_motif' => 'Motif de l’annulation',
        'annulation_confirmer' => 'Annuler la vente',

        // Formulaire d'ouverture / cloture de caisse.
        'ouverture_titre' => 'Ouvrir la caisse :point',
        'ouverture_fond' => 'Fond de caisse (FCFA)',
        'cloture_titre' => 'Clôturer la caisse :point',
        // maitre — caisse-ui.js l.145 : le libellé exact du champ, sans ajout.
        'cloture_constate' => 'Montant réellement compté',
        'cloture_theorique' => 'Théorique — fond + ventes encaissées',

        // Le RECAP de la modale de clôture — maitre, caisse-ui.js l.140-149.
        'cloture_recap_fond' => 'Fond de caisse',
        'cloture_recap_especes' => 'Espèces encaissées',
        'cloture_recap_theorique' => 'Théorique en caisse',
        'cloture_recap_aide' => 'Seules les espèces sont dans le tiroir. Mobile Money, carte et notes de '
            .'chambre en sont exclus.',

        // Messages d'issue.
        'vente_enregistree' => 'Vente :numero enregistrée.',
        'caisse_ouverte_message' => 'Caisse :point ouverte.',
        // maitre — caisse-ui.js l.158 : « écart de :ecart », jamais un signe brut.
        'caisse_cloturee' => 'Caisse :point clôturée — écart de :ecart.',
        // maitre — caisse-ui.js l.157 : « aucun écart » plutôt qu'un écart de zéro.
        'caisse_cloturee_sans_ecart' => 'Caisse :point clôturée — aucun écart.',
        'vente_annulee' => 'Vente :numero annulée. Les sorties de stock sont compensées.',
        'ligne_retiree' => '« :article » retiré du panier.',
        'panier_abandonne' => 'Panier abandonné.',

        // Refus, chacun avec sa raison.
        'refus_panier_vide' => 'Le panier est vide : il n\'y a rien à encaisser.',
        'refus_sans_caisse' => 'Aucune caisse n\'est ouverte à ce point de vente. '
            .'Ouvrez-la avant d\'encaisser : sans elle, la vente ne serait rattachée à aucun fond.',
        'refus_caisse_deja_ouverte' => 'Une caisse est déjà ouverte à ce point de vente. '
            .'Clôturez-la avant d\'en ouvrir une seconde.',
        'refus_motif_obligatoire' => 'Le motif de l\'annulation est obligatoire : '
            .'une vente annulée reste au journal, et le journal doit dire pourquoi.',
        'refus_encaissement' => 'La vente n\'a pas été enregistrée. Le panier est conservé : rien n\'est perdu.',
    ],

    // =====================================================================
    // POS clients heberges — prototype_v2/pages/pos-heberges.html
    // =====================================================================

    'heberges' => [
        /*
         * ⚠ Le titre porte le nom du maitre A LA LETTRE, cadratin compris :
         * `pos-heberges.html` l.24 ecrit « Point de vente — clients hébergés ».
         * `BaliseTitrePwaTest` derive l'attendu de ce <h1> et refuse toute
         * reformulation — un titre reformule est un ecart de gabarit, au meme
         * titre qu'une classe changee.
         */
        'titre_page' => 'Point de vente — clients hébergés — TATACORA AFRIQUE',

        // maitre — pos-heberges.html l.24-28
        'titre' => 'Point de vente — clients hébergés',
        'sous_titre' => 'Le panier reste ouvert de l’arrivée au départ. Bar, restaurant, '
            .'tourisme et location y entrent ensemble — un seul panier, une seule facture à la clôture.',

        // maitre — pos-heberges.html l.38-39
        'sejours' => 'Séjours en cours',
        'sejours_aide' => 'Un panier par séjour, jamais deux.',
        'sejours_vide' => 'Aucun séjour en cours. Le POS hébergés n’a de sens que pour un client présent.',
        'badge_panier_ouvert' => 'PANIER OUVERT',
        'badge_aucun_panier' => 'AUCUN PANIER',

        // maitre — pos-heberges.html l.49
        'rechercher' => 'Rechercher une consommation ou une prestation…',
        // maitre — pos-heberges.html l.150
        'categorie_prestations' => 'Tourisme & location',
        'categorie_bar' => 'Bar',
        'categorie_restauration' => 'Restauration',
        // maitre — pos-heberges.html l.253
        'tarif_manquant' => 'tarif manquant',

        // maitre — rendreKpis()
        'kpi_paniers' => 'Paniers ouverts',
        'kpi_encours' => 'En-cours séjours',

        // maitre — rendrePanier()
        'panier' => 'Panier',
        'panier_aucun_sejour' => 'Sélectionnez un séjour à gauche pour voir ou ouvrir son panier.',
        'panier_vide' => 'Panier ouvert, aucune consommation. Choisissez un article dans le catalogue.',
        'total_sejour' => 'Total du séjour',
        'cloturer' => 'Clôturer et facturer',
        'depart_prevu' => 'Départ prévu le :date',

        // maitre — dialogue « Clôturer avant le départ ? » (pos-heberges.html l.430-437)
        'cloture_titre' => 'Clôturer avant le départ ?',
        'cloture_message' => 'Aucune consommation ne pourra plus être enregistrée pour ce séjour.',
        'cloture_detail' => 'Le panier est clôturé, une vente en note de chambre est enregistrée au journal, '
            .'et la facture du séjour est émise : nuitées d’abord, consommations ensuite, un seul document.',

        /*
         * RECAPITULATIF DE CLOTURE — directive PO du 02/09/2026. La modale
         * montre les deux blocs (hebergement, consommations) et un TOGGLE
         * « Payer separement » sur l'hebergement : decoche, la facture emise
         * ne porte QUE les consommations, et le rappel dit ce qui restera du
         * sur la fiche du client. ⚠ RG-04 (« un seul document ») est AMENDEE
         * par cette directive : voir `PosHeberges::cloturerEtFacturer()`.
         */
        'cloture_bloc_hebergement' => 'Hébergement',
        'cloture_bloc_consommations' => 'Consommations',
        'cloture_nuitees' => ':nuitees nuitée(s) × :tarif',
        'cloture_payer_separement' => 'Payer séparément (l\'hébergement sera facturé plus tard)',
        'cloture_rappel_hebergement' => 'L\'hébergement n\'est pas réglé : :nuitees nuitée(s) × :tarif '
            .'resteront dues sur la fiche du client.',
        'cloture_total_facture' => 'Total facturé',
        'cloture_facture' => 'Facture',
        'facture_emise_consommations' => 'Consommations facturées pour :client. L\'hébergement reste dû '
            .'sur la fiche du client.',

        /*
         * PROPRE a la PWA — PA-161, 31/08/2026.
         *
         * ⚠ Cette cle REMPLACE `panier_volatil`, dont le motif a cesse d'etre
         * vrai le jour ou la table `paniers` a ete livree. Elle disait :
         * « Panier ouvert sur ce poste et dans ce navigateur seulement :
         * aucune table ne le porte encore. Un changement d'équipe ou une
         * session expirée le perd. » Un avertissement perime est pire qu'aucun
         * — il fait cloturer par prudence un panier qui n'avait rien a
         * craindre, et il apprend a ignorer le bandeau (PA-144).
         *
         * Ce qui reste vrai est dit, et rien de plus : le panier ne part vers
         * aucun autre poste, `paniers` n'etant pas au registre
         * `TABLES_SYNCHRONISABLES`. Annoncer une synchronisation qui n'aura
         * pas lieu serait PA-59/60/61.
         */
        'panier_sur_ce_poste' => 'Panier ouvert de l’arrivée au départ : il survit au changement '
            .'d’équipe et de navigateur. Enregistré sur ce poste — il ne part vers aucun autre.',

        /*
         * PROPRE a la PWA — PA-24. `MODULES_ENCAISSABLES` vaut ['M4','M5'] :
         * ni le tourisme ni la location n'ont de catalogue d'ou FIGER un prix
         * cote serveur. Les accepter obligerait l'ecran a transmettre un
         * montant au clavier. Les articles restent AFFICHES avec leur raison
         * plutot qu'omis : un rayon absent ne se distingue pas d'un rayon vide.
         */
        'prestation_refusee' => 'Tourisme et location ne sont pas encaissables au comptoir '
            .'(31/08/2026) : leur prix devrait être saisi au clavier, ce que le registre des '
            .'ventes refuse. Ces prestations passent par leur propre module.',

        // Messages d'issue.
        'facture_emise' => 'Séjour facturé. Panier clôturé et facture émise pour :client.',
        'ligne_retiree' => '« :article » retiré du panier du séjour.',

        // Refus, chacun avec sa raison.
        'refus_aucun_sejour' => 'Choisissez d\'abord un séjour : un panier appartient à un séjour, jamais au poste.',
        'refus_panier_vide' => 'Le panier du séjour est vide : il n\'y a rien à facturer.',
        'refus_tarif_absent' => 'La catégorie de l\'unité de ce séjour ne porte aucun tarif : '
            .'la facture ne peut pas être émise. Renseignez le tarif de la catégorie avant de clôturer.',
        'refus_deja_facture' => 'Ce séjour porte déjà une facture. Une seconde émission refacturerait les nuitées.',
        /*
         * Le message ne reprend JAMAIS `$e->getMessage()` : il porterait du SQL
         * ou le detail d'un service au comptoir. La cause part au journal
         * technique par `report()`, ou elle est lisible par qui doit la lire.
         */
        'refus_facturation' => 'La facturation a échoué : rien n\'a été enregistré et LE PANIER EST INTACT. '
            .'Prévenez la gérance — la cause est au journal technique.',
    ],

    // =====================================================================
    // Journal des ventes — prototype_v2/pages/historique-ventes.html
    // =====================================================================

    'journal' => [
        'titre_page' => 'Historique des ventes — TATACORA AFRIQUE',

        /*
         * L'ACCORDÉON de la bande d'indicateurs (03/09/2026, demande du
         * Product Owner). Le journal des ventes est un écran de RECHERCHE :
         * cinq cartes en tête repoussaient le tableau sous la ligne de
         * flottaison. Déplié par défaut — un écran qui s'ouvre vide se lit
         * comme un écran cassé — et l'état est retenu par le navigateur.
         */
        'kpis_accordeon' => 'Indicateurs du journal',
        'kpis_aide' => 'Repliez la bande pour gagner de la hauteur de tableau.',

        // maitre — historique-ventes.html l.24
        'titre' => 'Historique des ventes',
        'sous_titre_avant' => 'Le journal des',
        'sous_titre_gras' => 'ventes',
        'sous_titre_apres' => ', pas des factures. Une vente peut exister sans facture si l’émission a '
            .'échoué ; une vente annulée reste une vente, là où une facture annulée produit un avoir. '
            .'Ici on retrouve un',
        'sous_titre_exemple_vente' => 'V-2026-00016',
        'sous_titre_liaison' => ', pas un',
        'sous_titre_exemple_facture' => 'F-2026-00042',

        // maitre — rendreKpis(), les cinq cartes dans l'ordre
        'kpi_ventes' => 'Ventes',
        'kpi_ventes_detail' => ':nombre annulée(s)',
        'kpi_ca' => 'Chiffre d’affaires',
        'kpi_ca_detail' => 'Ventes validées',
        'kpi_encaisse' => 'Encaissé',
        'kpi_encaisse_detail' => 'Réellement dans le tiroir',
        'kpi_note' => 'Porté en note',
        'kpi_note_detail' => 'Créance client, réglée au départ',
        'kpi_stock' => 'Sans impact stock',
        'kpi_stock_detail' => 'Articles sans lien au stock',
        'kpi_stock_detail_ok' => 'Toutes les ventes ont décrémenté',

        // maitre — filtres l.36-51
        'rechercher' => 'N° de vente, table, chambre…',
        'tous_postes' => 'Tous les postes',
        'toutes_activites' => 'Toutes les activités',
        'tous_reglements' => 'Tous les règlements',
        'tous_statuts' => 'Tous les statuts',
        'statut_validees' => 'Validées',
        'statut_annulees' => 'Annulées',
        'export_excel' => 'Export Excel',
        'export_pdf' => 'Export PDF',

        // maitre — colonnes l.247-256
        'colonne_numero' => 'N°',
        'colonne_date' => 'Date',
        'colonne_poste' => 'Poste',
        'colonne_activites' => 'Activités',
        'colonne_reglement' => 'Règlement',
        'colonne_montant' => 'Montant',
        'colonne_statut' => 'Statut',
        'colonne_actions' => 'Actions',

        // maitre — lignes l.222-245
        'badge_annulee' => 'annulée',
        'badge_encaissee' => 'encaissée',
        'badge_note' => 'en note',
        'badge_stock' => 'stock ✕',
        'badge_stock_infobulle' => 'Articles sans lien au stock : la vente n’a rien décrémenté',
        'detail' => 'Détail',
        'liste_vide' => 'Aucune vente ne correspond à ces critères.',

        // Pagination du tableau d'écran (décision du PO du 13/10/2026) — les
        // mots du pied « Réservations en cours » de l'hébergement.
        'decompte_avant' => 'Affichage de',
        'decompte_liaison' => 'sur',
        'page_precedent' => '← Précédent',
        'page_suivant' => 'Suivant →',
        'page_sur' => 'Page :page / :total',

        // maitre — modale de detail `ov-vente`
        'detail_total' => 'Total',
        'detail_fermer' => 'Fermer',
        // 'detail_imprimer' est purgee (PO 02/09/2026) : le bouton de la modale de detail est retire, aucun appelant.
        'detail_telecharger' => 'Télécharger',
        // Meme ajout que `comptant.ticket_thermique` — 01/09/2026.
        'detail_ticket_thermique' => 'Ticket 80 mm',
        'detail_porte_en_note' => 'Porté en note de chambre : ce montant n’est PAS dans le tiroir. '
            .'Il devient une créance, réglée au départ du client.',
        'detail_stock' => ':nombre article(s) n’ont décrémenté aucun stock : :articles. '
            .'Leur lien au stock est absent.',
        'detail_annulee' => 'Vente annulée:motif. Elle reste au journal : rien n’est effacé.',
        'detail_annuler_titre' => 'Annuler cette vente',
        'detail_motif' => 'Motif de l’annulation',
        'detail_annuler' => 'Annuler la vente',

        // Export — PA-119 : un export porte sur ce qui est AFFICHE, et il DIT son filtre.
        'export_titre' => 'Exporter le journal des ventes',
        'export_vide' => 'Rien à exporter : la liste filtrée est vide.',
        'export_fichier' => 'journal_des_ventes',
        'filtre_aucun' => 'Aucun filtre — tout le registre',
        'filtre_recherche' => 'recherche « :terme »',
        'filtre_point' => 'poste :valeur',
        'filtre_activite' => 'activité :valeur',
        'filtre_mode' => 'règlement :valeur',
        'filtre_statut' => 'statut :valeur',
        'filtre_debut' => 'à partir du :date',
        'filtre_fin' => 'jusqu\'au :date',

        // Messages d'issue.
        'vente_annulee' => 'Vente :numero annulée. Elle reste au journal.',
        'refus_motif_obligatoire' => 'Le motif de l\'annulation est obligatoire : '
            .'une vente annulée reste au journal, et le journal doit dire pourquoi.',
        'refus_vente_absente' => 'Cette vente n\'existe plus au registre.',
    ],

    // =====================================================================
    // Documents imprimes — PA-101 : le ticket et la facture sont DEUX pieces.
    // =====================================================================

    'document' => [
        'ticket_titre' => 'TICKET DE VENTE',
        'ticket_mention' => 'Document transactionnel unitaire. Ne vaut pas facture normalisée.',
        'journal_titre' => 'JOURNAL DES VENTES',

        /*
         * ⚠ Les entetes ci-dessous sont ceux du MAITRE, a la lettre — y compris
         * « Quantite », « Activite » et « Reglement » sans accent, tels que
         * `pos.html` l.835/856/908 et `historique-ventes.html` l.333/348 les
         * ecrivent. Les accentuer serait plus joli et rendrait la garde de
         * conformite incapable de les retrouver : le maitre fait foi sur ce qui
         * se voit, pas notre gout.
         */
        'entete_article' => 'Article',
        'entete_activite' => 'Activite',
        'entete_quantite' => 'Quantite',
        'entete_prix_unitaire' => 'Prix unitaire',
        'entete_montant' => 'Montant',
        'entete_numero' => 'N°',
        'entete_heure' => 'Heure',
        'entete_table_chambre' => 'Table / chambre',
        'entete_reglement' => 'Règlement',
        'entete_statut' => 'Statut',

        /*
         * Le jeu d'entetes de l'EXPORT du journal — `historique-ventes.html`
         * l.348. Il differe de celui du tableau a l'ecran (l.248-255) : il
         * porte « Table » et « Encaisse » en plus, et il ecrit « Reglement »
         * sans accent la ou l'ecran ecrit « Règlement ». Ce sont deux jeux
         * distincts du maitre, pas une incoherence a lisser.
         */
        'entete_date' => 'Date',
        'entete_poste' => 'Poste',
        'entete_table' => 'Table',
        'entete_reglement_export' => 'Reglement',
        'entete_encaisse' => 'Encaisse',

        // Titre de l'annexe du journal imprimé : le détail des lignes de
        // chaque vente affichée (les cinq entetes du ticket, l.333).
        'detail_lignes_titre' => 'Détail des lignes',

        'colonne_designation' => 'Désignation',
        'colonne_activite' => 'Activité',
        'colonne_quantite' => 'Quantité',
        'colonne_prix' => 'Prix unitaire',
        'colonne_montant' => 'Montant',

        'total_encaisse' => 'Total encaissé',
        'total_porte_en_note' => 'Total porté en note de chambre',
        // Remise (PO 02/09/2026) — DERIVEE sur le document : lignes brutes −
        // net encaisse (`Vente::remiseDeduite()`), jamais une copie stockee.
        'remise' => 'Remise',
        // La mention client du comptoir (PO 02/09/2026) — un nom imprime,
        // jamais une fiche client.
        'client' => 'Client',
        'reglement' => 'Règlement',
        'edite_le' => 'Édité le',
        'auteur' => 'Auteur',
        'filtre' => 'Filtre appliqué',
        'periode' => 'Période',
        'visa_caisse' => 'Visa Caissier / Barman',
        'visa_direction' => 'Visa Direction / Contrôle',

        /*
         * PA-101 — aucun cachet fiscal n'est INVENTE. Le format du QR MECeF
         * n'est pas public (MECEF_INTEGRATION_SPEC.md §5) : l'emplacement est
         * reserve et NOMME, sans rien de scannable. IFU et RCCM sont vides
         * ici, donc absents : imprimer un exemple de format sur un document
         * remis serait un faux identifiant fiscal.
         */
        'mecef_reserve' => 'Emplacement réservé au cachet fiscal MECeF',
        // Passage au réel (01/09/2026, décision PO) : plus de mention
        // « démonstration » sur un document remis — l'attente reste dite,
        // dérivée de l'état réel (PA-61).
        'mecef_absent' => 'Certification MECeF : en attente d\'inscription (DGI)',
        'mecef_certifiee' => 'Certifiée MECeF n° :numero',

        // Pied du ticket 80 mm — 01/09/2026. Une `Vente` ne porte AUCUN champ
        // MECeF (`ventes` n'a ni `numero_mecef` ni `statut` de certification :
        // seule `Facture` en porte) : la mention est donc TOUJOURS vraie tant
        // que le schéma reste ainsi — un fait structurel, pas une constante
        // choisie au hasard. Si `Vente` gagnait un jour un lien vers
        // `Facture`, cette clé redeviendrait à dériver comme
        // `facturation_pwa.document_mention_demo` l'est déjà.
        'ticket_thermique_pied' => 'Certification MECeF : en attente d\'inscription auprès de la DGI.',
    ],

];
