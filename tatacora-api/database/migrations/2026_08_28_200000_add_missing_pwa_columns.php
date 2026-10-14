<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        // 1. Colonne 'categorie' sur la table 'plats'
        if (Schema::hasTable('plats') && !Schema::hasColumn('plats', 'categorie')) {
            Schema::table('plats', function (Blueprint $table) {
                $table->string('categorie')->nullable()->after('menu_id')->index();
            });
        }

        // 2. Colonnes financières et statut sur 'contrats_location'
        if (Schema::hasTable('contrats_location')) {
            Schema::table('contrats_location', function (Blueprint $table) {
                if (!Schema::hasColumn('contrats_location', 'statut')) {
                    $table->string('statut')->default('actif')->after('vehicule_id')->index();
                }
                if (!Schema::hasColumn('contrats_location', 'numero')) {
                    $table->string('numero')->nullable()->after('id')->index();
                }
                if (!Schema::hasColumn('contrats_location', 'client_nom')) {
                    $table->string('client_nom')->nullable()->after('client_id');
                }
                if (!Schema::hasColumn('contrats_location', 'montant')) {
                    $table->decimal('montant', 12, 2)->default(0)->after('date_fin');
                }
                if (!Schema::hasColumn('contrats_location', 'acompte')) {
                    $table->decimal('acompte', 12, 2)->default(0)->after('montant');
                }
                if (!Schema::hasColumn('contrats_location', 'reste_a_payer')) {
                    $table->decimal('reste_a_payer', 12, 2)->default(0)->after('acompte');
                }
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('plats') && Schema::hasColumn('plats', 'categorie')) {
            Schema::table('plats', function (Blueprint $table) {
                $table->dropColumn('categorie');
            });
        }

        if (Schema::hasTable('contrats_location')) {
            Schema::table('contrats_location', function (Blueprint $table) {
                $columns = ['statut', 'numero', 'client_nom', 'montant', 'acompte', 'reste_a_payer'];
                foreach ($columns as $col) {
                    if (Schema::hasColumn('contrats_location', $col)) {
                        $table->dropColumn($col);
                    }
                }
            });
        }
    }
};
