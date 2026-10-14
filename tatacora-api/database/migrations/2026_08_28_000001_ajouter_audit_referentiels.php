<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Colonnes d'audit sur les tables de RÉFÉRENTIEL — préalable au CRUD PWA (PA-159).
 *
 * Jusqu'ici, `auditColumns()` n'était posé que sur les tables transactionnelles
 * (réservations, factures, ventes, commandes…). Les référentiels — articles,
 * cartes, parc, circuits, plannings — n'en portaient aucune : ajouter
 * `use Auditable;` à `Article` produisait une erreur SQL (« Unknown column
 * `utilisateur_creation_id` »), le trait écrivant des colonnes inexistantes.
 *
 * Or la PWA passe en CRUD sur ces référentiels (décision du Product Owner du
 * 28/08/2026), et RG-15 exige la traçabilité de toute écriture : changer un
 * seuil d'alerte, un tarif de véhicule ou un prix de boisson est exactement le
 * genre de geste dont on demandera après coup « à partir de quelle valeur ? ».
 *
 * Migration **additive** : aucune colonne existante n'est touchée, les lignes
 * déjà posées gardent leurs valeurs (`date_creation` reçoit CURRENT_TIMESTAMP
 * à l'exécution de l'ALTER, les auteurs restent NULL — l'historique antérieur
 * à l'audit ne s'invente pas).
 *
 * Les tables de LIGNES (`lignes_commande_restaurant`, `lignes_vente_bar`,
 * `ingredients_recette`) et `presences`/`evaluations` restent volontairement
 * hors du lot : aucune n'entre au périmètre d'écriture des neuf vagues, et le
 * plan (PA-159) mesure quinze tables, pas dix-huit. Les auditer « au cas où »
 * sans modèle `Auditable` en face serait une colonne que rien ne remplit.
 *
 * @see RG-15 Journalisation intégrale
 */
return new class () extends Migration {
    use HasAuditColumns;

    /**
     * Les quinze tables mesurées sans colonne d'audit (plan PA-159, fait b) —
     * vérifiées une à une contre les migrations de création avant l'écriture
     * de ce fichier : aucune ne porte ne serait-ce qu'une colonne partielle.
     *
     * @var list<string>
     */
    private const TABLES = [
        // M6 Stocks (2026_08_01_000500) — zéro appel à auditColumns() sur ses huit tables.
        'articles',
        'points_stockage',
        'mouvements_stock',
        'inventaires',
        'lignes_inventaire',
        'cartes_boisson',
        // M4 Restaurant (2026_08_01_000300) — seule `commandes_restaurant` était auditée.
        'plats',
        'menus',
        'recettes',
        // M8 Véhicules (2026_08_01_000700) — seule `contrats_location` était auditée.
        'vehicules',
        'entretiens_vehicule',
        // M9 Tourisme (2026_08_01_000800) — seule `reservations_tour` était auditée.
        'circuits',
        'guides',
        // M13 Rh (2026_08_01_001000) — seules `primes_sanctions` et `bulletins_paie` l'étaient.
        'plannings',
        'conges',
    ];

    public function up(): void
    {
        foreach (self::TABLES as $nomTable) {
            Schema::table($nomTable, function (Blueprint $table): void {
                $this->auditColumns($table);
            });
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $nomTable) {
            Schema::table($nomTable, function (Blueprint $table): void {
                $table->dropConstrainedForeignId('utilisateur_creation_id');
                $table->dropConstrainedForeignId('utilisateur_modification_id');
                $table->dropColumn(['date_creation', 'date_modification']);
            });
        }
    }
};
