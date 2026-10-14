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
        Schema::create('articles', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('libelle');
            $table->string('categorie');
            $table->string('unite_mesure');
            $table->decimal('seuil_alerte', 10, 2); // ALERTES_CRITIQUES_DE_STOCK.md
            $table->decimal('seuil_reappro', 10, 2)->nullable(); // distinct du seuil d'alerte — usage M7
            $table->decimal('cout_moyen_pondere', 15, 4)->default(0);
            $table->timestamps();
        });

        Schema::create('points_stockage', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('libelle'); // Magasin général, Cuisine, Bar, Garage
            $table->string('type')->nullable();
            $table->timestamps();
        });

        // mouvements_stock : PAS de colonne quantite_stock ailleurs dans le schéma —
        // le stock théorique est TOUJOURS calculé par agrégation de cette table
        // (03_DATABASE_ENGINEERING.md §7, StockTheoriqueService).
        Schema::create('mouvements_stock', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('article_id')->constrained('articles')->restrictOnDelete();
            $table->foreignUuid('point_id')->constrained('points_stockage')->restrictOnDelete();
            $table->enum('type_mouvement', ['entree', 'sortie', 'perte', 'inventaire']);
            $table->decimal('quantite', 10, 2);
            $table->string('motif'); // ex. "vente:{id_vente}" pour les sorties automatiques — RG-15
            $table->foreignUuid('utilisateur_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->timestamp('date_mouvement');
            $table->timestamps();

            $table->index(['article_id', 'point_id']); // performance StockTheoriqueService
        });

        Schema::create('inventaires', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('point_id')->constrained('points_stockage')->restrictOnDelete();
            $table->date('date_inventaire');
            $table->foreignUuid('utilisateur_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->timestamps();
        });

        Schema::create('lignes_inventaire', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('inventaire_id')->constrained('inventaires')->restrictOnDelete();
            $table->foreignUuid('article_id')->constrained('articles')->restrictOnDelete();
            $table->decimal('quantite_theorique', 10, 2);
            $table->decimal('quantite_constatee', 10, 2);
            $table->decimal('ecart', 10, 2); // constatee - theorique, calculé applicativement
            $table->timestamps();
        });

        // --- §9bis / §10bis : tables différées de M4/M5, dépendantes de `articles` ---

        Schema::create('ingredients_recette', function (Blueprint $table) {
            $table->foreignUuid('recette_id')->constrained('recettes')->restrictOnDelete();
            $table->foreignUuid('article_id')->constrained('articles')->restrictOnDelete();
            $table->decimal('quantite_unitaire', 10, 3);
            $table->primary(['recette_id', 'article_id']);
        });

        Schema::create('cartes_boisson', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('article_id')->constrained('articles')->restrictOnDelete();
            $table->string('libelle');
            $table->enum('categorie', ['locale', 'maison', 'importee']);
            $table->decimal('prix_vente', 15, 2);
            $table->timestamps();
        });

        Schema::create('lignes_vente_bar', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('vente_id')->constrained('ventes_bar')->restrictOnDelete();
            $table->foreignUuid('boisson_id')->constrained('cartes_boisson')->restrictOnDelete();
            $table->unsignedSmallInteger('quantite');
            $table->decimal('prix_unitaire', 15, 2);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('lignes_vente_bar');
        Schema::dropIfExists('cartes_boisson');
        Schema::dropIfExists('ingredients_recette');
        Schema::dropIfExists('lignes_inventaire');
        Schema::dropIfExists('inventaires');
        Schema::dropIfExists('mouvements_stock');
        Schema::dropIfExists('points_stockage');
        Schema::dropIfExists('articles');
    }
};
