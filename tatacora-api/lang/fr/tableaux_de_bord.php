<?php

declare(strict_types=1);

/*
 * Libelles du tableau de bord (M11) — SPEC_ECRAN_M11_TABLEAU_DE_BORD.md.
 *
 * Les intitules de KPI sont imprimes sur un document exporte (RG-19) : ils
 * vivent ici et nulle part ailleurs (06 §4.4).
 */

return [
    'titre' => 'Tableau de bord',
    'sous_titre' => 'Vision consolidée et en temps réel de la performance de chaque activité',

    'periode_inconnue' => 'Période inconnue : « :code ». Valeurs admises : '
        . "aujourd'hui, 7j, 30j, trimestre, annee.",

    /*
     * Les fenetres CALENDAIRES ont leur propre registre (Periode::resoudre).
     * Un seul message pour les deux familles enverrait l'appelant essayer
     * « 30j » sur un filtre d'ecran qui ne le connait pas.
     */
    'periode_calendaire_inconnue' => 'Période inconnue : « :code ». Valeurs admises : '
        . "aujourdhui, semaine, mois, trimestre, semestre, annee, personnalisee.",

    'periode' => [
        'du_au' => 'Du :debut au :fin',
        'aujourdhui' => "Aujourd'hui",
        '7j' => '7 derniers jours',
        '30j' => '30 derniers jours',
        'trimestre' => 'Ce trimestre',
        'annee' => 'Cette année',
    ],

    /*
     * Intitules choisis pour dire ce qui est REELLEMENT calcule (PA-49) :
     * « encaisse » et non « paye », « impayees » et non « en attente ».
     * Un intitule fidele evite qu'un Gerant lise un chiffre pour un autre.
     */
    'kpi' => [
        'chiffre_affaires_encaisse' => "Chiffre d'affaires encaissé",
        'chiffre_affaires_facture' => "Chiffre d'affaires facturé",
        'taux_occupation' => "Taux d'occupation (nuitées)",
        'tresorerie_caisse' => 'Trésorerie en caisse',
        'depenses_cumulees' => 'Dépenses cumulées',
        'reservations_en_attente' => 'Réservations en attente',
        'factures_impayees' => 'Factures non soldées',
        'valeur_stock' => 'Valeur du stock (CMP)',
        'employes_actifs' => 'Employés actifs',
    ],

    'col_indicateur' => 'Indicateur',
    'col_periode' => 'Période',
    'col_precedent' => 'Période précédente',
    'col_variation' => 'Variation',

    'non_comparable' => '—',

    'etat' => [
        'libelle' => 'Tableau de bord — synthèse consolidée',
    ],
];
