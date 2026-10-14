<?php

declare(strict_types=1);

/*
 * Écran M11 « Tableau de bord » de la PWA.
 *
 * Maître : `prototype_v2/pages/tableau-de-bord.html`.
 *
 * ## Pourquoi un fichier séparé de `lang/fr/pwa.php`
 *
 * `06_DEVELOPMENT_STANDARDS.md` §4.4 : un fichier de langue par domaine.
 * `pwa.php` porte la COQUILLE (menu, barre supérieure, châssis) et les sept
 * pages transverses ; cet écran-ci est le seul écran de module qui vive à la
 * racine de `app/Pwa/Livewire`, et ses libellés n'ont aucun autre lecteur.
 *
 * ## LES INTITULÉS DISENT CE QUI EST RÉELLEMENT CALCULÉ — PA-49
 *
 * Le maître écrit « Chiffre d'affaires (payé) », « Factures en attente » et
 * dérive le taux d'occupation de `unites.statut`. Aucun des trois n'est
 * calculable ainsi sur ce schéma, et les deux premiers seraient FAUX :
 * `factures.statut` porte le cycle de certification MECeF, pas un état de
 * paiement. Les libellés ci-dessous disent donc « encaissé » et « non
 * soldées ». Ne pas les « corriger » vers les mots du maître : c'est l'écart
 * qui est juste, et il est tracé en PA-49.
 */

return [

    'titre' => 'Tableau de bord',
    'titre_page' => 'Tableau de bord — TATACORA AFRIQUE',
    'tiret' => '—',
    /*
     * Les colonnes du RAPPORT de synthèse — celles du maître, au mot près
     * (`prototype_v2/assets/js/rapports-engine.js` l.64 :
     * `entetes: ['Indicateur', 'Valeur', 'Détail']`).
     *
     * Elles étaient inventées jusqu'au 31/08/2026 (« Indicateur / Montant /
     * Variation vs période précédente »). Un document remis au comptable ne
     * porte pas les intitulés que le développeur a trouvés clairs : il porte
     * ceux que le client a validés.
     */
    'col_indicateur' => 'Indicateur',
    'col_valeur' => 'Valeur',
    'col_detail' => 'Détail',

    /*
     * L'ÉTAT CONSOLIDÉ du panneau Pilotage — le document PDF du maître
     * (`m11-pilotage.js`, `etatCourant()` : `entetes: ['Rubrique',
     * 'Indicateur', 'Valeur']`, titre « Pilotage consolidé — tous modules »).
     * « Indicateurs consolidés » est la rubrique des six cartes de la bande
     * KPI, que le maître groupe par module comptable ; la PWA groupe par les
     * sections que son panneau affiche réellement (même arbitrage que PA-49).
     */
    'etat_consolide' => [
        'titre' => 'Pilotage consolidé — tous modules',
        'col_rubrique' => 'Rubrique',
        'rubrique_indicateurs' => 'Indicateurs consolidés',
    ],
    'sous_titre' => 'Vision consolidée et en temps réel de la performance de chaque activité',

    'onglets' => [
        'exploitation' => 'Vue d\'exploitation',
        'pilotage' => 'Pilotage consolidé',
        'croise' => 'Tableau croisé dynamique',
    ],

    'periodes' => [
        'aujourdhui' => 'Aujourd\'hui',
        'semaine' => 'Cette semaine',
        'mois' => 'Ce mois',
        'trimestre' => 'Ce trimestre',
        'semestre' => 'Ce semestre',
        'annee' => 'Cette année',
        'personnalisee' => 'Période personnalisée',
    ],
    'periode_du' => 'Du',
    'periode_au' => 'Au',

    /*
     * PA-59/60/61 — le repli se DIT, il ne se tait pas.
     *
     * Un code de période inconnu (`?periode=ce_siecle`) est refusé par
     * `Periode::resoudre()`. L'écran ne le laisse pas lever — un 500 sur une
     * URL que n'importe qui peut composer — et ne se replie pas non plus en
     * silence : il retombe sur le défaut ET le nomme. Sans cette phrase,
     * quelqu'un qui a demandé « ce siècle » lirait les chiffres du mois sous
     * un libellé qu'il n'a pas demandé, sans jamais savoir que sa demande
     * n'avait pas été comprise.
     */
    'periode_inconnue' => 'La période demandée (« :code ») n\'existe pas. Les chiffres '
        . 'ci-dessous sont ceux de la période par défaut, « :defaut » — ils ne '
        . 'répondent pas à la demande qui a été faite.',

    'actualiser' => 'Actualiser',
    // « PDF » / « Excel » — les mots du maître (`m11-pilotage.html`), gardés
    // ici pour la garde des trois sources. Plus AUCUN bouton ne les rend :
    // export unifié sous « Exporter » (`pwa.export.bouton`), dérogation PO du
    // 01/09/2026 rappelée le 02/09/2026 — voir `DerogationsMaquette`
    // (export_bouton_unique).
    'export_pdf' => 'PDF',
    'export_excel' => 'Excel',
    'export_titre' => 'Exporter le tableau de bord',

    /*
     * L'accordéon d'indicateurs — libellé du maître au mot près
     * (`tableau-de-bord.html` l.74). La dérogation accordée le 31/08/2026
     * (`App\Pwa\Support\DerogationsMaquette`) porte sur le fait que
     * l'accordéon existe à tous les formats et retient son état, jamais sur
     * son intitulé.
     */
    'kpis_accordeon' => 'Indicateurs clés (8)',
    'kpis_aide' => '— Cliquer pour masquer/afficher',

    /*
     * Les huit indicateurs de `TableauDeBordService::indicateurs()`, dans son
     * ordre. La clé est celle du service : renommer l'une sans l'autre
     * afficherait la clé brute, et c'est visible immédiatement.
     */
    'kpi' => [
        'chiffre_affaires_encaisse' => [
            'libelle' => 'Chiffre d\'affaires encaissé',
            'note' => 'Somme des paiements reçus sur la période',
        ],
        'taux_occupation' => [
            'libelle' => 'Taux d\'occupation hôtel',
            'note' => 'Nuitées vendues rapportées à la capacité de la période',
        ],
        'tresorerie_caisse' => [
            'libelle' => 'Trésorerie (caisse)',
            'note' => 'Sessions de caisse ouvertes et leurs encaissements',
        ],
        'depenses_cumulees' => [
            'libelle' => 'Dépenses cumulées',
            'note' => 'Écritures validées de classe 6 sur la période',
        ],
        'reservations_en_attente' => [
            'libelle' => 'Réservations en attente',
            'note' => 'À confirmer',
        ],
        'factures_impayees' => [
            'libelle' => 'Factures non soldées',
            'note' => 'Certifiées dont le règlement reste incomplet',
        ],
        'valeur_stock' => [
            'libelle' => 'Valeur du stock',
            'note' => 'Au coût moyen pondéré, à l\'instant — jamais au prix de vente',
        ],
        'employes_actifs' => [
            'libelle' => 'Employés actifs',
            'note' => 'Sur :total au total',
        ],
    ],

    /*
     * ⚠ ARTICLE 7 ET PA-59/60/61 — « ZÉRO » N'EST PAS « PAS DE RÉPONSE ».
     *
     * Une lecture qui échoue rend `null`, jamais `0` ni une collection vide :
     * « 0 chambre disponible » se lit comme un hôtel complet, « 0 article
     * critique » comme un stock sain. Le précédent est l'écran Carte du bar du
     * client Flutter, qui distingue trois états — un chiffre, « sans lien de
     * stock », « non consulté ».
     */
    'non_consulte' => 'Non consulté',
    'lecture_impossible' => 'Cette donnée n\'a pas pu être lue. Ce n\'est pas un zéro : '
        . 'rien n\'a été mesuré.',

    'acces_rapide' => [
        'reservation' => 'Nouvelle réservation',
        'client' => 'Ajouter un client',
        'stocks' => 'Stocks critiques',
        'rapport' => 'Générer un rapport',
        'depense' => 'Nouvelle dépense',
        'sans_droit' => 'Votre rôle ne permet pas ce geste depuis cet écran.',
    ],

    /*
     * Les écrans de consultation de `Accueil::ECRANS_AUTORISES`.
     *
     * Les libellés eux-mêmes vivent sous `pwa.ecrans.<module>` : les dupliquer
     * ici ferait diverger le texte affiché de sa traduction, et c'est ce que
     * `MessagesUtilisateurTest` vérifie sur la constante.
     */
    'ecrans_titre' => 'Consultation de secours',
    'ecrans_sous_titre' => 'Les écrans auxquels votre rôle donne accès.',

    /*
     * Le récapitulatif de la journée — bandeau sombre du maître
     * (`tableau-de-bord.js` l.400-409).
     *
     * ⚠ « Encaissé aujourd'hui » compte les VENTES ENCAISSÉES du jour, pas les
     * acomptes de réservation comme le fait le maître. `reservations.acompte`
     * est un montant porté sur la fiche SANS date de règlement : le sommer par
     * date d'arrivée compterait comme encaissé aujourd'hui un acompte versé il
     * y a trois semaines. La note le dit sous le chiffre.
     */
    'recap' => [
        'titre' => '📋 Récapitulatif de la journée — :jour',
        'arrivees' => 'Arrivées prévues',
        'departs' => 'Départs prévus',
        'nouvelles' => 'Nouvelles réservations',
        'encaisse' => 'Encaissé aujourd\'hui',
        'encaisse_note' => 'Ventes encaissées du jour — les acomptes de réservation ne portent '
            . 'aucune date de règlement au schéma.',
    ],

    /*
     * Le bandeau rouge d'alertes de stock (`tableau-de-bord.js` l.226-234).
     * Il ne s'affiche QUE s'il y a des articles sous seuil : le maître vide sa
     * zone quand il n'y en a aucun, et une bande verte « stock sain » serait
     * une affirmation que personne n'a demandée.
     */
    'alerte_stock' => [
        'titre' => '⚠ Alertes critiques de stock (:nombre)',
        'voir' => 'Voir',
    ],

    'reservations_jour' => [
        'titre' => 'Réservations du jour',
        'voir_tout' => 'Voir tout →',
        'col_client' => 'Client',
        'col_services' => 'Services',
        'col_arrivee' => 'Arrivée',
        'col_depart' => 'Départ',
        'col_canal' => 'Canal',
        'col_acompte' => 'Acompte',
        'col_actions' => 'Actions',
        'vide' => 'Aucune réservation enregistrée pour le moment.',
        'checkin' => 'Check-in',
        'checkout' => 'Check-out',
        'deja_arrive' => 'Arrivé',
        // maître — `tableau-de-bord.js` l.342. REFUS LEVÉ le 02/09/2026
        // (PA-165) : voir le docblock d'`Accueil::factureAPayer()`.
        'payer' => 'Payer',
    ],

    'modale_payer' => [
        'titre' => 'Encaisser un règlement',
        'aucune_facture' => 'Aucune facture figée et non soldée ne couvre cette réservation.',
        'succes' => 'Règlement enregistré pour :client.',
    ],

    'chambres' => [
        'titre' => 'Chambres disponibles',
        'voir_tout' => 'Voir tout →',
        'col_code' => 'Code',
        'col_unite' => 'Unité',
        'col_categorie' => 'Catégorie',
        'col_tarif' => 'Tarif / nuit',
        'col_actions' => 'Actions',
        'vide' => 'Aucune chambre disponible actuellement.',
        // Bouton VERT du maître (`tableau-de-bord.js` l.385) — REFUS LEVÉ le
        // 02/09/2026, remplace l'ancien libellé « Réserver ».
        'checkin' => 'Effectuer Check-in',
    ],

    /*
     * « À traiter » — le panneau d'alertes du pilotage consolidé.
     *
     * ⚠ CHAQUE ENTRÉE NAÎT D'UNE MESURE, JAMAIS D'UNE SUPPOSITION. Le maître
     * (`m11-pilotage.js` l.150-200) agrège dix alertes de sept moteurs ; cinq
     * familles sont servies ici, chacune par un Service existant, et le compte
     * des sources RÉELLEMENT consultées est affiché à côté. « Aucune alerte »
     * et « rien n'a été lu » ne se disent pas de la même façon (Article 7).
     */
    'alertes' => [
        'titre' => 'À traiter',
        'sous_titre' => 'Alertes opérationnelles, tous modules confondus.',

        'compta_desequilibree' => 'Comptabilité déséquilibrée',
        'compta_desequilibree_detail' => 'Aucun état financier n\'est exploitable tant que '
            . 'l\'écart subsiste. Vérifiez la balance générale.',
        'brouillons' => ':nombre écriture(s) en brouillon',
        'brouillons_detail' => 'Elles n\'entrent dans aucun état et bloqueront la clôture.',
        'creances' => ':montant de créances clients',
        'factures_non_soldees' => ':nombre facture(s) non soldée(s)',
        'reservations_en_attente' => ':nombre réservation(s) en attente',
        'stock_critique' => ':nombre article(s) sous le seuil de réapprovisionnement',
        'stock_critique_detail' => 'Réapprovisionnement à déclencher.',

        'voir' => 'Voir les articles',
        'ouvrir' => 'Ouvrir',
        'aucune' => 'Aucune alerte opérationnelle sur les sources consultées.',
        'sources' => ':lues source(s) consultée(s) sur :total — celles que votre rôle '
            . 'vous donne le droit de lire.',
        'non_mesuree' => 'Les alertes de stock n\'ont pas pu être lues : aucune alerte '
            . 'n\'est affirmée ici, ni dans un sens ni dans l\'autre.',
    ],

    'reserves' => [
        'titre' => 'Ce que ces chiffres ne disent pas',
        'sous_titre' => 'Incertitudes déclarées par les moteurs eux-mêmes. Un tableau de bord '
            . 'qui les masquerait serait plus dangereux qu\'utile.',
        // PA-19 (taux d'IS non tranché) — la référence vit ici, jamais à
        // l'écran : un code de suivi interne n'aide pas l'exploitant, et le
        // Product Owner a demandé le retrait de toute justification
        // d'ingénierie des écrans (01/09/2026).
        'is' => 'Impôt sur les bénéfices : le taux d\'IS n\'est pas encore arrêté. '
            . 'Aucun résultat net n\'est affiché ici — seule la marge brute de la période.',
        'structure' => 'Charges de structure non réparties : « Dépenses cumulées » est le '
            . 'total des charges validées, il n\'est ventilé par activité nulle part.',
        // PA-21 : les recouvrements n'existent pas au schéma.
        'recouvrements' => 'Les encaissements partiels ne sont pas enregistrés : le montant '
            . 'dû affiché est un maximum.',
        'stock' => 'La valeur du stock est une photographie à l\'instant : elle ne se compare '
            . 'pas à la période précédente, et aucune variation n\'est affichée pour elle.',

        // Titres + pastilles module (02/09/2026) — markup du maître
        // (`m11-pilotage.js` l.219-278), quatre des huit réserves qu'il
        // déclare : les autres (coût employeur, POS/Stocks, prix
        // provisoires, tourisme, RBAC amendé) dépendent de moteurs que cet
        // écran ne lit pas encore pour d'autres blocs.
        'is_titre' => 'Résultat affiché avant impôt',
        'structure_titre' => 'Charges de structure non réparties',
        'recouvrements_titre' => 'Recouvrements partiels non enregistrés',
        'stock_titre' => 'Valeur du stock non comparable',
        'module_comptabilite' => 'Comptabilité',
        'module_analytique' => 'Analytique',
        'module_creances' => 'Créances',
        'module_stocks' => 'Stocks',
    ],

    'serie' => [
        'titre' => 'Chiffre d\'affaires vs Dépenses',
        // Le maître écrit « Basé sur les réservations et dépenses
        // enregistrées » (tableau-de-bord.html l.119). La courbe ne trace pas
        // des réservations : elle trace l'ENCAISSÉ et les dépenses validées
        // (PA-121, même code que la bande d'indicateurs). Un intitulé dit ce
        // qui est réellement calculé (PA-49) — le mot est corrigé, le ton et
        // la longueur restent ceux du maître.
        'sous_titre' => 'Basé sur les encaissements et dépenses enregistrés',
        'mois_3' => '3 mois',
        'mois_6' => '6 mois',
        'mois_12' => '1 an',
        'col_mois' => 'Mois',
        'col_ca' => 'Chiffre d\'affaires encaissé',
        'col_depenses' => 'Dépenses',
        'col_solde' => 'Solde',
        'vide' => 'Aucun mouvement sur les mois demandés.',
    ],

    'activite' => [
        // Le `<h2>` du maître (`tableau-de-bord.html` l.225) — depuis le
        // 02/09/2026 la section porte les NEUF cartes de `rendreModules()`
        // (voir `pilotage.modules`) et NON PLUS la ventilation par facture :
        // les clés de colonnes et le sous-titre qui la décrivaient sont
        // retirés avec elle. `col_montant` reste : c'est le libellé de série
        // du graphique « Statistiques de ventes par activité ».
        'titre' => 'Par module',
        'col_montant' => 'Montant facturé',
    ],

    /*
     * Les deux graphiques de la ligne du maître (`tableau-de-bord.html`
     * l.122-133) — TITRES DU MAÎTRE, SOUS-TITRES CORRIGÉS.
     *
     * ⚠ PA-49 EN TOUTES LETTRES : l'intitulé secondaire dit ce qui est
     * RÉELLEMENT calculé. Le maître compte « le nombre de réservations
     * incluant chaque service » ; cette mesure n'existe pas côté serveur — les
     * cinq services d'une fiche sont une table du client hors ligne (PA-110),
     * et `reservations` n'en porte aucun. Ce que le serveur sait ventiler, ce
     * sont les MONTANTS FACTURÉS par module d'origine
     * (`lignes_facture.source_module`, RG-04). Le titre reste celui du maître,
     * validé par le client ; le sous-titre nomme la mesure, pour que personne
     * ne lise un compte de réservations dans une somme d'argent.
     */
    'repartition' => [
        'titre' => 'Réservations par activité',
        'sous_titre' => 'Sur la période sélectionnée',
        // Le maître compte des réservations par service ; cette mesure
        // n'existe pas au schéma serveur (PA-110) — on ventile des montants
        // facturés. L'écran dit la mesure réelle, sans le numéro de suivi.
        'mesure_reelle' => 'Ventilation des montants facturés par activité.',
        'vide' => 'Aucune ligne facturée sur la période.',
    ],

    'ventes_activite' => [
        'titre' => '📊 Statistiques de ventes par activité',
        'sous_titre' => 'Nombre de réservations incluant chaque service, période sélectionnée',
        // Même source que l'anneau : `lignes_facture.source_module` (RG-04),
        // une seule mesure pour deux tracés (PA-121).
        'mesure_reelle' => 'Montants facturés par activité, même mesure que l\'anneau '
            . 'ci-dessus.',
        'vide' => 'Aucune ligne facturée sur la période.',
    ],

    /*
     * « Marge sur coûts directs par activité » — le calcul vient
     * d'`AnalytiqueService`, jamais réécrit ici. Le sous-titre est celui du
     * maître AU MOT PRÈS : ce sont des marges, pas des résultats nets, et le
     * `ReadModel` du domaine porte le même motif.
     */
    'marge' => [
        'titre' => 'Marge sur coûts directs par activité',
        'sous_titre' => 'Charges de structure non réparties : ce sont des marges, pas des '
            . 'résultats nets.',
        'vide' => 'Aucune écriture analytique sur l\'exercice ouvert.',
    ],

    'occupation' => [
        'titre' => 'Occupation & meilleures ventes',
        // RG-02 : le taux se calcule, il n'est jamais lu d'une colonne.
        'sous_titre' => 'Taux calculé en nuitées vendues, rapportées à la capacité de la période.',
        'nuitees' => 'Taux d\'occupation sur la période',
        'taux' => 'Taux d\'occupation',
    ],

    /*
     * Les quatre classements de « meilleures ventes ».
     *
     * ⚠ DEUX SONT STRUCTURELLEMENT VIDES AUJOURD'HUI, et l'écran ne le cache
     * pas : `VenteService::MODULES_ENCAISSABLES` ne contient que M4 et M5 — un
     * encaissement de tourisme ou de location est REFUSÉ par le domaine faute
     * de catalogue serveur d'où figer un prix. La carte est rendue avec son
     * état vide plutôt qu'omise : la retirer ferait croire que le classement
     * n'existe pas, quand il existe et n'a rien à classer.
     */
    'top_ventes' => [
        'food' => 'Restaurant — plats',
        'drinks' => 'Bar — boissons',
        'circuit' => 'Tourisme — circuits',
        'location' => 'Location — véhicules',
        'par_quantite' => 'classé par quantité vendue',
        'par_montant' => 'classé par montant',
        'unite_quantite' => 'vendu(s)',
        'unite_montant' => 'FCFA', // PA-186 — non rendue : la colonne passe par MontantFcfa.
        'vide' => 'Aucune vente sur cette période.',
    ],

    /*
     * Les cartes de l'onglet « Pilotage consolidé » qui n'existent nulle part
     * ailleurs. Les cinq autres reprennent les clés de `kpi.*` : deux libellés
     * pour la même grandeur finiraient par diverger, et le lecteur ne saurait
     * plus si la différence est un calcul ou une reformulation (Article 10).
     */
    'pilotage' => [
        'resultat_net' => 'Résultat net',
        'resultat_net_source' => 'Comptabilité non consultée',
        'creances_clients' => 'Créances clients',
        'avant_impot' => 'Exercice :annee · avant impôt',
        'exercice' => 'Exercice :annee',
        // 6e carte — masse salariale : `LivreDePaieService::totaux()`, jamais
        // le coût employeur total (PA-53, cf. tête de fichier de la vue).
        'masse_salariale' => 'Masse salariale',
        'masse_salariale_note' => ':effectif salarié(s) · coût réel non arrêté',
        // Absence RÉELLE (aucun bulletin établi ce mois-ci), distincte de
        // « Non consulté » (droit absent) — les deux ne disent pas la même
        // chose et ne doivent pas se lire pareil.
        'masse_salariale_absente' => 'Aucun bulletin établi ce mois-ci',

        // Les titres et libellés partagés des cartes « Par module »
        // (02/09/2026) — markup du maître (`m11-pilotage.js` l.362-475,
        // fonction `bloc()`). Les libellés propres à chaque carte vivent
        // dans `modules` ci-dessous ; `module_paie_effectif`,
        // `module_paie_note` et `module_creances_pieces` sont retirés le
        // 02/09/2026 avec la version à trois cartes qu'ils servaient.
        'module_paie_titre' => 'Personnel & paie',
        'module_paie_vps' => 'VPS à reverser',
        'module_creances_titre' => 'Clients & créances',
        'module_creances_clients' => 'Clients débiteurs',
        'module_creances_total' => 'Total dû',
        'module_compta_titre' => 'Comptabilité',
        'module_compta_va' => 'Valeur ajoutée',
        'module_compta_ebe' => 'Excédent brut',
        'module_compta_bilan' => 'Total bilan',
        'module_compta_pieces' => 'Pièces saisies',
        'module_compta_note' => ':nombre brouillon(s) à trancher.',

        /*
         * Les NEUF cartes « Par module » du maître (`m11-pilotage.js`,
         * `rendreModules()` l.362-475) — directive du Product Owner du
         * 02/09/2026, mots EXACTS du maître, apostrophes typographiques
         * comprises. Les libellés déjà écrits plus haut (module_paie_titre,
         * masse_salariale, module_paie_vps, module_creances_*,
         * module_compta_*) sont RÉUTILISÉS, jamais recopiés : deux clés pour
         * le même mot finiraient par diverger (Article 10).
         */
        'modules' => [
            'reservations' => [
                'titre' => 'Réservations & hébergement',
                'a_venir' => 'À venir',
                'en_cours' => 'En cours',
                'nuitees' => 'Nuitées',
                'reste' => 'Reste à encaisser',
            ],
            'pos' => [
                'titre' => 'Point de vente — aujourd’hui',
                'ventes' => 'Ventes',
                'ca' => 'Chiffre d’affaires',
                'panier_moyen' => 'Panier moyen',
                'note_chambre' => 'Porté en note de chambre',
                'note' => ':nombre vente(s) ne décrémentent aucun stock.',
            ],
            'stocks' => [
                'titre' => 'Stocks',
                'suivies' => 'Références suivies',
                'journalier' => 'Achat journalier (non suivi)',
                'valeur' => 'Valeur au coût moyen',
                'sous_seuil' => 'Sous seuil',
            ],
            'vehicules' => [
                'titre' => 'Location de véhicules',
                'parc' => 'Parc',
                'contrats' => 'Contrats actifs',
                'ca' => 'Chiffre d’affaires',
                'jours' => 'Jours loués',
                'note' => ':nombre véhicule(s) immobilisé(s).',
            ],
            'tourisme' => [
                'titre' => 'Tourisme & circuits',
                'departs' => 'Départs planifiés',
                'places' => 'Places vendues',
                'remplissage' => 'Remplissage',
                'ca' => 'Chiffre d’affaires',
                'note' => ':nombre départ(s) à durée indéterminée.',
            ],
            'paie' => [
                // Le mot du maître — et sa mesure est celle du maître : les
                // bulletins du mois (`PaieEngine.kpis()`), pas le référentiel
                // des employés.
                'effectif' => 'Effectif actif',
                'cout' => 'Coût employeur',
                'cout_valeur' => ':min à :max',
                // Note FIXE du maître — la fourchette vient du taux CNSS
                // « risques professionnels » non confirmé (la référence de
                // fond vit dans le code, jamais à l'écran).
                'note' => 'Fourchette : le taux de risques professionnels n’est pas confirmé.',
            ],
            'creances' => [
                'douteux' => 'Dont + de 90 jours',
                'encaisse_30j' => 'Encaissé sur 30 jours',
            ],
            'compta' => [
                // Sans exercice ouvert, la carte rend des tirets et le DIT —
                // jamais des zéros plausibles (Article 7).
                'absent' => 'Aucun exercice comptable n’est ouvert : rien n’a été mesuré.',
            ],
            'depenses' => [
                'titre' => 'Dépense courante',
                'total' => 'Total décaissé',
                'nombre' => 'Nombre',
                'sans_recu' => ':nombre dépense(s) sans reçu.',
            ],
            // L'état vide du maître (`rendreModules()`, dernière ligne) —
            // rendu quand le RBAC a filtré toutes les cartes.
            'vide' => 'Aucun module ne remonte de données.',
        ],
    ],

    /*
     * « Créances par ancienneté » — quatre tranches CALCULÉES depuis
     * `factures.date_emission`, sur le prédicat d'impayé de M3.
     *
     * ⚠ CE BLOC NE TRANCHE PAS PA-20. La politique de balance âgée — ce qu'on
     * fait d'une créance de 95 jours, et sur quelle échéance on la compte —
     * reste OUVERTE auprès de l'Architecte. Ce qui est affiché ici, ce sont
     * des faits datés : l'âge d'une pièce depuis son émission. `factures` ne
     * porte AUCUNE date d'échéance, et `age_source` le dit à l'écran plutôt
     * que de laisser croire qu'un délai de paiement a été appliqué.
     */
    'creances' => [
        'titre' => 'Créances par ancienneté',
        'sous_titre' => 'Au-delà de 90 jours, le recouvrement devient incertain.',
        'total' => 'Montant dû, toutes pièces confondues',
        'pieces' => ':nombre pièce(s) non soldée(s) chez :clients client(s)',
        // `factures` ne porte aucune date d'échéance et la politique de
        // relance n'est pas arbitrée (PA-20) : l'émission est le seul point
        // de départ possible.
        'age_source' => 'Âge compté depuis la date d\'émission de la facture.',
        'tranches' => [
            '0_30' => '0 à 30 jours',
            '30_60' => '31 à 60 jours',
            '60_90' => '61 à 90 jours',
            'plus_90' => 'Plus de 90 jours',
        ],
        'vide' => 'Aucune créance non soldée.',
    ],

    'exercice_entier' => 'Exercice entier',

    'croise' => [
        'intro' => 'Croisez les ventes, les dépenses et les réservations sur la période '
            . 'choisie en haut de page. Les factures sont volontairement absentes : une '
            . 'facture est le document d\'une vente ou d\'une réservation déjà comptée, et '
            . 'l\'ajouter doublerait chaque montant. Une dépense compte en négatif : le '
            . 'total est un solde, pas une somme.',
        'col_axe' => 'Axe',
        'col_montant' => 'Montant',
        'total' => 'Total',
        'ca' => 'Chiffre d\'affaires encaissé',
        'depenses' => 'Dépenses cumulées',

        /*
         * Les quatre sélecteurs du maître (`tableau-de-bord.html` l.243-258).
         * Le refus qui les couvrait — « deux sources seulement sont servies » —
         * a cessé d'être vrai le 02/09/2026 : les trois registres du maître
         * existent côté serveur (`lignes_vente`, `lignes_depense`,
         * `reservations`). Le motif est daté de sa levée, jamais recopié
         * (PA-144).
         */
        'lignes' => 'Lignes',
        'colonnes' => 'Colonnes',
        'mesure' => 'Mesure',
        'sources' => 'Sources',
        'export_pdf' => 'Export PDF',
        'export_excel' => 'Export Excel',

        'axes' => [
            'source' => 'Source',
            'module' => 'Module',
            'activite' => 'Activité',
            'libelle' => 'Produit / libellé',
            'tiers' => 'Point de vente / canal',
            'mode' => 'Mode de paiement',
            'jour' => 'Jour',
            'mois' => 'Mois',
            'aucun' => '— aucun —',
        ],

        'mesures' => [
            'montant' => 'Montant (FCFA)',
            'encaisse' => 'Encaissé (FCFA)',
            'quantite' => 'Quantité',
            'nombre' => 'Nombre de lignes',
        ],

        /*
         * Les libellés des trois sources, en TABLEAU et non en trois clés
         * suffixées.
         *
         * `__('accueil_pwa.croise.source_' . $source)` compilait, s'affichait
         * correctement… et faisait rougir `MessagesUtilisateurTest` : la garde
         * relit le code à la recherche des clés appelées, et une clé dont la
         * FIN est une variable lui apparaît tronquée (`…croise.source_`) donc
         * absente de `lang/fr/`. Elle a raison de le refuser — une clé qu'aucun
         * balayage ne peut résoudre est une clé que personne ne peut vérifier.
         * Le tableau se lit d'un seul appel statique, et l'index vient du
         * registre fermé `Accueil::SOURCES_CROISE`.
         */
        'sources_libelles' => [
            'ventes' => 'Ventes',
            'depenses' => 'Dépenses',
            'reservations' => 'Réservations',
        ],
        'activite_hebergement' => 'Hébergement',

        'aucune_source' => 'Aucune source sélectionnée. Cochez au moins un registre.',
        'vide' => 'Aucun mouvement sur cette période. Élargissez la période en haut de page.',

        /*
         * ⚠ LA NOTE PORTE UN AVERTISSEMENT DE SCHÉMA, ET IL EST NÉCESSAIRE.
         * `reservations` ne porte AUCUN montant de séjour (PA-29, PA-57) :
         * `acompte` est le seul montant qui existe. Le rendre sous l'intitulé
         * « Montant » sans le nommer ferait lire un chiffre de séjour là où il
         * n'y a qu'un versement.
         */
        'note' => ':nombre mouvement(s) agrégé(s) — les dépenses comptent en négatif : le '
            . 'total est un solde.',
        // `reservations` ne porte ni tarif ni total au schéma serveur
        // (PA-29) : l'acompte est le seul montant qui existe.
        'note_reservations' => 'Le montant retenu pour une réservation est son acompte.',
    ],

    /* -------------------------------------------------------- MODALES */

    'modale_client' => [
        'titre' => 'Ajouter un client',
        'nom' => 'Nom complet',
        'telephone' => 'Téléphone',
        'type' => 'Type de client',
        'type_particulier' => 'Particulier',
        'type_groupe' => 'Groupe',
        'type_agence' => 'Agence partenaire',
        'type_structure' => 'Structure',
        'valider' => 'Ajouter',
        'succes' => 'Client « :nom » ajouté.',
    ],

    // Les cinq services d'une fiche — noms du maître
    // (`tableau-de-bord.js` l.30, `NOMS_SERVICES`).
    'services' => [
        'hebergement' => 'Hébergement',
        'restauration' => 'Restauration',
        'bar' => 'Bar',
        'tourisme' => 'Tourisme',
        'vehicule' => 'Véhicule',
    ],

    'modale_reservation' => [
        'titre' => 'Réservation rapide — Hébergement',
        'renvoi' => 'Pour combiner plusieurs services (restauration, bar, tourisme, '
            . 'véhicule), utilisez le formulaire complet.',
        'renvoi_lien' => 'formulaire complet',
        'client' => 'Client',
        'unite' => 'Unité',
        // Le libellé du maître (`tableau-de-bord.html` l.318), rendu depuis
        // PA-163.
        'canal' => 'Canal de réservation',
        'choisir_canal' => 'Choisissez un canal',
        'nouveau_client' => '+ Nouveau client',
        'client_nom' => 'Nom complet',
        'client_telephone' => 'Téléphone',
        'arrivee' => 'Arrivée',
        'nuits' => 'Nuits',
        'acompte' => 'Acompte',
        'choisir_client' => 'Choisissez un client',
        'choisir_unite' => 'Choisissez une unité libre sur la période',
        'aucune_unite' => 'Aucune unité n\'est libre sur cette période.',
        'valider' => 'Enregistrer',
        'succes' => 'Réservation enregistrée.',
    ],

    'modale_checkin' => [
        'titre' => 'Check-in',
        'client' => 'Client',
        'nuits' => 'Nombre de nuits',
        'unite' => 'Unité',
        'sejour' => 'Séjour',
        'valider' => 'Confirmer le Check-in',
        'succes' => 'Check-in enregistré pour :client.',
        // Un séjour se rattache toujours à une réservation existante
        // (`sejours.reservation_id` NOT NULL) — retaper client et nuits
        // permettrait de les faire diverger.
        'aide' => 'Le client et le nombre de nuits sont ceux de la réservation.',
    ],

    'modale_checkout' => [
        'titre' => 'Check-out',
        'valider' => 'Confirmer le départ',
        'succes' => 'Check-out enregistré. L\'unité passe en nettoyage.',
        'aide' => 'L\'unité passe en NETTOYAGE, pas en « libre » : elle n\'est pas prête à '
            . 'recevoir tant que le ménage n\'est pas fait.',
    ],

    /*
     * « Check-in » DEPUIS « Chambres disponibles » — `modale-checkin-rapide`
     * du maître (`tableau-de-bord.html` l.379-399 : titre dynamique « Check-in
     * — <nom de l'unité> », client, nombre de nuits, rien d'autre).
     *
     * ⚠ Le client est une VRAIE clé étrangère (sélection ou création), jamais
     * le champ texte libre du maître — même écart, assumé pour la même
     * raison, que la modale « Réservation rapide » (règle du dépôt).
     */
    'modale_checkin_chambre' => [
        'titre' => 'Check-in — :unite',
        'client' => 'Client',
        'nouveau_client' => '+ Nouveau client',
        'choisir_client' => 'Choisissez un client',
        'client_nom' => 'Nom complet',
        'client_telephone' => 'Téléphone',
        'nuits' => 'Nombre de nuits',
        'valider' => 'Confirmer le Check-in',
        'succes' => 'Check-in enregistré.',
    ],

    'modale_stocks' => [
        'titre' => 'Articles sous le seuil d\'alerte',
        'col_article' => 'Article',
        'col_stock' => 'Stock théorique',
        'col_seuil' => 'Seuil d\'alerte',
        'vide' => 'Aucun article sous son seuil sur les mouvements enregistrés.',
        'gerer' => 'Gérer les stocks',
    ],

    /*
     * Les SIX rapports du maître (`rapports-engine.js`) — libellés au mot
     * près. Les colonnes de chacun (02/09/2026) reprennent celles du maître
     * quand la donnée servie est de même nature ; « creances » adapte les
     * siennes aux QUATRE TRANCHES réellement exportées (PA-119 — voir la
     * tête de fichier d'`Accueil.php`, §6).
     */
    'modale_rapport' => [
        'titre' => 'Générer un rapport',
        'type' => 'Type de rapport',
        'format' => 'Format',
        'format_pdf' => 'PDF',
        'format_excel' => 'Excel',
        'valider' => 'Télécharger',
        'synthese' => 'Synthèse du tableau de bord',
        'reservations' => 'Liste des réservations',
        'stocks' => 'État des stocks',
        'creances' => 'État de créances',
        'recettes' => 'État de recettes',
        'ventes' => 'État de ventes',

        'reservations_col_client' => 'Client',
        'reservations_col_canal' => 'Canal',
        'reservations_col_arrivee' => 'Arrivée',
        'reservations_col_depart' => 'Départ',
        'reservations_col_total' => 'Total',
        'reservations_col_reste' => 'Reste dû',

        // Chaque ligne de ce rapport est déjà SOUS le seuil par construction
        // (PA-119) : l'état est constant, jamais « normal ».
        'stocks_col_article' => 'Article',
        'stocks_col_quantite' => 'Quantité',
        'stocks_col_seuil' => 'Seuil d\'alerte',
        'stocks_col_etat' => 'État',
        'stocks_etat' => 'Sous le seuil d\'alerte',

        'creances_col_tranche' => 'Tranche d\'ancienneté',
        'creances_col_pieces' => 'Pièces',
        'creances_col_montant' => 'Montant dû',

        'recettes_col_date' => 'Date',
        'recettes_col_mouvements' => 'Mouvements',
        'recettes_col_ca' => 'Chiffre d\'affaires',
        'recettes_col_encaisse' => 'Encaissé',
        'recettes_col_ecart' => 'Écart (créances)',

        'ventes_col_date' => 'Date',
        'ventes_col_produit' => 'Produit / service',
        'ventes_col_activite' => 'Activité',
        'ventes_col_point_vente' => 'Point de vente',
        'ventes_col_quantite' => 'Quantité',
        'ventes_col_montant' => 'Montant',
        'ventes_col_mode' => 'Mode de paiement',

        // PA-119 : un export porte sur ce qui est affiché, et il dit son filtre.
        'note' => 'Chaque rapport porte sur ce que cet écran affiche déjà. « État des '
            . 'stocks » et « État de créances » sont des états à l\'instant : la période '
            . 'sélectionnée ne s\'y applique pas. Les autres portent sur la période choisie '
            . 'en haut de page.',
        'vide' => 'Il n\'y a rien à exporter sur cette période : le document ne sera pas '
            . 'produit.',
    ],

];
