<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * L'EMPREINTE du reçu d'une dépense (lot L4, décision du PO du 27/10/2026 : le
 * poste joint un reçu en image, comme l'écran web, et le fichier voyage par la
 * synchronisation).
 *
 * `recu_path` existait seul : le chemin du fichier rangé sur le disque public.
 * Trois colonnes NULLABLES s'y ajoutent, posées avec le fichier :
 *
 *  * `recu_sha256` : l'empreinte du fichier. C'est elle qui rend le dépôt
 *    IDEMPOTENT (le même fichier redéposé après une coupure n'écrit rien) et
 *    qui permet à un autre poste de vérifier ce qu'il télécharge ;
 *  * `recu_taille` : sa taille en octets ;
 *  * `recu_type` : son type MIME réel (lu du contenu, jamais du nom).
 *
 * Un reçu joint AVANT cette migration (écran web) garde ces trois colonnes à
 * `null` : aucune valeur n'est inventée. Le téléchargement en calcule alors
 * l'empreinte à la volée.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('depenses', 'recu_sha256')) {
            Schema::table('depenses', function (Blueprint $table): void {
                $table->string('recu_sha256', 64)->nullable()->after('recu_path');
                $table->unsignedInteger('recu_taille')->nullable()->after('recu_sha256');
                $table->string('recu_type', 50)->nullable()->after('recu_taille');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('depenses', 'recu_sha256')) {
            Schema::table('depenses', function (Blueprint $table): void {
                $table->dropColumn(['recu_sha256', 'recu_taille', 'recu_type']);
            });
        }
    }
};
