<?php

declare(strict_types=1);

/**
 * Écran PWA « Facturation & Caisse MECeF » (M2) — les gestes d'écriture.
 *
 * `lang/fr/pwa.php` porte déjà les libellés de LECTURE du registre (titres,
 * colonnes, compteurs, blocs de refus) et n'est pas modifiable par ce lot.
 * Ce fichier-ci ne porte que ce que le lot ajoute : l'avoir (RG-03) et le
 * document A4. Les deux registres restent distincts, comme
 * `depenses.php` / `depenses_pwa.php`.
 *
 * ⚠ Aucun de ces messages n'affirme une certification. `MecefClientFake`
 * produit des numéros `MECEF-DEMO-`, et PA-17 (inscription DGI) n'est pas
 * lancée : tout ce qui se dit ici se dérive de `Facture::estCertifiee()`,
 * jamais d'une constante (PA-61, PA-100, PA-119).
 */
return [

    // --- Colonne du maître rendue vide (Article 7) ------------------------
    //
    // `m2-facturation.html` l.266-267 la déclare dans la configuration de son
    // moteur. Elle est RENDUE — sinon la colonne disparaîtrait sans que rien
    // ne le dise — et vide, parce que la donnée n'existe pas côté serveur.

    'col_mode_paiement' => 'Mode de paiement',

    // --- Avoir (RG-03) ----------------------------------------------------

    'avoir_action' => 'Avoir',
    'avoir_titre' => 'Émettre un avoir',
    'avoir_sous_titre' => "La facture d'origine reste inchangée : l'avoir la neutralise, "
        .'en tout ou partie. Les deux pièces coexistent.',

    'avoir_facture' => 'Facture',
    'avoir_montant' => 'Montant de l\'avoir (FCFA)',
    'avoir_montant_aide' => 'Au plus le montant TTC de la facture — :plafond.',
    'avoir_motif' => "Motif de l'avoir",
    'avoir_motif_invite' => 'ex. Prestation non fournie — nuitée annulée',
    'avoir_valider' => "Émettre l'avoir",
    'avoir_emis' => 'Avoir de :montant émis sur la facture :numero.',

    'avoir_introuvable' => "Cette facture n'existe plus au registre : l'avoir n'a pas été émis.",

    // --- Registre imprimé (forme document du moteur du maître) ------------
    //
    // Les trois libellés que le maître n'écrit QUE dans la configuration de
    // son moteur CRUD (`m2-facturation.html`, bloc `"colonnes"`) : « N° MECeF »,
    // « Services combinés », « Montant TTC ». Les quatre autres colonnes du
    // même bloc (Client, Date, Mode de paiement, Statut) réutilisent les clés
    // existantes — deux auteurs pour un même mot finiraient par diverger.

    'registre_col_numero_mecef' => 'N° MECeF',
    'registre_col_services' => 'Services combinés',
    'registre_col_montant_ttc' => 'Montant TTC',

    // --- Document A4 ------------------------------------------------------

    'document_action' => 'Facture A4',
    'document_titre' => 'Facture',
    'document_fichier' => 'facture',

    'document_numero' => 'N° MECeF',
    'document_date' => "Date d'émission",
    'document_client' => 'Client',
    'document_etabli_par' => 'Établie par',

    'document_col_designation' => 'Désignation',
    'document_col_activite' => 'Activité',
    'document_col_quantite' => 'Qté',
    'document_col_prix' => 'Prix unitaire',
    'document_col_montant' => 'Montant',

    'document_total_ht' => 'Total HT',
    'document_tva' => 'TVA',
    'document_total_ttc' => 'Total TTC',

    // Le libellé visible ne porte plus « (RG-03) » depuis le 01/09/2026 —
    // Article 8 : la référence va en commentaire, jamais à l'écran.
    'document_avoirs' => 'Avoirs rattachés',
    'document_avoir_ligne' => 'Avoir du :date — :motif',
    'document_net' => 'Net après avoirs',

    // Encaissements et reste dû — PA-165. Un paiement annulé (PA-168) reste
    // affiché, jamais masqué (RG-15) : la clé dédiée le nomme explicitement,
    // plutôt qu'un badge ajouté en aval.
    'document_encaissements' => 'Encaissements reçus',
    'document_encaissement_ligne' => 'Encaissement du :date — :mode',
    'document_encaissement_ligne_annulee' => 'Encaissement du :date — :mode — annulé (:motif)',
    'document_reste_du' => 'Reste dû',

    // Filigrane et mentions fiscales — dérivés, jamais figés. Les libellés
    // ci-dessous ne portent plus de code PA-xx ni de nom de fichier depuis le
    // 01/09/2026 (Article 8) ; le motif reste documenté dans le docblock de
    // ce fichier et de `pdf/facture-mecef.blade.php`.
    // `document_filigrane` et `document_mention_demo` supprimées le
    // 01/09/2026 — passage au réel (décision PO) : la facture est un
    // document commercial remis au client. La mention ci-dessous reste
    // DÉRIVÉE de l'état réel de certification, jamais figée (PA-61).
    'document_mention_attente' => 'Certification électronique MECeF : en attente d\'inscription '
        .'auprès de la Direction Générale des Impôts du Bénin.',
    'document_cachet_reserve' => 'Emplacement réservé au cachet fiscal MECeF',
    'document_cachet_absent' => "Aucun cachet n'est imprimé : le format du code fiscal n'est pas "
        .'public, et en dessiner un exemple sur un document remis à un client produirait un faux.',

    // --- Refus déclarés (Article 8) --------------------------------------

    // --- État vide (crud-ui.js) -------------------------------------------

    'aucun_resultat' => 'Aucun résultat',
    'aucun_resultat_detail' => 'Essayez de modifier votre recherche ou vos filtres.',

    // --- Tableau générique du maître (crud-engine.js) — 01/09/2026 --------
    //
    // Sélection et pagination, portées avec le même vocabulaire que
    // `achats_pwa.tableau` : le moteur du maître est UN, chaque écran en
    // reprend les mots dans son propre registre.

    'selection_tout' => 'Tout sélectionner',
    'selection_ligne' => 'Sélectionner cette ligne',
    'affichage' => 'Affichage de :debut-:fin sur :total',
];
