<?php

declare(strict_types=1);

/**
 * Écran PWA « Comptabilité SYSCOHADA » (M10, hub) — libellés et messages.
 *
 * Fichier distinct de `lang/fr/comptabilite.php`, qui sert le DOMAINE : ses
 * messages nomment un refus métier et sont partagés avec l'API le cas
 * échéant. Ceux-ci n'existent que pour l'écran — Vague E, 01/09/2026,
 * onglets « Passer écriture », « Immobilisations », « Plan comptable » et
 * « Clôtures » du hub `prototype_v2/pages/m10-syscohada.html`.
 *
 * ⚠ Consigne du lot : « jamais pwa.php si évitable » — les clés déjà posées
 * dans `lang/fr/pwa.php` sous `comptabilite.*` par le lot précédent (bandeau,
 * filtres, export Excel du Journal…) restent là où elles sont : les
 * dupliquer ici aurait fait deux registres pour le même écran. Ce fichier ne
 * porte QUE les clés introduites par ce lot.
 */
return [

    // --- Onglet « Passer écriture » — m10-syscohada.js vueSaisie() -------

    'saisie_intro_titre' => 'Passer une écriture comptable',
    'saisie_intro_detail' => 'Journal, date, libellé de pièce et lignes Compte / Libellé / Centre / '
        . 'Débit / Crédit. Contrôles appliqués à l’enregistrement : débit = crédit '
        . '(une pièce déséquilibrée n’est jamais enregistrée), date dans un exercice ouvert, '
        // Article 8 (02/09/2026) : la reference RG-12 vit ici, jamais a l'ecran.
        . 'compte existant au plan, et centre analytique obligatoire sur les classes 6, 7 et 8.',
    'saisie_bouton' => 'Nouvelle écriture',
    'saisie_aucun_exercice' => 'Aucun exercice ouvert.',
    'saisie_aucun_exercice_detail' => 'Ouvrez un exercice depuis l’onglet Clôtures avant de saisir la moindre écriture.',

    'modale_piece_titre' => 'Passer écriture',
    'champ_journal' => 'Journal',
    'champ_date' => 'Date',
    'champ_libelle_piece' => 'Libellé de la pièce',
    'champ_libelle_piece_invite' => 'Ex. Facture FAC-2026-0142 — séjour KORA',
    'col_libelle_ligne' => 'Libellé de la ligne',
    'ligne_ajouter' => 'Ajouter une ligne',
    'ligne_retirer' => 'Retirer la ligne',
    'enregistrer_brouillon' => 'Enregistrer en brouillon',
    'enregistrer_valider' => 'Enregistrer et valider',
    'immuabilite_titre' => 'Validation = immuabilité.',
    // Article 8 (02/09/2026) : la reference RG-11 vit ici, jamais a l'ecran.
    'immuabilite_detail' => 'Une écriture validée ne peut plus être ni modifiée ni supprimée. '
        . 'Le brouillon reste corrigeable, mais il bloque la clôture tant qu’il n’est pas tranché.',
    'choisir' => 'Choisir…',
    'totaux' => 'Totaux',
    'piece_equilibree' => 'Pièce équilibrée.',
    'piece_ecart' => 'Écart de :montant.',
    'piece_brouillon_enregistree' => 'Pièce enregistrée en brouillon.',
    'piece_validee_enregistree' => 'Pièce enregistrée et validée.',
    'ligne_debit_et_credit' => 'Ligne :position : le débit et le crédit ne peuvent pas être renseignés en même temps.',
    'ligne_montant_requis' => 'Ligne :position : un montant est requis, au débit ou au crédit.',

    // --- Plan comptable — « + Créer un compte » ---------------------------

    'creer_compte' => 'Créer un compte',
    'compte_modale_titre' => 'Créer un compte',
    'champ_numero' => 'Numéro',
    'champ_intitule' => 'Intitulé',
    'champ_intitule_invite' => 'Produits d’entretien',
    'champ_nature' => 'Type',
    'champ_nature_aide' => 'Le type commande le poste de bilan. Un type faux rend le compte '
        . 'invisible au bilan : il ne se devine pas.',
    'nature_actif' => 'Actif',
    'nature_passif' => 'Passif',
    'nature_charge' => 'Charge',
    'nature_produit' => 'Produit',
    'compte_cree' => 'Compte :numero créé.',
    'enregistrer' => 'Enregistrer',
    'plan_recherche' => 'Rechercher un compte (numéro ou libellé)',

    // --- Onglet « Immobilisations » ---------------------------------------

    'immo_titre_tableau' => 'Tableau des immobilisations — exercice :annee',
    'immo_duree_titre' => 'Durée d’utilité : une estimation de l’entité, jamais un défaut.',
    'immo_duree_detail' => 'Sous SYSCOHADA révisé, la durée d’utilité relève de l’entité (AUDCIF art. 45) '
        . 'et non d’un barème. Elle est donc obligatoire à la saisie et sans valeur pré-remplie. '
        . 'Amortissement linéaire, prorata temporis de la première annuité en mois entamés.',
    'immo_ajouter' => 'Immobilisation',
    'immo_aucune' => 'Aucune immobilisation enregistrée.',
    'immo_recherche' => 'Rechercher une immobilisation (code ou libellé)',
    'immo_aucune_filtre' => 'Aucune immobilisation ne correspond à cette recherche.',
    'immo_modale_titre' => 'Nouvelle immobilisation',
    'immo_duree_invite' => 'à décider',
        // L'invite du maitre (modale-immo).
        'immo_libelle_invite' => 'Ex. Toyota Land Cruiser Prado',
    'immo_aide' => 'Aucune durée n’est proposée par défaut : c’est une estimation propre à l’entité, pas un barème.',
    'immo_enregistree' => 'Immobilisation :code enregistrée.',
    'champ_compte_immo' => 'Compte d’immobilisation',
    'champ_valeur_origine' => 'Valeur d’origine (FCFA)',
    'champ_date_mise_service' => 'Mise en service',
    'champ_duree_annees' => 'Durée d’utilité (années)',
    'col_code' => 'Code',
    'col_immobilisation' => 'Immobilisation',
    'col_duree' => 'Durée',
    'col_valeur_origine' => 'Valeur d’origine',
    // `col_dotation` (« Dotation :annee ») supprimée le 02/09/2026 : la
    // colonne de l'onglet Immobilisations porte désormais « Dotation » seul
    // (voir l'écart déclaré dans `onglets/immo.blade.php`), l'année vivant
    // dans le titre du tableau.
    'col_dotation_annuelle' => 'Dotation',
    'col_amort_cumules' => 'Amort. cumulés',
        // « Cumul » : le mot du maitre dans la modale du plan (modale-plan).
        'col_cumul' => 'Cumul',
    'col_vnc' => 'VNC',
    'plan_amortissement' => 'Plan',
    'plan_amortissement_titre' => 'Plan d’amortissement',
    'plan_amortissement_note' => 'La dernière annuité absorbe l’arrondi : sans cela, la somme des annuités '
        . 's’écarterait de la valeur d’origine et la VNC finale ne tomberait pas exactement à zéro.',
    'col_exercice' => 'Exercice',
    'col_base' => 'Base',
    'total' => 'TOTAL',

    // --- Onglet « Clôtures » — commande du Product Owner (Vague E) -------

    'exercice_ouvrir' => 'Ouvrir un exercice',
    'exercice_annee' => 'Année de l’exercice',
    'exercice_ouvrir_valider' => 'Ouvrir l’exercice',
    'exercice_ouvert' => 'Exercice :annee ouvert.',
    'cloturer_exercice' => 'Clôturer l’exercice :annee',
    'cloture_perimetre_note' => 'Ce geste change uniquement le statut de l’exercice, et refuse tant qu’une '
        . 'écriture y reste en brouillon. Aucun compte de gestion n’est soldé et aucune écriture de résultat '
        . 'n’est passée par ce bouton — la clôture comptable complète reste à faire, sous l’arbitrage du Comptable.',
    'exercice_cloture' => 'Exercice :annee clôturé.',

    // --- Export « Journal » (PDF/Excel unifiés) ---------------------------

    'export_journal_titre' => 'Journal comptable',
    'col_date' => 'Date',
    'col_numero_piece' => 'N° pièce',
    'col_journal' => 'Journal',
    'col_compte' => 'Compte',
    'col_centre' => 'Centre',
    'col_debit' => 'Débit',
    'col_credit' => 'Crédit',
];
