<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Anomalies SIGNALÉES par la synchronisation des documents — lot S3,
 * décisions du Product Owner du 15/10/2026.
 *
 * ## Pourquoi une table, et pas un refus
 *
 * Un document poussé par un poste décrit un fait DÉJÀ ACCOMPLI : la bière est
 * bue, l'argent est dans le tiroir. Le serveur, seul maître comptable (D246),
 * l'enregistre — mais il ne doit ni le refuser (l'argent disparaîtrait des
 * livres) ni le « corriger » en silence (le grand livre dirait autre chose
 * que le ticket remis au client). Le PO a tranché : l'écart est SIGNALÉ —
 * stocké ici, et rendu au poste dans le résultat de l'opération.
 *
 * Cas couverts à la création :
 * - `ecart_prix` — prix de la vente au poste ≠ prix du catalogue serveur
 *   (le prix du POSTE fait foi, l'écart se lit ici) ;
 * - `vente_en_rupture` — vente faite alors que le stock serveur était
 *   insuffisant : la sortie est FORCÉE (RG-06, trace `rupture_stock_forcee`)
 *   au lieu de rejeter une vente déjà faite ;
 * - `vente_session_inconnue` / `vente_session_cloturee` — vente rattachée à
 *   un tiroir que le serveur ne connaît pas, ou déjà clos ;
 * - `ecart_theorique_caisse` — le théorique de clôture calculé par le poste
 *   diffère de celui que le serveur recalcule sur SES ventes ;
 * - `ecart_conformite_reception` — verdict RG-10 du poste ≠ celui du serveur.
 *
 * ## Idempotence
 *
 * Unicité `(table_concernee, entite_id, type, reference)` : un rejeu du même
 * document ne signale pas deux fois le même écart. `reference` vaut `''` (et
 * jamais NULL) quand l'écart porte sur le document entier — MySQL admet
 * plusieurs NULL dans un index unique, ce qui annulerait la garantie.
 *
 * Aucune clé étrangère sur `entite_id` : la table sert plusieurs tables de
 * documents (même raison que `correspondances_synchronisation`).
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('anomalies_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('poste_id');
            $table->foreignUuid('utilisateur_id')->nullable()->constrained('utilisateurs')->restrictOnDelete();
            $table->string('table_concernee', 64);
            $table->uuid('entite_id');
            $table->string('type', 40);
            // Ligne ou article concerné, `''` pour le document entier.
            $table->string('reference', 64)->default('');
            $table->decimal('valeur_poste', 15, 2)->nullable();
            $table->decimal('valeur_serveur', 15, 2)->nullable();
            $table->json('details')->nullable();
            // `a_examiner` à la création ; l'examen est un geste ultérieur.
            $table->string('statut', 20)->default('a_examiner');
            $table->timestamps();

            $table->unique(['table_concernee', 'entite_id', 'type', 'reference'], 'anomalies_sync_unicite');
            $table->index(['statut', 'type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('anomalies_synchronisation');
    }
};
