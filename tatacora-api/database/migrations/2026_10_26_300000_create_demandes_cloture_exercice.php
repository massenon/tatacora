<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Les DEMANDES de clôture d'exercice envoyées par un poste (26/10/2026, décision
 * du Product Owner : « la clôture annuelle SYSCOHADA DOIT ÊTRE IMPLÉMENTÉE EN
 * POSTE ET WEB »).
 *
 * Le poste clôture sur ses propres pièces, mais le serveur reste le SEUL
 * comptable (D246) : le poste lui envoie une demande — démarrer la clôture,
 * reprendre la saisie, clôturer, rouvrir — comme document SOURCE, et le serveur
 * rejoue ses règles par `ClotureExerciceService`. Seule une demande EXÉCUTÉE
 * est écrite ici (un refus annule la transaction : le poste lit la phrase du
 * serveur dans « À traiter »). La table sert aussi à reconnaître un rejeu :
 * l'identifiant est l'UUID du poste.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('demandes_cloture_exercice', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('exercice_id')->constrained('exercices_comptables')->restrictOnDelete();
            $table->unsignedSmallInteger('annee');
            // demarrer | reprendre_saisie | cloturer | rouvrir
            $table->string('action', 20);
            $table->text('motif')->nullable();
            // executee | deja_dans_cet_etat (l'exercice était déjà là où la demande l'amène)
            $table->string('issue', 24);
            $table->string('statut_exercice', 12);
            $table->string('piece_cloture')->nullable();
            $table->string('piece_a_nouveaux')->nullable();
            $table->decimal('resultat', 15, 2)->nullable();
            $table->string('archive_empreinte', 64)->nullable();
            $table->string('poste_id');
            $table->foreignUuid('demandeur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('demandee_le')->nullable();
            $table->timestamps();
            $table->index(['annee', 'action']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('demandes_cloture_exercice');
    }
};
