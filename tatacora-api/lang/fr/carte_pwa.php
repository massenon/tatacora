<?php

declare(strict_types=1);

/*
 * ÉCRANS DE CARTE DE LA PWA — bar (M5) et restaurant (M4), plus le catalogue
 * des plats (M4).
 *
 * Maîtres :
 *   prototype_v2/pages/m5-bar-carte.html
 *   prototype_v2/pages/m4-restaurant-carte.html
 *   prototype_v2/pages/m4-restauration.html
 *   prototype_v2/pages/carte-module.js  (le corps des deux premières)
 *
 * ## Pourquoi un fichier à part de `pwa.php`
 *
 * `lang/fr/pwa.php` porte déjà trois sections (`bar_carte`,
 * `carte_restaurant`, `restauration`) écrites du temps où la PWA était en
 * LECTURE SEULE STRICTE. Elles décrivent un écran qui n'existe plus : elles
 * refusent le point de vente, les exports, le CRUD et les cinq modales, et
 * `bar_carte.sous_titre` y affirme un rattachement « 1 pour 1 » que la colonne
 * `unites_vendables_par_unite_stock` a rendu faux le 31/08/2026.
 *
 * Un motif de refus qui a cessé d'être vrai transforme une décision en oubli
 * (PA-144) : ces clés doivent être reprises par qui détient `pwa.php`. Elles
 * ne sont PAS reprises ici — deux listes écrites à deux endroits finissent par
 * diverger, et ce fichier-ci est celui que les écrans lisent réellement.
 *
 * ## Le maître fait foi sur le mot, la documentation sur le calcul
 *
 * Chaque libellé porte en commentaire sa ligne au maître quand il en vient.
 * Les écarts sont NOMMÉS avec leur raison et leur date, jamais glissés.
 */

return [

    /*
    |---------------------------------------------------------------------------
    | Commun aux deux cartes — le maître n'a qu'un fichier pour les deux
    |---------------------------------------------------------------------------
    |
    | `carte-module.js` s'annonce lui-même « ÉCRAN DE CARTE — partagé par le
    | Restaurant (M4) et le Bar (M5) » : ce qui change tient dans le module et
    | son bandeau. Séparer les libellés ferait deux écrans jumeaux qui
    | divergeraient au premier ajustement.
    |
    */
    'commun' => [
        // maître — m5-bar-carte.html l.35-47, m4-restaurant-carte.html l.34-46
        'lien_pos' => 'Point de vente',
        'lien_stocks' => 'Stocks',
        'bouton_rapprocher' => 'Rapprocher automatiquement',
        // Les boutons « Excel » / « PDF » du maître (l.37-39) sont fusionnés
        // en un seul « Exporter » (`pwa.export.bouton`) — dérogation PO du
        // 01/09/2026, rappelée le 02/09/2026 ; voir `DerogationsMaquette`
        // (export_bouton_unique). Leurs clés sont retirées : une clé que
        // plus rien ne lit finit recopiée par erreur.
        'bouton_fiche_prix' => 'Imprimer la fiche des prix',

        // maître — l.56-57
        'onglet_carte' => 'Carte du jour',
        'onglet_couverture' => 'Couverture du stock',

        /*
        |-----------------------------------------------------------------
        | Onglet « Ventes du rayon » — AJOUT du 03/09/2026 (Product Owner)
        |-----------------------------------------------------------------
        |
        | N'existe au maître ni sur `m5-bar-carte.html`, ni sur
        | `m4-restaurant-carte.html` : ce n'est pas un portage, et le bloc est
        | déclaré au comparateur de squelette
        | (`structure-ajout:<page>#<bloc>`) plutôt que posé en silence.
        |
        | Le LIBELLÉ de l'onglet, lui, n'est pas ici : il diffère d'un rayon à
        | l'autre (« Ventes du Bar » / « Ventes du Restaurant ») et vit dans la
        | section de chaque page, comme le titre et le bandeau.
        */
        'ventes_titre' => 'Lignes de vente du rayon',
        'ventes_recherche' => 'Rechercher un article, un ticket, un utilisateur…',
        'ventes_tous_statuts' => 'Tous les statuts',
        // Les deux valeurs RÉELLES de `ventes.statut` (`Vente::STATUTS`).
        'ventes_statut_validee' => 'Validée',
        'ventes_statut_annulee' => 'Annulée',
        'ventes_du' => 'Du',
        'ventes_au' => 'Au',
        'ventes_bornes_aide' => 'Les deux bornes sont incluses : une vente du dernier jour de la '
            . 'plage figure au tableau.',

        'ventes_col_date' => 'Date',
        'ventes_col_ticket' => 'N° vente',
        'ventes_col_article' => 'Article',
        /*
         * « Stock ACTUEL », jamais « Stock ». Le chiffre est celui
         * d'aujourd'hui : `lignes_vente` ne garde aucune trace du stock au
         * moment de l'encaissement, et `mouvements_stock` ne permet pas de le
         * reconstituer par article de carte. Un entête « Stock » sur cette
         * colonne laisserait lire un relevé historique — un chiffre faux mais
         * plausible, la famille PA-59/60/61.
         */
        'ventes_col_stock' => 'Stock actuel',
        'ventes_col_prix' => 'Prix unitaire',
        'ventes_col_quantite' => 'Quantité',
        'ventes_col_montant' => 'Montant',
        'ventes_col_statut' => 'Statut',
        'ventes_col_utilisateur' => 'Utilisateur',

        'ventes_compteur' => ':nombre ligne(s) · Total validé : :total',
        'ventes_compteur_annulees' => 'dont :nombre annulée(s), hors total',
        'ventes_total_page' => 'TOTAL DE LA PAGE',
        'ventes_total_page_aide' => 'Somme des lignes validées affichées ci-dessus. Une vente '
            . 'annulée reste au registre mais son montant n\'est pas compté.',
        'ventes_stock_aide' => 'Le stock affiché est celui d\'aujourd\'hui, jamais celui du jour de '
            . 'la vente.',
        'ventes_stock_hors_carte' => 'Cet article n\'est plus à la carte : son stock ne se lit plus '
            . 'nulle part. Ce n\'est pas un stock nul.',
        'ventes_vide' => 'Aucune ligne de vente ne correspond à ces critères.',
        'ventes_affichage' => 'Affichage de :debut-:fin sur :total',

        /*
        | Les libellés du DOCUMENT de ventes (PDF et tableur), ajout du
        | 03/09/2026 — voir `pdf/carte-ventes.blade.php`. Ce sont les seules
        | chaînes du document qui ne viennent pas déjà de l'écran : les entêtes
        | de colonnes, le compteur et l'avertissement de stock sont ceux du
        | tableau, lus aux clés `ventes_col_*`, `ventes_compteur*` et
        | `ventes_stock_aide` — les recopier ici ferait deux registres, et
        | « Stock actuel » redeviendrait « Stock » sur le papier.
        */
        'ventes_doc_periode' => 'Période',
        'ventes_doc_edite_le' => 'Édité le',
        'ventes_doc_par' => 'Par',
        'ventes_doc_filtre' => 'Filtre appliqué',

        // maître — l.64 à l.77
        'recherche' => 'Rechercher un article…',
        'toutes_categories' => 'Toutes les catégories',
        'tous_articles' => 'Tous les articles',
        'etat_indisponible' => 'Retirés du jour',
        'etat_lie' => 'Liés au stock',
        'etat_sans_lien' => 'Sans lien de stock',
        'etat_rupture' => 'En rupture de stock',
        // maître — m5-bar-carte.html l.71 : la sixième option du filtre.
        'etat_provisoire' => 'Prix provisoire',

        // maître — carte-module.js l.338-353
        'kpi_articles' => 'Articles à la carte',
        'kpi_articles_detail' => ':nombre disponible(s)',
        'kpi_retires' => 'Retirés du jour',
        'kpi_retires_detail' => 'Rupture ou retrait',
        'kpi_lies' => 'Liés au stock',
        'kpi_lies_detail' => ':taux % de couverture',
        'kpi_sans_lien' => 'Ne décrémentent rien',
        'kpi_sans_lien_detail' => 'Stock surévalué d\'autant',
        'kpi_rupture' => 'En rupture de stock',
        'kpi_rupture_detail' => ':nombre sous seuil',
        // maître — carte-module.js l.395-396
        'kpi_provisoires' => 'Prix provisoires',
        'kpi_provisoires_detail' => 'À confronter à la carte',

        /*
         * maître — carte-module.js l.108-109, AU PIXEL.
         *
         * Ces deux marques se rendent SOUS le prix, sur la carte du bar, sur
         * celle du restaurant, ET sur la fiche des prix remise au client. Un
         * prix provisoire imprimé sans sa marque devient un tarif ferme :
         * c'est le risque qui a motivé l'arbitrage PA-161 (b).
         */
        'marque_provisoire' => 'provisoire',
        'marque_corrige_main' => 'corrigé à la main',

        // maître — carte-module.js l.127-130. La casse est celle du maître :
        // c'est `uppercase` qui met les entêtes en capitales à l'écran, et
        // l'export sort la chaîne telle qu'elle est écrite ici.
        'col_article' => 'Article',
        'col_categorie' => 'Catégorie',
        'col_prix' => 'Prix',
        'col_article_stock' => 'Article de stock',
        'col_stock_vendable' => 'Stock vendable',
        'col_actions' => 'Actions',

        // maître — carte-module.js l.397-404 (l'état exporté). « Réserve »
        // porte les DEUX mentions de fin de ligne, « prix provisoire » et
        // « ne décrémente rien », séparées par un point médian (l.413-414).
        'export_col_disponible' => 'Disponible',
        'export_col_reserve' => 'Réserve',
        'export_oui' => 'oui',
        'export_non' => 'non',
        'export_sans_lien' => 'ne décrémente rien',
        // maître — carte-module.js l.413 : la première des deux mentions de
        // la colonne « Réserve ». Elle en avait été retirée faute de colonne.
        'export_prix_provisoire' => 'prix provisoire',

        // maître — carte-module.js l.129-130
        'tableau_titre' => ':nombre article(s)',
        'tableau_aside' => 'Le stock vendable est <strong>calculé</strong>, jamais saisi.',
        'vide' => 'Aucun article ne correspond à ces critères.',

        // maître — carte-module.js l.89-93 et l.110-114
        'badge_non_suivi' => 'non suivi',
        'badge_rupture' => 'rupture',
        'bouton_rendre_indispo' => 'Rendre indispo.',
        'bouton_remettre' => 'Remettre',
        'bouton_lier' => 'Lier au stock',
        'bouton_modifier_lien' => 'Modifier le lien',
        'bouton_delier' => 'Délier',

        // Ajout fonctionnel (01/09/2026, demande du Product Owner) : n'existe
        // pas au maître, qui n'a pas encore d'historique des prix. Déclaré au
        // comparateur de squelette (`structure-ajout:<page>#<bloc>`) plutôt
        // que porté en silence.
        // Modifier le prix — directive PO du 02/09/2026 (second volet du
        // retracage : la trace existait, le geste manquait).
        // Accordeon de la bande d'indicateurs (PO 03/09/2026).
        // Etiquette du bloc « nombre de lignes » dans l'en-tete du document de
        // carte (03/09/2026 — l'en-tete passe par le partiel unique, qui
        // attend une paire libelle/valeur a la place du numero de piece).
        // Creation de boisson au bar (PO 03/09/2026) : le geste manquait
        // entierement a la PWA, l'API et l'import CSV etaient les seules
        // voies. Propre au bar (le restaurant cree ses plats ailleurs).
        'bouton_nouvelle_boisson' => 'Nouvelle boisson',
        'modale_boisson_titre' => 'Nouvelle boisson',
        'modale_boisson_sous_titre' => "La boisson entre à la carte du bar et devient vendable au comptoir.",
        'champ_boisson_libelle' => 'Libellé',
        'champ_boisson_categorie' => 'Catégorie',
        'champ_boisson_prix' => 'Prix de vente (FCFA)',
        'champ_boisson_article' => 'Article de stock',
        'champ_boisson_article_invite' => 'Rechercher un article…',
        'champ_boisson_article_aide' => "L'article de stock est obligatoire : c'est lui que chaque vente décrémente. Le conditionnement (un casier de 24 ?) se règle ensuite par « Lier au stock ».",
        'boisson_confirmer' => 'Créer la boisson',
        'toast_boisson_creee' => '« :article » est à la carte du bar.',
        'export_lignes' => 'Lignes',
        'kpis_accordeon' => 'Indicateurs de la carte',
        'kpis_aide' => 'Repliez la bande pour gagner de la hauteur de tableau.',
        // « Modifier la boisson » (PO 08/10/2026) : renommer ou reclasser une
        // boisson existante. Le geste n'existait nulle part sur la PWA - seul
        // le prix, le lien au stock et le retrait de la carte se modifiaient.
        'bouton_modifier_boisson' => 'Modifier',
        'modale_modifier_boisson_titre' => 'Modifier la boisson — :article',
        'modale_modifier_boisson_sous_titre' => "Le libellé et la catégorie changent ; le prix, le lien au stock et l'historique restent ceux de la boisson.",
        'modifier_boisson_confirmer' => 'Enregistrer la boisson',
        'toast_boisson_modifiee' => '« :article » est à jour.',
        'bouton_modifier_prix' => 'Prix',
        'modale_prix_titre' => 'Modifier le prix — :article',
        'modale_prix_sous_titre' => "Le changement est tracé dans l'historique des prix.",
        'champ_nouveau_prix' => 'Nouveau prix de vente (FCFA)',
        'prix_trace' => 'Un prix à zéro est refusé : pour suspendre la vente, utilisez « Retirer de la carte », qui porte son motif.',
        'prix_confirmer' => 'Enregistrer le prix',
        'toast_prix_modifie' => 'Prix de « :article » modifié.',
        'bouton_historique_prix' => 'Historique des prix',

        // maître — carte-module.js l.209-212 (`motif_sans_lien`)
        'sans_lien_bar' => 'Non rattaché à un article de stock — la vente ne décrémentera rien.',
        'sans_lien_restaurant' => 'Fiche technique absente : une recette ne se décrémente '
            . 'pas comme un article.',

        // maître — carte-module.js l.135-143 (`formaterConversion`)
        'conversion_par_unite' => ':nombre par :unite',
        'conversion_par_vente' => ':nombre :unite par vente',
        // maître — carte-engine.js l.137 : `art.unite_mesure || 'unité'`
        'unite_defaut' => 'unité',

        // maître — carte-module.js l.184-186
        'couverture_titre' => 'Couverture du lien au stock, catégorie par catégorie',
        'couverture_col_categorie' => 'Catégorie',
        'couverture_col_articles' => 'Articles',
        'couverture_col_lies' => 'Liés au stock',
        'couverture_col_sans_lien' => 'Sans lien',
        'couverture_col_couverture' => 'Couverture',
        'couverture_col_indisponibles' => 'Indisponibles',
        // maître — carte-module.js l.184 : la septième colonne du tableau de
        // couverture, qui manquait faute de colonne au schéma.
        'couverture_col_provisoires' => 'Prix provisoires',
        'couverture_total' => 'TOTAL',

        // maître — carte-module.js l.193-201
        'couverture_dette_titre' => ':nombre article(s) ne décrémentent rien à la vente.',
        'couverture_dette_texte' => 'Chaque vente de ces articles laisse le stock inchangé. La valeur '
            . 'du stock affichée est surévaluée d\'autant, et l\'écart n\'apparaîtra qu\'à l\'inventaire '
            . 'physique — au moment où il est le plus coûteux à expliquer.',
        'couverture_complete_titre' => 'Couverture complète.',
        'couverture_complete_texte' => 'Chaque vente décrémente le stock correspondant.',

        /*
         * Les trois états du stock vendable, et pourquoi ils sont TROIS.
         *
         * Un chiffre, « sans lien de stock », « non consulté ». Replier les
         * deux derniers sur zéro afficherait une rupture là où il n'y a
         * qu'une absence d'information — et « 0 » se lit comme un fait
         * (PA-129, même distinction que sur la carte du bar du client Flutter).
         */
        'stock_non_consulte' => 'non consulté',
        'stock_non_consulte_detail' => 'Le stock de cet article n\'a pas pu être lu : le chiffre est '
            . 'absent, il n\'est pas nul.',

        // Toasts — maître, carte-module.js l.300, l.362, l.371, l.446-448
        'toast_lien_enregistre' => '« :article » est rattaché au stock.',
        'toast_retire' => '« :article » retiré de la carte du jour.',
        'toast_remis' => '« :article » est de nouveau à la carte.',
        'toast_lien_retire' => 'Lien retiré.',
        'toast_rapprochement' => ':nombre article(s) rattaché(s) automatiquement.',
        'toast_rapprochement_vide' => 'Aucun nouveau rapprochement possible — les libellés restants ne '
            . 'correspondent à aucun article de stock.',
    ],

    /*
    |---------------------------------------------------------------------------
    | Les trois modales — au mot et à la mesure du maître
    |---------------------------------------------------------------------------
    */
    'modale_lien' => [
        // maître — carte-module.js l.226-227
        'titre' => 'Lier au stock',
        'sous_titre' => ':article — :prix',

        // maître — carte-module.js l.233-246
        'label_article' => 'Article de stock',
        'invite_article' => 'Rechercher un article de stock…',

        /*
         * ⚠ L'ÉCART DÉCLARÉ LE 31/08/2026 EST LEVÉ. Il disait que `articles`
         * ne portait aucune colonne de mode de suivi, et que recopier la
         * phrase du maître affirmerait un filtre que rien n'applique.
         * `articles.suivi` existe depuis PA-161 (a), et le filtre est
         * réellement appliqué par `articlesDeStock()` : la phrase du maître
         * est donc reprise au mot près (`carte-module.js` l.240-243). Une
         * réserve qui a cessé d'être vraie devient un oubli (PA-144).
         */
        'aide_article' => 'Seuls les articles en <strong>suivi permanent</strong> apparaissent : un '
            . 'article en achat journalier n\'est pas suivi, le rattacher ne décrémenterait rien.',
        'label_conversion' => 'Combien de « :article » dans une unité de stock ?',
        'aide_conversion' => 'Un casier de 24 bouteilles ? Saisissez <strong>24</strong>. Un bidon '
            . 'd\'huile utilisé entier ? Saisissez <strong>1</strong>.',

        // maître — carte-module.js l.276-286 (l'aperçu)
        'apercu_stock' => 'Stock actuel',
        'apercu_vendables' => 'Soit, en unités vendables',
        'apercu_decrement' => 'Chaque vente décrémentera',

        // maître — carte-module.js l.254-255
        'bouton_enregistrer' => 'Enregistrer le lien',

        'aucun_article_stock' => 'Aucun article en suivi permanent ne correspond à cette recherche.',
    ],

    'modale_dispo' => [
        // maître — carte-module.js l.324-325
        'titre' => 'Retirer de la carte du jour',

        // maître — carte-module.js l.330-347
        'label_motif' => 'Motif',
        'invite_motif' => 'Rechercher un motif…',
        'label_commentaire' => 'Commentaire',
        'invite_commentaire' => 'Ex. livraison attendue jeudi',
        'aide' => 'Une <strong>rupture</strong> revient d\'elle-même au réapprovisionnement ; un '
            . '<strong>retrait</strong> est une décision commerciale. Les confondre ferait disparaître '
            . 'un plat sans que personne ne sache s\'il faut le racheter.',

        // maître — carte-module.js l.351
        'bouton_retirer' => 'Retirer',

        /*
         * Le maître distingue `temporaire: true` de `temporaire: false`, et
         * c'est tout l'objet de son paragraphe d'aide. La propriété est portée
         * par le MOTIF (`IndisponibiliteCarte::MOTIFS`), jamais par une
         * colonne : une colonne l'aurait dupliquée, donc rendue capable de
         * mentir.
         */
        'temporaire' => 'revient au réapprovisionnement',
        'definitif' => 'décision commerciale',
    ],

    'modale_delier' => [
        // maître — carte-module.js l.428-437, rendu par `assets/js/modal.js`
        // l.128-148 (`Dialogue.confirmer`, ton « alerte »).
        'titre' => 'Retirer le lien au stock ?',
        'message' => 'Les ventes de cet article ne décrémenteront plus aucun stock.',

        /*
         * ⚠ ÉCART DE TEXTE DÉCLARÉ (31/08/2026). Le maître écrit « ce qui sort
         * réellement DU BAR » (`carte-module.js` l.434), parce que son
         * dialogue a été écrit en lisant la page du bar. La même modale sert
         * les deux rayons : « de l'établissement » est juste sur les deux.
         * L'écart est déclaré ici plutôt que glissé dans la vue.
         */
        'detail' => 'La fiche de stock cessera de refléter ce qui sort réellement de l\'établissement.',

        // maître — carte-module.js l.435
        'bouton_confirmer' => 'Retirer le lien',
    ],

    /*
     * « Historique des prix » — AJOUT FONCTIONNEL du 01/09/2026, demande du
     * Product Owner : « on doit retracer les changements de prix ». N'existe
     * pas au maître (`m5-bar-carte.html`, `m4-restaurant-carte.html`
     * n'ont aucune modale de ce nom) — ce n'est pas un portage.
     */
    'modale_historique_prix' => [
        'titre' => 'Historique des prix',
        'sous_titre' => ':article',

        'col_date' => 'Date',
        'col_champ' => 'Champ',
        'col_ancien_prix' => 'Ancien',
        'col_nouveau_prix' => 'Nouveau',
        'col_par' => 'Par',

        // Les deux valeurs du registre fermé `HistoriquePrixCarte::CHAMP_*` —
        // le libellé affiché, jamais le nom de colonne brut.
        'champ_prix_vente' => 'Prix de vente',
        'champ_prix_corrige_main' => 'Corrigé à la main',

        // La bascule d'un booléen se lit en mots, pas en 0.00/1.00 : le
        // montant brut de la table n'a de sens que pour `prix_vente`.
        'marque_active' => 'Oui',
        'marque_inactive' => 'Non',

        'vide' => 'Aucun changement de prix enregistré pour cet article.',

        'bouton_fermer' => 'Fermer',
    ],

    /*
    |---------------------------------------------------------------------------
    | M5 — Carte du bar (`prototype_v2/pages/m5-bar-carte.html`)
    |---------------------------------------------------------------------------
    */
    'bar' => [
        // maître — l.31
        'titre' => 'Carte du bar',
        // maître — l.34, in extenso : la contenance est désormais portée par
        // `unites_vendables_par_unite_stock`, la phrase est redevenue vraie.
        'sous_titre' => 'Chaque boisson vendue décrémente son casier. Le rapprochement contrôle la '
            . '<strong>contenance</strong> : une 33 cl ne sort pas du casier de 66 cl.',

        // Onglet AJOUTÉ le 03/09/2026 (Product Owner) — le libellé est celui
        // du rayon, jamais un « Ventes » générique : les deux écrans partagent
        // le même corps, et deux onglets homonymes ne se distingueraient pas
        // dans un signet ou une capture d'écran.
        'onglet_ventes' => 'Ventes du Bar',

        'export_titre' => 'Exporter — Carte du bar',
        // L'export suit l'ONGLET COURANT (PO 03/09/2026) : la modale NOMME ce
        // qu'elle produira. Un titre resté « Carte du bar » sur l'onglet des
        // ventes ferait douter du périmètre du fichier téléchargé — c'est
        // exactement ce que le maître évite en titrant « Exporter — <entité> »
        // (`crud-ui.js` l.147).
        'export_titre_ventes' => 'Exporter — Ventes du Bar',

        /*
         * Le stock vendable est celui du POINT BAR, jamais tous points
         * confondus : 24 bouteilles au bar et 100 au magasin font 24 vendables
         * au comptoir. Sans point déclaré, aucun chiffre n'est rendu.
         */
        'point_absent' => 'Aucun point de stockage de type « bar » n\'est encore déclaré : le stock '
            . 'vendable ne peut pas être calculé, et aucun chiffre n\'est affiché. Ce qui dort au '
            . 'magasin n\'est pas vendable au comptoir — replier sur le stock tous points confondus '
            . 'annoncerait des bouteilles que le barman n\'a pas.',
    ],

    /*
    |---------------------------------------------------------------------------
    | M4 — Carte du restaurant (`prototype_v2/pages/m4-restaurant-carte.html`)
    |---------------------------------------------------------------------------
    */
    'restaurant' => [
        // maître — l.30
        'titre' => 'Carte du restaurant',
        // maître — l.33
        'sous_titre' => 'Composition, disponibilité du jour et lien au stock. Le stock affiché est '
            . '<strong>calculé</strong>, jamais saisi.',

        // Onglet AJOUTÉ le 03/09/2026 (Product Owner) — voir `bar.onglet_ventes`.
        'onglet_ventes' => 'Ventes du Restaurant',

        /*
         * L'ACCES A L'ECRAN DU CATALOGUE — AJOUT (PO 04/09/2026).
         *
         * `/pwa/restaurant/plats` porte « Nouveau plat », les fiches techniques
         * et les menus, et AUCUN clic n'y menait : l'entree de menu
         * « Restaurant » ouvre la carte, et aucune vue ne renvoyait vers lui.
         * Un ecran livre que personne ne peut atteindre est le symetrique de
         * l'entree de menu inerte que l'Article 3.3 interdit.
         *
         * Le libelle NOMME les trois choses qu'on y fait : c'est ce qui evite
         * qu'on le prenne pour un second affichage de la meme carte.
         */
        'bouton_catalogue' => 'Plats, fiches techniques & menus',

        'export_titre' => 'Exporter — Carte du restaurant',
        // Voir `bar.export_titre_ventes` : la modale nomme l'onglet exporté.
        'export_titre_ventes' => 'Exporter — Ventes du Restaurant',

        'point_absent' => 'Aucun point de stockage de type « cuisine » n\'est encore déclaré : le '
            . 'stock vendable ne peut pas être calculé, et aucun chiffre n\'est affiché. Ce qui dort '
            . 'au magasin n\'est pas servi en salle.',

        // La fiche technique est le chemin NORMAL : elle est nommée dans la
        // colonne « Article de stock » quand elle remplace le lien direct.
        'fiche_technique' => 'Fiche technique (:nombre ingrédient(s))',
    ],

    /*
    |---------------------------------------------------------------------------
    | M4 — Restaurant & Cuisine (`prototype_v2/pages/m4-restauration.html`)
    |---------------------------------------------------------------------------
    */
    'restauration' => [
        // maître — l.28
        'titre' => 'Restaurant & Cuisine',
        // maître — l.30
        'sous_titre' => 'Gestion des menus, fiches de recette et prise de commande, avec déduction '
            . 'automatique du stock cuisine',

        // maître — config `texteRecherche` et `filtres`
        'recherche' => 'Rechercher un plat...',
        'toutes_categories' => 'Toutes les catégories',

        // maître — config `colonnes`
        'col_plat' => 'Plat',
        'col_categorie' => 'Catégorie',
        'col_prix' => 'Prix de vente',
        'col_disponible' => 'Disponible',
        'col_actions' => 'Actions',

        // 02/09/2026 — « Fiche Technique » et « Coût Matière » retirées du
        // tableau (garde G5) : aucun tableau du maître ne les porte, et une
        // colonne supplémentaire se décide, elle n'apparaît pas par
        // copier-coller. La fiche technique reste accessible par la modale
        // d'édition du plat.

        'disponible_oui' => 'Oui',
        'disponible_non' => 'Non',

        // maître — config `champsFormulaire`
        'bouton_nouveau' => 'Nouveau plat',
        'form_titre_creation' => 'Nouveau plat',
        'form_titre_modification' => 'Modifier le plat',
        'label_nom' => 'Nom du plat',
        'invite_nom' => 'Ex. Poulet DG',
        'label_categorie' => 'Catégorie',
        'label_prix' => 'Prix de vente (FCFA)',

        /*
         * PA-161 (b) — la marque « prix provisoire », et l'etat derive.
         *
         * Le maitre n'a pas de case a cocher : il tient ces marques dans son
         * propre jeu de donnees, releve sur la carte papier. La case est donc
         * un AJOUT declare — sans elle, aucun geste du produit ne permettrait
         * de lever une marque une fois le tarif confronte a l'ardoise, et les
         * six boissons resteraient signalees « a valider » indefiniment.
         *
         * « Corrige a la main » n'est PAS offert : c'est un fait deduit
         * (`App\Domain\Carte\MarquesDePrix`), rendu en lecture seule.
         */
        'label_prix_provisoire' => 'Prix provisoire',
        'aide_prix_provisoire' => 'À cocher quand le tarif a été posé faute de relevé : il reste à '
            . 'confronter à la carte physique. La marque s\'imprime en regard du prix, y compris sur '
            . 'la fiche remise au client.',
        'etat_prix_corrige_main' => 'Ce tarif a été corrigé à la main : la marque « corrigé à la '
            . 'main » s\'imprime en regard du prix. Elle est posée automatiquement quand le prix '
            . 'd\'un article provisoire est modifié, et ne se lève pas depuis cet écran.',
        'label_fiche' => 'Fiche technique (recette)',
        'invite_fiche' => 'Choisir une fiche technique',
        /*
         * `plats.recette_id` est NOT NULL au schéma. Le formulaire livré
         * proposait « Aucune fiche technique » : l'insertion aurait échoué sur
         * la contrainte, message SQL à l'appui, et le plat n'aurait jamais été
         * créé — sans que l'écran sache dire pourquoi.
         */
        'aide_fiche' => 'Obligatoire : un plat se décrémente par sa fiche technique. '
            . 'Créez d\'abord la recette si elle n\'existe pas.',
        'label_menu' => 'Menu',
        'invite_menu' => 'Choisir un menu',
        'bouton_enregistrer' => 'Enregistrer',

        'action_editer' => 'Modifier',
        'action_archiver' => 'Retirer de la carte',

        'vide' => 'Aucun plat ne correspond à ces critères.',

        // Tableau générique du maître (crud-ui.js / crud-engine.js) —
        // état vide, sélection et pagination, portés le 01/09/2026 (G6).
        'vide_titre' => 'Aucun résultat',
        'vide_detail' => 'Essayez de modifier votre recherche ou vos filtres.',
        'selection_tout' => 'Tout sélectionner',
        'selection_ligne' => 'Sélectionner cette ligne',
        'affichage' => 'Affichage de :debut-:fin sur :total',
        'selectionnes' => ':nombre sélectionné(s)',

        'kpi_total' => 'Plats au catalogue',
        'kpi_avec_fiche' => 'Avec fiche technique',
        'kpi_sans_fiche' => 'Sans fiche technique',
        'kpi_retires' => 'Retirés de la carte',

        'cree' => 'Le plat « :plat » est au catalogue.',
        'modifie' => 'Le plat « :plat » est à jour.',

        /*
         * ARCHIVER UN PLAT = LE RETIRER DE LA CARTE, et il n'y a pas d'autre
         * geste possible.
         *
         * `plats` n'a AUCUNE colonne d'archivage ni de statut (relevé
         * `SHOW COLUMNS FROM plats` du 31/08/2026 : quatorze colonnes, aucune).
         * Le « D » de CRUD n'existe nulle part dans ce dépôt — `->delete()`
         * effacerait un plat que `lignes_commande_restaurant` référence en
         * `restrictOnDelete`, et la ligne de commande deviendrait illisible.
         *
         * Le geste métier équivalent existe et il est du maître : le motif
         * `retire` d'`IndisponibiliteCarte`, « décision commerciale », qui se
         * lève depuis la carte du restaurant. Rien n'est effacé, tout est
         * restaurable — exactement ce que promet la modale d'archivage.
         */
        'archiver_titre' => 'Retirer « :plat » de la carte ?',
        'archiver_message' => 'Le plat quitte la carte du jour et reste au catalogue — rien n\'est '
            . 'effacé. Il revient depuis la carte du restaurant, bouton « Remettre ».',
        'archiver_confirmer' => 'Retirer de la carte',
        'archive' => 'Le plat « :plat » est retiré de la carte.',
        'verrou_deja_retire' => 'Ce plat est déjà retiré de la carte (:motif). Il se remet en ligne '
            . 'depuis la carte du restaurant.',
        'verrou_commandes' => 'Élément engagé dans :nombre commande(s) en cours : :liste',

        /*
        |-----------------------------------------------------------------------
        | LA SORTIE D'IMPASSE — menus et fiches techniques (03/09/2026)
        |-----------------------------------------------------------------------
        |
        | `plats.menu_id` et `plats.recette_id` sont NOT NULL, et AUCUN écran de
        | la PWA ne créait ni menu ni recette : les deux Services existaient,
        | avec un seul appelant chacun, leur contrôleur d'API. Sur une base
        | neuve, le formulaire « Nouveau plat » présentait donc deux sélecteurs
        | vides sans dire pourquoi ni où aller — constat du Product Owner.
        |
        | Les messages ci-dessous disent le MANQUE et le GESTE qui le lève, à
        | l'endroit du champ concerné. « Aucun menu » tout court laisserait
        | croire à une panne de chargement.
        */
        'aucun_menu' => 'Aucun menu n\'existe encore : un plat ne peut pas être créé sans lui. '
            . 'Créez d\'abord un menu — vous reviendrez ici avec votre saisie.',
        'aucune_fiche' => 'Aucune fiche technique n\'existe encore : un plat ne peut pas être créé '
            . 'sans elle. Créez d\'abord la fiche — vous reviendrez ici avec votre saisie.',
        'bouton_creer_menu' => 'Créer un menu',
        'bouton_creer_fiche' => 'Créer une fiche technique',
        'bouton_nouveau_menu' => 'Nouveau menu',
        'bouton_nouvelle_fiche' => 'Nouvelle fiche technique',

        // --- Modale « Nouveau menu » (EF-M4-01) ---
        'menu_form_titre' => 'Nouveau menu',
        'menu_form_sous_titre' => 'Une carte à laquelle rattacher les plats.',
        'menu_label_libelle' => 'Nom du menu',
        'menu_invite_libelle' => 'Ex. Carte du jour',
        'menu_label_type' => 'Type de carte',
        /*
         * Les trois valeurs de l'`enum` MySQL, dans les mots du maître
         * (`m4-restauration.html`, filtre « Toutes les catégories »). La clé est
         * construite depuis `Menu::TYPES` : un type ajouté à l'enum sans sa clé
         * de langue s'afficherait sous son nom technique, ce qui se voit.
         */
        'menu_type_local' => 'Local',
        'menu_type_europeen' => 'Européen',
        'menu_type_special' => 'Spécial',
        'menu_label_date_debut' => 'Début de saison',
        'menu_label_date_fin' => 'Fin de saison',
        'menu_aide_dates' => 'Facultatives : un menu permanent n\'a pas de saison. Une fin '
            . 'antérieure au début est refusée — la carte ne rendrait jamais aucun plat.',
        // Le parametre se nomme `:libelle` et non `:menu` (03/09/2026) :
        // `['menu' => $…]` dans le composant est indiscernable d'une cle de
        // vue pour `ClesDuSocleReserveesTest`, qui protege les cles de la
        // coquille. Renommer le parametre leve l'ambiguite sans affaiblir
        // une garde dont la grossierete est deliberee.
        'menu_cree' => 'Le menu « :libelle » est créé.',

        // --- Modale « Nouvelle fiche technique » (EF-M4-02, PA-23) ---
        'recette_form_titre' => 'Nouvelle fiche technique',
        'recette_form_sous_titre' => 'La nomenclature qui fait décrémenter le stock à chaque vente.',
        'recette_label_libelle' => 'Nom de la fiche',
        'recette_invite_libelle' => 'Ex. Recette Poulet DG',
        'recette_composition_titre' => 'Composition',
        /*
         * PA-23 — le maître porte « Ingrédients principaux » en TEXTE LIBRE.
         * Porté tel quel, aucune décrémentation n'est possible : une chaîne ne
         * se rattache à aucun article. L'écart est nommé ici, pas dissimulé.
         */
        'recette_composition_aide' => 'Chaque ingrédient est un article de stock réel, avec la '
            . 'quantité consommée pour UNE portion.',
        'recette_recherche_article' => 'Rechercher un article de stock...',
        'recette_label_article' => 'Article de stock',
        'recette_invite_article' => 'Choisir un article',
        'recette_label_quantite' => 'Quantité par portion',
        'recette_bouton_ajouter_ingredient' => 'Ajouter un ingrédient',
        'recette_bouton_retirer_ingredient' => 'Retirer cette ligne',
        'recette_aucun_article' => 'Aucun article de stock ne correspond. Élargissez la recherche, '
            . 'ou créez l\'article depuis l\'écran Stocks.',
        /*
         * ⚠ CE MESSAGE DISAIT « la composition se complète plus tard depuis
         * l'API », ET C'ÉTAIT LE DÉFAUT (corrigé le 04/09/2026).
         *
         * C'était vrai à l'écriture — aucun écran ne composait une fiche
         * existante — et cette phrase renvoyait l'utilisateur vers un chemin
         * qu'il n'a pas. Résultat : 82 fiches vides, et un point de vente
         * restaurant bloqué en entier sans que personne sache où aller. Le
         * geste existe désormais sur cet écran ; le message dit la CONSÉQUENCE
         * réelle, qui n'est pas « c'est permis » mais « la vente sera refusée ».
         */
        'recette_sans_ingredient' => 'Sans ingrédient, cette fiche ne décrémente aucun stock : le '
            . 'point de vente REFUSERA la vente du plat qui l\'utilise. Ajoutez au moins un article '
            . 'de stock, ou revenez la composer depuis l\'onglet « Fiches techniques ».',
        /*
         * LE COÛT MATIÈRE A TROIS ÉTATS, ET IL N'EST JAMAIS SAISI.
         *
         * Il se calcule depuis les lignes et le coût moyen pondéré de chaque
         * article (M6). Un article jamais réceptionné porte un CMP à zéro : il
         * n'est pas gratuit, il est NON VALORISÉ. Annoncer « 0 F » ferait lire
         * « marge = prix de vente entier » sur l'écran où l'on fixe un prix —
         * la forme exacte de PA-126.
         */
        'recette_creee' => 'La fiche « :recette » est créée. Coût matière calculé : :cout.',
        'recette_creee_sans_ingredient' => 'La fiche « :recette » est créée, sans ingrédient : elle '
            . 'ne décrémentera aucun stock tant que sa composition est vide.',
        'recette_creee_cout_incomplet' => 'La fiche « :recette » est créée. Son coût matière reste '
            . 'INCONNU : :articles n\'ont pas de coût moyen pondéré (jamais réceptionnés).',

        /*
        |-----------------------------------------------------------------------
        | ONGLET « FICHES TECHNIQUES » — le déblocage du POS (04/09/2026)
        |-----------------------------------------------------------------------
        |
        | Constat du Product Owner : aucune vente possible au point de vente
        | restaurant. Relevé en base — 83 plats, 83 recettes, TROIS lignes
        | d'`ingredients_recette`. Chaque plat avait sa fiche, et elle était
        | vide ; or une fiche vide n'est pas neutre, c'est une vente REFUSÉE
        | (`RecetteManquanteException`).
        |
        | Le geste qui manquait n'était pas la création — livrée le 03/09 —
        | mais la composition d'une fiche EXISTANTE. Les libellés ci-dessous
        | disent l'ÉTAT de chaque fiche, parce que c'est l'état qui commande la
        | vente : « composée », « vide », « provisoire ».
        */
        'onglet_plats' => 'Catalogue des plats',
        'onglet_fiches' => 'Fiches techniques',
        'onglet_menus' => 'Menus',

        'fiches_kpi_total' => 'Fiches techniques',
        'fiches_kpi_vides' => 'Fiches vides — vente refusée',
        'fiches_kpi_provisoires' => 'Compositions provisoires',
        'fiches_kpi_provisoires_detail' => 'Quantités posées, jamais pesées',

        'fiches_recherche' => 'Rechercher une fiche technique...',
        'fiches_filtre_vides' => 'Fiches vides seulement',
        'fiches_filtre_vides_aide' => 'Ce sont elles qui bloquent la vente au comptoir.',

        'fiches_col_fiche' => 'Fiche technique',
        'fiches_col_plat' => 'Plat servi',
        'fiches_col_ingredients' => 'Ingrédients',
        'fiches_col_cout' => 'Coût matière',
        'fiches_col_etat' => 'État',

        'fiches_etat_composee' => 'Composée',
        'fiches_etat_vide' => 'Vide — ne décrémente rien',
        'fiches_etat_vide_infobulle' => 'Toute vente de ce plat au point de vente restaurant est '
            . 'REFUSÉE tant que la composition est vide : la cuisine ne saurait pas quoi sortir du '
            . 'stock.',
        /*
         * LE TROISIEME ETAT, ET IL N'EST NI « composee » NI « vide ».
         *
         * Une fiche dont TOUS les ingredients sont des articles `journalier`
         * (laitue, tomate, oignon, concombre : achetes et consommes le jour
         * meme, jamais inventories) ne fait bouger AUCUN stock. C'est la
         * verite d'une salade verte, et la vente passe. Mais rendue
         * « Composee » sans plus, elle se lirait comme une fiche qui
         * decremente — un indicateur qui affirme un etat qu'il n'a pas
         * verifie (PA-59/60/61).
         */
        'fiches_etat_sans_suivi' => 'Aucun stock suivi',
        'fiches_etat_sans_suivi_infobulle' => 'Cette fiche est composee, et elle ne decremente '
            . 'aucun stock : tous ses ingredients sont suivis « au jour le jour » (achetes le '
            . 'matin, jamais inventories). La vente passe, rien ne bouge, et c’est correct.',

        'fiches_etat_provisoire' => 'Provisoire',
        'fiches_etat_provisoire_infobulle' => 'Les quantités de cette fiche ont été POSÉES pour '
            . 'débloquer le service, elles n\'ont jamais été pesées. Le stock décrémenté à chaque '
            . 'vente est donc approximatif. Enregistrez la composition relevée en cuisine : la '
            . 'marque tombe d\'elle-même.',

        /*
         * LE COÛT MATIÈRE A TROIS ÉTATS DANS LE TABLEAU AUSSI.
         *
         * Un « 0 F » à la place des deux derniers ferait lire « marge = prix de
         * vente entier » sur la liste même où l'on décide quoi corriger — la
         * forme exacte de PA-126.
         */
        'fiches_cout_incomplet' => 'Incomplet',
        'fiches_cout_incomplet_infobulle' => 'Sans coût moyen pondéré (jamais réceptionnés) : '
            . ':articles',
        'fiches_cout_vide' => 'Non calculable',
        'fiches_cout_vide_infobulle' => 'Une composition vide n\'a pas de coût : ce n\'est pas un '
            . 'plat gratuit.',

        'fiches_action_composer' => 'Modifier',
        'fiches_aucune' => 'Aucune fiche technique ne correspond à ces critères.',
        'fiches_sans_plat' => 'Aucun plat',

        /*
         * Le bandeau d'entête de l'onglet. Il dit ce que l'écran attend de
         * l'utilisateur, à l'endroit où il peut le faire — la Directive
         * interdit un écran qui montre un problème sans offrir le geste.
         */
        'fiches_bandeau' => 'Une fiche sans ingrédient ne décrémente aucun stock, et le point de '
            . 'vente REFUSE la vente du plat qui l\'utilise. Ouvrez la fiche, posez ses articles de '
            . 'stock et leurs quantités par portion : le coût matière se calcule tout seul.',

        // --- Modale « Modifier la fiche technique » (04/09/2026) ---
        'recette_form_titre_modification' => 'Modifier la fiche technique',
        'recette_form_sous_titre_modification' => 'Composition, libellé et coût matière de la fiche.',
        'recette_cout_actuel' => 'Coût matière enregistré',
        'recette_cout_actuel_aide' => 'Calculé depuis la composition ci-dessous et le coût moyen '
            . 'pondéré de chaque article. Jamais saisi — il se recalcule à l\'enregistrement.',
        'recette_bandeau_provisoire' => 'Composition PROVISOIRE : ces quantités ont été posées pour '
            . 'débloquer le service, personne ne les a pesées. Corrigez-les et enregistrez — la '
            . 'marque tombera d\'elle-même.',
        'recette_modifiee' => 'La fiche « :recette » est à jour. Coût matière calculé : :cout.',
        'recette_modifiee_sans_ingredient' => 'La fiche « :recette » est enregistrée SANS '
            . 'ingrédient : elle ne décrémente aucun stock, et toute vente du plat qui l\'utilise '
            . 'sera refusée au comptoir.',
        'recette_modifiee_cout_incomplet' => 'La fiche « :recette » est à jour. Son coût matière '
            . 'reste INCONNU : :articles n\'ont pas de coût moyen pondéré (jamais réceptionnés).',

        // --- Onglet « Menus » (04/09/2026) ---
        'menus_col_menu' => 'Menu',
        'menus_col_type' => 'Type de carte',
        'menus_col_saison' => 'Saison',
        'menus_col_plats' => 'Plats rattachés',
        'menus_saison_permanente' => 'Permanent',
        'menus_action_editer' => 'Modifier',
        'menus_aucun' => 'Aucun menu n\'existe encore. Le bouton « Nouveau menu » en crée un : sans '
            . 'lui, aucun plat ne peut être enregistré.',
        'menu_form_titre_modification' => 'Modifier le menu',
        'menu_modifie' => 'Le menu « :libelle » est à jour.',
    ],

    /*
    |---------------------------------------------------------------------------
    | Les refus communs aux trois écrans
    |---------------------------------------------------------------------------
    */
    /*
     * ⚠ `refus.prix_provisoire` A ÉTÉ RETIRÉ LE 02/09/2026, ET C'EST LE LIVRABLE.
     *
     * Il disait que le filtre « Prix provisoire », l'indicateur « Prix
     * provisoires » et les deux marques de ligne n'étaient pas rendus, faute
     * de colonne — la PWA les dérivait de `prix_vente <= 0` sur deux colonnes
     * NOT NULL, donc affichait « aucun prix provisoire » en permanence sans
     * l'avoir vérifié (PA-59/60/61).
     *
     * PA-161 (b) a créé `prix_provisoire` et `prix_corrige_main` sur
     * `cartes_boisson` ET sur `plats`. Le motif a cessé d'être vrai : le
     * garder à l'écran aurait transformé une décision en oubli (PA-144), et
     * l'affaire est plus grave ici qu'ailleurs — la fiche des prix est un
     * papier REMIS AU CLIENT, et un prix provisoire imprimé sans sa marque
     * devient un tarif ferme.
     *
     * Le tableau `refus` est vide, donc supprimé : `pwa.partials.bloc-refus`
     * ne rend rien pour un tableau vide, mais une clé morte laisserait croire
     * qu'un refus subsiste.
     */

    /*
    |---------------------------------------------------------------------------
    | Refus et erreurs — messages levés vers l'écran
    |---------------------------------------------------------------------------
    */
    'fiche_prix_vide' => 'Aucun article tarifé : la fiche des prix ne serait qu\'une page d\'en-tête. '
        . 'Renseignez au moins un tarif avant de l\'imprimer.',
    'export_vide' => 'La liste affichée est vide : il n\'y a rien à exporter. Élargissez le filtre '
        . 'plutôt que de produire un document que l\'on croirait complet.',
    /*
     * Onglet « Ventes » — le refus a SES mots (PO 03/09/2026).
     *
     * Il ne peut pas reprendre `export_vide`, qui invite à élargir « le
     * filtre » de la carte : ici les filtres sont la période, le statut et la
     * recherche du tableau des ventes, et un rayon peut n'avoir simplement
     * rien vendu sur la plage demandée. Le message le dit, pour que personne
     * ne cherche une panne là où il n'y a qu'une plage vide.
     */
    'export_ventes_vide' => 'Aucune ligne de vente ne correspond à ces critères : il n\'y a rien à '
        . 'exporter. Élargissez la période ou le statut plutôt que de produire un document que l\'on '
        . 'croirait complet.',

    'filtre_aucun' => 'Aucun filtre — l\'export porte sur toute la carte.',
    'filtre_categorie' => 'Catégorie : :categorie',
    'filtre_terme' => 'Recherche : « :terme »',
    'filtre_etat' => 'État : :etat',
    'filtre_statut' => 'Statut : :statut',

    /*
     * La période du document de ventes — écrite MÊME sans borne.
     *
     * « Toutes les dates » est une information, pas un silence : un journal de
     * ventes sans période affichée laisserait supposer le mois courant, et
     * c'est le premier chiffre qu'un comptable rapproche. Les deux bornes sont
     * INCLUSES, comme au tableau (`ventes_bornes_aide`).
     */
    'filtre_periode' => 'Période : :periode',
    'periode_du_au' => 'du :debut au :fin (bornes incluses)',
    'periode_depuis' => 'à partir du :debut (borne incluse)',
    'periode_jusqu_au' => 'jusqu\'au :fin (borne incluse)',
    'periode_toutes' => 'toutes les dates',
    'fiche_prix_titre_bar' => 'Fiche des prix — Bar',
    'fiche_prix_titre_restaurant' => 'Fiche des prix — Restaurant',
    'fiche_prix_sans_prix' => ':nombre article(s) sans tarif ont été écartés de la fiche.',

    /*
     * ⚠ ÉCART DÉCLARÉ, ASSUMÉ, ET C'EST LE CŒUR DE PA-161 (b).
     *
     * `assets/js/fiche-prix.js` du maître n'imprime AUCUNE marque : il écarte
     * les articles sans tarif et compte les manquants, rien de plus. Le
     * Product Owner a tranché le 31/08/2026 dans l'autre sens, et la raison
     * est plus forte que la fidélité : la fiche des prix est le papier REMIS
     * AU CLIENT. Six boissons y figurent à un tarif inventé — « ce sont des
     * prix de vente INVENTÉS : ils sont appliqués à de vrais clients à chaque
     * service » (`referentiel-carte.js` l.28-29). L'imprimer sans le dire fait
     * de ce tarif un prix ferme, opposable au comptoir. C'est la version
     * papier de PA-61 : un document qui affirme une certitude que personne n'a
     * établie.
     *
     * La marque est donc imprimée à côté du prix, et l'avertissement de pied
     * de page la compte — comme les articles sans tarif.
     */
    'fiche_prix_marque_provisoire' => 'prix provisoire',
    'fiche_prix_marque_corrige_main' => 'prix corrigé à la main',
    'fiche_prix_avertissement_provisoire' => ':nombre article(s) portent un tarif PROVISOIRE, posé '
        . 'faute de relevé et signalé comme tel en regard du prix. Ces montants restent à confronter '
        . 'à la carte physique avant d\'être tenus pour fermes.',
];
