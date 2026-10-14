<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        // EF-M14-06 — archivage horodaté de tout état généré, distinct de journal_audit
        // (volume et cycle de rétention différents, cf. 05_MODULE_SPECIFICATIONS.md §M14).
        Schema::create('etats_generes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('module'); // module ou onglet Hub M14 d'origine
            $table->string('nom_etat');
            $table->json('filtres_appliques'); // période, service, centre de coût...
            $table->foreignUuid('utilisateur_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->timestamp('date_edition')->useCurrent();
            $table->enum('format', ['pdf', 'excel']);
            $table->string('chemin_fichier_archive')->nullable();
            $table->timestamps();

            $table->index(['module', 'date_edition']);
        });

        // Planification d'états récurrents — EF-M14-05, diffusés via M12
        Schema::create('etats_planifies', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('module');
            $table->string('nom_etat');
            $table->json('filtres_appliques');
            $table->enum('frequence', ['quotidien', 'hebdomadaire', 'mensuel']);
            $table->json('destinataires'); // liste d'utilisateurs/canaux
            $table->boolean('actif')->default(true);
            $table->timestamp('derniere_execution')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('etats_planifies');
        Schema::dropIfExists('etats_generes');
    }
};
