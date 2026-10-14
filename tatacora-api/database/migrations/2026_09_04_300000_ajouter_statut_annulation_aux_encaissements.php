<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Statut d'annulation sur `paiements` et `reglements_fournisseur` — décision
 * du Product Owner du 01/09/2026 (« implémente le statut au schéma en se
 * basant sur les règles »), fermant la lacune nommée en PA-165.
 *
 * ## Les règles appliquées
 *
 * - Un encaissement ne se SUPPRIME jamais (RG-15, `PaiementPolicy::delete()`
 *   rend `false`) : l'annulation est un ÉTAT, tracé (qui, quand, pourquoi).
 * - La correction comptable reste la CONTRE-PASSATION de la pièce entière
 *   (RG-11) — le statut ne remplace pas la pièce inverse, il rend le fait
 *   lisible côté métier et sort le montant des formules de créance.
 * - Cohérence au schéma : un enregistrement annulé porte OBLIGATOIREMENT son
 *   motif et sa date — un « annulé » sans motif serait invérifiable.
 *
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-165, PA-168
 */
return new class () extends Migration {
    private const TABLES = ['paiements', 'reglements_fournisseur'];

    public function up(): void
    {
        foreach (self::TABLES as $table) {
            Schema::table($table, function (Blueprint $t): void {
                $t->string('statut', 20)->default('actif');
                $t->string('motif_annulation', 500)->nullable();
                $t->foreignUuid('annule_par_id')->nullable()
                    ->constrained('utilisateurs')->restrictOnDelete();
                $t->timestamp('date_annulation')->nullable();
            });

            DB::statement(
                "ALTER TABLE {$table} ADD CONSTRAINT chk_{$table}_statut CHECK (statut IN ('actif', 'annule'))",
            );
            DB::statement(
                "ALTER TABLE {$table} ADD CONSTRAINT chk_{$table}_annulation_coherente "
                ."CHECK ((statut = 'annule') = (motif_annulation IS NOT NULL AND date_annulation IS NOT NULL))",
            );
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $table) {
            DB::statement("ALTER TABLE {$table} DROP CONSTRAINT chk_{$table}_statut");
            DB::statement("ALTER TABLE {$table} DROP CONSTRAINT chk_{$table}_annulation_coherente");

            Schema::table($table, function (Blueprint $t): void {
                $t->dropConstrainedForeignId('annule_par_id');
                $t->dropColumn(['statut', 'motif_annulation', 'date_annulation']);
            });
        }
    }
};
