<?php

declare(strict_types=1);

/*
 * Libelles du moteur d'etats (M14) — RG-19, DIRECTIVE_EXPORT_PDF.md.
 *
 * Ces chaines sont imprimees sur des documents remis a des tiers (comptable
 * externe, DGI) : elles sont ici et nulle part ailleurs (06 §4.4).
 */

return [
    'entete' => [
        /*
         * REPRIS le 02/09/2026 (directive PO sur l'en-tete de TOUS les
         * documents imprimes) : ligne 1 « TATACORA AFRIQUE », ligne
         * d'enseigne « gîte chez noël » EN MINUSCULES. L'enseigne est donc
         * sortie de `sous_titre` : elle est DERIVEE par l'auteur unique
         * `ReportHeaderService::identite()` (separation sur le tiret de la
         * raison sociale parametree, minuscules appliquees la-bas), et
         * `enseigne` ci-dessous n'est que le REPLI quand la raison sociale
         * parametree ne porte pas de tiret. `localisation` reste la seconde
         * ligne du bloc.
         *
         * ⚠ `localisation` est AUSSI la ligne sous la marque de la barre
         * supérieure de la PWA (`pwa/partials/barre-superieure.blade.php`,
         * décision du Product Owner du 13/10/2026, qui y remplace
         * « LogiRestock ») ET la ligne sous l'enseigne de l'écran de
         * démarrage (`pwa/demarrage.blade.php`, même décision étendue le
         * 13/10/2026, PA-208) ; le client Flutter la relit. La modifier ici
         * change les deux écrans et le papier ensemble — c'est voulu.
         *
         * DÉCISION DU PRODUCT OWNER DU 13/10/2026 (PA-209, ticket D389) :
         * « Système d'Information Intégré » devient « Système de gestion
         * Intégré » — casse EXACTE du PO. Ne pas rétablir l'ancienne
         * formule : `AucunLogiRestockAfficheTest` rougit.
         *
         * DÉCISION DU PRODUCT OWNER DU 14/10/2026 : la mention sous la marque
         * devient « Système de gestion Intégré — Gîte Chez Noël, Natitingou
         * (Bénin) » — la même phrase que `pwa.aide.enseigne`.
         */
        'enseigne' => 'Gîte Chez Noël',
        'localisation' => 'Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)',

        /*
         * Pied institutionnel exige par la grille RESPECT_TABLEAU_RAPPORT.md
         * (« mention PAEB/FAGUEZ SARL + date/heure d'edition »).
         */
        'mention_institutionnelle' => 'Projet PAEB — Cabinet FAGUEZ SARL',

        'genere_par' => 'Généré par : :auteur',
        'edite_le' => 'Le :date',

        /*
         * Aucun nom generique n'est fabrique : RESPECT_TABLEAU_RAPPORT.md §4
         * recense « Auteur affiche = "Administrateur" par defaut » comme
         * non-conformite frequente.
         */
        'auteur_inconnu' => 'Auteur non identifié',
    ],

    /*
     * Zone de signatures des PDF d'export — `Directive.txt` §6.2 (l.416), au
     * mot : « Visa Ordonnateur / Caissier », « Visa Direction / Contrôle ».
     * Mise en conformité décidée par le Product Owner le 11/09/2026 (PA-192).
     * Un document qui porte des visas PROPRES à son circuit (magasinier,
     * responsable achats…) les garde : c'est une zone de signatures, et elle
     * nomme mieux qui signe.
     */
    'signatures' => [
        'visa_ordonnateur' => 'Visa Ordonnateur / Caissier',
        'visa_direction' => 'Visa Direction / Contrôle',
    ],

    'etat_inconnu' => 'Aucun état ne correspond au code « :code ».',
    'aucune_donnee' => 'Aucune donnée pour cette période ou ce filtre.',
    'format_inconnu' => 'Format d\'export inconnu : « :format ». Formats admis : pdf, excel.',
    'flux_indisponible' => 'Le fichier d\'export n\'a pas pu être ouvert en écriture.',

    'periode' => [
        'toutes' => 'Toutes périodes',
        'du_au' => 'Du :debut au :fin',
        'a_compter_du' => 'À compter du :debut',
        'jusqu_au' => "Jusqu'au :fin",
        'exercice' => 'Exercice :annee',
    ],
];
