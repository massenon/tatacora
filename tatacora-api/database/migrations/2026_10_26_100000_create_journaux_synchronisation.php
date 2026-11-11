<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Les deux journaux de la synchronisation, côté serveur (demande du PO du
 * 26/10/2026 : « l'écran de synchronisation avec le module ENVOI et
 * RÉCEPTION… identifier la CAUSE des échecs, corriger et relancer »).
 *
 * ## `journal_reception_synchronisation` — ce que le serveur REÇOIT des postes
 *
 * Une ligne par opération de `POST /api/v1/sync` (clé : `uuid_operation`, la
 * même que la mémoire d'idempotence). Elle ne REMPLACE pas
 * `deduplication_synchronisation` (purgée à 30 jours, qui sert à rejouer la
 * même réponse) ni `anomalies_synchronisation` (les écarts SIGNALÉS d'un
 * document accepté) : elle les relie à ce qu'un humain doit voir — qui,
 * quoi, quand, avec quelle issue, POURQUOI — et garde la charge reçue pour
 * pouvoir la corriger et la rejouer depuis la PWA.
 *
 *  * `issue` : acceptee | fusionnee | dupliquee | signalee | conservee |
 *    conflit | rejetee | erreur ;
 *  * `code_motif` / `motif` / `cause` : le motif STRUCTURÉ (code stable +
 *    phrase rendue au poste) et la cause expliquée en français ;
 *  * `tentatives` : combien de fois le poste a envoyé cette opération ;
 *  * `traitement` : `a_traiter` (rejet, conflit, erreur ou signalement qui
 *    attend un humain), `corrige` (charge corrigée, prête à rejouer),
 *    `relance` (rejouée et aboutie), `ignore` (écartée, motif tracé).
 *
 * ## `journal_envoi_synchronisation` — ce que le serveur MET À DISPOSITION
 *
 * Une ligne par (poste, table) : combien d'éléments du flux
 * `GET /api/v1/referentiels` ont été livrés, quand, et si la table n'est pas
 * livrée faute de droit (`en_attente_droits` = éléments existants non livrés).
 *
 * ## Colonnes ajoutées à `etats_postes_synchronisation`
 *
 * Le dernier curseur rendu au poste, si le dernier passage était complet, la
 * demande de « redescendre depuis le début » (consommée au passage suivant du
 * poste, qui repart alors sans curseur), et les refus 409 « génération
 * périmée » opposés à ce poste.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('journal_reception_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('uuid_operation')->unique();
            $table->uuid('session_id')->nullable();
            $table->string('poste_id');
            $table->foreignUuid('utilisateur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->string('table_concernee');
            $table->string('entite_id');
            $table->string('type_operation', 20);
            $table->timestamp('horodatage_poste')->nullable();
            $table->timestamp('recu_le');
            $table->string('issue', 20);
            $table->string('code_motif', 60)->nullable();
            $table->text('motif')->nullable();
            $table->text('cause')->nullable();
            $table->json('details')->nullable();
            $table->unsignedInteger('tentatives')->default(1);
            $table->timestamp('derniere_tentative_le');
            $table->json('payload')->nullable();
            $table->json('payload_corrige')->nullable();
            $table->string('traitement', 20)->nullable();
            $table->foreignUuid('traite_par')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('traite_le')->nullable();
            $table->text('motif_traitement')->nullable();
            $table->uuid('operation_relance_id')->nullable();
            $table->timestamps();

            $table->index(['poste_id', 'recu_le']);
            $table->index(['table_concernee', 'recu_le']);
            $table->index(['issue', 'traitement']);
            $table->index('recu_le');
            $table->index('entite_id');
        });

        Schema::create('journal_envoi_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('poste_id');
            $table->string('table_concernee');
            $table->unsignedBigInteger('livres_total')->default(0);
            $table->unsignedInteger('dernier_passage_nb')->default(0);
            $table->timestamp('derniere_livraison_le')->nullable();
            $table->unsignedInteger('en_attente_droits')->default(0);
            $table->timestamp('droits_constates_le')->nullable();
            $table->timestamps();

            $table->unique(['poste_id', 'table_concernee']);
        });

        Schema::table('etats_postes_synchronisation', function (Blueprint $table) {
            $table->text('curseur_descente')->nullable();
            $table->boolean('descente_complete')->default(false);
            $table->timestamp('descente_complete_le')->nullable();
            $table->timestamp('redescente_demandee_le')->nullable();
            $table->foreignUuid('redescente_demandee_par')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('redescente_faite_le')->nullable();
            $table->timestamp('generation_perimee_le')->nullable();
            $table->unsignedInteger('generation_perimee_nb')->default(0);
        });
    }

    public function down(): void
    {
        Schema::table('etats_postes_synchronisation', function (Blueprint $table) {
            $table->dropConstrainedForeignId('redescente_demandee_par');
            $table->dropColumn([
                'curseur_descente', 'descente_complete', 'descente_complete_le', 'redescente_demandee_le',
                'redescente_faite_le', 'generation_perimee_le', 'generation_perimee_nb',
            ]);
        });
        Schema::dropIfExists('journal_envoi_synchronisation');
        Schema::dropIfExists('journal_reception_synchronisation');
    }
};
