<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * « Postes & Appairage » (21/10/2026) : la colonne « Dernier contrôle » — le
 * dernier passage d'un poste sur `GET /sync/coherence` (son contrôle de
 * cohérence). Le poste n'y envoie pas son nom : c'est celui de son jeton.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('etats_postes_synchronisation', function (Blueprint $table) {
            $table->timestamp('dernier_controle_le')->nullable()->after('demande_lue_le');
        });
    }

    public function down(): void
    {
        Schema::table('etats_postes_synchronisation', function (Blueprint $table) {
            $table->dropColumn('dernier_controle_le');
        });
    }
};
