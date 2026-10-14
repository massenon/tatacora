<?php

declare(strict_types=1);

/*
|--------------------------------------------------------------------------
| M14 — ÉTATS & RAPPORTS (les neuf états ajoutés le 01/09/2026)
|--------------------------------------------------------------------------
|
| Un état par module — `App\Domain\<Module>\Etats\Etat*`. Les libellés
| rendus par le catalogue (`m14-etats-studio.html`, `pwa.etats.*`) restent
| dans `lang/fr/pwa.php` ; ce fichier ne porte que le contenu propre à
| chaque document — titre, période, KPI, colonnes.
|
*/

return [

    // -------------------------------------------------------------- commun
    'periode_du_au' => 'Du :debut au :fin',
    'arrete_au' => 'Arrêté au :date',

    // ----------------------------------------------------------- réservations (M1)
    'reservations' => [
        'libelle' => 'État des réservations',
        'periode_toutes' => 'Toutes dates',
        'kpi_nombre' => 'Réservations',
        'kpi_montant' => 'Montant total',
        'kpi_reste_du' => 'Reste dû',
        'kpi_sans_tarif' => 'Sans tarif figé',
        'col_client' => 'Client',
        'col_unite' => 'Unité',
        'col_arrivee' => 'Arrivée',
        'col_depart' => 'Départ',
        'col_nuits' => 'Nuits',
        'col_statut' => 'Statut',
        'col_montant' => 'Montant',
        'col_reste_du' => 'Reste dû',
        'statut' => [
            'en_attente' => 'En attente',
            'confirmee' => 'Confirmée',
            'en_cours' => 'En cours',
            'terminee' => 'Terminée',
            'annulee' => 'Annulée',
        ],
    ],

    // -------------------------------------------------------- créances clients (M3)
    'creances' => [
        'libelle' => 'État des créances clients',
        'kpi_clients_debiteurs' => 'Clients débiteurs',
        'kpi_pieces' => 'Pièces impayées',
        'kpi_total_du' => 'Total dû (maximum)',
        'col_client' => 'Client',
        'col_telephone' => 'Téléphone',
        'col_type' => 'Type',
        'col_pieces' => 'Pièces',
        'col_solde' => 'Solde dû',
    ],

    // ------------------------------------------------------------------ ventes (M5)
    'ventes' => [
        'libelle' => 'État des ventes',
        'periode_toutes' => 'Toutes dates',
        'kpi_nombre' => 'Ventes',
        'kpi_encaissees' => 'Encaissées',
        'kpi_montant' => 'Montant total',
        'col_numero' => 'N°',
        'col_date' => 'Date',
        'col_point_vente' => 'Point de vente',
        'col_client' => 'Client',
        'col_mode_paiement' => 'Mode de paiement',
        'col_encaisse' => 'Encaissée',
        'col_montant' => 'Montant',
        'encaisse_oui' => 'Oui',
        'encaisse_non' => 'Non',
    ],

    // ---------------------------------------------------------------- dépenses (M10)
    'depenses' => [
        'libelle' => 'État des dépenses',
        'periode_toutes' => 'Toutes dates',
        'kpi_nombre' => 'Dépenses',
        'kpi_montant' => 'Montant total',
        'col_numero' => 'N°',
        'col_date' => 'Date',
        'col_libelle' => 'Libellé',
        'col_tresorerie' => 'Trésorerie',
        'col_montant' => 'Montant',
        'col_ecriture' => 'Écriture',
        'ecriture_passee' => 'Passée',
        'ecriture_absente' => 'Absente',
    ],

    // ------------------------------------------------- achats / dettes fournisseurs (M7)
    'achats' => [
        'libelle' => 'État des achats et dettes fournisseurs',
        'periode_toutes' => 'Toutes dates',
        'kpi_nombre' => 'Commandes',
        'kpi_montant' => 'Montant total',
        'kpi_reste_du' => 'Reste dû',
        'col_fournisseur' => 'Fournisseur',
        'col_date' => 'Date',
        'col_statut' => 'Statut',
        'col_montant' => 'Montant',
        'col_regle' => 'Réglé',
        'col_reste_du' => 'Reste dû',
    ],

    // ------------------------------------------------------------- locations (M8)
    'locations' => [
        'libelle' => 'État des locations de véhicules',
        'periode_toutes' => 'Toutes dates',
        'kpi_nombre' => 'Contrats',
        'kpi_montant' => 'Montant total',
        'col_client' => 'Client',
        'col_vehicule' => 'Véhicule',
        'col_debut' => 'Début',
        'col_fin' => 'Fin',
        'col_jours' => 'Jours',
        'col_montant' => 'Montant',
    ],

    // -------------------------------------------------------------- tourisme (M9)
    'tourisme' => [
        'libelle' => 'État des réservations de circuits',
        'periode_toutes' => 'Toutes dates',
        'kpi_nombre' => 'Réservations',
        'kpi_participants' => 'Participants',
        'kpi_montant' => 'Montant total',
        'col_circuit' => 'Circuit',
        'col_client' => 'Client',
        'col_guide' => 'Guide',
        'col_date' => 'Date',
        'col_participants' => 'Participants',
        'col_statut' => 'Statut',
        'col_montant' => 'Montant',
    ],

    // ------------------------------------------------------- paie & effectif (M13)
    'paie' => [
        'libelle' => 'État Paie & Effectif',
        'periode' => 'Période :periode',
        'kpi_effectif' => 'Effectif total',
        'kpi_actifs' => 'Actifs',
        'kpi_masse_brute' => 'Masse salariale brute',
        'kpi_net_periode' => 'Net à payer (période)',
        'kpi_bulletins_periode' => 'Bulletins de la période',
        'col_nom' => 'Nom',
        'col_matricule' => 'Matricule',
        'col_poste' => 'Poste',
        'col_service' => 'Service',
        'col_embauche' => 'Embauche',
        'col_statut' => 'Statut',
        'col_salaire_base' => 'Salaire de base',
    ],

    // ------------------------------------------------------------- balance (M10)
    'balance' => [
        'libelle' => 'Balance générale — Exercice :annee',
        'libelle_sans_exercice' => 'Balance générale',
        'aucun_exercice' => 'Aucun exercice comptable n\'a encore été ouvert.',
        'kpi_comptes' => 'Comptes mouvementés',
        'kpi_total_debit' => 'Total débit',
        'kpi_total_credit' => 'Total crédit',
        'kpi_equilibree' => 'Équilibrée',
        'oui' => 'Oui',
        'non' => 'Non',
        'col_compte' => 'Compte',
        'col_libelle' => 'Libellé',
        'col_debit' => 'Débit',
        'col_credit' => 'Crédit',
        'col_solde_debiteur' => 'Solde débiteur',
        'col_solde_crediteur' => 'Solde créditeur',
    ],

];
