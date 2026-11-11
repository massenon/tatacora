<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Les DÉPÔTS et RETRAITS de la signature et du cachet des documents A4, faits depuis un poste
 * (11/11/2026, décision du PO : « téléverser la signature et le cachet DEPUIS LE POSTE »).
 *
 * Le fichier lui-même vit où le web le range (disque `public`, `apparence/signature.<ext>` et
 * `apparence/cachet.<ext>`, par `ApparenceEtablissementService`). Cette table ne garde que la
 * TRACE du geste, sans les octets : l'identifiant est l'UUID du poste — c'est lui qui reconnaît
 * un rejeu (réponse perdue entre le traitement et l'accusé) sans réécrire l'image.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('depots_images_document', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // signature | cachet
            $table->string('nature', 12);
            // deposer | retirer
            $table->string('action', 10);
            $table->string('type_mime', 32)->nullable();
            // 16 premiers caractères du SHA-256 de l'image rangée (null : retrait).
            $table->string('empreinte', 16)->nullable();
            $table->string('poste_id');
            $table->foreignUuid('auteur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamps();
            $table->index(['nature', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('depots_images_document');
    }
};
