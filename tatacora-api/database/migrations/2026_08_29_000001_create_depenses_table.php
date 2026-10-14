<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        if (!Schema::hasTable('depenses')) {
            Schema::create('depenses', function (Blueprint $table) {
                $table->id();
                $table->string('numero')->unique();
                $table->date('date_transaction');
                $table->string('tresorerie', 50)->default('caisse'); // caisse, momo, banque
                $table->string('compte_tresorerie', 20)->default('5711');
                $table->decimal('montant_total', 15, 2)->default(0);
                $table->string('libelle');
                $table->string('recu_path')->nullable();
                $table->string('ecriture_id')->nullable();
                $table->text('ecriture_refus')->nullable();
                $table->string('utilisateur_id', 100)->nullable();
                $table->json('lignes_json')->nullable();
                $table->timestamps();

                $table->index('date_transaction');
                $table->index('tresorerie');
                $table->index('utilisateur_id');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('depenses');
    }
};
