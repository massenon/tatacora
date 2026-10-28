<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Les SUPPRESSIONS que les postes doivent apprendre (28/10/2026, A5 « Purger »).
 *
 * Le flux descendant est incrémental : il sert les lignes qui existent, jamais
 * celles qui ont disparu. La purge définitive d'une unité d'hébergement ou d'un
 * véhicule archivé (seul endroit de l'application où une donnée disparaît
 * vraiment) laisse donc ICI une trace minimale — la table et l'identifiant —
 * pour que chaque poste rejoue la suppression localement, SI aucune saisie
 * locale n'y est rattachée.
 *
 * Écrite par les deux services de parc (`purger`), donc par l'écran web comme
 * par la synchronisation : une seule source. Aucune clé étrangère (la ligne
 * référencée n'existe plus, par construction).
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('suppressions_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('table_concernee');
            $table->uuid('entite_id');
            $table->timestamp('created_at')->useCurrent();

            // Idempotent : une purge notée deux fois ne produit qu'une ligne.
            $table->unique(['table_concernee', 'entite_id']);
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('suppressions_synchronisation');
    }
};
