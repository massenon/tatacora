<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        Schema::create('utilisateurs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('login')->unique();
            $table->string('mot_de_passe_hash');
            $table->foreignUuid('role_id')->constrained('roles')->restrictOnDelete();
            // employe_id ajouté par une migration différée après create_employes_services
            // (dépendance circulaire évitée — voir §6 de ce document)
            $table->enum('statut', ['actif', 'suspendu', 'desactive'])->default('actif');
            $table->timestamp('derniere_connexion')->nullable();
            $table->rememberToken();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('utilisateurs');
    }
};
