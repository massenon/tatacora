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
        Schema::create('fournisseurs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('raison_sociale');
            $table->string('contact')->nullable();
            $table->string('categorie')->nullable();
            $table->string('conditions_paiement')->nullable();
            $table->enum('evaluation', ['excellent', 'bon', 'moyen', 'a_revoir'])->nullable();
            $this->auditColumns($table);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fournisseurs');
    }
};
