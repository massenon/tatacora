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
        // carte_boisson.article_id référence articles — créée dans §11bis (après create_stocks)

        Schema::create('ventes_bar', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('session_id')->constrained('sessions_caisse')->restrictOnDelete();
            $table->foreignUuid('client_id')->nullable()->constrained('clients')->nullOnDelete(); // EF-M5-06 imputation chambre
            $table->timestamp('date_vente');
            $table->decimal('montant', 15, 2);
            $this->auditColumns($table);
            $table->timestamps();
        });

        // lignes_vente_bar.boisson_id référence cartes_boisson — créée dans §11bis
    }

    public function down(): void
    {
        Schema::dropIfExists('ventes_bar');
    }
};
