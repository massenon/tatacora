<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * La clôture SYSCOHADA annuelle — lot 2 (décisions du Product Owner du
 * 20/10/2026 : clôture ANNUELLE, réouverture par LE COMPTABLE, archive au
 * format SYSCOHADA révisé / DGI Bénin).
 *
 *  - `clotures_exercices` : l'historique des clôtures d'un exercice — les
 *    numéros des deux pièces qu'elle a passées (solde des comptes de
 *    gestion en 131/139, à-nouveaux de N+1), le résultat, l'archive et son
 *    empreinte, et, le cas échéant, la réouverture (qui, quand, pourquoi).
 *    Une clôture rouverte reste en historique : rien ne s'efface.
 *  - le journal `AN` (à-nouveaux), où se datent au 1er janvier de N+1 les
 *    soldes des comptes de bilan de N ; et le journal `CL` (clôture), qui
 *    porte le solde des comptes de gestion — à part, pour que les états
 *    financiers d'un exercice clôturé restent ceux d'AVANT la clôture.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('clotures_exercices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('exercice_id')->constrained('exercices_comptables')->restrictOnDelete();
            $table->string('piece_cloture')->nullable();
            $table->string('piece_a_nouveaux')->nullable();
            $table->decimal('resultat', 15, 2);
            $table->foreignUuid('cloturee_par')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('cloturee_le');
            $table->string('archive_chemin')->nullable();
            $table->string('archive_empreinte', 64)->nullable();
            $table->foreignUuid('rouverte_par')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('rouverte_le')->nullable();
            $table->text('motif_reouverture')->nullable();
            $table->timestamps();
            $table->index(['exercice_id', 'rouverte_le']);
        });

        foreach (['AN' => 'Journal des à-nouveaux', 'CL' => 'Journal de clôture'] as $code => $libelle) {
            if (! DB::table('journaux_comptables')->where('code', $code)->exists()) {
                DB::table('journaux_comptables')->insert([
                    'id' => (string) Str::uuid(),
                    'code' => $code,
                    'libelle' => $libelle,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('clotures_exercices');
    }
};
