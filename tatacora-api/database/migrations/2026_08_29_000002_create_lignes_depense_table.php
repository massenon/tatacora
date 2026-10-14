<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        if (!Schema::hasTable('lignes_depense')) {
            Schema::create('lignes_depense', function (Blueprint $table) {
                $table->id();
                $table->foreignId('depense_id')->constrained('depenses')->cascadeOnDelete();
                $table->string('libelle')->nullable();
                $table->string('compte_charge', 20); // 601, 602, 6051, etc.
                $table->string('nature', 100);       // Oignon, Transport, etc.
                $table->string('famille', 50);        // Marché, Services
                $table->decimal('montant', 15, 2);
                $table->timestamps();

                $table->index('compte_charge');
                $table->index('famille');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('lignes_depense');
    }
};
