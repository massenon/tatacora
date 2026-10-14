<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        Schema::create('parametres_systeme', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('cle')->unique();
            $table->text('valeur'); // type réel interprété applicativement selon la clé
            $table->string('description')->nullable();
            $table->foreignUuid('utilisateur_modification_id')->nullable()
                ->constrained('utilisateurs')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('parametres_systeme');
    }
};
