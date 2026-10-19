<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Les SECRETS techniques saisis à l'écran — décision du Product Owner du
 * 19/10/2026 (« on doit enregistrer les configurations dans le poste et le
 * web » ; mot de passe SMTP du serveur : « chiffré en base »).
 *
 * Une table À PART de `parametres_systeme` : celle-là est lue par tout profil
 * qui ouvre Paramètres, descend vers les postes et s'exporte. Ici, la valeur
 * est CHIFFRÉE par la clé de l'application (`APP_KEY`, en `.env` seulement) :
 * une copie de la base sans le `.env` ne révèle rien. Registre fermé des clés
 * (`SecretsConfigurationService::CLES`) ; jamais exportée, jamais
 * synchronisée, conservée par la réinitialisation.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('secrets_configuration', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('cle')->unique();
            $table->text('valeur');
            $table->foreignUuid('utilisateur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('secrets_configuration');
    }
};
