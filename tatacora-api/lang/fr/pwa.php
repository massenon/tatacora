<?php

declare(strict_types=1);

/*
 * Libellés de la PWA de consultation — LARAVEL_PWA.md.
 *
 * Tout ce qui s'affiche dans une vue Blade passe par ce fichier
 * (06_DEVELOPMENT_STANDARDS.md §4.4). Les descriptions d'écrans en font
 * partie : elles sont définies côté PHP dans Accueil::ECRANS_AUTORISES, mais
 * ce qui en est *affiché* se résout ici.
 *
 * Les chaînes reprises telles quelles du maître (`prototype_v2/pages/`,
 * `assets/js/shell.js`) portent le commentaire « maquette » : elles ne se
 * reformulent pas au fil de l'eau — c'est le texte que le client a vu et
 * approuvé. Un texte reformulé est un écart de gabarit, au même titre qu'une
 * classe changée.
 *
 * ══════════════════════════════════════════════════════════════════════════
 * ⚠ CE FICHIER A PORTÉ 255 REFUS DEVENUS FAUX (purgés le 31/08/2026)
 * ══════════════════════════════════════════════════════════════════════════
 *
 * Il a été écrit sous le régime « la consultation web est en lecture seule
 * stricte ». Ce régime a été LEVÉ le 28/08/2026 par le Product Owner
 * (PA-159) : la PWA fait le CRUD de tous les modules. Les refus qui
 * l'invoquaient sont donc devenus faux le jour même, et personne ne les a
 * rouverts — parce qu'un refus écrit se lit comme une décision, pas comme une
 * hypothèse à revérifier.
 *
 * Ce que la purge a retiré, mesuré et non estimé : six sections
 * (`bar_carte`, `carte_restaurant`, `locations`, `tourisme`, `restauration`,
 * `hebergement`) portaient 290 clés, dont **255 que plus aucune vue ni aucun
 * composant ne lisait** — les écrans lisent désormais
 * `lang/fr/<module>_pwa.php`. Trois exemples de ce qu'elles affirmaient :
 *
 *   - `hebergement.refus_cycle` : « la colonne `unites_hebergement.statut`
 *     n'est écrite par personne » — faux depuis que `SejourService` et
 *     l'écran d'hébergement l'écrivent (check-in, check-out, nettoyage) ;
 *   - `locations.refus_ecriture`, `tourisme.refus_ecriture`,
 *     `restauration.refus_crud` : « la consultation web est en lecture seule
 *     stricte » — levé ;
 *   - `bar_carte.sous_titre` : « 1 pour 1 » — faux depuis que
 *     `cartes_boisson.unites_vendables_par_unite_stock` permet une conversion.
 *
 * C'est la QUATRIÈME occurrence documentée du motif dans ce dépôt (PA-107,
 * PA-120, PA-144, puis celle-ci). D'où la règle, qui vaut pour toute clé
 * ajoutée ici :
 *
 *   **UN REFUS SE DATE.** Écrire « X n'est pas rendu parce que Y » sans dire
 *   depuis quand, c'est transformer une décision en oubli : le jour où Y
 *   cesse d'être vrai, personne ne rouvre la question, puisque le texte
 *   affirme que c'est impossible. Datez la raison, et vérifiez-la avant de
 *   vous y fier.
 *
 * Corollaire de la même purge : une clé que plus personne ne lit est du code
 * mort qui a l'air d'une spécification. Le balayage qui l'a établie est
 * reproductible — chercher `pwa.<section>.<clé>` dans `app/`, `resources/`,
 * `tests/`, `routes/`, `config/` et `database/`.
 */

return [
    'marque' => 'TATACORA AFRIQUE',
    'baseline' => 'Consultation de secours — Gîte Chez Noël',

    // maquette — badge de la barre supérieure (shell.js, construireTopBar)
    'enseigne_courte' => 'Gîte Chez Noël',
    'alt_logo' => 'Logo TATACORA AFRIQUE',
    // maquette — mention de bas de page de login.html
    'pied_de_page' => 'TATACORA AFRIQUE © 2026 — PAEB / FAGUEZ SARL',
    // maquette — pied du menu latéral (shell.js, construireSidebar)
    'mention_pied_menu' => 'TATACORA AFRIQUE — PAEB / FAGUEZ SARL',

    // Message du 405 de `ForcerLectureSeule` : les routes /pwa sont GET-only,
    // les écritures passent par les actions des écrans, jamais par une route.
    'ecriture_refusee' => 'Les routes de la consultation web ne reçoivent aucune écriture. '
        . 'Les saisies passent par les écrans de l\'interface.',

    'connexion' => [
        // Le nom d'onglet est le <h1> de la page (BaliseTitrePwaTest, même
        // règle que les 49 autres pages), suivi de la marque.
        //
        // DÉCISION DU PRODUCT OWNER DU 13/10/2026 (PA-208, ticket D385) :
        // « LogiRestock » — nom d'un autre produit, que l'ancienne maquette
        // `login.html` portait en titre de colonne gauche — est REMPLACÉ par
        // la mention que la barre supérieure et l'en-tête des états rendent
        // déjà (`rapports.entete.localisation`, D373). Ne pas le rétablir :
        // `AucunLogiRestockAfficheTest` rougit.
        //
        // SECONDE DÉCISION DU PO DU 13/10/2026 (PA-209, ticket D389) : la
        // mention elle-même devient « Système de gestion Intégré » (casse
        // exacte du PO) ; l'ancienne formule, « Système d'Information
        // Intégré », rougit la même garde.
        'titre_page' => 'Système de gestion Intégré TATACORA AFRIQUE — TATACORA AFRIQUE',

        // Panneau image de gauche (`hidden lg:block lg:w-1/2`). Le <br> tient
        // le titre sur deux lignes à la césure voulue, quelle que soit la
        // largeur. Mêmes décisions du 13/10/2026 que `titre_page`.
        'titre_panneau' => 'Système de gestion Intégré<br>TATACORA AFRIQUE',
        // maquette — `login.html` l.20
        'accroche_panneau' => 'Hébergement, restauration, tourisme, véhicules, '
            . 'achats, stocks, comptabilité et ressources humaines — une seule '
            . 'plateforme, pour le Gîte Chez Noël à Natitingou.',
        'alt_couverture' => 'Gîte Chez Noël, Natitingou',

        // maquette — colonne de droite
        'sous_titre' => 'Connectez-vous à votre espace de travail',
        'login' => 'Identifiant',
        'exemple_login' => 'ex. n.nabogou',
        'mot_de_passe' => 'Mot de passe',
        'afficher_mot_de_passe' => 'Afficher le mot de passe',
        'masquer_mot_de_passe' => 'Masquer le mot de passe',
        'valider' => 'Se connecter',

        // La limitation de débit porte sur le couple (login + IP) : au Gîte,
        // tous les postes sortent derrière la même adresse publique, et
        // limiter par IP y bloquerait la réception entière.
        'trop_de_tentatives' => 'Trop de tentatives. Réessayez dans un instant.',

        // ⚠ La clé `mention_lecture_seule` a été RETIRÉE le 01/09/2026.
        //
        // Elle recopiait le texte du maître qui ANNONCE la grille de comptes
        // cliquables (`login.html` l.53 : « […] cliquez pour vous connecter
        // instantanément […] ») alors que la grille elle-même n'est pas
        // rendue (SECURITY_STRICT.md §12) : la phrase invitait à cliquer sur
        // des tuiles qui n'existaient pas. Doctrine `BRIEF_TRANSCRIPTION.md`
        // — « le texte qui les annonce : le garder seulement s'il reste vrai
        // sans les tuiles, sinon l'omettre » — il ne restait pas vrai, donc
        // omis. Le refus est déclaré dans `pwa.livewire.connexion`
        // (`maitre-refuse:login.html#comptes-demo`), pas ici.
    ],

    'demarrage' => [
        // maquette — `splash.html` l.28-30
        'enseigne' => 'GÎTE CHEZ NOËL — AGENCE DE VOYAGES & HÉBERGEMENT',
        // ⚠ La clé `localisation` (« Natitingou, Bénin — LogiRestock ») a été
        // RETIRÉE le 13/10/2026 (décision du Product Owner, PA-208, ticket
        // D385) : la vue rend désormais `rapports.entete.localisation`
        // (« Natitingou, Bénin — Système de gestion Intégré » depuis PA-209), la même
        // clé que la barre supérieure (D373) et l'en-tête des états. Une clé
        // dédiée de même valeur divergerait à la première retouche.
        'cadre' => 'Réalisé dans le cadre du',
        'programme' => 'Projet d\'Appui à l\'Entrepreneuriat au Bénin',

        // maquette — `splash.html` l.50-56, les CINQ étapes dans l'ordre.
        // Le minutage est celui de la maquette : les raccourcir ferait défiler
        // le texte plus vite que la barre, et l'écran paraîtrait saccadé.
        'etapes' => [
            'Initialisation du système...',
            'Chargement de la charte graphique...',
            'Connexion au socle applicatif...',
            'Vérification de la session utilisateur...',
            'Prêt.',
        ],
    ],

    /*
     * ATTENTION : le titre de cette page ne doit reprendre le libelle
     * d\'AUCUN module. Un role sans droit sur M11 lirait « Tableau de
     * bord » en en-tete alors que l\'entree lui est masquee — et croirait
     * a une fuite de droits.  le verifie.
     */
    'accueil' => [
        'titre' => 'Consultation de secours',
        'sous_titre' => 'Consultation de secours — les écrans auxquels votre '
            . 'rôle donne accès.',

        // Un écran qui ne rend jamais rien passe pour cassé : on dit POURQUOI
        // la liste est vide plutôt que de laisser une page blanche.
        'aucun_ecran' => 'Votre rôle ne donne accès à aucun écran de '
            . 'consultation. Ce n\'est pas une panne : la liste suit vos droits.',

        'lecture_seule' => 'Lecture seule',
        'acces_complet' => 'Accès complet dans l\'application',

        // Une entrée sans écran servi est rendue INERTE, jamais liée : un lien
        // mort promettrait une page qui n'existe pas. Ce n'est PAS un état
        // final — Article 3.3 : la réponse est de livrer l'écran, et ces
        // cartes sont le backlog visible.
        'ecran_a_venir' => 'Écran de consultation à venir',

        // Et son pendant, pour un écran réellement servi.
        'ouvrir_ecran' => 'Ouvrir l\'écran →',

        'deconnexion' => 'Déconnexion',
        // Les clés `bandeau_titre`/`bandeau_detail` (« Cette interface web
        // sert à consulter… ») ont été RETIRÉES le 28/08/2026 : le bandeau
        // permanent mentait dès la première écriture. Ses remplaçants,
        // conditionnés au droit réel, vivent sous `coquille.banniere_*`.
    ],

    /*
     * Les SEPT écrans de consultation de la liste fermée
     * `Accueil::ECRANS_AUTORISES` — six de `LARAVEL_PWA.md` §2, plus M10
     * ajouté le 27/08/2026 (voir la constante, qui porte la motivation).
     *
     * **Libellés et descriptions repris de `LARAVEL_PWA.md` §2**, qui fait foi.
     * Les reformuler est un écart : ce sont les intitulés que les tests
     * attestent, et ceux que le client a validés.
     *
     * Un module ajouté à cette liste sans entrée ici afficherait sa clé brute
     * (« pwa.ecrans.M7.libelle ») à l'écran. Les deux listes se tiennent donc
     * la main : ajouter un module, c'est ajouter son libellé.
     *
     * Les descriptions disent ce qu'on VIENT y chercher, pas ce que le module
     * fait : la PWA est une consultation de secours, on l'ouvre avec une
     * question précise.
     */
    'ecrans' => [
        'M11' => [
            'libelle' => 'Tableau de bord',
            'description' => 'Les indicateurs consolidés de l\'exploitation.',
        ],
        'M1' => [
            'libelle' => 'Planning d\'occupation',
            'description' => 'Vérification rapide de disponibilité sans passer par un poste.',
        ],
        'M6' => [
            'libelle' => 'État des stocks',
            'description' => 'Consultation d\'urgence, avant un déplacement d\'achat impromptu.',
        ],
        'M2' => [
            'libelle' => 'Journal de caisse',
            'description' => 'Mouvements et clôtures de caisse, pour le Comptable et le Gérant.',
        ],
        'M3' => [
            'libelle' => 'Fiches clients',
            'description' => 'Consultation rapide de l\'historique d\'un client.',
        ],
        'M14' => [
            'libelle' => 'États & rapports',
            'description' => 'Génération et export d\'états — seule exception à la lecture stricte.',
        ],

        /*
         * M10 n'est PAS dans la table de `LARAVEL_PWA.md` §2 : c'est une
         * extension du périmètre décidée le 27/08/2026, motivée dans
         * `Accueil::ECRANS_AUTORISES`. Le libellé reprend celui de l'entrée de
         * menu du maître (`shell.js`, groupe « Finance ») plutôt que d'en
         * inventer un septième.
         */
        'M10' => [
            'libelle' => 'Comptabilité',
            'description' => 'Journal, grand livre, balance et états financiers SYSCOHADA — en consultation.',
        ],
    ],

    // Cloche — alertes d'ouverture DÉRIVÉES (audit PO du 01/09/2026).
    // Chaque alerte est recalculée des tables opérationnelles à la lecture,
    // jamais stockée (PA-59/60/61) ; voir App\Pwa\Support\AlertesOuverture.
    'cloche' => [
        'tout_marquer_lu' => 'Tout marquer comme lu',
        'aucune_non_lue' => 'Aucune notification non lue.',
        'rupture_titre' => 'Rupture de stock',
        'rupture_detail' => ':article — stock épuisé (:stock).',
        'seuil_titre' => 'Stock sous seuil',
        'seuil_detail' => ':article — :stock en stock (seuil :seuil).',
        'caisse_titre' => 'Clôture de caisse en attente',
        'caisse_detail' => 'La session :point ouverte le :date n\'est pas clôturée.',
        'arrivee_titre' => 'Arrivée attendue aujourd\'hui',
        'arrivee_detail' => ':client — le check-in n\'est pas enregistré.',
        'creance_titre' => 'Créance à relancer',
        'creance_detail' => ':client — :montant restant dus depuis le :date.',
        'client_inconnu' => 'Client inconnu',
    ],

    // Les DEUX modales d'ouverture de session — maître :
    // `prototype_v2/assets/js/alertes-ouverture.js` (vérifiées manquantes par
    // le PO le 02/09/2026). Mots du maître au plus près du serveur.
    'alertes_ouverture' => [
        'titre_stock' => 'Stock critique',
        'sous_titre_stock' => 'Articles au niveau ou sous leur seuil de réapprovisionnement. Les lignes en rouge sont déjà en rupture.',
        'titre_operations' => 'Opérations du jour à traiter',
        'sous_titre_operations' => 'Départs arrivés à échéance et créances à relancer. Rien n’est bloquant, mais tout se dégrade si personne ne le voit.',

        'bloc_stock_titre' => 'Articles à réapprovisionner',
        'bloc_stock_sous_titre' => 'Relevé à l’ouverture de votre session',
        'stock_detail' => 'Stock :stock :unite — seuil d’alerte :seuil',
        'lien_stocks' => 'Ouvrir les stocks',

        'bloc_departs_titre' => 'Réservations arrivées à échéance',
        'bloc_departs_sous_titre' => 'Départ du jour, ou départ dépassé sans check-out (en rouge)',
        'depart_depasse' => 'Départ prévu le :date — check-out non effectué',
        'depart_aujourdhui' => 'Départ aujourd’hui',
        'lien_reservations' => 'Ouvrir les réservations',
        'checkout' => 'Check-out',
        'fait' => 'Fait',
        'sejour_introuvable' => 'Ce séjour n’existe plus : rien n’a été modifié.',

        'bloc_creances_titre' => 'Créances à relancer',
        'bloc_creances_sous_titre' => 'Sommes échues de plus de 30 jours — en rouge, au-delà de 90 jours',
        'creance_detail' => ':montant restant dus · :jours j d’ancienneté',
        'jamais_relance' => ' · jamais relancé',
        'relance_le' => ' · relancé le :date',
        'lien_creances' => 'Ouvrir les créances',
        'relancer' => 'Relancer',
        'tracee' => 'Tracée',
        'relance_recente' => 'relance récente',
        'relance_indisponible' => 'Cette créance n’est pas relançable pour le moment.',
        'relance_commentaire' => 'Relance déclenchée depuis les alertes d’ouverture de session',
        'canal_telephone' => 'Appel téléphonique',
        'canal_whatsapp' => 'WhatsApp',
        'canal_email' => 'E-mail',
        'canal_courrier' => 'Courrier',
        'canal_visite' => 'Visite',

        'suivant' => 'Suivant →',
        'pris_connaissance' => 'J’ai pris connaissance',
        'droit_manquant' => 'Votre rôle ne permet pas ce geste depuis les alertes d’ouverture.',
        'et_autres' => '… et :nombre autre(s).',
    ],

    // Recherche globale — AJOUT à la maquette (audit PO du 01/09/2026).
    // Pagination du maître (`crud-engine.js` `renderPagination`) — un seul
    // auteur pour toutes les listes paginées (02/09/2026).
    'pagination' => [
        'navigation' => 'Pagination',
        'precedent' => '← Précédent',
        'page_sur' => 'Page :page / :pages',
        'suivant' => 'Suivant →',
    ],

    'recherche_globale' => [
        'invite' => 'Rechercher partout…',
        'trop_court' => 'Saisissez au moins deux caractères.',
        'aucun' => 'Aucun résultat pour cette recherche.',
        'famille_pages' => 'Pages',
        'famille_clients' => 'Clients',
        'famille_articles' => 'Articles en stock',
        'famille_plats' => 'Plats',
        'famille_carte_bar' => 'Carte du bar',
        'famille_factures' => 'Factures',
        'famille_fournisseurs' => 'Fournisseurs',
        'famille_vehicules' => 'Véhicules',
        'famille_circuits' => 'Circuits',
    ],

    'coquille' => [
        // maquette — `shell.js` l.100, attribut `aria-label`
        'ouvrir_menu' => 'Ouvrir le menu',
        // Bascule plein ecran (directive PO du 02/09/2026) : masque ou
        // raffiche le menu lateral sur grand ecran. Absente du maitre —
        // ajout decide, declare a la garde des traces.
        'plein_ecran' => 'Masquer ou afficher le menu latéral (vue plein écran)',

        /*
         * ÉCART DÉLIBÉRÉ — `prototype_v2/assets/js/shell.js` l.116
         * Le maître : « Réseau Synchronisé », badge vert de la barre supérieure.
         * Ici : « Réseau ».
         * Raison : élément décoratif au maître — la PWA n'a AUCUNE file de
         * synchronisation, c'est le client Flutter qui en tient une. Un badge
         * affirmant une synchronisation que rien ne vérifie est le défaut exact
         * de PA-59/60/61. Le mot restant ne dit que ce qui est établi : la page
         * vient d'être servie par le réseau.
         */
        // Sélecteur d'exercice global (PO, 20/10/2026, SPEC_SELECTEUR_EXERCICE).
        'exercice_consulte' => 'Exercice',
        'exercice_option' => ':annee — :statut',
        'exercice_statuts' => ['ouvert' => 'ouvert', 'en_cloture' => 'en clôture', 'cloture' => 'clôturé'],
        'exercice_pastille' => 'Vous consultez :annee (:statut)',
        'exercice_revenir' => 'Revenir à :annee',
        'exercice_portee' => 'Exercice :annee (:statut)',
        'reseau' => 'Réseau',

        // maquette — `shell.js` l.126. La capitale d'« Audit » est celle du
        // maître : un libellé recasse est un écart au même titre qu'un
        // synonyme (DIRECTIVE_CONFORMITE_100.md Article 1, interdit n° 05).
        'journal_audit' => 'Journal d\'Audit',
        // Décision PO du 18/10/2026 : le bouton « Synchroniser » du serveur.
        'synchronisation_postes' => 'Synchroniser les postes',

        // maquette — `shell.js` l.135
        'notifications' => 'Notifications',

        /*
         * ÉCART DÉLIBÉRÉ — `prototype_v2/assets/js/shell.js` l.339
         * Le maître : « Aucune notification  . » — le gabarit intercale un
         * fragment vide quand le filtre vaut « toutes », ce qui laisse une
         * espace avant le point.
         * Ici : « Aucune notification. »
         * Raison : bug de maquette. L'espace orpheline ne se recopie pas ;
         * la phrase, elle, garde sa ponctuation.
         */
        'aucune_notification' => 'Aucune notification.',

        // maquette — `shell.js` l.139-140
        'filtre_toutes' => 'Toutes',
        'filtre_non_lues' => 'Non lues',
        // maquette — `shell.js` l.136
        // « Vente » — directive PO du 02/09/2026 (le maître écrit « Point
        // de vente », l'écart est décidé et déclaré à la garde du châssis).
        'vente' => 'Vente',
        'vente_titre' => 'Vente — encaisser une consommation sans réservation',
        'caisse_fermee' => 'Caisse fermée',
        'caisse_cloturer' => 'Clôturer la caisse',
        'caisse_cloturer_titre' => 'Clôturer la caisse du :point',
        'tout_marquer_lu' => 'Tout marquer comme lu',
        // maquette — `shell.js` l.144. La flèche fait partie du libellé validé.
        'voir_notifications' => 'Voir toutes les notifications →',
        'changer_profil' => 'Changer de profil',

        /*
         * Le bandeau de la coquille (`#shell-banniere`), conditionné au droit
         * réel — lot 0.6, voir `App\Pwa\Support\BanniereEcriture` et le
         * partial `banniere-lecture-seule.blade.php`.
         *
         * maquette — `shell.js` l.244 pour l'état lecture seule ; l'écart sur
         * la fin de phrase (« les actions d'écriture » au lieu des trois
         * boutons nommés) est motivé dans le partial. L'état « non ouvert »
         * n'a pas d'équivalent au maître, qui offre le CRUD partout : il dit
         * un manque transitoire de CE canal, jamais un état final.
         */
        'banniere_lecture_titre' => 'Accès lecture seule',
        'banniere_lecture_detail' => 'sur ce module avec le profil actuel — les actions d\'écriture '
            . 'sont masquées (droits RBAC).',
        // maquette — `shell.js` l.247. La flèche fait partie du libellé.
        'banniere_changer_profil' => 'Se connecter avec un autre profil →',
        // maquette — les CINQ entrées du menu de profil (`shell.js`
        // l.162-181), dans l'ordre. Elles manquaient toutes sauf une, avec
        // leurs deux séparateurs : le menu servi n'en portait que deux
        // lignes sur sept (PA-143).
        'mon_profil' => 'Mon profil',
        'parametres_compte' => 'Paramètres du compte',
        'import_export' => 'Import & Export',
        'aide_a_propos' => 'Aide & À propos',
        'contact_editeur' => 'Contactez l\'éditeur',

        /*
         * Deux raisons DISTINCTES pour une entrée inerte, et les confondre
         * ferait chercher un droit là où il manque un écran.
         *
         * Depuis le 26/08/2026, `DIRECTIVE_CONFORMITE_100.md` Article 3.3
         * tranche qu'« un lien de menu qui ne navigue pas est un défaut, pas
         * une décoration ». Ces deux titres ne sont donc PAS un état final :
         *
         *  - « à venir » nomme un manque INSCRIT AU BACKLOG. La directive
         *    précise que la conséquence n'est pas de supprimer l'entrée, mais
         *    de livrer l'écran. Aucune route `/pwa` ne sert d'écran de données
         *    à ce jour (`routes/web.php` n'en déclare que quatre : démarrage,
         *    hors-connexion, connexion, accueil) — c'est ce qui bloque le
         *    câblage, pas un choix de gabarit.
         *  - « hors périmètre » nomme un refus DÉFINITIF, et il n'ira jamais
         *    au backlog : Import & Export est une ÉCRITURE, que le canal en
         *    lecture seule stricte refuse structurellement.
         *
         * ⚠ La parenthèse ci-dessus — « aucune route /pwa ne sert d'écran de
         * données » — était vraie le 26/08/2026 et NE L'EST PLUS depuis le
         * 27 : les douze pages M10 sont servies. Elle est conservée parce
         * qu'elle explique encore les 23 autres entrées, mais elle est datée :
         * lisez `routes/web.php`, pas ce commentaire (PA-144).
         */
        'ecran_a_venir' => 'Écran de consultation à venir',
        'hors_perimetre' => 'Hors du périmètre de la consultation web',
        // TROISIÈME raison d'inertie, apparue le 27/08/2026 avec les premiers
        // écrans transverses derrière un contrôle de module. Les trois se
        // distinguent, et les confondre coûte cher : « à venir » fait attendre
        // une livraison, « hors périmètre » ferme la question, « sans droit »
        // désigne un écran qui EXISTE et un accès à demander.
        'sans_droit' => 'Votre profil n\'a pas accès à cet écran',
    ],

    'hors_connexion' => [
        // PA-185 (11/09/2026) : l'onglet dit le titre de la page, comme sur
        // tout écran de la PWA (`BaliseTitrePwaTest`). « Hors connexion » était
        // un second nom pour la même page ; le <h1> dit ce qui manque, c'est
        // lui qui fait foi.
        'titre_page' => 'Connexion Internet requise — TATACORA AFRIQUE',
        'titre' => 'Connexion Internet requise',

        // Aucun équivalent au maître : la page n'existe que pour la PWA, qui
        // est servie par le réseau. Elle DIT ce qui manque plutôt que
        // d'afficher une erreur de navigateur.
        'explication' => 'Cette interface de consultation est servie par le '
            . 'serveur : sans réseau, elle n\'a rien à afficher.',
        'orientation' => 'L\'application TATACORA, elle, fonctionne hors '
            . 'connexion : les saisies du comptoir y sont conservées et '
            . 'repartent seules au retour du réseau.',

        // Directive PO du 02/09/2026 : la page porte le geste de reprise —
        // reessayer, ou aller se connecter — et une variante quand une
        // session etait ouverte sur ce poste. La variante ne montre AUCUN
        // formulaire de mot de passe : hors reseau, rien ne peut le
        // verifier, et un champ qui ne verifie rien serait l'indicateur
        // PA-59/60/61. Le formulaire de deverrouillage reel (VerrouSession)
        // s'affiche de lui-meme au rechargement si la session s'est
        // verrouillee entre-temps.
        'reessayer' => 'Réessayer',
        'se_connecter' => 'Se connecter',
        'session_titre' => 'Session interrompue par la perte du réseau',
        'session_explication' => 'Votre session reste ouverte sur ce poste. '
            . 'Rétablissez le réseau puis réessayez : si la session s\'est '
            . 'verrouillée entre-temps, le formulaire de déverrouillage '
            . 's\'affichera.',
    ],

    /*
     * Page d'erreur 404 (`resources/views/errors/404.blade.php`).
     *
     * Aucun équivalent au maître : `prototype_v2/` ne maquette pas d'écran
     * d'erreur. Habillée aux couleurs de la coquille (navy/gold, logo,
     * `assets/css/app.css`) plutôt que la page blanche par défaut de Laravel,
     * qui ne dit ni où l'on est ni où revenir — et qui, servie par le même
     * serveur mutualisé cPanel que le reste de l'application, ne doit
     * charger aucune ressource distante (`DIRECTIVE_CONFORMITE_100.md`).
     */
    'erreur_404' => [
        'titre_page' => 'Page introuvable — TATACORA AFRIQUE',
        'titre' => 'Page introuvable',
        'explication' => 'Cette adresse ne correspond à aucune page de TATACORA AFRIQUE : elle a peut-être '
            . 'été déplacée, ou son lien était incorrect.',
        'retour' => 'Retour au tableau de bord',
    ],

    /*
     |--------------------------------------------------------------------------
     | M10 — Comptabilité SYSCOHADA révisé, en CONSULTATION
     |--------------------------------------------------------------------------
     |
     | Les libellés que le maître pose sont écrits DANS les vues, comme partout
     | ailleurs dans cette coquille : ce sont ceux que le client a validés des
     | yeux, et les recopier dans un second fichier les ferait diverger. Ne
     | vivent ici que les textes qui n'ont PAS d'équivalent au maître — les
     | refus nommés (Article 8) et la traduction des registres fermés de codes
     | que le serveur renvoie.
     |
     | Un code de motif affiché brut (`report_a_nouveau_absent`) serait
     | illisible ; un motif TU serait pire — c'est le défaut PA-59/60/61. La
     | traduction est donc obligatoire, et un code inconnu se voit : Laravel
     | rend la clé elle-même, ce qui signale le motif manquant au lieu de le
     | masquer.
     */
    'comptabilite' => [
        /*
         * ⚠ UNE CLÉ SANS AUCUN APPELANT FAISAIT POURTANT UN TRAVAIL (02/09/2026).
         *
         * Six clés de refus de cette section ont été retirées le 02/09/2026 :
         * `refus_saisie`, `refus_immobilisations`, `refus_filtres`,
         * `refus_export`, `refus_creation_compte`, `action_non_exposee`. Zéro
         * appelant applicatif, mesuré par `grep` — donc mortes, à première vue.
         *
         * Elles ne l'étaient pas toutes. `refus_saisie` portait, dans son
         * texte, le libellé du maître « Passer écriture » — et c'était le SEUL
         * endroit du dépôt où il apparaissait. Le comparateur des trois
         * sources cherche chaque libellé du maître dans le code concaténé
         * (vues + `app/Pwa` + `lang/fr`) : la supprimer a fait tomber deux
         * écarts sur `m10-syscohada.html`, un pour le bouton, un pour l'onglet.
         *
         * **La leçon vaut au-delà de ce fichier** : « zéro appelant » se
         * mesure sur les appels `__()`, et le comparateur, lui, lit le TEXTE.
         * Une chaîne peut donc être morte pour l'application et vivante pour
         * la garde. Le remplacement correct n'est pas de restaurer la clé —
         * elle n'était rendue nulle part — mais de DÉCLARER le refus, ce qui
         * le rend visible à chaque exécution au lieu de dépendre d'un texte
         * que personne n'affiche.
         *
         * L'onglet « Passer écriture » du maître (`m10-syscohada.html` l.51)
         * n'est pas porté : la saisie manuelle d'une pièce n'est pas exposée à
         * l'écran. Les écritures naissent des gestes métier — une dépense, une
         * vente — qui passent leur pièce par `PasserEcritureService` dans la
         * même transaction que le mouvement d'argent (règle du 31/08/2026).
         * Offrir une saisie libre à côté ouvrirait un second chemin vers un
         * registre immuable (RG-11), sans le mouvement qui le justifie.
         *
         *   maitre-refuse:m10-syscohada.html#saisie
         */

        // --- Le socle commun aux douze pages -------------------------------
        'exercice' => 'Exercice',
        'exercice_choisir' => 'Choisir un exercice',
        'aucun_exercice_titre' => 'Aucun exercice comptable n\'est sélectionné',

        // Article 7 : un écran vide dit POURQUOI il est vide et CE QU'IL FAUT
        // FAIRE. La raison n'est pas une limitation technique, c'est une règle
        // comptable — et l'écran l'énonce plutôt que de choisir à la place de
        // l'utilisateur.
        'aucun_exercice_detail' => 'Tout état de comptabilité se lit dans le '
            . 'cadre d\'un exercice : un état « toutes années confondues » '
            . 'n\'aurait pas de sens comptable. Choisissez l\'exercice à '
            . 'consulter.',
        'aucun_exercice_ouvert' => 'Aucun exercice comptable n\'a encore été '
            . 'ouvert. Cela se fait depuis l\'application TATACORA.',

        // La ligne unique d'un panneau d'onglet NON ouvert du hub (squelette,
        // 02/09/2026) : le tableau montre sa structure, la ligne dit que les
        // chiffres seront calculés à l'ouverture de l'onglet — jamais des
        // montants qu'aucun Service n'a produits.
        'onglet_non_ouvert' => 'Les chiffres de cet onglet sont calculés à son ouverture.',

        'statut_ecritures' => 'Écritures retenues',
        'statut_toutes' => 'Toutes',

        // Barre de filtres du Hub — clés posées le 02/09/2026 (passage
        // navigateur : quatre libellés étaient écrits en dur dans la vue).
        'filtre_journal' => 'Journal',
        'filtre_tous_journaux' => 'Tous les journaux',
        'filtre_brouillons' => 'Inclure les brouillons',
        'filtre_reinitialiser' => 'Réinitialiser',
        'titre_hub' => 'Comptabilité — SYSCOHADA révisé',
        'pilotage_intro' => 'Pilotage financier SYSCOHADA — plan comptable, journal, bilan, clôture et analytique.',
        'desequilibre_titre' => 'Comptabilité déséquilibrée.',
        'statut_brouillon' => 'Brouillons seuls',
        'statut_validee' => 'Validées seules',
        'repartition' => ':validee validée(s) · :brouillon brouillon(s)',

        'retour_hub' => 'Retour au Hub Comptabilité',
        'lecture_seule' => 'Consultation — cet écran ne modifie rien.',

        // maquette — `m10-syscohada.html` l.47-48. « Excel » seul, sur
        // l'onglet Journal — porté le 01/09/2026 (audit navigateur), voir le
        // docblock de `Hub::exporterExcel()`.
        'excel' => 'Excel',
        'export_onglet_refuse' => 'L\'export Excel n\'est offert que sur l\'onglet Journal.',
        'export_vide' => 'Rien à exporter : aucune écriture ne correspond aux filtres affichés.',

        // --- Les refus nommés (Article 8) ----------------------------------
        'refus_titre' => 'Ce que cet écran ne fait pas, et pourquoi',
        'refus_actions_cloture' => 'Ouvrir un exercice, clôturer une période '
            . 'ou clôturer l\'exercice sont des écritures. Cet écran en montre '
            . 'l\'ÉTAT ; il ne déclenche rien, et le serveur ne l\'expose pas.',

        // --- Ce que le serveur signale et qu'il faut dire -------------------
        'hors_ecran_titre' => 'Comptes hors des sept classes affichées',
        'hors_ecran_detail' => 'Le schéma admet les classes 8 (hors activités '
            . 'ordinaires) et 9 (analytique), que cet écran n\'a aucun bouton '
            . 'pour atteindre. Les taire rendrait ces comptes invisibles sous '
            . 'un plan qui aurait l\'air complet.',
        'sans_nature' => ':nombre compte(s) sans nature renseignée — la '
            . 'colonne affiche « — », qui n\'est pas une nature.',

        'solde_ouverture_inconnu' => 'Solde d\'ouverture inconnu, jamais zéro : '
            . 'aucun report à nouveau n\'existe encore. Le solde progressif '
            . 'part donc des seuls mouvements de l\'exercice.',

        'comptes_hors_rubrique_titre' => 'Comptes mouvementés hors nomenclature',
        'comptes_hors_rubrique_detail' => 'Leur solde n\'apparaît ni au Bilan '
            . 'ni au Compte de résultat. Sans cette liste, ils ne produiraient '
            . 'qu\'un déséquilibre inexplicable.',

        'structure_non_repartie' => 'Aucune charge de structure n\'est '
            . 'répartie : les montants ci-dessous sont des marges sur coûts '
            . 'directs, pas des résultats nets. Une clé de répartition est une '
            . 'décision de gestion, pas une constante technique.',

        'resultat_avant_impot' => 'Résultat affiché avant Impôt sur les '
            . 'Sociétés : aucun impôt n\'est comptabilisé en classe 89 sur cet '
            . 'exercice. Le montant est celui qui a été enregistré, jamais un '
            . 'taux appliqué.',

        'limites_titre' => 'Ce que ce contrôle ne peut pas vérifier',

        // --- Registres FERMÉS de codes rendus par le serveur ---------------
        //
        // Un code ajouté au serveur sans traduction ici affiche sa clé, ce qui
        // le signale. C'est délibéré : l'inverse — un `??` silencieux — le
        // ferait disparaître.
        'motifs' => [
            'report_a_nouveau_absent' => 'Aucun mécanisme de report à nouveau n\'existe.',
            'detail_physique_hors_domaine_m10' => 'Le détail physique relève des stocks (M6), hors de la comptabilité.',
            'effectif_hors_domaine_m10' => 'L\'effectif relève des ressources humaines (M13), hors de la comptabilité.',
            'non_saisi_par_le_comptable' => 'Rubrique en texte libre : rien n\'a encore été saisi.',
            'lettrage_par_anciennete_non_arbitre' => 'Le lettrage par ancienneté (30/60/90 jours) n\'est pas arbitré.',
            'impot_non_comptabilise' => 'Aucun impôt sur le résultat n\'est comptabilisé en classe 89.',
            'charges_de_structure_non_reparties' => 'Les charges de structure ne sont pas réparties entre les centres.',
            'inventaire_physique_hors_domaine_m10' => 'L\'inventaire physique relève des stocks (M6), hors de la comptabilité.',
            'action_de_cloture_non_exposee' => 'L\'action de clôture n\'est exposée par aucune route du serveur.',
            'depend_d_une_etape_non_atteinte' => 'Dépend d\'une étape précédente qui n\'est pas atteinte.',
            'cloture_non_demarree' => 'La clôture n\'est pas démarrée (onglet « Clôtures » de la comptabilité).',
            'cloture_non_passee' => 'La clôture définitive n\'est pas encore passée.',
            'journal_a_nouveaux_absent' => 'Les journaux de clôture (CL) et d\'à-nouveaux (AN) ne sont pas tous deux au référentiel.',
            'comptes_de_resultat_absents' => 'Les comptes 131 et 139 ne sont pas tous deux au plan comptable.',
            'centre_de_cloture_absent' => 'Le centre de coût qui porte les écritures de clôture est absent.',
            'ecritures_en_brouillon' => 'Des écritures restent en brouillon.',
            'balance_desequilibree' => 'La balance générale n\'est pas équilibrée.',
            'bilan_desequilibre' => 'Le bilan n\'est pas équilibré.',
            'releves_bancaires_non_rapproches' => 'Des relevés bancaires ne sont pas rapprochés.',
            // Article 8 (02/09/2026) : la reference PA-28 vit ici, jamais a l'ecran.
            'perimetre_cloture_non_arbitre' => 'Le périmètre de la clôture — mensuelle ou annuelle — n\'est pas arbitré.',
        ],

        'etats' => [
            'conforme' => 'Conforme',
            'bloque' => 'Bloqué',
            'non_verifiable' => 'Non vérifiable',
            'non_atteint' => 'Non atteint',
        ],

        'note_etats' => [
            'disponible' => 'Disponible',
            'indisponible' => 'Indisponible',
            'non_saisie' => 'Non saisie',
        ],
    ],

    /*
     * Aide & À propos — `prototype_v2/pages/aide-a-propos.html`.
     *
     * Tout ce bloc est du COPYWRITING DU MAÎTRE, repris mot pour mot : c'est le
     * texte que le client a vu et approuvé. Un synonyme est un écart de gabarit
     * (Article 1, interdit n° 05). Ne reformulez rien ici sans rouvrir la page
     * du maître à côté.
     */
    'aide' => [
        'titre_page' => 'Aide & À propos — TATACORA AFRIQUE',
        // maquette — l.24-26
        'titre' => 'Aide & À propos',
        'sous_titre' => 'Documentation complète, guide des modules et foire aux questions.',

        // maquette — l.29-70, la présentation du logiciel
        // DÉCISION DU PRODUCT OWNER DU 13/10/2026 (PA-208, ticket D385) :
        // « LogiRestock » (nom d'un autre produit) est remplacé, comme sur la
        // barre supérieure (D373). Seconde décision du PO du même jour
        // (PA-209, D389) : la mention est « Système de gestion Intégré »,
        // casse exacte du PO.
        'enseigne' => 'Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)',
        'presentation_1' => 'TATACORA AFRIQUE réunit en une seule application les quatorze métiers du Gîte : '
            . 'l\'hébergement et les réservations, la restauration et le bar, les stocks et les achats, le '
            . 'tourisme et la location de véhicules, la comptabilité SYSCOHADA révisé, la paie et le pilotage.',
        'presentation_2_avant' => 'L\'ensemble est conçu ',
        'presentation_2_fort' => 'hors connexion d\'abord',
        'presentation_2_apres' => ' : la saisie fonctionne sans réseau et se synchronise au retour de la '
            . 'liaison. C\'est une contrainte du terrain à Natitingou, pas une option de confort — une '
            . 'réservation prise pendant une coupure ne doit pas être perdue, et un guide en circuit de '
            . 'plusieurs jours travaille sans couverture.',

        'version_titre' => 'Version du prototype',
        // ÉCART Article 8 — voir le bloc de `AideAPropos` : la version du
        // maître désigne le prototype, pas la PWA.
        'version_valeur' => 'Maquette de référence v2.0 — 18/08/2026',
        'moe_titre' => 'Maîtrise d\'œuvre',
        'moe_valeur' => 'Cabinet FAGUEZ SARL / PAEB',
        'po_titre' => 'Product Owner',
        'po_valeur' => 'Mr NABOGOU Winribasse Noël',
        'referentiel_titre' => 'Référentiel comptable',
        'referentiel_valeur' => 'SYSCOHADA révisé (AUDCIF)',

        // maquette — l.73-87, les modules
        'modules_titre' => 'Modules du logiciel',
        'modules_sous_titre' => 'Quatorze modules, plus l\'administration. Cliquez sur une carte pour ouvrir le module.',
        'modules_compteur' => ':accessibles module(s) accessible(s) sur :total avec votre profil',
        'modules_note' => 'Les modules sur lesquels votre profil n\'a aucun droit sont affichés en grisé et ne '
            . 'sont pas cliquables. Ils restent visibles ici — savoir qu\'un module existe n\'est pas y accéder, '
            . 'et masquer la carte laisserait croire à une application incomplète.',
        'badge_lecture' => 'LECTURE',
        'badge_sans_acces' => 'SANS ACCÈS',
        'sans_acces_titre' => 'Votre profil n\'a pas accès à ce module',
        // Article 3.3 : une carte sans écran servi ne navigue pas, et le dit.
        'module_ecran_a_venir' => 'Écran de consultation à venir dans la PWA',

        // maquette — l.183-215, les seize cartes. Ordre et mots du maître.
        'modules' => [
            'M1' => [
                'nom' => 'Hébergement & Réservations',
                'description' => 'Unités, disponibilités, séjours et check-in. Contrôle de chevauchement : deux '
                    . 'réservations ne peuvent pas occuper la même chambre aux mêmes dates.',
            ],
            'M2' => [
                'nom' => 'Facturation',
                'description' => 'Factures normalisées MECeF, avoirs et suivi de certification DGI. Une facture '
                    . 'validée ne se modifie pas : elle se corrige par avoir.',
            ],
            'M3' => [
                'nom' => 'Clients & Créances',
                'description' => 'Fiche client unique et balance âgée. Le solde est calculé depuis les pièces, '
                    . 'jamais saisi à la main.',
            ],
            'M4' => [
                'nom' => 'Restaurant',
                'description' => 'Carte, fiches techniques et disponibilité des plats. Un plat sans fiche '
                    . 'technique ne décrémente aucun stock, et c\'est signalé.',
            ],
            'M5' => [
                'nom' => 'Bar & Point de vente',
                'description' => 'Carte des boissons et encaissement au POS. La vente d\'une boisson sort '
                    . 'l\'article du stock au coût moyen pondéré.',
            ],
            'M6' => [
                'nom' => 'Stocks',
                'description' => 'Articles, mouvements, inventaires et seuils d\'alerte. Valorisation au coût '
                    . 'moyen pondéré, recalculée à chaque entrée.',
            ],
            'M7' => [
                'nom' => 'Achats & Fournisseurs',
                'description' => 'Commandes, réceptions et fournisseurs. La réception d\'une commande alimente '
                    . 'le stock et la comptabilité.',
            ],
            'M8' => [
                'nom' => 'Véhicules & Locations',
                'description' => 'Parc, contrats de location, entretiens et disponibilité. Un véhicule loué ou '
                    . 'en entretien n\'est pas proposé ailleurs.',
            ],
            'M9' => [
                'nom' => 'Tourisme',
                'description' => 'Circuits, départs, guides et capacités. La capacité se contrôle cumulée sur le '
                    . 'départ, pas réservation par réservation.',
            ],
            'M10' => [
                'nom' => 'Comptabilité SYSCOHADA',
                'description' => 'Plan comptable, journal, grand livre, balance, compte de résultat et bilan. '
                    . 'Une écriture validée se corrige par contre-passation.',
            ],
            'M11' => [
                'nom' => 'Tableau de bord',
                'description' => 'Indicateurs consolidés de toute l\'exploitation. Les intitulés disent ce qui '
                    . 'est réellement calculé — « encaissé », pas « payé ».',
            ],
            'M12' => [
                'nom' => 'Notifications',
                'description' => 'Modèles de messages WhatsApp, e-mail et Android, et leurs déclencheurs. '
                    . 'L\'envoi effectif dépend d\'une API non encore contractée.',
            ],
            'M13' => [
                'nom' => 'Personnel & Paie',
                'description' => 'Employés, planning, congés et bulletins. CNSS, ITS et VPS calculés ; la part '
                    . 'de charge patronale non confirmée est refusée, pas estimée.',
            ],
            'M14' => [
                'nom' => 'États & Rapports',
                'description' => 'Catalogue d\'états exportables en PDF et CSV, avec en-tête normalisée unique. '
                    . 'Le droit d\'éditer un état suit son module source.',
            ],
            'ROLES' => [
                'nom' => 'Rôles & Permissions',
                'description' => 'Matrice des droits par module et par rôle. Trois niveaux : masquage de '
                    . 'l\'interface, contrôle serveur, filtrage en base.',
            ],
            'PARAM' => [
                'nom' => 'Paramètres & Import/Export',
                'description' => 'Identité de l\'entreprise, canaux de communication, activation des actions '
                    . 'sensibles, sauvegardes et restauration.',
            ],
        ],

        // maquette — l.89-108, la foire aux questions
        'faq_titre' => 'Foire aux questions',
        'faq_sous_titre' => 'Les questions qui reviennent le plus souvent en formation et en exploitation.',
        'faq_recherche' => 'Rechercher dans l\'aide…',
        'faq_vide' => 'Aucune réponse ne correspond à cette recherche.',

        // maquette — l.217-244, les douze entrées, dans son ordre.
        'faq' => [
            [
                'categorie' => 'Prise en main',
                'question' => 'Je ne vois pas un module dans le menu — est-ce une erreur ?',
                'reponse' => 'Non. Le menu est filtré par votre rôle : un module sur lequel vous n\'avez aucun '
                    . 'droit est retiré, pas grisé. Un élément grisé invite à cliquer et ne produit qu\'un refus. '
                    . 'Pour savoir ce que couvre chaque profil, ouvrez Rôles & Permissions ; pour obtenir un '
                    . 'accès, la demande passe par l\'administrateur système.',
            ],
            [
                'categorie' => 'Prise en main',
                'question' => 'Pourquoi certains montants ne sont-ils pas modifiables ?',
                'reponse' => 'Toute valeur calculable est affichée en lecture seule : stock disponible, total '
                    . 'd\'une réservation, net à payer, résultat de l\'exercice. Un champ calculé que l\'on peut '
                    . 'saisir finit par contredire le calcul, et c\'est la saisie qui gagne — on ne sait alors '
                    . 'plus quel chiffre est le bon. Pour changer un total, changez ce qui le produit : les '
                    . 'quantités, les dates, les tarifs.',
            ],
            [
                'categorie' => 'Données',
                'question' => 'J\'ai supprimé une fiche par erreur. Est-elle perdue ?',
                'reponse' => 'Non. Dans tous les modules, « supprimer » archive : l\'enregistrement complet part '
                    . 'aux archives et reste restaurable depuis Import & Export › Restaurer. Seul un '
                    . 'administrateur peut purger définitivement une archive, et c\'est le seul endroit de '
                    . 'l\'application où une donnée disparaît vraiment.',
            ],
            [
                'categorie' => 'Données',
                'question' => 'Pourquoi le bouton Supprimer n\'apparaît-il pas ?',
                'reponse' => 'La suppression et la duplication sont désactivées par défaut, pour toute '
                    . 'l\'application. Un administrateur les ouvre dans Paramètres › Activation & Sécurité, et '
                    . 'son choix est tracé au journal d\'audit. Sur un outil d\'exploitation, l\'action '
                    . 'destructrice ne doit pas être à portée de clic par défaut.',
            ],
            [
                'categorie' => 'Données',
                'question' => 'Je n\'arrive pas à archiver une boisson ou un plat.',
                'reponse' => 'C\'est un refus volontaire : l\'élément est engagé dans une réservation ou une '
                    . 'vente encaissée. L\'archiver laisserait une ligne pointant vers le vide, et le montant '
                    . 'facturé deviendrait inexplicable lors d\'un contrôle. Le message précise les opérations '
                    . 'concernées. Pour retirer l\'article de la carte sans toucher à l\'historique, passez-le '
                    . 'en indisponible.',
            ],
            [
                'categorie' => 'Import & export',
                'question' => 'Mon fichier d\'import est refusé. Que dois-je faire ?',
                'reponse' => 'Téléchargez d\'abord le modèle du module concerné dans Import & Export › Importer : '
                    . 'il porte les colonnes et les libellés exacts attendus. Après dépôt, un contrôle de '
                    . 'cohérence compare votre fichier au référentiel et liste les écarts ligne par ligne — '
                    . 'colonne manquante, valeur hors liste, doublon, montant illisible. Corrigez le fichier et '
                    . 'redéposez-le : rien n\'est importé tant qu\'une erreur bloquante subsiste.',
            ],
            [
                'categorie' => 'Import & export',
                'question' => 'À quelle fréquence dois-je sauvegarder la base ?',
                'reponse' => 'Une sauvegarde est générée automatiquement chaque semaine et vous êtes averti de '
                    . 'la télécharger. Une sauvegarde qui reste sur la machine ne protège de rien : c\'est le '
                    . 'téléchargement qui la met à l\'abri. Vous pouvez en générer une à tout moment depuis '
                    . 'Import & Export › Sauvegardes, avant une opération sensible par exemple.',
            ],
            [
                'categorie' => 'Comptabilité',
                'question' => 'Puis-je corriger une écriture comptable validée ?',
                'reponse' => 'Non, et c\'est une règle du référentiel SYSCOHADA, pas une limite de l\'outil. Une '
                    . 'écriture validée est immuable ; la correction passe exclusivement par une '
                    . 'contre-passation, qui laisse les deux écritures visibles. Modifier ou supprimer '
                    . 'effacerait la trace de l\'erreur, ce qu\'un contrôle fiscal considère comme une anomalie '
                    . 'plus grave que l\'erreur elle-même.',
            ],
            [
                'categorie' => 'Comptabilité',
                'question' => 'Pourquoi le total des charges patronales n\'est-il pas affiché sur les bulletins ?',
                'reponse' => 'Parce qu\'un de ses taux n\'est pas confirmé. La CNSS annonce un taux « risques '
                    . 'professionnels » de 1 % à 4 % selon l\'activité, sans valeur publiée pour '
                    . 'l\'hôtellerie-restauration. La part établie — 19,4 % du brut : pension 6,4 %, prestations '
                    . 'familiales 9 %, VPS 4 % — est calculée et affichée. Pour le reste, l\'application publie '
                    . 'la fourchette au lieu de retenir un milieu : un taux plausible inscrit une fois devient '
                    . 'la règle appliquée en production, et personne ne le rouvre.',
            ],
            [
                'categorie' => 'Hors connexion',
                'question' => 'Que se passe-t-il si je saisis une réservation sans réseau ?',
                'reponse' => 'La saisie est enregistrée localement et marquée « en attente de synchronisation ». '
                    . 'Elle part au retour de la liaison. Si un autre poste a réservé la même unité entre-temps, '
                    . 'le serveur rejette la vôtre avec un motif explicite : la donnée n\'est pas perdue, elle '
                    . 'est à rejouer sur une autre unité ou d\'autres dates.',
            ],
            [
                'categorie' => 'Hors connexion',
                'question' => 'Deux postes ont modifié la même fiche. Laquelle gagne ?',
                'reponse' => 'Sur les données non financières, la plus récente. Sur les factures, paiements, '
                    . 'mouvements de caisse et mouvements de stock, aucune résolution automatique n\'a lieu : le '
                    . 'conflit part dans une file d\'arbitrage manuel, réservée aux profils gérant, comptable et '
                    . 'administrateur. Choisir automatiquement entre deux montants revient à en effacer un sans '
                    . 'que personne ne le sache.',
            ],
            [
                'categorie' => 'Sécurité',
                'question' => 'Où sont stockées mes données ?',
                'reponse' => 'Sur ce prototype, dans le navigateur du poste (localStorage) — c\'est une maquette '
                    . 'de démonstration, pas un environnement de production. L\'application réelle stocke sur un '
                    . 'serveur MySQL, avec sauvegarde quotidienne automatique. Ne saisissez aucune donnée client '
                    . 'réelle dans le prototype.',
            ],
        ],

        // maquette — l.110-139, les ressources utiles
        'ressources_titre' => 'Ressources utiles',
        'modeles_import_titre' => 'Modèles d\'import',
        'modeles_import_detail' => 'Fichiers d\'exemple par module, colonnes et libellés attendus.',
        'journal_audit_titre' => 'Journal d\'audit',
        'journal_audit_detail' => 'Qui a fait quoi, quand, depuis quel poste.',
        'roles_titre' => 'Rôles & permissions',
        'roles_detail' => 'La matrice des droits, module par module et rôle par rôle.',
        'alertes_titre' => 'Revoir mes alertes',
        'alertes_detail' => 'Réaffiche les stocks critiques et créances échues du jour.',

        // maquette — l.140-160, le bandeau de contact
        'contact_titre' => 'Vous ne trouvez pas de réponse ?',
        'contact_detail' => 'Contactez l\'éditeur : assistance technique, suggestions d\'évolution et '
            . 'signalement d\'anomalies.',
        'contact_bouton' => 'Contacter l\'éditeur',

        /*
         * Ce que cet écran ne fait pas — Article 8, chaque phrase adossée au
         * bloc de dérogation du composant `AideAPropos`.
         *
         * Le jeton `maitre-refuse:aide-a-propos.html#ressources` est déclaré
         * dans la vue, pour que `t-trois-sources.js` distingue un bloc refusé
         * d'un bloc oublié.
         */
        'refus_titre' => 'Ce que cet écran ne fait pas, et pourquoi',
        'refus_alertes' => '« Revoir mes alertes » n\'est pas proposé : aucune source d\'alerte n\'existe côté '
            . 'serveur — le domaine Notifications est vide tant que l\'API WhatsApp n\'est pas contractée. Un '
            . 'bouton qui n\'affiche jamais rien se lirait comme « rien à signaler », ce qui est une affirmation '
            . '(constat du 27/08/2026).',
        'refus_modeles_import' => '« Modèles d\'import » n\'ouvre rien : l\'import est une écriture, exclue du '
            . 'périmètre de la consultation web. La carte reste visible et le dit, plutôt que de disparaître.',
    ],

    /*
     * Contactez l'éditeur — `prototype_v2/pages/contact-editeur.html`.
     *
     * Les deux formulaires du maître ne sont pas portés (Article 6 : le maître
     * lui-même écrit qu'aucun message n'est transmis). Chaque contrôle refusé
     * est NOMMÉ à l'écran avec les mots du maître — un onglet, un champ ou un
     * bouton silencieusement retiré empêcherait de savoir si la fonction manque
     * ou si l'écran est cassé.
     */
    'contact' => [
        'titre_page' => 'Contactez l\'éditeur — TATACORA AFRIQUE',
        // maquette — l.23-25
        'titre' => 'Contactez l\'éditeur',
        'sous_titre' => 'Assistance technique, suggestions et signalement d\'anomalies.',

        // maquette — l.29-38, l'encart d'orientation, placé AVANT les formulaires
        'avant_titre' => 'Avant de nous contacter',
        'avant_detail_avant' => 'Consultez d\'abord l\'',
        'avant_lien' => 'Aide & FAQ',
        'avant_detail_apres' => ' — la réponse à votre question s\'y trouve peut-être déjà.',
        'avant_bouton' => 'Ouvrir l\'aide',

        // maquette — l.152-186, la colonne de coordonnées
        'coordonnees_titre' => 'Coordonnées de l\'éditeur',
        'editeur_initiales' => 'MR',
        'editeur_nom' => 'Dr MASSENON Rhodes',
        'editeur_fonction' => 'Éditeur du logiciel',
        'editeur_email_1' => 'rarhodes06@gmail.com',
        'editeur_email_2' => 'contact@massenonrhodes.com',
        'editeur_telephone' => '+229 01 51 33 50 40',
        'editeur_horaires' => 'Lun-Ven, 8h-17h (GMT)',

        // maquette — l.46-56, les deux onglets (ouvrent une modale, 01/09/2026)
        'onglet_message' => 'Envoyer un message',
        'onglet_bug' => 'Signaler un bug',

        // maquette — l.58-82, formulaire « Envoyer un message »
        'message_sous_titre' => 'Question d\'utilisation, demande d\'évolution ou remarque générale.',
        'message_objet' => 'Objet',
        'message_objet_invite' => 'ex : Question sur le module Comptabilité',
        'message_corps' => 'Message',
        'message_corps_invite' => 'Décrivez votre question ou suggestion...',
        'message_bouton' => 'Envoyer le message',
        // Rendu SEULEMENT quand le courriel est réellement parti (14/10/2026).
        'message_envoye' => 'Message envoyé à l\'éditeur.',
        // Échec SMTP ou messagerie non configurée : le message est gardé.
        'envoi_en_attente' => 'Enregistré, en attente d\'envoi : la messagerie n\'a pas pu joindre '
            . 'l\'éditeur. Le message sera renvoyé automatiquement.',

        // maquette — l.84-136, formulaire « Signaler un bug »
        'bug_sous_titre' => 'Un comportement inattendu, un calcul douteux, un écran qui ne répond pas.',
        'bug_module' => 'Module concerné',
        'bug_module_invite' => '-- Sélectionner --',
        'bug_description' => 'Description du problème',
        'bug_description_invite' => 'Que s\'est-il passé ? Qu\'attendiez-vous ?',
        'bug_etapes' => 'Étapes pour reproduire',
        'bug_etapes_invite' => '1. Aller dans... 2. Cliquer sur...',
        'bug_etapes_note' => 'C\'est le champ le plus utile du formulaire. Un bug que l\'éditeur sait reproduire '
            . 'est corrigé ; un bug décrit sans ses étapes est d\'abord une enquête.',
        'bug_capture' => 'Capture d\'écran (optionnel)',
        'bug_capture_invite' => 'PNG ou JPG, 2 Mo maximum.',
        'bug_bouton' => 'Signaler le bug',
        'bug_objet' => 'Bug — :module',
        'bug_signale' => 'Signalement envoyé à l\'éditeur.',

        // maquette — l.138-145, « Vos envois » — liste RÉELLE depuis le 01/09/2026
        'envois_titre' => 'Vos envois',
        'envois_sous_titre' => 'Vos 50 derniers envois. « Transmis » signifie que le courriel est '
            . 'réellement parti vers l\'éditeur.',
        'envois_vide' => 'Aucun envoi depuis ce compte.',
        'envois_statut_transmis' => 'Transmis',
        'envois_statut_a_transmettre' => 'En attente d\'envoi',
        'envois_capture' => '1 capture jointe',

        /*
         * maquette — l.188-200, le bandeau « Sur cette maquette » — NON RENDU
         * depuis le 01/09/2026 : la phrase du maître est devenue fausse (voir
         * le docblock de `App\Pwa\Livewire\Transverse\ContactEditeur`).
         */
        'maquette_titre' => 'Sur cette maquette',

        // maquette — l.202-214 — NON RENDU, voir le docblock du composant
        'accompagne_titre' => 'Ce qui accompagne votre envoi',
        'accompagne_1' => 'Votre nom et votre rôle',
        'accompagne_2' => 'La page depuis laquelle vous écrivez',
        'accompagne_3' => 'La version du logiciel et le navigateur',
    ],

    /*
     * Journal d'Audit — `prototype_v2/pages/journal-audit.html`.
     *
     * Les six intitulés de colonnes et les deux invites de filtre sont ceux du
     * maître, au mot et à la casse près (Article 4.3 : « mêmes en-têtes, même
     * casse »).
     */
    // Décision PO du 18/10/2026 : « le serveur doit avoir aussi le bouton
    // synchroniser, pour envoyer les données en local si le serveur a été
    // utilisé pour enregistrer des données ».
    'synchronisation_postes' => [
        'titre_page' => 'Synchroniser les postes — TATACORA AFRIQUE',
        'titre' => 'Synchroniser les postes',
        'sous_titre' => 'Ce qui a été enregistré ici part vers les postes Windows à leur prochain passage. '
            . 'Le bouton les fait passer tout de suite (moins d\'une minute) : chacun envoie sa file, '
            . 'puis reçoit tout ce que le serveur détient, tous modules.',
        'bouton' => 'Synchroniser maintenant',
        'demande_faite' => 'Demande envoyée le :date. Les postes allumés et connectés la suivent dans la minute.',
        'aucune_demande' => 'Aucune demande de synchronisation n\'a encore été faite depuis le serveur.',
        'derniere_demande' => 'Dernière demande : :date',
        'col_poste' => 'Poste',
        'col_compte' => 'Compte',
        'col_montee' => 'Dernier envoi',
        'col_descente' => 'Dernière réception',
        'col_attente' => 'En attente d\'envoi',
        'col_demande' => 'Dernière demande',
        'demande_suivie' => 'Reçue',
        'demande_non_suivie' => 'Pas encore reçue',
        'jamais' => '—',
        'aucun_poste' => 'Aucun poste ne s\'est encore synchronisé avec ce serveur.',
        'note' => 'Un poste éteint ou hors réseau suivra la demande à sa prochaine connexion : '
            . 'rien de ce qui a été enregistré n\'est perdu.',
        // Appairage des postes (19/10/2026, décision du PO).
        'col_appairage' => 'Appairage',
        'appaire' => 'Appairé',
        'appaire_utilise' => 'Appairé — dernier usage :date',
        'revoque' => 'Non appairé',
        'bouton_revoquer' => 'Révoquer',
        'revocation_titre' => 'Révoquer l\'appairage du poste « :poste » ?',
        'revocation_texte' => 'Le poste ne pourra plus envoyer ni recevoir tant qu\'un Administrateur ne l\'aura pas '
            . 'réappairé (Paramètres → Synchronisation, sur le poste). Ce qu\'il a enregistré reste dans sa file : '
            . 'rien n\'est perdu.',
        'revocation_confirmer' => 'Révoquer l\'appairage',
        'revocation_faite' => 'Appairage du poste « :poste » révoqué.',
    ],

    'journal_audit' => [
        'titre_page' => 'Journal d\'Audit — TATACORA AFRIQUE',
        // maquette — l.24-26
        'titre' => 'Journal d\'Audit',
        'sous_titre' => 'Traçabilité intégrale de toute action sensible — utilisateur, action, entité '
            . 'concernée, date et heure (, chap. 11.4 du CdCF)',

        // maquette — l.30-33, les deux filtres
        'recherche' => 'Rechercher (utilisateur, action, détail)...',
        'toutes_actions' => 'Toutes les actions',

        // maquette — l.49-54, les six colonnes
        'col_utilisateur' => 'Utilisateur',
        'col_action' => 'Action',
        'col_detail' => 'Détail',
        'col_date' => 'Date',
        'col_heure' => 'Heure',
        'col_poste' => 'Poste',

        /*
         * LE LIBELLÉ FRANÇAIS DE CHAQUE TABLE TRACÉE — registre FERMÉ, lu
         * par `JournalAudit::libelleTable()` via UN SEUL appel `__()` à clé
         * littérale (`pwa.journal_audit.tables`), puis indexé en PHP : une
         * clé concaténée à la volée (`__('…tables.'.$table)`) échapperait à
         * tout balayage statique des libellés (02/09/2026, correction de la
         * colonne « Détail »).
         *
         * Mesuré le 02/09/2026 : `grep -rl "use Auditable;" app/` — 33
         * modèles. Une table absente d'ici garde son nom technique plutôt
         * qu'un libellé inventé : c'est un manque à combler, jamais masqué.
         */
        'tables' => [
            'reservations' => 'Réservation',
            'clients' => 'Client',
            'factures' => 'Facture',
            'cartes_boisson' => 'Article de la carte du bar',
            'ventes_bar' => 'Vente au bar',
            'indisponibilites_carte' => 'Indisponibilité de carte',
            'ecritures_comptables' => 'Écriture comptable',
            'depenses' => 'Dépense',
            'lignes_depense' => 'Ligne de dépense',
            'commandes_restaurant' => 'Commande restaurant',
            'menus' => 'Menu',
            'plats' => 'Plat',
            'recettes' => 'Recette',
            'bulletins_paie' => 'Bulletin de paie',
            'conges' => 'Congé',
            'employes' => 'Employé',
            'plannings' => 'Planning',
            'articles' => 'Article de stock',
            'inventaires' => 'Inventaire',
            'lignes_inventaire' => 'Ligne d\'inventaire',
            'mouvements_stock' => 'Mouvement de stock',
            'points_stockage' => 'Point de stockage',
            'circuits' => 'Circuit touristique',
            'guides' => 'Guide',
            'reservations_tour' => 'Réservation de circuit',
            'contrats_location' => 'Contrat de location',
            'entretiens_vehicule' => 'Entretien de véhicule',
            'vehicules' => 'Véhicule',
            'lignes_panier' => 'Ligne de panier',
            'lignes_vente' => 'Ligne de vente',
            'paniers' => 'Panier',
            'ventes' => 'Vente',
            'commandes_achat' => 'Commande d\'achat',
            'fournisseurs' => 'Fournisseur',
            'parametres_systeme' => 'Paramètre système',
        ],

        // maquette — l.57
        'vide' => 'Aucune entrée ne correspond à votre recherche.',
        // maquette — l.59, la mention de pied de page, reprise telle quelle :
        // elle dit exactement ce que ce canal garantit.
        'mention_lecture_seule' => '🔒 Ce journal est en lecture seule pour tous les profils, y compris '
            . 'l\'Administrateur, conformément au chap. 11.4 du CdCF.',

        // Le décompte réel, affiché à côté du tableau : une troncature doit se
        // voir, sinon elle se lit comme « il n'y a que ça ».
        'decompte' => ':total entrée(s) au registre pour ce filtre.',
        'tronque' => 'Seules les :plafond entrées les plus récentes sont affichées sur :total. Affinez la '
            . 'recherche ou le filtre d\'action pour atteindre les autres.',

        /*
         * Ce que cet écran ne fait pas — Article 8, chaque phrase adossée à un
         * bloc de dérogation de `App\Pwa\Livewire\Transverse\JournalAudit`.
         */
        'refus_titre' => 'Ce que cet écran ne fait pas, et pourquoi',
        'refus_reinitialiser' => 'Le bouton « Réinitialiser les données de démo » du maître n\'est pas rendu : '
            . 'c\'est un outil de démonstration, et il est destructeur. Le journal d\'audit est inaltérable pour '
            . 'tous les profils, y compris l\'Administrateur — c\'est la mention que le maître affiche lui-même '
            . 'sous son tableau.',
        'refus_detail' => 'La colonne « Détail » nomme la table concernée en français et, quand elle sait '
            . 'encore le lire, le libellé réel de l\'enregistrement (numéro, nom, libellé de carte…) — jamais la '
            . 'phrase libre du maître, que le registre n\'a aucune colonne pour porter. Les instantanés « avant » '
            . 'et « après » que le schéma conserve ne sont pas affichés — ils contiennent le contenu des lignes '
            . 'touchées (un numéro de téléphone client, un montant), et le journal deviendrait une seconde '
            . 'surface d\'exposition.',
        'refus_import_export' => 'Les actions « Import » et « Export » du maître n\'apparaîtront pas dans la '
            . 'liste : aucun code de ce dépôt n\'en écrit (constat du 27/08/2026). La liste ne propose que les '
            . 'actions réellement présentes — un filtre qui propose une valeur inatteignable passe pour cassé.',
    ],

    /*
     * Mon profil — `prototype_v2/pages/mon-profil.html`.
     *
     * Les intitulés des deux formulaires du maître sont CONSERVÉS : ceux qui
     * ont une valeur réelle la portent en lecture, les autres portent « — » et
     * disent pourquoi. Retirer un intitulé empêcherait de savoir si la donnée
     * manque ou si l'écran est amputé.
     */
    'profil' => [
        'titre_page' => 'Mon profil — TATACORA AFRIQUE',
        // maquette — l.22-24
        'titre' => 'Mon profil',
        'sous_titre' => 'Vos informations personnelles, votre mot de passe et la trace de vos dernières '
            . 'actions dans le système.',

        // maquette — l.38-50, les métadonnées de session
        'metadonnees' => 'MÉTADONNÉES DE SESSION',
        'derniere_connexion' => 'Dernière connexion',
        'adresse_ip' => 'Adresse IP du poste',
        'statut_compte' => 'Statut du compte',
        // maquette — l.52-55, la note sous les métadonnées. Reprise telle
        // quelle : elle décrit exactement ce que la PWA fait, puisque son
        // adresse vient du serveur.
        'note_ip' => 'L\'adresse IP affichée est celle relevée par le poste. Sur l\'application réelle elle '
            . 'vient du serveur : une adresse déclarée par le navigateur ne prouve rien et ne doit jamais '
            . 'servir de contrôle d\'accès.',

        // maquette — l.61-97, informations personnelles
        'infos_titre' => 'Informations personnelles',
        'nom_complet' => 'Nom complet',
        'email' => 'Email',
        'telephone' => 'Téléphone',
        'fonction' => 'Fonction',
        'exemple_email' => 'ex. nom@tatacora.com',
        'exemple_telephone' => '+229 01 XX XX XX XX',
        // maquette — l.86-91, la note bleue. Reprise mot pour mot : elle dit
        // pourquoi la fonction est en lecture, et cela reste vrai ici.
        'note_fonction_avant' => 'La fonction et les droits d\'accès (RBAC) sont gérés par l\'administrateur '
            . 'système — voir ',
        'note_fonction_lien' => 'Rôles & Permissions',
        'note_fonction_apres' => '. Un utilisateur qui pourrait modifier sa propre fonction contournerait la '
            . 'matrice de droits en un clic.',
        'enregistrer_infos' => 'Enregistrer les informations',
        'sans_fiche_rh' => 'Aucune fiche employé n\'est rattachée à ce compte.',
        'sans_colonne' => 'Non porté par le schéma.',

        // maquette — l.99-141, mot de passe — écriture réelle depuis le 01/09/2026
        'mdp_titre' => 'Modifier le mot de passe',
        'mdp_sous_titre' => 'Le changement est immédiat et ne ferme pas votre session.',
        'mdp_ouvrir' => 'Modifier le mot de passe',
        'mdp_ancien' => 'Ancien mot de passe',
        'mdp_nouveau' => 'Nouveau mot de passe',
        'mdp_confirmation' => 'Confirmer le nouveau mot de passe',
        'mdp_regle' => 'Min. 8 caractères.',
        'mdp_bouton' => 'Mettre à jour le mot de passe',
        'mdp_note' => 'La vérification de l\'ancien mot de passe et le hachage du nouveau ont lieu côté '
            . 'serveur — un contrôle fait dans le navigateur se contourne en ouvrant la console.',
        'mdp_confirmation_invalide' => 'Le nouveau mot de passe et sa confirmation ne correspondent pas.',
        'mdp_identique' => 'Le nouveau mot de passe est identique à l\'ancien.',
        'mdp_ancien_invalide' => 'L\'ancien mot de passe est incorrect.',
        'mdp_mise_a_jour' => 'Mot de passe mis à jour.',

        // maquette — l.144-166, le journal personnel
        'journal_titre' => 'Journal d\'audit — :nombre dernières actions',
        'journal_sous_titre' => 'Vos actions uniquement. Le journal complet, tous utilisateurs, est réservé '
            . 'aux profils qui y ont droit.',
        'journal_complet' => 'Journal complet →',
        'col_date_heure' => 'DATE / HEURE',
        'col_action' => 'ACTION',
        'col_module' => 'MODULE',
        'col_ip' => 'IP',
        'journal_vide' => 'Aucune action tracée pour ce compte.',

        // Les quatre clés « refus_* » qui documentaient ici « Ce que cet écran
        // ne fait pas » sont RETIRÉES (directive du Product Owner du
        // 31/08/2026, voir le docblock de `MonProfil`) : elles n'étaient déjà
        // plus rendues par la vue — un panneau qui catalogue ses absences ne
        // se maintient pas en lang une fois l'écran qui le portait supprimé.
    ],

    /*
     * Rôles & Permissions — `prototype_v2/pages/roles-permissions.html`.
     *
     * La matrice est LUE depuis `permission_role`, jamais recopiée : voir le
     * bloc de tête de `App\Pwa\Livewire\Transverse\RolesPermissions`.
     */
    'roles' => [
        'titre_page' => 'Rôles & Permissions — TATACORA AFRIQUE',
        // maquette — l.23-25
        'titre' => 'Rôles & Permissions',
        'sous_titre' => 'Contrôle d\'accès basé sur les rôles (RBAC) — socle du chap. 11.2 du CdCF, '
            . 'amendable. C = accès complet, L = lecture seule, — = aucun accès.',

        // maquette — l.40-47, la matrice et sa légende
        'matrice_titre' => 'Matrice complète des permissions',
        'legende_complet' => 'Accès complet (C)',
        'legende_lecture' => 'Lecture seule (L)',
        'legende_aucun' => 'Aucun accès',
        'col_module' => 'Module',

        // maquette — l.136-137, les deux compteurs de chaque carte
        'carte_complet' => ':nombre accès complet',
        'carte_lecture' => ':nombre lecture seule',
        // ÉCART : le maître affiche « Compte démo : <identifiant> ». Ici, le
        // nombre réel de comptes portant le rôle — voir le bloc du composant.
        'carte_comptes' => ':nombre compte(s) rattaché(s)',
        'carte_aucun_compte' => 'Aucun compte rattaché',
        'referentiel_vide' => 'Aucun rôle n\'est enregistré : le référentiel RBAC n\'a pas été semé sur cette '
            . 'base. Sans lui, aucun profil ne peut se connecter — c\'est une anomalie d\'installation, pas un '
            . 'écran vide.',
        'total_comptes' => ':nombre compte(s) d\'accès au total.',

        // ---------------------------------------------------- édition RÉELLE (01/09/2026)
        'bouton_nouveau_role' => '+ Nouveau rôle',
        'bouton_retablir_socle' => 'Rétablir le socle du CdCF',
        'bouton_modifier_droits' => 'Modifier les droits',
        'nouveau_role_titre' => 'Nouveau rôle',
        'tout_retirer' => 'Tout retirer',
        'nouveau_role_libelle' => 'Libellé',
        'nouveau_role_libelle_invite' => 'ex. veilleur_nuit',
        'nouveau_role_description' => 'Description',
        'nouveau_role_cree' => 'Rôle créé — tous les modules sont fermés (« — ») jusqu\'à ce que vous lui '
            . 'accordiez des droits.',
        'modifier_droits_titre' => 'Modifier les droits — :role',
        'modifier_droits_sous_titre' => 'C = accès complet, L = lecture seule, — = aucun accès.',
        'modifier_droits_enregistre' => 'Droits mis à jour.',
        'verrou_administrateur' => 'Verrouillé : un administrateur ne peut pas se retirer l\'accès à '
            . '« Rôles & Permissions ».',
        'retablir_socle_titre' => 'Rétablir le socle du CdCF',
        'retablir_socle_texte' => 'Chaque rôle du socle (onze rôles métier) retrouvera exactement la matrice du '
            . 'CdCF. Tout amendement que vous ou un autre administrateur avez apporté à CES rôles sera perdu. '
            . 'Les rôles que vous avez créés depuis cet écran ne sont pas concernés.',
        'retablir_socle_confirmer' => 'Rétablir',
        'retablir_socle_fait' => ':nombre rôle(s) du socle rétabli(s).',
        'badge_conforme' => 'Conforme au socle du CdCF',
        'badge_amendee' => 'Matrice amendée — elle diffère du socle du CdCF',

        // Les clés « refus_* » qui documentaient ici « Ce que cet écran ne
        // fait pas » sont RETIRÉES : la vue ne les rend plus (les deux motifs
        // — « Compte démo », niveau dérivé — restent datés en commentaire du
        // composant, sous forme de jetons `maitre-refuse:` mesurables).

        // ---------------------------------------------------------------- refus du Service
        'libelle_requis' => 'Le libellé du rôle est obligatoire.',
        'role_deja_existant' => 'Un rôle « :libelle » existe déjà.',
        'niveau_invalide' => 'Niveau hors registre : :niveau.',
        'verrouillage_administrateur' => 'Un administrateur ne peut pas se retirer l\'accès à Rôles & '
            . 'Permissions : cela le verrouillerait hors de cet écran, y compris pour se corriger lui-même.',
    ],

    /*
     * Paramètres — `prototype_v2/pages/parametres.html`.
     *
     * Les libellés des CHAMPS ne sont PAS ici : ils viennent du registre
     * serveur (`RegistreParametres`), source unique partagée avec l'API
     * Flutter. Les recopier ferait deux listes, qui divergeraient.
     */
    'parametres' => [
        'titre_page' => 'Paramètres — TATACORA AFRIQUE',
        // maquette — l.22-24
        'titre' => 'Paramètres',
        'sous_titre' => 'Identité de l\'entreprise, informations légales, canaux de communication et '
            . 'paramétrage technique du système.',

        // Les deux sections de l'onglet « Identité & Légal » du maître
        // (l.40 et l.51), à leurs titres.
        'section_identite' => 'Identité de l\'entreprise',
        'section_legal' => 'Informations légales & fiscales',
        // Le titre de l'onglet « Communication » (l.70) et « Email (SMTP) »
        // (l.83) du maître.
        'section_communication' => 'Canaux de notification (Module M12)',
        'section_email' => 'Configuration Email (SMTP)',
        // Les deux groupes du registre serveur sans onglet dédié au maître :
        // logés sous « Activation & Sécurité » depuis le 01/09/2026, qui est
        // le seul onglet à portée transverse (décision n° 2 de
        // DIRECTIVE_CONFORMITE_100.md — aucun groupe réel ne disparaît).
        'section_social' => 'Charges sociales',
        'section_exploitation' => 'Exploitation',
        'section_hors_onglet' => 'Servi par le registre serveur — le maître ne pose pas de champ dédié pour ce '
            . 'groupe sous cet onglet, et le masquer ailleurs rendrait ses réglages invisibles.',
        // Les deux titres de l'onglet « Activation & Sécurité » du maître
        // (l.176 et l.195), repris tels quels au-dessus des groupes qu'ils
        // encadrent désormais.
        'section_activation_actions' => 'Actions sensibles',
        'section_activation_suppression' => 'Rappel sur la suppression',

        /*
         * ONGLET « ACTIVATION & SÉCURITÉ » — les mots du maître (l.174-202),
         * découpés autour de ses <strong> (même motif que `presentation_2_fort`).
         * ⚠ L'ancienne clé `mention_bascules_absentes` (« elles n'existent pas
         * côté serveur ») a cessé d'être vraie le 02/09/2026 — trois bascules
         * existent et sont LUES (archivage M1, onglet Seeders, alertes de la
         * cloche) : supprimée plutôt que corrigée (PA-144).
         */
        'activation_intro_a' => 'Ces bascules commandent ce que l\'application propose',
        'activation_intro_fort_profils' => 'à tous les profils',
        'activation_intro_b' => ', dans ',
        'activation_intro_fort_modules' => 'tous les modules',
        'activation_intro_c' => '. Elles ne remplacent pas les droits RBAC, qui disent ce que chaque profil a le '
            . 'droit de faire : les deux s\'appliquent, et la plus restrictive gagne.',
        'activation_info_a' => 'Une action désactivée est',
        'activation_info_fort' => 'retirée',
        'activation_info_b' => ' de l\'écran, pas grisée : un bouton grisé invite à cliquer et ne produit qu\'un '
            . 'refus. Chaque changement est tracé au journal d\'audit.',
        'risque_faible' => 'Risque faible',
        'risque_modere' => 'Risque modéré',
        'risque_eleve' => 'Risque élevé',
        'bascule_activee' => ':titre — activée.',
        'bascule_desactivee' => ':titre — désactivée.',
        'suppression_rappel_a' => 'Même activée, la suppression',
        'suppression_rappel_fort' => 'archive',
        'suppression_rappel_b' => ' : l\'enregistrement complet part aux archives et reste restaurable depuis ',
        'suppression_rappel_lien' => 'Import & Export › Restaurer',
        'suppression_rappel_c' => '. Un élément engagé dans une réservation ou une vente encaissée est refusé à '
            . 'l\'archivage — la ligne correspondante deviendrait illisible.',

        /*
         * LES DEUX SEULS CHAMPS DU MAÎTRE QUI RESTENT REFUSÉS (02/09/2026) —
         * deux SECRETS, rendus en ligne avec leur mention réelle. Tout le
         * reste (promoteur, régime fiscal, WhatsApp, SMTP hors mot de passe,
         * logo/favicon, tables de salle, bascules) est RÉEL depuis cette
         * date : l'ancien tableau `champs_non_couverts` disait des absences
         * qui ont cessé d'être vraies — supprimé plutôt que corrigé (PA-144).
         * Le « Message de bienvenue » du maître, lui, est couvert par les
         * MODÈLES du module Notifications, pas par une clé de paramètre.
         */
        'communication_cle_api_libelle' => 'Clé API WhatsApp Business',
        'communication_cle_api_mention' => 'Secret technique : n\'entrera jamais dans les paramètres système, '
            . 'lisibles par tout profil ayant accès à cet écran — il vit en configuration serveur.',
        'communication_message_libelle' => 'Message de bienvenue (notifications automatiques)',
        'communication_message_mention' => 'Porté par les modèles du module Notifications (un texte par '
            . 'évènement et par canal) : une seconde source de texte ici finirait par diverger de la première.',
        'email_motdepasse_libelle' => 'Mot de passe SMTP',
        'email_motdepasse_mention' => 'Secret technique : n\'entre jamais dans les paramètres système. Rangé '
            . 'chiffré sur le serveur, il n\'est jamais réaffiché, exporté ni synchronisé ; sans lui, la '
            . 'configuration serveur (.env) s\'applique. L\'envoi de test ci-dessous l\'emprunte réellement.',
        // Saisie du mot de passe SMTP (19/10/2026, « chiffré en base »).
        'email_motdepasse_invite' => 'Saisir un nouveau mot de passe',
        'email_motdepasse_enregistrer' => 'Enregistrer le mot de passe',
        'email_motdepasse_effacer' => 'Effacer',
        'email_motdepasse_renseigne' => 'Renseigné le :date par :par — jamais réaffiché.',
        // Commun au serveur et au poste (le repli `.env` est dit par la mention).
        'email_motdepasse_absent' => 'Non renseigné ici.',
        'email_motdepasse_reserve' => 'Seul un Administrateur peut saisir ou effacer ce mot de passe.',
        'email_motdepasse_enregistre' => 'Mot de passe SMTP enregistré (chiffré).',
        'email_motdepasse_efface' => 'Mot de passe SMTP effacé : la configuration serveur (.env) s\'applique.',
        'secret_invalide' => 'Le mot de passe doit compter entre 1 et :max caractères.',
        'secret_inconnu' => 'Secret inconnu : « :cle ».',
        'secret_reserve' => 'Réservé aux Administrateurs.',

        /*
         * ONGLET « EMAIL (SMTP) » — le test d'envoi RÉEL (02/09/2026). Trois
         * issues honnêtes, jamais un « envoyé » simulé : la version
         * précédente du prototype répondait « avec succès (simulation) ».
         */
        'email_test_bouton' => 'Envoyer un email de test',
        'email_test_objet' => 'Email de test — TATACORA AFRIQUE',
        'email_test_corps' => 'Cet email confirme que la configuration SMTP de TATACORA AFRIQUE fonctionne. '
            . 'Il a été envoyé depuis l\'écran Paramètres, onglet Email (SMTP).',
        'email_test_sans_adresse' => 'Aucune adresse de destination : renseignez d\'abord « Email de contact » '
            . '(onglet Identité & Légal).',
        'email_test_sans_configuration' => 'Aucun transport réel n\'est configuré : le serveur SMTP est vide '
            . 'ici ET la configuration serveur (.env) pointe un canal qui ne délivre rien (journal local). '
            . 'Rien n\'a été envoyé.',
        'email_test_echec' => 'Échec de l\'envoi — le transport a répondu : :erreur',
        'email_test_envoye' => 'Email de test envoyé à :adresse.',

        /*
         * ONGLET « LOGO & APPARENCE » — téléversement RÉEL (02/09/2026),
         * libellés et invites du maître (l.103-119).
         */
        'apparence_logo_titre' => 'Logo de l\'entreprise',
        'apparence_logo_bouton' => 'Changer le logo',
        'apparence_logo_aide' => 'Format carré recommandé, fond transparent de préférence.',
        'apparence_logo_alt' => 'Logo actuel',
        'apparence_favicon_titre' => 'Favicon (icône d\'onglet navigateur)',
        'apparence_favicon_bouton' => 'Changer le favicon',
        'apparence_favicon_alt' => 'Favicon actuel',
        'apparence_champ_logo' => 'Sélectionnez un fichier PNG/JPG (recommandé 512×512px).',
        'apparence_champ_favicon' => 'Sélectionnez un fichier .ico ou .png 32×32px.',
        'apparence_televersement' => 'Téléversement en cours…',
        'apparence_logo_enregistre' => 'Logo remplacé — l\'ancien fichier n\'est pas conservé.',
        'apparence_favicon_enregistre' => 'Favicon remplacé — l\'ancien fichier n\'est pas conservé.',

        /*
         * ONGLET « ESPACES & TABLES » — le référentiel `tables_salle`
         * (02/09/2026), les mots du maître (l.156-172 et `rendreTables()`).
         */
        'tables_intro_a' => 'Les tables proposées au point de vente.',
        'tables_intro_fort_numeros' => 'Les numéros ne sont pas codés dans le logiciel',
        'tables_intro_b' => ' : créez, renumérotez, activez ou désactivez sans intervention technique. Le ',
        'tables_intro_fort_comptoir' => 'Comptoir',
        'tables_intro_c' => ' n\'a pas de table — une vente au comptoir n\'en exige aucune.',
        'tables_intro_fort_panier' => 'Une table dont le panier est ouvert ne se désactive pas',
        'tables_intro_d' => ' : les consommations servies n\'auraient plus de table pour les porter jusqu\'à '
            . 'l\'addition.',
        'tables_bouton_ajouter' => 'Ajouter une table',
        'tables_bouton_reinit' => 'Rétablir le jeu initial',
        'tables_bouton_renumeroter' => 'Renuméroter',
        'tables_prefixe' => 'préfixe :prefixe',
        'tables_places' => ':places place(s)',
        'tables_badge_panier_ouvert' => 'panier ouvert',
        'tables_badge_libre' => 'libre',
        'tables_badge_desactivee' => 'désactivée',
        'tables_espace_vide' => 'Aucune table dans cet espace.',
        'tables_comptoir_sans_table' => 'Aucune table — une vente au comptoir ne se rattache à aucune table.',
        'table_modale_titre_ajout' => 'Nouvelle table',
        'table_modale_titre_renumerotation' => 'Renuméroter :libelle',
        'table_aide_renumerotation' => 'Le libellé suivra le nouveau numéro.',
        'table_champ_espace' => 'Espace',
        'table_espace_choisir' => 'Choisir un espace…',
        'table_champ_numero' => 'Numéro',
        'table_champ_places' => 'Places',
        'table_creee' => 'Table :libelle créée.',
        'table_renumerotee' => 'Table renumérotée.',
        'table_basculee' => 'État de la table mis à jour.',
        'tables_retablir_titre' => 'Rétablir le jeu initial ?',
        'tables_retablir_message' => 'Les treize tables d\'origine remplaceront la configuration actuelle. '
            . 'Les ventes déjà enregistrées ne sont pas touchées.',
        'tables_retablir_confirmer' => 'Rétablir',
        'tables_jeu_retabli' => 'Jeu initial rétabli.',

        // Les badges, dérivés des états du serveur — jamais des commutateurs
        // bruts (PA-61).
        'etats_titre' => 'État réel de la configuration',
        'etat_tva' => 'TVA',
        'etat_mecef' => 'MECeF',

        'valeur_non_renseignee' => 'Non renseigné',
        'type_inconnu' => 'Type non reconnu par cet écran : la valeur est affichée telle que le serveur la '
            . 'stocke, sans interprétation.',
        'aucun_parametre' => 'Aucun paramètre n\'est déclaré pour ce groupe.',

        // maquette — l.121-129, la charte graphique, DÉJÀ en lecture au maître
        'charte_titre' => 'Couleurs de la charte graphique (lecture seule — chap. 9.3.1 du CdCF)',
        'charte_navy' => 'Navy',
        'charte_gold' => 'Gold',
        'charte_succes' => 'Succès',
        'charte_alerte' => 'Alerte',
        'charte_erreur' => 'Erreur',

        /*
         * ONGLET « CANAUX DE RÉSERVATION » — canaux_reservation est un
         * référentiel réel depuis PA-163 (01/09/2026) : ces libellés
         * reprennent les colonnes exactes du tableau du maître (l.146-149).
         *
         * Gestion (ajout, renommage, désactivation) ouverte le 01/09/2026 par
         * `CanalReservationService` — le motif « ces gestes n'y sont pas
         * encore ouverts » a cessé d'être vrai le jour même où il a été
         * écrit et est retiré plutôt que corrigé (PA-144).
         */
        'canaux_colonne_canal' => 'Canal',
        'canaux_colonne_reservations' => 'Réservations',
        'canaux_colonne_etat' => 'État',
        'canaux_colonne_actions' => 'Actions',
        'canaux_etat_actif' => 'actif',
        'canaux_etat_desactive' => 'désactivé',
        'canaux_aucun' => 'Aucun canal enregistré.',

        // maquette — bouton d'en-tête l.141, actions de ligne du moteur
        // `canaux-engine.js` (« Renommer », « Désactiver »/« Réactiver »).
        'canaux_bouton_ajouter' => 'Ajouter un canal',
        'canaux_bouton_renommer' => 'Renommer',
        'canaux_bouton_desactiver' => 'Désactiver',
        'canaux_bouton_reactiver' => 'Réactiver',
        'canaux_modale_titre_ajout' => 'Nouveau canal de réservation',
        'canaux_modale_titre_renommage' => 'Renommer le canal',
        'canaux_champ_nom' => 'Nom du canal',
        'canaux_aide_renommage' => 'Les réservations déjà saisies conservent l’ancien libellé : renommer ne '
            . 'réécrit pas le passé.',
        // maquette — confirmation avant désactivation d'un canal employé
        // (`canaux-engine.js`, `Dialogue.confirmer`).
        'canaux_confirmation_desactivation' => 'Désactiver « :nom » ? :n réservation(s) l’emploient. Elles le '
            . 'conserveront ; il ne sera simplement plus proposé aux nouvelles saisies.',
        // maquette l.136-140 — la phrase COMPLÈTE du maître, découpée autour
        // de son <strong> (remplace `canaux_mention_gestion`, qui omettait la
        // première phrase — alignée le 02/09/2026).
        'canaux_intro_a' => 'Les canaux proposés à la saisie d’une réservation, ici et dans la réservation '
            . 'rapide du tableau de bord.',
        'canaux_intro_fort' => 'Un canal utilisé ne se supprime pas, il se désactive',
        'canaux_intro_b' => '— l’effacer laisserait des réservations pointant vers un canal inexistant, et '
            . 'l’analyse par canal perdrait son historique.',
        // maquette — `Dialogue.saisir` du bouton d'ajout (`parametres.html`
        // l.390-398) : le message du maître, en sous-titre de la modale.
        'canaux_aide_ajout' => 'Le nom tel qu’il apparaîtra dans les formulaires de réservation.',
    ],

    /*
     * Import & Export — `prototype_v2/pages/import-export.html`.
     *
     * ⚠ Les jetons de refus qui couvraient la page entière (« l'import, la
     * sauvegarde, la restauration et la réinitialisation sont des écritures
     * par nature ») sont RETIRÉS le 02/09/2026 : la directive du Product
     * Owner rend les quatre onglets FONCTIONNELS, et un motif de refus qui a
     * cessé d'être vrai transforme une décision en oubli (PA-144). Chaque
     * phrase reprend les mots du maître ; les adaptations à la réalité
     * serveur (rythme quotidien, rétention 30 jours, « serveur » et non
     * « poste »/« navigateur ») sont notées clé par clé.
     */
    'import_export' => [
        'titre_page' => 'Import & Export — TATACORA AFRIQUE',
        // maquette — l.23-25
        'titre' => 'Import & Export',
        'sous_titre' => 'Chargement de données par module, sauvegardes de la base, restauration des éléments '
            . 'archivés et réinitialisation des jeux de test.',

        // -------------------------------------------------------------- onglets (maquette l.28-32)
        'onglet_importer' => 'Importer les données',
        'onglet_sauvegardes' => 'Sauvegardes de la base',
        'onglet_restaurer' => 'Restaurer',
        'onglet_seeders' => 'Réinitialiser les données de test',

        // -------------------------------------------- onglet Importer — RÉEL (02/09/2026)
        // Les trois cartes numérotées du maître (l.44-98).
        'importer_module_label' => '1. Choisir le module à alimenter',
        'importer_module_aide' => 'Chaque module a ses propres colonnes. Le modèle et le contrôle en découlent.',
        'importer_module_invite' => '-- Sélectionner un module --',
        'colonnes_attendues' => 'Colonnes attendues',
        'badge_obligatoire' => 'OBLIGATOIRE',
        'badge_facultatif' => 'facultatif',
        'importer_modele_titre' => '2. Télécharger le fichier modèle',
        'importer_modele_bouton' => 'Télécharger le modèle',
        // maquette l.77-81 — le <strong> est posé par la vue.
        'importer_modele_aide_1' => 'Le modèle porte les colonnes exactes et une ligne d\'exemple. Il est généré '
            . 'depuis la même déclaration que le contrôle : il ne peut pas s\'en écarter. Ouvrez-le dans Excel, '
            . 'remplacez la ligne d\'exemple par vos données, conservez la ligne d\'en-tête, puis enregistrez en',
        'importer_modele_aide_format' => 'CSV UTF-8',
        'importer_depot_titre' => '3. Déposer le fichier rempli',
        'importer_depot_aide' => 'Formats acceptés : CSV (séparateur point-virgule ou virgule).',
        'importer_depot_glisser' => 'Glissez votre fichier ici',
        'importer_depot_cliquer' => 'ou cliquez pour le sélectionner',
        'importer_fichier_selectionne' => 'Fichier sélectionné : :nom (:taille Ko)',
        'importer_valider' => 'Valider et contrôler le fichier',

        // Le rapport de contrôle (maquette l.455-527, rendu JS reproduit).
        'rapport_conforme' => 'Fichier conforme au référentiel',
        'rapport_non_conforme' => 'Fichier non conforme — rien n\'a été importé',
        'rapport_resume' => ':total ligne(s) lue(s) ·',
        'rapport_resume_exploitables' => 'exploitable(s) ·',
        'rapport_resume_erreurs' => 'en erreur ·',
        'rapport_resume_avertissements' => ':nombre avertissement(s)',
        'rapport_badge_erreur' => 'ERREUR',
        'rapport_badge_avertissement' => 'AVERTIS.',
        'rapport_ligne' => 'Ligne :numero',
        'rapport_suite_erreurs' => '… et :nombre autre(s) erreur(s).',
        'rapport_aucune_anomalie' => 'Aucune anomalie relevée. Toutes les colonnes et toutes les valeurs '
            . 'correspondent au référentiel.',
        'rapport_confirmer' => 'Confirmer l\'import de :nombre ligne(s)',
        'rapport_corriger' => 'Corrigez les lignes ci-dessus dans votre fichier, enregistrez-le à nouveau en '
            . 'CSV UTF-8, puis redéposez-le. Le contrôle se relance à chaque dépôt.',

        // La colonne latérale « Démarche à suivre » (maquette l.110-141).
        'demarche_titre' => 'Démarche à suivre',
        'demarche_1' => 'Choisissez le module. Les colonnes attendues s\'affichent.',
        'demarche_2_avant' => 'Téléchargez le modèle et remplissez-le',
        'demarche_2_fort' => 'sans modifier la ligne d\'en-tête',
        'demarche_3' => 'Enregistrez en CSV UTF-8. Sans cet encodage, les accents deviennent illisibles à la relecture.',
        'demarche_4' => 'Déposez le fichier et lancez le contrôle. Rien n\'est importé à ce stade.',
        'demarche_5' => 'Corrigez les erreurs signalées, redéposez, puis confirmez l\'import.',
        'demarche_encadre_fort' => 'Aucun import partiel.',
        'demarche_encadre' => 'Tant qu\'une erreur subsiste, rien n\'entre en base. Importer '
            . '« ce qui passe » laisserait un jeu incomplet dont personne ne saurait dire ce qui manque.',

        // « Historique des imports » (maquette l.143-148) — RÉEL, table
        // `journal_imports`. « depuis ce poste » du maître devient « pour
        // l'instant » : l'historique est celui du SERVEUR, pas d'un poste.
        'historique_titre' => 'Historique des imports',
        'historique_vide' => 'Aucun import réalisé pour l\'instant.',
        'historique_lignes' => ':nombre ligne(s) importée(s)',

        // -------------------------------------------------------- onglet Sauvegardes — RÉEL (01/09/2026)
        // Le libellé du maître (l.179-181) depuis le 02/09/2026 — l'ancien
        // « Générer une sauvegarde maintenant » était une reformulation.
        'sauvegardes_generer' => 'Générer une sauvegarde de la base',
        'sauvegardes_generation_reussie' => 'Sauvegarde générée : :fichier (:taille).',
        'sauvegardes_vide' => 'Aucune sauvegarde. Utilisez le bouton ci-dessus pour en générer une.',
        'sauvegardes_rythme' => 'La sauvegarde automatique tourne chaque nuit à 02h00, '
            . 'rétention glissante de 30 jours. « Générer une sauvegarde de la base » appelle le MÊME code, '
            . 'hors de son horaire.',
        // Les 4 KPI du maître (l.159-176). « Rythme automatique » vaut la
        // planification RÉELLE (`routes/console.php` l.44-45 : dailyAt 02:00),
        // jamais le « Hebdomadaire » du prototype ; « Dernière sauvegarde »
        // est la date du fichier réel le plus récent — les fichiers listés ont
        // passé le contrôle d'intégrité du Job (PA-60 : un dump incomplet est
        // retiré avant d'être listé).
        'kpi_tables' => 'Tables en base',
        'kpi_sauvegardes' => 'Sauvegardes conservées',
        'kpi_derniere' => 'Dernière sauvegarde',
        'kpi_rythme' => 'Rythme automatique',
        'kpi_rythme_valeur' => 'Quotidien (02h00)',
        'exporter_table_bouton' => 'Exporter une table existante',
        // Les entêtes du maître, en capitales COMME LUI (`import-export.html`
        // l.194-197 les écrit ainsi dans son HTML — la garde de casse
        // l'admet précisément parce que le maître le fait).
        'col_fichier' => 'FICHIER',
        'col_date' => 'DATE',
        'col_table' => 'TABLE',
        'col_action' => 'ACTION',
        'sauvegarde_contenu' => 'Base complète',
        'action_telecharger' => 'Télécharger',
        'action_retirer' => 'Retirer de la liste',
        'sauvegarde_non_telechargee' => 'non téléchargée',
        // Pied du tableau (maquette l.204-207) — « Les 5 dernières » devient
        // la rétention RÉELLE (30 jours glissants, `SauvegardeBaseQuotidienneJob`),
        // et « ce poste » le serveur ; la seconde phrase est celle du maître.
        'sauvegardes_retention' => 'Les sauvegardes des 30 derniers jours sont conservées sur ce serveur. '
            . 'Une sauvegarde restée sur la machine ne protège de rien : c\'est le téléchargement qui la met à l\'abri.',
        // Bandeaux (maquette l.612-629) — « hebdomadaire » retiré du titre
        // vert : la sauvegarde générée ici est manuelle, et le rythme réel est
        // quotidien.
        'bandeau_generee_titre' => 'Sauvegarde générée',
        'bandeau_generee_texte' => ':fichier — téléchargez-la : tant qu\'elle reste sur ce serveur, '
            . 'elle ne protège de rien.',
        'bandeau_rappel_titre' => 'Sauvegarde en attente de téléchargement',
        'bandeau_rappel_texte' => ':fichier du :date n\'a pas été téléchargée.',
        // Modale de retrait (maquette l.593-599, Dialogue.confirmer) —
        // « dans ce navigateur » devient « sur ce serveur » : c'est là que
        // vivent les fichiers réels.
        'retrait_titre' => 'Sauvegarde jamais téléchargée',
        'retrait_message' => 'Cette sauvegarde n\'existe que sur ce serveur.',
        'retrait_detail' => 'La retirer la perd définitivement : il n\'en existe aucune copie ailleurs.',
        'retrait_confirmer' => 'Retirer quand même',
        'sauvegarde_retiree' => 'Sauvegarde retirée de la liste.',
        // Modale « Exporter une table existante » (maquette l.342-358) —
        // portée le 02/09/2026 (directive PO) ; liste fermée `ExportTableService`.
        'export_table_titre' => 'Exporter une table existante',
        'export_table_aide' => 'Le contenu actuel de la table, au format JSON.',
        'export_table_invite' => '-- Sélectionner une table --',
        'export_table_choisir' => 'Sélectionnez une table.',
        'export_table_refusee' => 'Cette table ne s\'exporte pas depuis cet écran.',

        // Le dictionnaire de colonnes d'un module (maquette l.56-62).
        'col_colonne' => 'COLONNE',
        'col_obligatoire' => 'OBLIGATOIRE',
        'col_valeurs_attendues' => 'VALEURS ATTENDUES',

        // ------------------------------------------------ onglet Restaurer — RÉEL (02/09/2026)
        // L'encadré bleu du maître (l.214-224). Le corps est ADAPTÉ à la
        // réalité serveur : « supprimer » archive sur les référentiels de
        // parc (M1, M8 — statut réversible, listés ici) ; les autres modules
        // n'ont AUCUNE suppression — leurs gestes sont l'annulation et la
        // contre-passation, qui laissent l'enregistrement lisible sur son
        // propre écran. La promesse du titre reste vraie mot pour mot.
        'restaurer_titre' => 'Aucune suppression n\'est définitive',
        'restaurer_texte' => 'Ici, « supprimer » archive : une unité d\'hébergement ou un véhicule retiré du parc '
            . 'est conservé au complet et peut être remis en place ci-dessous. Partout ailleurs, rien ne se supprime '
            . '— on annule ou on contre-passe, et l\'enregistrement reste lisible sur l\'écran de son module. '
            . 'La purge définitive existe, mais elle est réservée à l\'administrateur et n\'a pas de retour : '
            . 'c\'est le seul endroit de l\'application où une donnée disparaît vraiment.',
        'recherche_archives' => 'Rechercher dans les archives…',
        'filtre_restaurables' => 'À restaurer',
        'filtre_toutes' => 'Toutes les entrées',
        'filtre_restaurees' => 'Déjà restaurées',
        'col_element' => 'ÉLÉMENT',
        'col_module' => 'MODULE',
        'col_archive_le' => 'ARCHIVÉ LE',
        'col_par' => 'PAR',
        'archives_vide' => 'Aucun élément archivé ne correspond.',
        'action_restaurer' => 'Restaurer',
        'badge_restaure' => 'RESTAURÉ',
        'action_purger' => 'Purger définitivement (administrateur)',
        'archive_restauree' => ':element remis en place.',
        'archive_purgee' => ':element purgé définitivement.',
        'archive_type_inconnu' => 'Ce type d\'élément n\'est pas au registre des archives.',
        'purge_titre' => 'Purger définitivement',
        'purge_message' => 'Cet élément sera effacé sans retour possible.',
        'purge_detail' => 'Contrairement à l\'archivage, la purge ne laisse aucune trace restaurable.',
        'purge_confirmer' => 'Purger',
        'purge_refusee_non_archive' => 'Purge refusée : seul un élément archivé se purge.',
        'purge_refusee_referencee' => 'Purge refusée : des enregistrements passés référencent encore cet élément, '
            . 'et l\'effacer les rendrait illisibles.',

        // -------------------------------------------------- onglet Réinitialiser — RÉEL (02/09/2026)
        // L'état VERROUILLÉ du maître (l.261-273).
        'seeders_verrouille_titre' => 'Réinitialisation désactivée',
        'seeders_verrouille_texte' => 'Cette fonction vide les jeux de données de démonstration. Elle reste fermée '
            . 'par défaut : laissée ouverte sur une base d\'exploitation réelle, elle détruirait le travail de l\'entreprise.',
        'seeders_verrouille_ouvrir_avant' => 'Un administrateur peut l\'ouvrir dans',
        'seeders_verrouille_ouvrir_lien' => 'Paramètres › Activation & Sécurité',
        // L'état OUVERT (l.275-305).
        'seeders_bandeau_titre' => 'Fonction ouverte — à refermer dès que l\'exploitation réelle commence',
        'seeders_bandeau_texte' => 'Une sauvegarde complète est générée automatiquement avant chaque '
            . 'réinitialisation. C\'est le seul filet si la bascule était restée ouverte par erreur.',
        'seeders_vide_titre' => 'Ce qui sera vidé',
        // « Réinitialiser comme neuf » — demande du Product Owner du
        // 14/10/2026 (lot E) : tiers et transactionnel vidés, référentiels
        // désignés gardés (voir `ReinitialisationDonneesTestService`).
        'seeders_vide_texte' => 'Tout ce que l\'exploitation produit : clients, employés et paie, fournisseurs, '
            . 'guides, réservations et séjours, ventes, factures, mouvements de stock, achats, dépenses, '
            . 'locations, écritures comptables, notifications, caches et files de tâches.',
        'seeders_conserve_titre' => 'Ce qui sera conservé',
        'seeders_conserve_texte' => 'Comptes et droits, paramètres, journaux, chambres du parc, articles de stock '
            . '(sans mouvements), fiche restaurant, carte du bar, véhicules, catalogue tourisme et plan comptable.',
        'seeders_rien_a_vider' => 'Aucune donnée à vider — la base est déjà vierge.',
        'seeders_bouton' => 'Réinitialiser comme neuf',
        // La modale du maître (l.313-338).
        'seeders_modale_titre' => 'Réinitialiser comme neuf ?',
        'seeders_modale_texte_avant' => ':nombre table(s)',
        'seeders_modale_texte_1' => 'vont être vidées : clients, employés, fournisseurs, guides, réservations, ventes, '
            . 'factures, stocks, écritures, paie, et tous les jeux de démonstration. Rien n\'est semé à nouveau.',
        'seeders_modale_texte_2' => 'Les paramètres de l\'entreprise, la matrice des droits, votre compte, le journal '
            . 'd\'audit, les chambres, les articles, la fiche restaurant, la carte du bar, les véhicules et le '
            . 'catalogue tourisme sont',
        'seeders_modale_texte_2_fort' => 'conservés',
        'seeders_modale_texte_2_fin' => '. Une sauvegarde complète est générée juste avant.',
        'seeders_confirmation_avant' => 'Pour confirmer, saisissez',
        'seeders_phrase_confirmation' => 'VIDER',
        'seeders_confirmation_aide' => 'Une saisie plutôt qu\'un simple clic : c\'est la seule barrière qui résiste '
            . 'à un double-clic distrait.',
        'seeders_confirmer' => 'Vider définitivement',
        'seeders_phrase_invalide' => 'La phrase tapée ne correspond pas à :phrase.',
        'seeders_fait' => ':nombre table(s) vidée(s), :lignes ligne(s) supprimée(s). Les paramètres, les droits, '
            . 'le journal et les référentiels gardés sont intacts — sauvegarde :sauvegarde générée juste avant. '
            . 'Les postes Windows s\'arrêtent de synchroniser jusqu\'à leur propre réinitialisation.',
        'reset_refuse_role' => 'Réinitialisation refusée : ce geste est réservé à l\'Administrateur.',
        'reset_cycle' => 'Réinitialisation refusée : les tables :tables se référencent en boucle, aucun ordre de '
            . 'vidage ne respecte leurs clés étrangères.',
        'reset_reference_bloquante' => 'Réinitialisation refusée : la référence :reference relie une table '
            . 'conservée à une table vidée et ne peut pas être détachée.',
        'reset_refuse_production' => 'Réinitialisation refusée : cet environnement est la Production. '
            . 'Cette action n\'existe délibérément que pour développement et recette.',
        'reset_refuse_bascule' => 'Réinitialisation refusée : la fonction est désactivée dans '
            . 'Paramètres › Activation & Sécurité.',
        'reset_environnement_production' => 'Cet écran s\'exécute en Production : la réinitialisation est '
            . 'désactivée, quel que soit votre rôle — c\'est l\'environnement qui refuse, pas un droit qui manque.',
        // Phase d'essais en production (19/10/2026).
        'reset_phase_essais' => 'Phase d\'essais en Production : la réinitialisation reste possible pour effacer les '
            . 'essais avant la mise en service. Chaque poste devra ensuite être réinitialisé à son tour. Retirez '
            . 'TATACORA_PHASE_ESSAIS du fichier .env le jour de la mise en service réelle.',
    ],

    /*
     * Le titre du bloc de refus des pages MÉTIER — `pwa/partials/bloc-refus`.
     *
     * Même phrase que `pwa.comptabilite.refus_titre` et que les six autres :
     * elle est devenue une convention d'écran, et deux formulations pour le
     * même bloc se remarqueraient d'une page à l'autre.
     */
    'refus_titre' => 'Ce que cet écran ne fait pas, et pourquoi',

    /*
     * M6 Stocks — maquette `prototype_v2/pages/m6-stocks.html`.
     *
     * Chaque chaîne est reprise TELLE QUELLE du maître, y compris ses
     * majuscules et son apostrophe droite (le maître en emploie 581 contre 39
     * typographiques). Les phrases de refus citent le libellé exact du
     * contrôle qu'elles écartent (PA-144) : qui compare les deux écrans doit
     * retrouver SA formulation.
     */
    'stocks' => [
        // maquette — `m6-stocks.html` l.26
        'titre' => 'Gestion des Stocks',
        // maquette — l.28-31, le <strong> compris
        'sous_titre' => 'Référentiel valorisé au coût moyen pondéré — le stock affiché est '
            . '<strong>calculé depuis les mouvements</strong>, il ne se saisit jamais.',

        // maquette — l.34-35
        'lien_inventaires' => 'Inventaires & fiches',
        'lien_approvisionnement' => 'Approvisionnement',

        // maquette — l.47
        'recherche' => 'Rechercher un article…',
        // maquette — l.126, l.128
        'toutes_categories' => 'Toutes catégories',
        'tous_points' => 'Tous les points',
        // maquette — l.58-60
        'tous_etats' => 'Tous les états',
        'etat_sous_seuil' => 'Sous seuil',
        'etat_rupture' => 'En rupture',

        // maquette — les cinq indicateurs, l.166-172
        'kpi_references' => 'Références',
        'kpi_valeur' => 'Valeur du stock',
        'kpi_valeur_detail' => 'au coût moyen pondéré',
        'kpi_sous_seuil' => 'Sous seuil',
        'kpi_sous_seuil_detail' => 'à réapprovisionner',
        'kpi_mouvements' => 'Mouvements 30 j',
        'kpi_gros_petit' => 'Gros / petit stock',
        'kpi_gros_petit_detail' => 'suivi vs journalier',
        /*
         * Le maître détaille « N suivies · N journalières » sous le compte de
         * références. Sans colonne de mode de suivi, la ventilation n'existe
         * pas : le détail dit ce qu'il compte réellement plutôt que d'inventer
         * une répartition (Article 7).
         */
        'kpi_references_detail' => 'toutes catégories de suivi confondues',

        // maquette — l.177-178
        'decompte' => ':nombre article(s)',
        'non_modifiable' => 'Stock calculé — non modifiable ici',
        // maquette — l.181
        'vide' => 'Aucun article ne correspond à ces filtres.',

        // maquette — les dix colonnes, l.192-201, dans son ordre
        'col_article' => 'Article',
        'col_categorie' => 'Catégorie',
        'col_point' => 'Point',
        'col_suivi' => 'Suivi',
        'col_stock' => 'Stock',
        'col_seuil' => 'Seuil',
        'col_valeur_achat' => 'Valeur d\'achat',
        'col_cmp' => 'CMP',
        'col_valeur_stock' => 'Valeur stock',
        'col_actions' => 'Actions',

        // maquette — l.242, la seule action de ligne qui mène quelque part
        'action_fiche' => 'Fiche',

        'tronque' => 'Seuls les :plafond premiers articles sont affichés sur :total. '
            . 'Affinez la recherche ou le filtre de catégorie pour atteindre les autres.',
        'portee' => 'Les compteurs ci-dessus portent sur TOUT le référentiel du point « :point », '
            . 'jamais sur les seules lignes affichées : masquer les articles sains ne change pas '
            . 'le nombre d\'articles à réapprovisionner.',

        /*
         * Les sept refus de l'écran. Chacun a son bloc Article 8 complet —
         * fichier et ligne du maître, comportement du maître, raison — dans
         * `App\Pwa\Livewire\Stocks\Stocks`.
         */
        'refus_nouvel_article' => 'Le bouton « + Nouvel article » du maître n\'est pas rendu : créer un '
            . 'article est une écriture, et la consultation web est en lecture seule stricte.',
        'refus_mouvement' => 'Les actions de ligne « Mouvement » et « Modifier », ainsi que les fenêtres '
            . '« Nouvel article » et « Mouvement de stock », ne sont pas rendues : un mouvement de stock '
            . 'manuel est nommément exclu de ce canal, y compris « simplifié » ou « d\'urgence ».',
        'refus_import' => 'Les boutons « Importer » et « Modèle » ne sont pas rendus : un import est une '
            . 'écriture en masse, et un import interrompu laisserait un référentiel partiellement faux '
            . 'que rien ne signalerait.',
        'refus_export' => 'Les boutons « Excel » et « PDF » ne sont pas rendus, et ce n\'est PAS une '
            . 'impossibilité technique : le moteur d\'états rend exactement cet état. C\'est une décision '
            . 'de périmètre — l\'exception à la lecture seule est accordée au seul Hub États & Rapports, '
            . 'pas à chaque écran de module. L\'étendre n\'est pas une décision d\'agent.',

        /*
         * Les fenêtres du maître, refusées en bloc pour le comparateur des
         * trois sources. Elles sont toutes des formulaires d'écriture.
         *
         * maitre-refuse:m6-stocks.html#fond-modale
         */
        'refus_modales' => 'Les fenêtres du maître ne sont pas portées : « Nouvel article » (« Nom de '
            . 'l\'article », « Catégorie », « Unité de mesure », « Point de stockage », « Valeur d\'achat '
            . 'unitaire (FCFA) », « Mode de suivi », « Seuil d\'alerte », « Stock d\'ouverture », puis '
            . '« Créer l\'article » ou « Annuler ») et « Mouvement de stock » (« Type de mouvement », '
            . '« Quantité », « Coût d\'achat unitaire (FCFA) », « Motif », puis « Enregistrer »), avec sa '
            . 'confirmation « Stock insuffisant » et son bouton « Forcer la sortie ». Toutes écrivent.',
    ],

    /*
     * M6 — Inventaires & fiches de stock, maquette
     * `prototype_v2/pages/m6-inventaires.html`.
     *
     * ⚠ Le maître écrit SANS ACCENTS plusieurs libellés du panneau de cycle
     * d'inventaire — « Periodicite », « Dernier inventaire cloture », « Etat »,
     * « Cycle d'inventaire par magasin ». Ils sont repris tels quels dans la
     * phrase de refus qui les cite : les accentuer ferait diverger la citation
     * de l'écran qu'elle décrit.
     */
    'inventaires' => [
        // maquette — l.25
        'titre' => 'Inventaires & Fiches de stock',
        // maquette — l.27-30
        'sous_titre' => 'Stock initial, entrées, sorties et stock théorique sur une période — le stock est '
            . '<strong>calculé</strong>, jamais saisi.',

        // maquette — les trois onglets, l.37-45, dans son ordre
        'onglet_fiche' => 'Fiche de stock',
        'onglet_inventaire' => 'Inventaire physique',
        'onglet_historique' => 'Inventaires clôturés',

        // maquette — l.52, l.58, l.64, l.68
        'champ_article' => 'Article',
        'champ_point' => 'Point de stockage',
        'champ_du' => 'Du',
        'champ_au' => 'Au',
        'tous_points' => 'Tous les points',
        // maquette — l.168
        'aucun_article_option' => 'Aucun article — créez-en un dans Stocks',

        // maquette — les quatre raccourcis, l.72-75
        'raccourci_7' => '7 jours',
        'raccourci_30' => '30 jours',
        'raccourci_90' => '90 jours',
        'raccourci_mois' => 'Ce mois',

        // maquette — l.196-197 (messageVide)
        'aucun_article_titre' => 'Aucun article',
        'aucun_article_detail' => 'Créez d\'abord un article dans l\'écran Stocks.',

        // maquette — l.209-212 : le bandeau qui disqualifie le document
        'incoherence_titre' => 'Incohérence détectée.',
        'incoherence_detail' => 'Le solde progressif ne retombe pas sur le stock théorique. '
            . 'Un mouvement a été écrit hors du moteur de stock — ce document ne doit pas servir '
            . 'de justificatif.',

        // maquette — les six indicateurs de la fiche, l.223-228
        'kpi_stock_initial' => 'Stock initial',
        'kpi_entrees' => 'Entrées',
        'kpi_sorties' => 'Sorties',
        'kpi_pertes' => 'Pertes',
        'kpi_regularisations' => 'Régularisations',
        'kpi_stock_theorique' => 'Stock théorique',

        // maquette — l.232-237
        'cmp' => 'CMP',
        'valeur_theorique' => 'Valeur du stock théorique',
        'point' => 'Point',
        'periode' => 'Période',
        'periode_du_au' => 'Du :debut au :fin',

        // maquette — l.243-244
        'detail_mouvements' => 'Détail des mouvements',
        'decompte_mouvements' => ':nombre mouvement(s)',
        'aucun_mouvement' => 'Aucun mouvement sur cette période.',

        // maquette — les sept colonnes du détail, l.250-256
        'col_date' => 'Date',
        'col_type' => 'Type',
        'col_motif' => 'Motif',
        'col_entree' => 'Entrée',
        'col_sortie' => 'Sortie',
        'col_solde' => 'Solde',
        'col_par' => 'Par',

        // maquette — l.135-137
        'type_entree' => 'Entrée',
        'type_sortie' => 'Sortie',
        'type_perte' => 'Perte',
        'type_regularisation' => 'Régularisation',

        // maquette — l.402-407 (l'état vide de l'onglet Inventaire physique)
        'aucun_en_cours' => 'Aucun inventaire en cours',
        'aucun_en_cours_detail' => 'Ouvrir un inventaire fige le stock théorique de chaque article à cet '
            . 'instant. Aucun inventaire n\'a encore été ouvert sur cet établissement — l\'ouverture se '
            . 'fait depuis l\'application TATACORA, ce canal étant en lecture seule.',

        // maquette — l.436-441
        'inventaire_du' => 'Inventaire du :date — :point',
        'avancement' => ':comptes / :total article(s) comptés · :ecarts écart(s) · impact valorisé',
        'sans_statut' => 'La table des inventaires ne porte aucun statut : rien ne distingue ici un '
            . 'inventaire clôturé d\'un inventaire encore ouvert. C\'est le plus récent qui est affiché.',

        // maquette — les cinq colonnes de comptage, l.460-464
        'col_article' => 'Article',
        'col_theorique' => 'Théorique',
        'col_compte' => 'Compté',
        'col_ecart' => 'Écart',
        'col_ecart_valorise' => 'Écart valorisé',

        // maquette — l.556 (messageVide de l'historique)
        'historique_vide_titre' => 'Aucun inventaire clôturé',
        'historique_vide_detail' => 'Les inventaires clôturés et leurs régularisations apparaîtront ici.',

        // maquette — les huit colonnes de l'historique, l.560-568
        'col_articles' => 'Articles',
        'col_regularises' => 'Régularisés',
        'col_manquants' => 'Manquants',
        'col_excedents' => 'Excédents',
        'col_impact' => 'Impact net',

        'historique_portee' => 'Cette liste porte sur TOUS les inventaires enregistrés, clôturés ou non : '
            . 'le schéma ne distingue pas les deux. Le nombre d\'articles est celui des lignes '
            . 'réellement comptées.',
        'historique_tronque' => 'Seuls les :plafond inventaires les plus récents sont affichés sur :total.',

        /*
         * Les sept refus de l'écran. Chacun a son bloc Article 8 complet dans
         * `App\Pwa\Livewire\Stocks\Inventaires`.
         *
         * maitre-refuse:m6-inventaires.html#fond-modale
         */
        'refus_periodicite' => 'Le panneau « Cycle d\'inventaire par magasin » du maître — ses colonnes '
            . '« Magasin », « Periodicite », « Dernier inventaire cloture » et « Etat », et sa mention '
            . '« La periodicite signale une echeance ; elle n\'empeche jamais de lancer un inventaire. » — '
            . 'n\'est pas rendu : aucune périodicité n\'existe au schéma, et la déduire des inventaires '
            . 'passés reviendrait à afficher « en retard » sur une règle que personne n\'a posée. La '
            . 'choisir serait de surcroît une écriture.',
        'refus_comptage' => 'Le champ de comptage « à compter » et le bouton « Lancer l\'inventaire » ne '
            . 'sont pas rendus : compter, c\'est écrire. L\'onglet montre l\'avancement réel et les écarts '
            . 'déjà constatés.',
        'refus_cloture' => 'Le bouton « Clôturer et régulariser » n\'est pas rendu, non plus que sa '
            . 'confirmation « Inventaire incomplet » et son « Clôturer partiellement » : la clôture '
            . 'génère un mouvement de régularisation par article en écart, l\'écriture la plus lourde '
            . 'du module.',
        'refus_manquants' => 'Les colonnes « Manquants » et « Excédents » rendent « — » : la séparation '
            . 'entre les deux n\'est produite que par la clôture. La refaire ici recopierait la règle qui '
            . 'décide de quel côté tombe un écart, et deux versions de cette règle divergeraient.',
        'refus_journalier' => 'Le bandeau « Article en suivi journalier » du maître n\'est pas rendu : la '
            . 'table des articles ne porte aucun mode de suivi, ici comme sur l\'écran Stocks.',
        'refus_par' => 'La colonne « Par » du détail des mouvements rend « — », et la mention '
            . '« (rupture forcée) » n\'est pas affichée : la fiche de stock projette la date, le type, le '
            . 'motif, l\'entrée, la sortie et le solde, pas leur auteur. Relire les mouvements ici '
            . 'obligerait à réécrire les bornes de la période et le filtre de point, qui finiraient par '
            . 'diverger de la fiche qu\'ils décrivent.',
        'refus_export' => 'Les boutons « Export PDF » et « Export Excel » ne sont pas rendus, et ce n\'est '
            . 'PAS une impossibilité technique : le moteur d\'états existe. C\'est une décision de '
            . 'périmètre — l\'exception à la lecture seule est accordée au seul Hub États & Rapports. Le '
            . 'jour où l\'export sera branché, la mention d\'incohérence devra partir avec le document, '
            . 'pas rester à l\'écran.',
    ],

    /*
     * M7 — Fournisseurs & Achats, maquette `prototype_v2/pages/m7-achats.html`
     * et les cinq modales de `assets/js/crud-ui.js` qu'elle charge.
     */
    'achats' => [
        // maquette — l.25
        'titre' => 'Fournisseurs & Achats',
        // maquette — l.27
        'sous_titre' => 'Référentiel fournisseurs, commandes d\'achat et rapprochement à trois voies',

        // maquette — les deux onglets, l.31-32
        'onglet_fournisseurs' => 'Fournisseurs',
        'onglet_commandes' => 'Commandes d\'achat',

        // maquette — l.59 et l.253
        'recherche_fournisseur' => 'Rechercher un fournisseur...',
        'recherche_commande' => 'Rechercher une commande (fournisseur)...',
        'toutes_evaluations' => 'Toutes les évaluations',
        'tous_statuts' => 'Tous les statuts',

        // maquette — les colonnes, l.72-97 puis l.258-263
        'col_fournisseur' => 'Fournisseur',
        'col_contact' => 'Contact',
        'col_categorie' => 'Catégorie fournie',
        'col_conditions' => 'Conditions',
        'col_evaluation' => 'Évaluation',
        'col_date_commande' => 'Date de commande',
        'col_montant_estime' => 'Montant estimé',
        'col_statut' => 'Statut',
        // maquette — `crud-ui.js` l.70
        'col_actions' => 'Actions',

        // maquette — `crud-ui.js` l.76-77
        'vide_titre' => 'Aucun résultat',
        'vide_detail' => 'Essayez de modifier votre recherche ou vos filtres.',

        // maquette — `crud-engine.js` l.254
        'decompte' => 'Affichage de :affiches sur :total',
        'tronque' => 'Liste tronquée à :plafond lignes',

        /*
         * Les cinq refus et les deux lacunes ouvertes. Chacun a son bloc
         * Article 8 complet dans `App\Pwa\Livewire\Achats\Achats`.
         */
        'refus_crud' => 'Les boutons « Actualiser », « Importer », « Exporter » et le bouton de création '
            . 'du maître ne sont pas rendus : la consultation web est en lecture seule stricte, et '
            . 'l\'export sort des données de l\'établissement.',
        'refus_actions_ligne' => 'Les quatre actions de ligne du maître — « Voir le détail », '
            . '« Modifier », « Dupliquer », « Supprimer » — ne sont pas rendues. Trois écrivent ; la '
            . 'quatrième ouvre une fenêtre de détail que cet écran ne porte pas.',
        'refus_selection' => 'La case à cocher de sélection et sa barre « :nombre sélectionné(s) » — avec '
            . '« Exporter la sélection » et « Supprimer » — ne sont pas rendues : elles n\'ont ici aucun '
            . 'autre usage, et un contrôle qui n\'ouvre rien empêche de savoir si la fonction manque ou '
            . 'si l\'écran est cassé.',
        'refus_pagination' => 'La pagination « ← Précédent » / « Suivant → » du maître est remplacée par '
            . 'un plafond de lignes, avec le décompte réel affiché : chaque bouton de pagination serait '
            . 'une action de plus sur le seul chemin par lequel cette consultation pourrait écrire.',

        /*
         * ⚠ `#modale-suppression` A ETE RETIRE de cette liste le 03/09/2026 :
         * la modale de confirmation EST portee (chassis partage
         * `<x-pwa.modale-archivage>`, appelee par
         * `Achats::confirmerArchivageFournisseur()`), et la declarer refusee
         * serait desormais une decision devenue oubli (PA-144). Les quatre
         * autres restent exactes.
         *
         * maitre-refuse:m7-achats.html#modale-formulaire
         * maitre-refuse:m7-achats.html#modale-detail
         * maitre-refuse:m7-achats.html#modale-export
         * maitre-refuse:m7-achats.html#modale-import
         */
        'refus_modales' => 'Les cinq fenêtres du maître ne sont pas portées : « Nouveau » et son '
            . '« Enregistrer » (champs « Raison sociale », « Contact (téléphone) », « Catégorie '
            . 'fournie », « Conditions de paiement », « Évaluation » ; et pour une commande '
            . '« Montant estimé (FCFA) »), « Détail — » et son « Modifier », « Confirmer la '
            . 'suppression » et son « Supprimer définitivement », « Exporter — Fournisseurs » avec '
            . '« Télécharger tous les résultats filtrés (.csv) », et « Importer — Fournisseurs » avec '
            . '« Glissez-déposez un fichier .csv ici », « Télécharger le modèle .csv » et « Importer ». '
            . 'Quatre écrivent, la cinquième exporte.',

        /*
         * ⚠ LACUNE FERMÉE LE 03/09/2026. Elle disait : « la table des
         * fournisseurs ne porte aucun indicateur d'activité […] à arbitrer,
         * pas à contourner ici ». La demande du Product Owner du 03/09/2026
         * EST cet arbitrage : `fournisseurs.actif` existe, et « Supprimer »
         * est rendu par ligne et en lot — comme ARCHIVAGE. La clé est
         * conservée parce qu'elle est encore lue par un test de conformité ;
         * son texte dit maintenant ce qui est vrai.
         */
        'lacune_actif' => 'Un fournisseur retiré du référentiel passe « Archivé » : il quitte le '
            . 'sélecteur des commandes, reste lisible sur celles qu\'il a déjà honorées, et se '
            . 'restaure. Aucune fiche n\'est effacée.',
        'lacune_annulation' => 'LACUNE OUVERTE — le statut d\'une commande d\'achat n\'admet aucune '
            . 'valeur « annulée » : « Brouillon », « Envoyée », « Réceptionnée partiellement », '
            . '« Réceptionnée », « Clôturée ». Une commande envoyée par erreur reste au registre, et '
            . 'la seule sortie disponible affirme autre chose. À arbitrer.',
    ],

    /*
     * M7 — Approvisionnement, maquette
     * `prototype_v2/pages/m7-approvisionnement.html`.
     */
    'appro' => [
        // maquette — l.24
        'titre' => 'Approvisionnement',
        // maquette — l.26-29, le <strong> compris
        'sous_titre' => 'Commandes fournisseurs, réceptions et dettes — la réception génère l\'entrée de stock, '
            . '<strong>jamais une double saisie</strong>.',

        // maquette — les quatre onglets, l.36-39
        'onglet_besoins' => 'Besoins',
        'onglet_commandes' => 'Commandes',
        'onglet_receptions' => 'Réceptions',
        'onglet_dettes' => 'Dettes fournisseurs',

        // maquette — les cinq indicateurs, l.132-137
        'kpi_sous_seuil' => 'Articles sous seuil',
        'kpi_en_attente' => 'Commandes en attente',
        'kpi_partielles' => 'Réceptions partielles',
        'kpi_a_payer' => 'Fournisseurs à payer',
        'kpi_total_du' => 'Total dû',

        // maquette — l.213-218
        'besoins_titre' => 'Articles à réapprovisionner',
        'besoins_detail' => 'Stock calculé ≤ seuil d\'alerte.',
        'recherche_besoin' => 'Article, point de stockage…',
        'besoins_vide' => 'Aucun article sous son seuil. Rien à commander.',
        'besoins_portee' => 'Le compteur « Articles sous seuil » porte sur TOUT le référentiel, jamais '
            . 'sur les seules lignes affichées : la recherche masque des lignes, elle ne réduit pas ce '
            . 'qu\'il y a à commander.',

        // maquette — les colonnes des besoins, l.241-247
        'col_article' => 'Article',
        'col_point' => 'Point',
        'col_stock' => 'Stock',
        'col_seuil' => 'Seuil',
        'col_manque' => 'Manque',
        'col_prix_achat' => 'Prix d\'achat',
        'col_a_commander' => 'À commander',

        // maquette — l.333, l.336
        'commandes_titre' => 'Bons de commande',
        'recherche_commande' => 'Fournisseur, n° de commande…',
        'tous_statuts' => 'Tous les statuts',
        'commandes_vide' => 'Aucune commande. Passez par l\'onglet Besoins.',

        // maquette — les colonnes des commandes, l.348-355
        'col_numero' => 'N°',
        'col_fournisseur' => 'Fournisseur',
        'col_date' => 'Date',
        'col_lignes' => 'Lignes',
        'col_montant' => 'Montant',
        'col_regle' => 'Réglé',
        'col_statut' => 'Statut',
        'col_actions' => 'Actions',

        // maquette — l.404-410, l.418-422
        'receptions_titre' => 'Bons de réception',
        'receptions_detail' => 'Chaque réception a généré une entrée de stock valorisée au prix de la '
            . 'commande, qui a recalculé le coût moyen pondéré de l\'article.',
        'recherche_reception' => 'N°, commande, fournisseur…',
        'toutes_receptions' => 'Toutes les réceptions',
        'receptions_conformes' => 'Conformes',
        'receptions_ecart' => 'Avec écart',
        'receptions_vide' => 'Aucune réception enregistrée.',

        // maquette — les colonnes des réceptions, l.430-436
        'col_commande' => 'Commande',
        'col_articles' => 'Articles',
        'col_conformite' => 'Conformité',

        // maquette — l.487-489, l.493
        'dettes_titre' => 'Dettes fournisseurs',
        'dettes_detail' => 'Commandes non intégralement réglées, par ancienneté.',
        'total_du' => 'Total dû',
        'dettes_vide' => 'Aucune dette fournisseur. Toutes les commandes sont soldées.',
        'jours' => ':nombre j',
        'dettes_portee' => 'Cette liste porte sur les commandes non clôturées et leur MONTANT COMMANDÉ. '
            . 'La colonne « Ancienneté » mesure l\'âge du bon de commande, pas le retard d\'un paiement.',

        /*
         * Les sept refus de l'écran. Chacun a son bloc Article 8 complet dans
         * `App\Pwa\Livewire\Achats\Approvisionnement`.
         */
        'refus_reglements' => 'Les colonnes « Réglé » et « Reste dû », le « Total dû » et l\'indicateur '
            . '« Fournisseurs à payer » rendent « — » : rien ne rattache un règlement à une commande '
            . 'd\'achat. La table des paiements existe bien, mais elle va dans l\'autre sens — vers les '
            . 'factures CLIENTS et les sessions de caisse, jamais vers un fournisseur. Additionner les '
            . 'commandes présenterait le montant COMMANDÉ comme une DETTE, sur l\'écran même où l\'on '
            . 'décide qui payer.',
        'refus_commander' => 'La case « cocher-tout », les cases de ligne, le champ « À commander » et '
            . 'le bouton « Commander la sélection » ne sont pas rendus : ouvrir une commande est une '
            . 'écriture.',
        'refus_receptionner' => 'Les actions de ligne « Réceptionner » et « Régler » ne sont pas '
            . 'rendues : une réception génère l\'entrée de stock et recalcule le coût moyen pondéré, '
            . 'l\'écriture la plus lourde du module.',
        'refus_colonnes' => 'Les colonnes « Point » et « Prix d\'achat » des besoins, et « Point » et '
            . '« Articles » des réceptions, rendent « — » : la table des articles ne porte ni point ni '
            . 'prix d\'achat, et un bon de réception n\'a aucune ligne de détail au schéma.',
        'refus_numero' => 'La colonne « N° » affiche l\'identifiant réel de la pièce : ni les commandes '
            . 'ni les bons de réception ne portent de numéro au schéma. Fabriquer un numéro ici créerait '
            . 'une référence introuvable partout ailleurs.',
        'refus_export' => 'Les boutons « Export Excel » et « Export PDF » des quatre onglets ne sont pas '
            . 'rendus : l\'exception à la lecture seule est accordée au seul Hub États & Rapports, et '
            . 'l\'étendre n\'est pas une décision d\'agent.',

        /*
         * maitre-refuse:m7-approvisionnement.html#fond-modale
         */
        'refus_modales' => 'La fenêtre du maître n\'est pas portée : « Nouvelle commande fournisseur », '
            . 'avec son « Fournisseur », son « Enregistrer la commande » et son « Annuler ». Elle crée '
            . 'un bon de commande.',
    ],

    /*
     * M2 — Facturation & Caisse MECeF, maquette
     * `prototype_v2/pages/m2-facturation.html`.
     */
    'facturation' => [
        // maquette — l.24
        'titre' => 'Facturation & Caisse MECeF',
        // maquette — l.26
        'sous_titre' => 'Émission de factures normalisées MECeF (DGI Bénin), consolidation '
            . 'multi-activités et suivi des encaissements',

        // maquette — l.85-89
        'registre_titre' => 'Registre des factures émises',
        'registre_detail' => 'Une seule séquence de numéros, toutes origines confondues — POS au comptant, '
            . 'séjours clôturés et factures directes.',
        // maquette — l.94
        'recherche' => 'N°, client…',
        // maquette — l.101
        'toutes_activites' => 'Toutes les activités',

        // maquette — la bande de compteurs, l.107-112
        'compteur_pieces' => 'Pièces',
        'compteur_avoirs' => 'Avoirs',
        'compteur_montant' => 'Montant',
        /*
         * La mention MECeF du maître, mot pour mot (l.111). Elle n'est PAS
         * écrite en dur : elle est choisie selon le nombre de pièces
         * réellement certifiées, et ce compte se dérive du NUMÉRO de chaque
         * facture, jamais de son statut (PA-119, PA-61, PA-100).
         */
        'mecef_aucune' => 'MECeF — <strong>non certifiées, démonstration</strong>',
        'mecef_certifiees' => 'MECeF — <strong>:nombre pièce(s) certifiée(s)</strong> sur :total affichée(s)',

        // maquette — l.117-118
        'registre_vide' => 'Aucune facture émise. Encaissez au point de vente ou clôturez un séjour.',

        // maquette — les sept colonnes, l.124-131, dans son ordre
        'col_numero' => 'N°',
        'col_date' => 'Date',
        'col_client' => 'Client',
        'col_origine' => 'Origine',
        'col_activites' => 'Activités',
        'col_montant' => 'Montant',
        'col_statut' => 'Statut',

        'avoirs_rattaches' => ':nombre avoir(s)',
        'tronque' => 'Seules les :plafond pièces les plus récentes sont affichées sur :total. '
            . 'Affinez la recherche ou le filtre d\'activité pour atteindre les autres.',

        // maquette — `m2-facturation.html` l.112-113 : « Export Excel » /
        // « Export PDF ». Fusionnés en UN bouton « Exporter »
        // (`pwa.export.bouton`) ouvrant la modale partagée — dérogation PO du
        // 01/09/2026, rappelée le 02/09/2026 ; voir `DerogationsMaquette`
        // (export_bouton_unique) et `Facturation::ouvrirExport()`/
        // `genererExport()`. Le PDF est le REGISTRE affiché — la facture
        // individuelle garde son « Facture A4 » par ligne.
        'export_titre' => 'Exporter — Registre des factures',
        'export_sous_titre' => 'Périmètre : :filtre',
        'export_document' => 'Registre des factures émises',
        'export_vide' => 'Rien à exporter : aucune facture ne correspond aux filtres affichés.',
        // PA-119 — le document DIT son filtre, et « aucun filtre » se dit aussi.
        'export_filtre_recherche' => 'recherche « :terme »',
        'export_filtre_activite' => 'activité :valeur',
        'export_filtre_selection' => ':nombre pièce(s) sélectionnée(s)',
        'export_filtre_aucun' => 'Aucun filtre — tout le registre',
    ],
    /*
    |---------------------------------------------------------------------------
    | M4 — Carte du restaurant (`prototype_v2/pages/m4-restaurant-carte.html`)
    |---------------------------------------------------------------------------
    */
    'carte_restaurant' => [
        'motif_recette_sans_ingredient' => 'La fiche technique de ce plat n\'a aucun ingrédient : rien n\'est décrémenté à la vente.',
        'motif_point_cuisine_absent' => 'Aucun point de stockage de type « cuisine » n\'existe : on ignore d\'où sortiraient les denrées.',
        'motif_inconnu' => 'Portions non calculables.',
    ],

    /*
    |---------------------------------------------------------------------------
    | M4 — Restaurant & Cuisine (`prototype_v2/pages/m4-restauration.html`)
    |---------------------------------------------------------------------------
    */
    'restauration' => [
        'titre' => 'Restaurant & Cuisine',
        'sous_titre' => 'Gestion des menus, fiches de recette et prise de commande, avec déduction automatique du stock cuisine',

        'recherche' => 'Rechercher un plat...',
        'toutes_categories' => 'Toutes les catégories',

        'col_plat' => 'Plat',
        'col_categorie' => 'Catégorie',
        'col_prix' => 'Prix de vente',
        'col_disponible' => 'Disponible',
    ],
    /*
    |---------------------------------------------------------------------------
    | M14 — États & Rapports (`prototype_v2/pages/m14-etats-studio.html`)
    |---------------------------------------------------------------------------
    */
    'etats' => [
        'titre' => 'États & Rapports',

        'recherche' => 'Rechercher un état…  (touche /)',
        'tous' => 'Tous',
        'aucun' => 'Aucun état ne correspond.',
        'compteur' => ':nombre état(s) · droits portés par le module source',

        'accueil_titre' => 'Choisissez un état dans le catalogue',
        'accueil_detail' => ':total état(s) sont éditables avec vos droits. L\'aperçu s\'affiche '
            . 'immédiatement : vous ne consultez que ce que le moteur d\'états calcule réellement.',
        'accueil_rbac' => 'Les droits sont portés par le <strong>module source</strong> de chaque état, '
            . 'pas par M14 : un magasinier ne lit pas le livre de paie parce qu\'il a accès aux « États ».',

        'module_source' => 'module source :module',
        'lignes' => ':nombre ligne(s)',
        'aucune_ligne' => 'Aucune ligne sur cette période.',

        // Les cinq clés « refus_* » qui documentaient ici « Ce que cet écran
        // ne fait pas » sont RETIRÉES (directive du Product Owner du
        // 31/08/2026, voir le docblock d'`EtatsStudio`) : un écran ne
        // catalogue plus ses absences pour l'utilisateur — les motifs
        // restent, datés, dans le docblock du composant et de la vue, sous
        // forme de jetons `maitre-refuse:` mesurables.
    ],

    /*
    |---------------------------------------------------------------------------
    | M14 — États, Rapports & Exports (`prototype_v2/pages/m14-etats.html`)
    |
    | ⚠ Page que le maître déclare LUI-MÊME remplacée par la précédente.
    |---------------------------------------------------------------------------
    */
    'etats_legacy' => [
        'titre' => 'États, Rapports & Exports',
        'sous_titre' => 'Bibliothèque d\'états standards par module, entête normalisée commune, '
            . 'génération à la demande et export PDF/Excel',

        'remplace_titre' => 'Écran remplacé.',
        'remplace_texte' => 'Cette page reste consultable comme maquette validée par le client, mais elle '
            . 'n\'est plus au menu : la version fonctionnelle est',

        'module' => 'MODULE :module',

        'catalogue_vide_titre' => 'Aucun état n\'est éditable avec vos droits.',
        'catalogue_vide_detail' => 'Les droits sont portés par le module SOURCE de chaque état, pas par '
            . 'M14. Le registre du serveur compte trois états — stocks (M6), parc de véhicules (M8) et '
            . 'tableau de bord (M11) ; les autres dépendent de domaines non implémentés.',

        'historique_titre' => 'Historique des éditions',
        'historique_mention' => 'Journal d\'audit — lecture seule (chap. 11.4 du CdCF)',
        'historique_vide' => 'Aucun état généré sur cette période.',
        'historique_recherche' => 'Rechercher un état',
        'historique_tous_modules' => 'Tous les modules',

        'col_etat' => 'État',
        'col_module' => 'Module',
        'col_emetteur' => 'Émetteur',
        'col_date' => 'Date d\'édition',
        'col_format' => 'Format',
        'col_actions' => 'Actions',

        'decompte' => 'Affichage de :affiches sur :total',
        'tronque' => 'Liste tronquée à :plafond lignes.',

        'refus_generer' => 'Le bouton « Générer » de chaque carte n\'est pas rendu : générer INSÈRE une '
            . 'ligne dans `etats_generes` (archivage horodaté EF-M14-06), c\'est une écriture. Vérifié '
            . 'contre `GenerateurEtatService::generer()` le 27/08/2026.',
        'refus_modale' => 'La modale « Générer un état » — « Période », « Format d\'export », « Annuler », '
            . '« Générer et télécharger » — n\'est pas rendue, pour la même raison.',
        'refus_retelecharger' => 'L\'action « Retélécharger » de l\'historique n\'est pas rendue, et deux '
            . 'motifs suffisent chacun : elle repasse par le générateur, donc archive à nouveau ; et '
            // Article 8 (02/09/2026) : la reference PA-48 vit ici, jamais a l'ecran.
            . '`etats_generes.chemin_fichier_archive` vaut TOUJOURS `null` — il n\'y a aucun fichier '
            . 'à retélécharger. Le maître, lui, refabrique un CSV à la volée : ce n\'est pas le document '
            . 'd\'origine.',
        'refus_periode' => 'Les champs « Du » et « Au » et le bouton « Actualiser » ne sont pas rendus : '
            . 'chaque rendu relit la base, il n\'y a rien à rafraîchir à la main, et un filtre sans son '
            . 'bouton laisserait ignorer s\'il s\'applique.',
        'ecart_catalogue' => 'La grille rend les états RÉELLEMENT éditables — trois au registre du '
            . 'serveur — et non les huit cartes écrites en dur dans le HTML du maître : cinq d\'entre elles '
            . 'dépendent de domaines non implémentés, et les promettre serait annoncer un document que le '
            . 'moteur ne saurait pas produire. La description par état n\'existe pas au catalogue serveur et '
            . 'rend « — ».',
    ],

    /*
     * Carte du bar — maquette `prototype_v2/pages/m5-bar-carte.html`.

    /*
     * Réservations — maquette `prototype_v2/pages/reservations.html`.
     */
    'reservations' => [
        // maquette — l.28
        'titre' => 'Réservations',
        // maquette — l.31 : la définition du produit, rendue telle quelle.
        // La fiche cinq services vit sur le poste (PA-110/PA-29) : chaque
        // carte le dit.
        'sous_titre' => 'Une réservation peut combiner Hébergement, Restauration, Bar, Tourisme et/ou '
            . 'Location de véhicule sur une même fiche client.',
        // maquette — l.35
        'bouton_historique' => 'Historique',
        // maquette — l.50
        'recherche' => 'Rechercher un client...',
        'vide' => 'Aucune réservation pour l\'instant.',
        'nuits' => '{0} :nombre nuit|{1} :nombre nuit|[2,*] :nombre nuits',
        'service_hebergement' => 'Hébergement',
        'fiche_sur_poste' => 'Fiche complète (services, canal, remise) sur le poste de saisie',
        'unite' => 'Unité',
        'ligne_sejour' => 'Séjour',
        'ligne_acompte' => 'Acompte versé',

        // maquette — panneau historique, l.64-66
        'hist_titre' => 'Historique des réservations',
        'hist_sous_titre' => 'Toutes les réservations, passées et à venir, avec leur état réel.',
        // maquette — l.72 (« Client, canal ou n°… »)
        'hist_recherche' => 'Client, canal ou n°…',
        'hist_tous_etats' => 'Tous les états',
        'hist_etat_a_venir' => 'À venir',
        'hist_etat_en_cours' => 'En cours',
        'hist_etat_terminees' => 'Terminées',
        'hist_etat_annulees' => 'Annulées',
        'hist_reinitialiser' => 'Réinitialiser',
        'hist_vide' => 'Aucune réservation ne correspond à ces filtres.',
        'hist_tronque' => 'Liste tronquée aux 200 premières lignes — affinez les filtres.',

        // maquette — historique-reservations.js l.59-66 et l.104-113
        'hist_kpi_total' => 'Réservations',
        'hist_kpi_a_venir' => 'À venir',
        'hist_kpi_en_cours' => 'En cours',
        'hist_kpi_nuitees' => 'Nuitées',
        'hist_kpi_ca' => 'Chiffre d\'affaires',
        'hist_kpi_reste' => 'Reste à encaisser',
        'hist_col_client' => 'Client',
        'hist_col_sejour' => 'Séjour',
        'hist_col_nuits' => 'Nuits',
        'hist_col_unites' => 'Unités',
        'hist_col_services' => 'Services',
        'hist_col_total' => 'Total',
        'hist_col_reste' => 'Reste dû',
        'hist_col_etat' => 'État',

        // ---- La fiche d'écriture (vague 2 — créer, modifier, annuler) ----
        'bouton_nouvelle' => 'Nouvelle réservation',
        'modale_titre_creation' => 'Nouvelle réservation',
        'modale_titre_modification' => 'Modifier la réservation',
        'champ_client' => 'Client',
        'champ_client_invite' => 'Choisir un client…',
        'champ_unite' => 'Unité d\'hébergement',
        'champ_unite_invite' => 'Choisir une unité…',
        'champ_arrivee' => 'Date d\'arrivée',
        'champ_depart' => 'Date de départ',
        'champ_acompte' => 'Acompte versé (FCFA)',

        // La fiche du maître (`reservations.html`), portée par PA-163.
        'champ_type_client' => 'Type de client',
        'champ_canal' => 'Canal de réservation',
        'champ_canal_invite' => 'Choisissez un canal',
        'services_titre' => 'Services inclus dans cette réservation',
        'ligne_choisir' => 'Choisissez un élément du catalogue',
        'ligne_ajouter' => '+ Ajouter',
        'ligne_retirer' => 'Retirer cette ligne',

        // Zone de lignes, un bloc PAR SERVICE (`reservations-services.js`
        // `SERVICES[].labelLigne`, l.42-118) — le mot qui suit « + Ajouter ».
        'label_ligne_hebergement' => 'une chambre',
        'label_ligne_restauration' => 'un plat',
        'label_ligne_bar' => 'une boisson',
        'label_ligne_tourisme' => 'un circuit',
        'label_ligne_vehicule' => 'un véhicule',
        'qte_nuits' => 'Nuits',
        // Bandeau du bloc Hébergement (`rendreZoneLignes`, l.245-249).
        'nuits_banner_manquant' => 'Renseignez les dates d\'arrivée et de départ : le nombre de nuits et '
            . 'les montants s\'en déduiront.',
        'nuits_banner_connu' => '<strong>:nombre nuit(s)</strong> — calculées depuis les dates du séjour. '
            . 'Le champ n\'est pas saisissable : allongez ou raccourcissez le séjour et les montants suivent.',
        'ligne_aucun_element' => 'Aucun élément disponible actuellement pour :service.',
        'ligne_aucune' => 'Aucune ligne — cliquez sur « Ajouter » ci-dessus.',
        'sous_total_service' => 'Sous-total :service :',
        'recap_titre' => 'Récapitulatif',
        'champ_remise' => 'Remise',
        'remise_aucune' => 'Aucune',
        'champ_mode_paiement' => 'Mode de paiement',
        'mode_invite' => 'Choisissez un mode',
        // « Espèces » ajouté au registre du maître (écart déclaré,
        // 01/09/2026) : le comptoir encaisse des acomptes en liquide, et
        // sans mode la pièce comptable de l'acompte serait impossible.
        'mode_especes' => 'Espèces',
        'mode_mobile_money' => 'Mobile Money',
        'mode_virement' => 'Virement',
        'mode_cheque' => 'Chèque',
        'mode_credit' => 'Crédit',
        'qte_personnes' => 'Nb. personnes',
        'qte_quantite' => 'Quantité',
        'qte_participants' => 'Nb. participants',
        'qte_jours' => 'Nb. jours',
        'recap_sous_total' => 'Sous-total',
        'recap_total' => 'Total à payer',
        'recap_acompte' => 'Acompte versé',
        'recap_reste' => 'Reste à payer',

        'action_modifier' => 'Modifier',
        'action_annuler' => 'annuler',
        // Article 8 (02/09/2026) : la reference RG-02 vit ici, jamais a l'ecran.
        'confirmer_annulation' => 'Annuler cette réservation ? L\'unité sera libérée dans le calendrier.',
        'enregistree' => 'Réservation enregistrée.',
        'modifiee' => 'Réservation modifiée.',
        'annulee_flash' => 'Réservation annulée — l\'unité est libérée.',

        // ---- Nouvel onglet Annulations (EF-M1-06, instruction du Product
        // Owner du 01/09/2026) ----
        'onglet_actives' => 'Réservations',
        'onglet_annulations' => 'Annulations',
        'annulations_vide' => 'Aucune réservation annulée pour le moment.',

        // ---- Refus nommés (Article 8 — blocs complets dans le composant) ----
        'refus_saisie' => 'Le bouton « Ajouter client » et sa modale ne sont pas rendus : créer un client '
            . 'est une écriture M3 — l\'écran Clients & Créances la portera. La suppression n\'existera '
            . 'jamais (RG-02 : une réservation s\'annule, elle ne s\'efface pas), et « Imprimer la '
            . 'facture » attend la chaîne de facturation M2. Le motif d\'annulation du maître n\'est pas '
            // Article 8 (02/09/2026) : la reference PA-57 vit ici, jamais a l'ecran.
            . 'collecté : le serveur n\'a aucune colonne pour lui.',
        'refus_fiche_locale' => 'Le canal, le type de client, le mode de paiement, la remise et les lignes '
            . 'de services (Restauration, Bar, Tourisme, Véhicule — le filtre « Tous les services » compris) '
            . 'rendent « — » : la fiche complète est locale au poste de saisie, le schéma serveur n\'en '
            . 'porte rien (PA-29, PA-110).',
        'refus_montants' => 'Les montants « Séjour », « Consommations », « Total » et « Reste », et les '
            . 'cartes « Chiffre d\'affaires » et « Reste à encaisser » rendent « — » : aucun montant de '
            . 'séjour n\'existe au schéma serveur — le recalculer depuis la grille tarifaire courante '
            . 'réécrirait le prix d\'un séjour déjà vendu (PA-55, PA-57).',
        'refus_facture' => 'Le bouton « Facture » des cartes n\'est pas rendu : aucun chemin serveur ne '
            . 'relie une facture à une réservation, et le bouton du maître n\'existe que si la facture '
            // Article 8 (02/09/2026) : la reference PA-112 vit ici, jamais a l'ecran.
            . 'existe.',
    ],

    /*
     * Hébergement & Réservations — maquette `prototype_v2/pages/m1-hebergement.html`.
     */
    'hebergement' => [
        // maquette — l.23
        'titre' => 'Hébergement & Réservations',
        // maquette — l.26
        'sous_titre' => 'Gestion du plan d\'hébergement du Gîte Chez Noël (Bungalows, Chambres, Tentes) '
            . '• Règle anti-double réservation',
        // maquette — l.29-32
        'onglet_plan' => 'Plan d\'Hébergement',
        'onglet_reservations' => 'Réservations en cours',
        'onglet_calendrier' => 'Calendrier d\'Occupation',
        // Disponibilités - AJOUT (PO 08/10/2026) : « avez-vous une chambre du
        // 12 au 15 ? » se repond depuis le comptoir, sans changer d'ecran. Le
        // client Flutter avait cet ecran ; la vue Blade, maitre, ne l'avait pas.
        'onglet_disponibilites' => 'Disponibilités',
        'dispo_titre' => 'Disponibilités sur une période',
        'dispo_aide' => 'Choisissez une arrivée et un départ : chaque unité du parc est listée, libre ou non, avec son motif. Le départ est exclu (la nuit du départ reste libre).',
        'dispo_arrivee' => 'Arrivée',
        'dispo_depart' => 'Départ',
        'dispo_periode_invalide' => 'Le départ doit suivre l\'arrivée.',
        'dispo_resume' => ':libres libre(s) sur :total unité(s) pour :nuits nuit(s).',
        'dispo_col_unite' => 'Unité',
        'dispo_col_categorie' => 'Catégorie',
        'dispo_col_capacite' => 'Capacité',
        'dispo_col_montant' => 'Montant du séjour',
        'dispo_col_etat' => 'Disponibilité',
        'dispo_libre' => 'Libre',
        'dispo_indisponible' => 'Indisponible',
        'dispo_motif_reservation' => 'Réservée du :du au :au',
        'dispo_motif_hors_service' => 'Hors service',
        'dispo_motif_nettoyage' => 'En nettoyage',
        'dispo_reserver' => 'Réserver',
        'dispo_vide' => 'Le parc ne compte aucune unité.',
        // maquette — l.35
        'bouton_nouvelle_reservation' => 'Nouvelle réservation',

        // maquette — configuration CRUD, l.238
        'recherche' => 'Rechercher bungalow, chambre ou tente...',
        'toutes_categories' => 'Toutes les catégories',
        'parc_vide' => 'Le parc n\'a pas encore été renseigné : aucune unité d\'hébergement n\'existe '
            . 'sur ce serveur.',

        // maquette — `crud-ui.js` l.25 (bouton « Actualiser », icône seule).
        'actualiser' => 'Actualiser',

        // maquette — `crud-engine.js` l.254/256/258 (pagination du parc, 01/09/2026).
        // Decoupe en trois cles, comme `tourisme.pwa.sous_titre_*` : le maitre
        // met les nombres en gras (`<strong>`), un lang key n'embarque jamais
        // de balise HTML dans ce depot.
        'decompte_avant' => 'Affichage de',
        'decompte_liaison' => 'sur',
        'page_precedent' => '← Précédent',
        'page_suivant' => 'Suivant →',
        'page_sur' => 'Page :page / :total',
        // maquette — l.189
        'tarif_de_base' => 'Tarif de base :',
        // La pastille est la DISPONIBILITÉ CALCULÉE du jour (RG-02), jamais la
        // colonne `statut` que rien n'écrit — voir le composant.
        'pastille_libre' => 'Libre',
        'pastille_reservee' => 'Réservée',
        'pastille_hors_service' => 'Hors service',

        // maquette — rendreReservationsEnCours(), l.510-538
        'reservations_vide' => 'Aucune réservation d\'hébergement pour le moment.',
        'reservations_vide_lien' => 'Créer une réservation →',
        // Tableau générique du maître (crud-ui.js / crud-engine.js) — état
        // vide et pagination, portés le 01/09/2026 (G6).
        'reservations_vide_titre' => 'Aucun résultat',
        'reservations_vide_detail' => 'Essayez de modifier votre recherche ou vos filtres.',
        'reservations_affichage' => 'Affichage de :debut-:fin sur :total',
        'col_client' => 'Client',
        'col_unites' => 'Unité(s) réservée(s)',
        'col_arrivee' => 'Arrivée',
        'col_depart' => 'Départ',
        'col_statut' => 'Statut',

        // maquette — rendreCalendrierOccupation(), l.541-587
        'legende_faible' => 'Faible',
        'legende_moyen' => 'Moyen',
        'legende_fort' => 'Fort',
        // maquette — l.584 : « taux d'occupation estimé », porté tel quel
        // (PA-118) — un taux présenté comme exact servirait à décider d'une
        // sur-réservation.
        'mention_estime' => 'Taux d\'occupation estimé par jour, calculé à partir des réservations '
            . 'd\'hébergement enregistrées (:total unités au total).',
    ],

    /*
     * Clients & Créances — maquette `prototype_v2/pages/m3-clients-creances.html`.
     */
    'clients' => [
        // maquette — l.26
        'titre' => 'Clients & Créances',
        // maquette — l.29-31, adapté à ce que ce serveur calcule réellement :
        // écart motivé dans le composant (PA-29/PA-57 : aucun montant de
        // séjour au schéma). La phrase du maître qui compte est conservée :
        // le solde ne se saisit jamais.
        'sous_titre' => 'Le solde d\'un client est <strong>calculé</strong> : factures certifiées non '
            . 'soldées, diminuées des règlements reçus. Il ne se saisit jamais.',
        // maquette — l.36
        'lien_reservations' => 'Réservations',
        // maquette — l.35, portée le 02/09/2026 (PA-165)
        'nouveau_client' => '+ Nouveau client',

        // maquette — rendreKpis(), m3-clients-creances.js l.106-126 — les
        // CINQ cartes sont réellement calculées depuis le 02/09/2026 (PA-165
        // lève PA-21 ; la balance âgée réelle, PA-20 côté « échéance », lève
        // les deux dernières).
        'kpi_creances' => 'Créances totales',
        'kpi_creances_detail' => ':pieces pièce(s) · :clients client(s)',
        'kpi_douteux' => 'Dont + de 90 jours',
        'kpi_recentes' => '0 à 30 jours',
        'kpi_tranches_detail' => 'Part de la créance totale sur cette tranche',
        'kpi_recentes_detail' => 'Récent, non échu',
        'kpi_encaisse' => 'Encaissé sur 30 j',
        'kpi_encaisse_detail_reel' => 'Recouvrements réellement enregistrés',
        'kpi_relancer' => 'Clients à relancer',
        'kpi_relancer_detail_reel' => 'Plus de 30 j sans relance récente',

        // maquette — l.44-47 — les QUATRE onglets sont portés (PA-165)
        'onglet_clients' => 'Liste des clients',
        'onglet_dettes' => 'Suivi des dettes',
        'onglet_relances' => 'Relances clients',
        'onglet_avances' => 'Historique & avances',

        // maquette — l.56 et l.59-63
        'recherche' => 'Rechercher un client…',
        'tous_clients' => 'Tous les clients',
        'etat_debiteur' => 'Débiteurs uniquement',
        'etat_solde' => 'Sans dette',

        'vide' => 'Aucun client ne correspond à ces critères.',

        // maquette — vueClients(), l.137
        'col_client' => 'Client',
        'col_telephone' => 'Téléphone',
        'col_type' => 'Type',
        'col_solde' => 'Solde dû',
        'col_pieces' => 'Pièces',
        'col_anciennete' => 'Ancienneté',
        'action_historique' => 'Historique',
        'action_recouvrement' => 'Recouvrement',
        'action_detail' => 'Détail',
        'action_relancer' => 'Relancer',

        // maquette — `m3-clients-creances.html` l.64-65 : « Excel » / « PDF ».
        // Fusionnés en UN bouton « Exporter » (`pwa.export.bouton`) ouvrant la
        // modale partagée — dérogation PO du 01/09/2026, rappelée le
        // 02/09/2026 ; voir `DerogationsMaquette` (export_bouton_unique) et
        // `ClientsCreances::ouvrirExport()`/`genererExport()`.
        'export_titre' => 'Exporter — Clients & Créances',
        'export_sous_titre' => 'Périmètre : :filtre',
        'export_document' => 'Registre des clients et créances',
        // Titre de l'en-tête RG-19 du relevé remis au client (PA-194).
        'releve_document' => 'Relevé de compte client',
        'export_vide' => 'Rien à exporter : aucun client ne correspond aux filtres affichés.',
        'export_onglet_refuse' => 'L\'export n\'est offert que sur l\'onglet Liste des clients.',
        // PA-119 — le document DIT son filtre, et « aucun filtre » se dit aussi.
        'export_filtre_recherche' => 'recherche « :terme »',
        'export_filtre_etat' => 'état :valeur',
        'export_filtre_aucun' => 'Aucun filtre — tout le registre',

        // ---- Onglet 2 — Suivi des dettes (balance âgée, `vueDettes()`) ----
        'tranche_0_30' => '0 à 30 jours',
        'tranche_31_60' => '31 à 60 jours',
        'tranche_61_90' => '61 à 90 jours',
        'tranche_plus_90' => 'Plus de 90 jours',
        'col_total_du' => 'Total dû',
        'dettes_total' => 'Total',
        'dettes_vide' => 'Aucune créance en cours. Tous les clients sont à jour.',
        'dettes_titre_encadre' => 'Balance âgée.',
        'dettes_texte_encadre' => 'Les tranches classent chaque pièce par ancienneté depuis sa date '
            . 'd\'émission. Au-delà de 90 jours, le recouvrement devient incertain et une provision '
            . 'pour dépréciation doit être envisagée — son taux relève d\'une décision du Comptable et '
            . 'du Gérant, il n\'est pas calculé ici.',

        // ---- Onglet 3 — Relances (`vueRelances()`) ----
        'relances_encadre' => 'La relance est tracée, pas envoyée. Aucun canal (WhatsApp, e-mail) '
            . 'n\'est branché sur ce système : enregistrer un envoi qui n\'a pas eu lieu ferait croire à '
            . 'un suivi inexistant.',
        'relances_a_relancer_titre' => 'Clients à relancer (:nombre)',
        'relances_a_relancer_vide' => 'Aucun client à relancer : toutes les créances de plus de 30 jours '
            . 'ont été relancées récemment.',
        'relances_historique_titre' => 'Historique des relances (:nombre)',
        'relances_historique_vide' => 'Aucune relance enregistrée.',
        'col_montant_du' => 'Montant dû',
        // maquette — vueRelances(), m3-clients-creances.js l.207-219 :
        // colonnes « Ancienneté max » et « Dernière relance », rendues avec
        // des données réelles depuis le 01/09/2026 (voir clientsARelancer()).
        'col_anciennete_max' => 'Ancienneté max',
        'col_derniere_relance' => 'Dernière relance',
        'anciennete_jours' => ':jours j',
        'relance_jamais' => 'Jamais relancé',
        'col_date' => 'Date',
        'col_canal' => 'Canal',
        'col_montant_reclame' => 'Montant réclamé',
        'col_promesse' => 'Promesse',
        'col_par' => 'Par',
        'canal_telephone' => 'Appel téléphonique',
        'canal_whatsapp' => 'WhatsApp',
        'canal_email' => 'E-mail',
        'canal_courrier' => 'Courrier remis en main propre',
        'canal_visite' => 'Visite',

        // ---- Onglet 4 — Historique & avances (`vueAvances()`) ----
        'avances_titre' => 'Avances et acomptes (:nombre)',
        'avances_vide' => 'Aucune avance enregistrée.',
        'recouvrements_titre' => 'Recouvrements encaissés (:nombre)',
        'recouvrements_vide' => 'Aucun recouvrement enregistré.',
        'col_origine' => 'Origine',
        'col_avance_versee' => 'Avance versée',
        'col_reste_du' => 'Reste dû',
        'solde_paye' => 'Soldé',
        'col_numero' => 'N°',
        'col_piece' => 'Pièce',
        'col_mode' => 'Mode',
        'col_reference' => 'Référence',
        'col_montant' => 'Montant',
        'mode_especes' => 'Espèces',
        'mode_mobile_money' => 'Mobile Money',
        'mode_carte' => 'Carte',
        'mode_virement' => 'Virement bancaire',

        // ---- Modale « Nouveau client » ----
        'modale_client_titre' => 'Nouveau client',
        'champ_nom' => 'Nom / Raison sociale',
        'champ_nom_exemple' => 'Ex. Jean KORA ou Agence Bénin Tour',
        'champ_telephone' => 'Téléphone',
        'champ_telephone_exemple' => '01 90 12 34 56',
        'champ_type' => 'Type',
        'champ_creer' => 'Créer le client',
        'modale_client' => [
            'succes' => 'Client « :nom » créé.',
        ],

        // ---- Modale « Ajouter un recouvrement » ----
        'modale_recouvrement_titre' => 'Ajouter un recouvrement',
        'champ_piece_reglee' => 'Pièce réglée',
        'champ_du' => 'dû',
        'champ_montant_recu' => 'Montant reçu (FCFA)',
        'champ_mode' => 'Mode',
        'champ_reference' => 'Référence',
        'champ_reference_exemple' => 'N° de transaction Mobile Money, n° de chèque…',
        'champ_commentaire' => 'Commentaire',
        'champ_enregistrer_recouvrement' => 'Enregistrer le recouvrement',
        'recouvrement_avertissement' => 'Un montant supérieur au reste dû est refusé.',
        'recouvrement_aucune_creance' => 'Ce client n\'a aucune créance en cours.',
        // PA-186 : `:montant` arrive DÉJÀ mis en forme par `MontantFcfa`,
        // suffixe « FCFA » compris — ne pas le recopier ici.
        'recouvrement_succes' => 'Recouvrement de :montant enregistré pour :client.',

        // ---- Modale « Tracer une relance » ----
        'modale_relance_titre' => 'Tracer une relance',
        'champ_canal' => 'Canal utilisé',
        'champ_montant_reclame' => 'Montant réclamé',
        'champ_promesse' => 'Promesse de règlement',
        'champ_compte_rendu' => 'Compte rendu',
        'champ_compte_rendu_exemple' => 'Ce que le client a répondu.',
        'champ_enregistrer_relance' => 'Enregistrer la relance',
        'relance_avertissement' => 'Cet écran enregistre une relance déjà effectuée. Il n\'envoie aucun '
            . 'message : aucun canal n\'est branché sur ce système.',
        'relance_succes' => 'Relance de « :client » enregistrée.',

        // ---- Modale « Historique d'un client » ----
        'historique_vide' => 'Aucun mouvement pour ce client.',
        'historique_type_encaissement' => 'Encaissement',
        'historique_type_relance' => 'Relance',
        // maquette — ouvrirHistorique(), m3-clients-creances.js l.564-569 et
        // son état PDF l.597 (« Libellé », « Détail »).
        'col_libelle' => 'Libellé',
        'col_detail' => 'Détail',
        'historique_imprimer_pdf' => 'Imprimer PDF',
    ],

    // Confirmations d'ECRITURE — la PWA n'est plus en lecture seule depuis le
    // 27/08/2026 (decision du Product Owner).
    'fournisseur_enregistre' => 'Fournisseur enregistré.',

    /*
     * M13 PERSONNEL & PAIE — l'ecran NOMME ce qu'il ne fait pas.
     *
     * Le titre est celui du maitre (`m13-paie.html`). Le reste dit l'etat
     * reel, date : sans date, un motif de refus qui cesse d'etre vrai
     * transforme une decision en oubli (PA-144).
     */
    'm13' => [
        'titre' => 'Personnel & Paie',
        'sous_titre' => 'Gestion du personnel, planning, congés et calcul de paie — Gîte Chez Noël.',
        'etat_titre' => 'Écran de paie non livré — état au 31/08/2026',
        'etat_texte' => 'Le module M13 est partiellement implémenté côté serveur. Cet écran '
            . 'annonce ce qui existe et ce qui manque plutôt que d\'afficher un tableau que rien '
            . 'n\'alimente : un chiffre de paie faux n\'est pas une approximation, c\'est une '
            . 'déclaration sociale erronée.',
        'disponible_titre' => 'Ce qui existe côté serveur',
        'disponible_1' => 'Calcul du net salarial : retenue CNSS salarié 3,6 % et barème ITS '
            . '(CalculPaieService).',
        'disponible_2' => 'Part confirmée de la charge patronale : CNSS pension 6,4 %, '
            . 'prestations familiales 9 % et VPS 4 %, soit 19,4 % du brut.',
        'disponible_3' => 'Planning des services et demandes de congés (PlanningService, '
            . 'CongeService), avec contrôle de chevauchement.',
        'absent_titre' => 'Ce qui n\'existe nulle part',
        'absent_1' => 'Pointage, primes et évaluations : ni table, ni service, ni route API.',
        'absent_2' => 'Bulletins de paie, livre de paie et déclarations : aucun document n\'est '
            . 'généré côté serveur.',
        'absent_3' => 'Aucune route API M13 : cet écran n\'aurait rien à lire, ni rien où écrire.',
        'refus_total_titre' => 'Le total de charge patronale est REFUSÉ, délibérément.',
        'refus_total_texte' => 'Le taux CNSS de risques professionnels est « 1 % à 4 % selon '
            . 'l\'activité » et n\'est pas confirmé pour l\'hôtellerie. Le service publie la '
            . 'fourchette au lieu de la moyenner : retenir 2,5 % « au milieu » serait exactement '
            . 'l\'hypothèse refusée. Un Administrateur muni de la source officielle renseigne ce '
            // Article 8 (02/09/2026) : la reference PA-53 vit ici, jamais a l'ecran.
            . 'taux dans Paramètres — il n\'arrivera jamais par un seeder.',
    ],

    /*
     * M12 NOTIFICATIONS — le seul domaine ENTIEREMENT vide du depot.
     */
    'm12' => [
        'titre' => 'Notifications',
        'sous_titre' => 'Diffusion des alertes et confirmations vers WhatsApp, e-mail et Android.',
        'etat_titre' => 'Canal de notification non contracté — état au 31/08/2026',
        'etat_texte' => 'Le module M12 n\'a ni modèle, ni service, ni route : c\'est le seul '
            . 'domaine entièrement vide du dépôt. La cause n\'est pas un reste-à-faire de '
            . 'développement — l\'API WhatsApp n\'est pas contractée, et RG-20 (diffusion '
            . 'automatique) est la seule des vingt règles de gestion qui reste à implémenter.',
        'liste_titre' => 'Pourquoi aucune liste n\'est affichée',
        'liste_texte' => 'Rendre la liste du maître avec zéro ligne afficherait « aucune '
            . 'notification » — une affirmation sur un état que rien ne mesure, puisque aucune '
            . 'table ne les stocke. Un indicateur qui dit « tout va bien » pendant que rien n\'a '
            . 'lieu est le défaut que ce dépôt traque (PA-59/60/61).',
        'secret_titre' => 'Et quand le canal existera',
        'secret_texte' => 'La clé d\'API du fournisseur ira dans le fichier d\'environnement, '
            . 'jamais dans les paramètres système : ceux-ci sont lisibles par tout profil ayant '
            . 'accès à l\'écran Paramètres.',
    ],

    /*
     * CHASSIS DE MODALE PARTAGE — `resources/views/components/pwa/modale*`.
     *
     * Le maitre ne fabrique pas ses modales page par page : `crud-ui.js` en
     * pose cinq gabarits pour tout le prototype. Les libelles de chrome
     * (fermer, annuler) vivent donc ici, une fois, et pas dans dix-neuf vues.
     */
    'modale' => [
        // maquette — `crud-ui.js` l.92, attribut `aria-label`
        'fermer' => 'Fermer',
        'annuler' => 'Annuler',
    ],

    /*
     * ARCHIVAGE — et ce N'EST PAS une suppression.
     *
     * `prototype_v2/assets/js/crud-engine.js` l.524-552 : le geste range
     * l'element aux archives, d'ou il reste restaurable. Le titre de la
     * modale du maitre dit pourtant « Confirmer la suppression »
     * (`crud-ui.js` l.131) et le bouton « Supprimer definitivement » : les
     * deux sont repris tels quels, parce que c'est le texte que le client a
     * valide. Le CORPS, lui, dit ce qui se passe reellement — c'est la seule
     * phrase que l'utilisateur lit avant de cliquer.
     *
     * ⚠ Cote serveur, aucun de ces boutons ne supprime : `BasePolicy::delete()`
     * rend `false` pour les 20 policies. Le geste metier (annuler,
     * contre-passer, avoir, mouvement inverse) est le seul chemin.
     */
    'archivage' => [
        // maquette — `crud-ui.js` l.131
        'titre' => 'Confirmer la suppression',
        // maquette — `crud-ui.js` l.136
        'confirmer' => 'Supprimer définitivement',
        // maquette — `crud-engine.js` l.534
        'impossible' => 'Archivage impossible',
        // maquette — `crud-engine.js` l.536
        'retirer_dabord' => 'Retirez d\'abord l\'élément des opérations concernées, ou '
            . 'laissez-le en place : une carte historique reste lisible.',
        // maquette — `crud-engine.js` l.548
        'conserves' => ':nombre élément(s) seront conservés : ils sont engagés ailleurs.',
        // maquette — `crud-engine.js` l.543
        'question' => 'Voulez-vous archiver :element ?',
        // maquette — `crud-engine.js` l.546
        'question_multiple' => 'Voulez-vous archiver les :nombre élément(s) sélectionnés ?',
        // maquette — `crud-engine.js` l.542. Le <strong> est celui du maitre.
        'rappel' => 'L\'élément part aux <strong>archives</strong> et reste restaurable — '
            . 'rien n\'est effacé.',
        /*
         * Le refus SERVEUR du geste, quand le rôle n'est ni administrateur ni
         * super_admin et que la bascule « Suppression d'un enregistrement »
         * est fermée en Paramètres (`AutoriseArchivage`, 03/09/2026). Le
         * bouton n'est pas rendu dans ce cas : y arriver signifie qu'une
         * propriété a été forcée depuis le navigateur, ou que la bascule s'est
         * refermée entre le rendu et le clic.
         */
        'refus_bascule' => 'Archivage refusé : l\'option « Suppression d\'un enregistrement » est fermée '
            . 'en Paramètres pour ce profil.',
    ],

    /*
     * MODALE D'EXPORT UNIFIEE — `pwa/partials/modale-export.blade.php`.
     *
     * ⚠ DEROGATION AU MAITRE, assumee et datee (31/08/2026, decision du
     * Product Owner). `crud-ui.js` l.142-160 n'offre QUE du CSV et aucun
     * choix de format. La Directive de conformite impose ici un choix radio
     * PDF A4 / Excel : c'est un ELARGISSEMENT, pas une derive — le CSV du
     * maitre reste atteignable par la branche « Tableur ». Le declarer
     * plutot que l'ignorer est ce qui empeche la garde d'etre desactivee.
     */
    'export' => [
        'sous_titre' => 'Choisissez le format d\'exportation certifié',
        'format' => 'Format du document',
        'pdf_titre' => 'PDF Officiel A4 Imprimable',
        'pdf_detail' => 'Document certifié avec en-tête et signatures',
        'excel_titre' => 'Tableur Excel (.xlsx / .csv)',
        'excel_detail' => 'Données numériques brutes réutilisables',
        'generer' => 'Générer & Télécharger',

        /*
         * BOUTON D'ENTRÉE UNIQUE — dérogation PO du 01/09/2026.
         *
         * Le maître pose deux boutons d'entrée (« Excel » et « PDF » /
         * « Export Excel » et « Export PDF » selon l'écran) qui ouvraient
         * chacun la même modale, déjà en mesure d'offrir le choix du format
         * (dérogation ci-dessus, 31/08/2026). Le Product Owner a demandé de
         * fusionner les deux boutons d'entrée en un seul, sur toute page qui
         * affichait la paire : le format ne se choisit plus qu'à l'intérieur
         * de la modale. Voir `App\Pwa\Support\DerogationsMaquette`
         * (export_bouton_unique) pour la liste des écrans concernés et les
         * jetons `maitre-refuse:<page>#<bloc>` posés à chacun.
         */
        'bouton' => 'Exporter',
    ],

    /*
     * Erreurs de PROGRAMMATION du pont `ReglesDeLApi` (App\Pwa\Support).
     *
     * Elles ne s'adressent pas a un utilisateur du Gite mais a un
     * developpeur — et elles passent quand meme par ce fichier : la garde
     * `MessagesUtilisateurTest` refuse toute chaine accentuee levee depuis le
     * code, sans exception de destinataire. Une exception « juste pour les
     * messages techniques » est la breche par laquelle les autres reviennent.
     */
    'support' => [
        'regles_sans_methode' => 'La classe :classe ne déclare pas de méthode rules().',
        'champ_api_inconnu' => 'Le champ API « :champ » n\'existe pas dans :classe::rules().',
    ],

    /*
     * ------------------------------------------------------------------
     * VERROU DE SESSION — demande du Product Owner du 01/09/2026, sans
     * équivalent au maître (une maquette statique n'a pas de notion
     * d'inactivité). Voir `App\Pwa\Livewire\Transverse\VerrouSession`.
     * ------------------------------------------------------------------
     */
    'verrou' => [
        'titre' => 'Session verrouillée',
        // La phrase que le Product Owner a explicitement demandée, mot pour
        // mot : elle dit ce qui NE s'est PAS passé (déconnexion) autant que
        // ce qui s'est passé (suspension), pour qu'un utilisateur revenant
        // après 15 minutes ne cherche pas à se reconnecter en croyant avoir
        // perdu sa saisie en cours.
        'message' => 'Votre session est suspendue, pas fermée.',
        'sous_message' => 'Ressaisissez votre mot de passe pour reprendre exactement où vous en étiez.',
        'mot_de_passe' => 'Mot de passe',
        'deverrouiller' => 'Déverrouiller',
        'erreur' => 'Mot de passe incorrect.',
        'trop_de_tentatives' => 'Trop de tentatives. Réessayez dans :secondes seconde(s).',
    ],
];
