<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        Schema::create('modeles_notification', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('evenement'); // 'reservation_creee', 'seuil_stock_atteint', 'synthese_quotidienne'...
            $table->enum('canal', ['whatsapp', 'email']);
            $table->text('contenu_template'); // placeholders {client}, {montant}... résolus à l'envoi
            $table->timestamps();

            $table->unique(['evenement', 'canal']);
        });

        Schema::create('notifications_envoyees', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('modele_id')->constrained('modeles_notification')->restrictOnDelete();
            $table->string('destinataire'); // numéro WhatsApp ou email
            $table->timestamp('date_envoi');
            $table->enum('statut_remise', ['envoye', 'livre', 'lu', 'echec'])->default('envoye');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notifications_envoyees');
        Schema::dropIfExists('modeles_notification');
    }
};
