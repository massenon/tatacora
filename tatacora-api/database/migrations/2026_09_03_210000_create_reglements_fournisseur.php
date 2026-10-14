<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Règlements fournisseur — le bouton « Régler » du maître (PA-165).
 *
 * ## Pourquoi une table de MOUVEMENTS alors que `montant_regle` existe
 *
 * `commandes_achat.montant_regle` est au schéma depuis l'origine, différé par
 * l'arbitrage PA-161 (d) « à PA-21 ». Un cumul incrémenté à la main perdrait
 * les faits — qui a payé quoi, quand, par quelle trésorerie — que la pièce
 * comptable exige de toute façon. Les règlements sont donc des LIGNES, et
 * `montant_regle` est RECALCULÉ depuis elles à chaque écriture, dans la même
 * transaction — le motif de `EmissionFactureService::recalculerTotaux()` :
 * un total qui ne correspond pas à ses lignes est indéfendable.
 *
 * `tresorerie` est le code du registre {@see \App\Domain\Depenses\Services\DepenseService::TRESORERIES}
 * (caisse / momo / banque) — les comptes font foi là-bas et nulle part ailleurs.
 *
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-161 (d), PA-165
 */
return new class () extends Migration {
    use HasAuditColumns;

    private const CONTRAINTES = [
        'chk_reglements_fourn_montant' => 'montant > 0',
        'chk_reglements_fourn_tresorerie' => "tresorerie IN ('caisse', 'momo', 'banque')",
    ];

    public function up(): void
    {
        Schema::create('reglements_fournisseur', function (Blueprint $table): void {
            $table->uuid('id')->primary();

            $table->foreignUuid('commande_id')
                ->constrained('commandes_achat')->restrictOnDelete();

            $table->decimal('montant', 15, 2);
            $table->string('tresorerie', 20);
            $table->date('date_reglement');

            $this->auditColumns($table);
            $table->timestamps();

            $table->index(['commande_id', 'date_reglement']);
        });

        foreach (self::CONTRAINTES as $nom => $expression) {
            DB::statement("ALTER TABLE reglements_fournisseur ADD CONSTRAINT {$nom} CHECK ({$expression})");
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('reglements_fournisseur');
    }
};
