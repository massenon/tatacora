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
        Schema::create('menus', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('libelle');
            $table->enum('type', ['local', 'europeen', 'special']);
            $table->date('date_debut')->nullable();
            $table->date('date_fin')->nullable();
            $table->timestamps();
        });

        Schema::create('recettes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('libelle');
            $table->decimal('cout_matiere_calcule', 15, 2)->default(0); // recalculé à chaque modification d'ingredients_recette
            $table->timestamps();
        });

        Schema::create('plats', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('menu_id')->constrained('menus')->restrictOnDelete();
            $table->foreignUuid('recette_id')->constrained('recettes')->restrictOnDelete();
            $table->string('libelle');
            $table->decimal('prix_vente', 15, 2);
            $table->timestamps();
        });

        // ingredients_recette référence articles — créée APRÈS create_stocks (§11),
        // voir migration différée en fin de ce fichier (§9bis) pour respecter l'ordre
        // des dépendances sans dupliquer la logique entre les deux fichiers.

        Schema::create('commandes_restaurant', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('table_ou_chambre_id')->nullable(); // référence libre table salle OU unites_hebergement (room-service)
            $table->foreignUuid('client_id')->nullable()->constrained('clients')->nullOnDelete();
            $table->timestamp('date_commande');
            $table->enum('statut', ['en_preparation', 'transmise_cuisine', 'servie', 'cloturee', 'annulee'])
                ->default('en_preparation');
            $this->auditColumns($table);
            $table->timestamps();
        });

        Schema::create('lignes_commande_restaurant', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('commande_id')->constrained('commandes_restaurant')->restrictOnDelete();
            $table->foreignUuid('plat_id')->constrained('plats')->restrictOnDelete();
            $table->unsignedSmallInteger('quantite');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('lignes_commande_restaurant');
        Schema::dropIfExists('commandes_restaurant');
        Schema::dropIfExists('plats');
        Schema::dropIfExists('recettes');
        Schema::dropIfExists('menus');
    }
};
