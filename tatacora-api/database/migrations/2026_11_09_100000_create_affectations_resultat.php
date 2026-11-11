<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * L'AFFECTATION DU RÉSULTAT d'un exercice clôturé (09/11/2026, demande du PO :
 * « ajoute l'affectation du résultat »).
 *
 * Une ligne par affectation passée : l'exercice dont le résultat est affecté
 * (N-1), la clôture dont le résultat est lu (`clotures_exercices.resultat`,
 * jamais recalculé), la pièce OD passée dans l'exercice N, la ventilation et
 * l'auteur. Une affectation CONTRE-PASSÉE reste en historique (rien ne
 * s'efface, RG-11) et n'est plus « active » : l'exercice peut être affecté de
 * nouveau. L'unicité de l'affectation ACTIVE est tenue par le service
 * (verrou de la ligne d'exercice), pas par un index : une contre-passée et une
 * active coexistent.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('affectations_resultat', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('exercice_id')->constrained('exercices_comptables')->restrictOnDelete();
            $table->foreignUuid('cloture_id')->constrained('clotures_exercices')->restrictOnDelete();
            $table->decimal('resultat', 15, 2);
            $table->date('date_approbation');
            $table->decimal('reserve_legale', 15, 2)->default(0);
            $table->decimal('autres_reserves', 15, 2)->default(0);
            $table->decimal('dividendes', 15, 2)->default(0);
            $table->decimal('report_a_nouveau_crediteur', 15, 2)->default(0);
            $table->decimal('report_a_nouveau_debiteur', 15, 2)->default(0);
            $table->string('piece_affectation');
            // Identifiant de la pièce du poste (rejeu idempotent), le cas échéant.
            $table->string('piece_origine_id')->nullable()->index();
            $table->text('motif')->nullable();
            $table->foreignUuid('affectee_par')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('affectee_le');
            $table->foreignUuid('contrepassee_par')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('contrepassee_le')->nullable();
            $table->text('motif_contrepassation')->nullable();
            $table->timestamps();
            $table->index(['exercice_id', 'contrepassee_le']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('affectations_resultat');
    }
};
