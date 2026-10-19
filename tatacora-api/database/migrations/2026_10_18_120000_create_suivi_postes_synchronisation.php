<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Le bouton « Synchroniser » du serveur — décision du Product Owner du
 * 18/10/2026 (« le serveur doit avoir aussi le bouton synchroniser, pour
 * envoyer les données en local si le serveur a été utilisé »).
 *
 * Le serveur ne peut pas POUSSER vers un poste (le poste n'écoute rien : il
 * appelle). Le bouton enregistre donc une DEMANDE ; chaque poste la lit à son
 * prochain passage court (toutes les 30 s) et lance aussitôt sa
 * synchronisation complète, au lieu d'attendre son réveil de 5 minutes.
 *
 *  * `demandes_synchronisation` : qui a demandé, quand (la plus récente fait
 *    foi) ;
 *  * `etats_postes_synchronisation` : par poste, sa dernière DESCENTE (lue
 *    du flux `/referentiels`), le nombre d'opérations qu'il déclare en
 *    attente, et la dernière demande qu'il a lue. Sa dernière MONTÉE se lit
 *    déjà dans `sessions_synchronisation` (un lot = une session).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('demandes_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('utilisateur_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->timestamp('demandee_le');
            $table->timestamps();

            $table->index('demandee_le');
        });

        Schema::create('etats_postes_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('poste_id')->unique();
            $table->foreignUuid('utilisateur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('derniere_descente_le')->nullable();
            $table->unsignedInteger('en_attente')->nullable();
            $table->timestamp('demande_lue_le')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('etats_postes_synchronisation');
        Schema::dropIfExists('demandes_synchronisation');
    }
};
