<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * LA DESCRIPTION, FACULTATIVE, d'un plat (décision du PO du 30/10/2026).
 *
 * Une colonne NULLABLE (500 caractères au plus, validés par la requête et par
 * la PWA), sans index. `null` = « pas de description » : aucune description
 * n'est déduite ni inventée pour les plats d'avant. Elle s'affiche en ligne
 * secondaire sous le nom du plat, quand elle existe.
 *
 * Ajout CONDITIONNEL : rejouable sur une base qui porte déjà la colonne.
 */
return new class () extends Migration {
    public function up(): void
    {
        if (Schema::hasTable('plats') && ! Schema::hasColumn('plats', 'description')) {
            Schema::table('plats', function (Blueprint $table): void {
                $table->string('description', 500)->nullable()->after('libelle');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('plats') && Schema::hasColumn('plats', 'description')) {
            Schema::table('plats', function (Blueprint $table): void {
                $table->dropColumn('description');
            });
        }
    }
};
