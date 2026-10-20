<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * La GÉNÉRATION des données du serveur — décision du Product Owner du
 * 19/10/2026 (« les essais en production suivis de la réinitialisation, sur
 * le web et le poste »).
 *
 * Chaque réinitialisation « comme neuf » ouvre une génération NOUVELLE. Un
 * poste qui a synchronisé avec l'ancienne ne peut plus rien envoyer ni
 * recevoir (409 `generation_perimee`) tant qu'il n'a pas été réinitialisé à
 * son tour : sans ce verrou, sa file d'essai repartirait vers un serveur
 * remis à neuf, et ses documents d'essai resteraient affichés sur le poste.
 *
 * La génération de départ est posée ICI, par la migration.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('generations_donnees', function (Blueprint $table) {
            // L'ORDRE des générations : deux réinitialisations dans la même
            // seconde se départagent sans ambiguïté.
            $table->id('rang');
            $table->uuid('generation')->unique();
            $table->foreignUuid('utilisateur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
            $table->string('motif', 64);
            $table->timestamp('created_at')->useCurrent();
        });

        DB::table('generations_donnees')->insert([
            'generation' => (string) Str::uuid(),
            'motif' => 'installation',
            'created_at' => now(),
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('generations_donnees');
    }
};
