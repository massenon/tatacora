<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        if (!Schema::hasTable('ventes')) {
            Schema::create('ventes', function (Blueprint $table) {
                $table->id();
                $table->string('numero')->unique();
                $table->string('session_id')->nullable();
                $table->string('point_vente', 50)->default('Bar');
                $table->unsignedBigInteger('client_id')->nullable();
                $table->string('table')->nullable();
                $table->string('table_id')->nullable();
                $table->decimal('montant_total', 15, 2)->default(0);
                $table->string('mode_paiement', 50)->default('especes');
                $table->boolean('encaisse')->default(true);
                $table->string('statut', 20)->default('validee');
                $table->string('motif_annulation')->nullable();
                $table->timestamp('annulee_at')->nullable();
                $table->unsignedBigInteger('utilisateur_id')->nullable();
                $table->json('stock_non_impacte')->nullable();
                $table->timestamps();

                $table->index('point_vente');
                $table->index('mode_paiement');
                $table->index('statut');
                $table->index('created_at');
            });
        }

        if (!Schema::hasTable('lignes_vente')) {
            Schema::create('lignes_vente', function (Blueprint $table) {
                $table->id();
                $table->foreignId('vente_id')->constrained('ventes')->cascadeOnDelete();
                $table->string('code')->nullable();
                $table->string('nom');
                $table->string('categorie')->nullable();
                $table->string('module', 10)->default('M5');
                $table->decimal('prix_unitaire', 15, 2);
                $table->integer('quantite')->default(1);
                $table->decimal('montant', 15, 2);
                $table->timestamps();

                $table->index('module');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('lignes_vente');
        Schema::dropIfExists('ventes');
    }
};
