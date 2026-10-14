<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    use HasAuditColumns;

    public function up(): void
    {
        Schema::create('commandes_achat', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('fournisseur_id')->constrained('fournisseurs')->restrictOnDelete();
            $table->date('date_commande');
            $table->enum('statut', ['brouillon', 'envoyee', 'receptionnee_partiellement', 'receptionnee', 'cloturee'])
                ->default('brouillon');
            $table->foreignUuid('utilisateur_id')->constrained('utilisateurs')->restrictOnDelete();
            $this->auditColumns($table);
            $table->timestamps();
        });

        Schema::create('lignes_commande_achat', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('commande_id')->constrained('commandes_achat')->restrictOnDelete();
            $table->foreignUuid('article_id')->constrained('articles')->restrictOnDelete();
            $table->decimal('quantite_commandee', 10, 2);
            $table->decimal('prix_unitaire', 15, 2);
            $table->timestamps();
        });

        Schema::create('bons_reception', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('commande_id')->constrained('commandes_achat')->restrictOnDelete();
            $table->date('date_reception');
            $table->foreignUuid('utilisateur_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->enum('conformite', ['totale', 'partielle', 'non_conforme']);
            $table->timestamps();
            // Déclenche IncrementerStockReception (listener) — jamais de saisie
            // manuelle du mouvement de stock correspondant, cf. 05_MODULE_SPECIFICATIONS.md §M7.
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bons_reception');
        Schema::dropIfExists('lignes_commande_achat');
        Schema::dropIfExists('commandes_achat');
    }
};
