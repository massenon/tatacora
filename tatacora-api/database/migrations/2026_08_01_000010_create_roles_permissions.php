<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        Schema::create('roles', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('libelle');
            $table->text('description')->nullable();
            $table->timestamps();
        });

        Schema::create('permissions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // M1-M14, ROLES, PARAM — cohérent avec le prototype déjà validé (roles-permissions.html)
            $table->string('module');
            $table->enum('action', ['lire', 'creer', 'modifier', 'supprimer', 'valider']);
            $table->timestamps();
            $table->unique(['module', 'action']);
        });

        // Table pivot — LA matrice RBAC 14×11 (03_DATABASE_ENGINEERING.md §13)
        Schema::create('permission_role', function (Blueprint $table) {
            $table->foreignUuid('role_id')->constrained('roles')->cascadeOnDelete();
            $table->foreignUuid('permission_id')->constrained('permissions')->cascadeOnDelete();
            $table->primary(['role_id', 'permission_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('permission_role');
        Schema::dropIfExists('permissions');
        Schema::dropIfExists('roles');
    }
};
