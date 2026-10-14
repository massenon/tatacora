<?php

declare(strict_types=1);

namespace Database\Migrations;

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class () extends Migration {
    public function up(): void
    {
        // 1. Colonnes additionnelles sur la table 'fournisseurs'
        if (Schema::hasTable('fournisseurs')) {
            Schema::table('fournisseurs', function (Blueprint $table) {
                if (!Schema::hasColumn('fournisseurs', 'nom')) {
                    $table->string('nom')->nullable()->after('id');
                }
                if (!Schema::hasColumn('fournisseurs', 'telephone')) {
                    $table->string('telephone')->nullable()->after('contact');
                }
                if (!Schema::hasColumn('fournisseurs', 'email')) {
                    $table->string('email')->nullable()->after('telephone');
                }
                if (!Schema::hasColumn('fournisseurs', 'ville')) {
                    $table->string('ville')->nullable()->after('email');
                }
                if (!Schema::hasColumn('fournisseurs', 'ifu')) {
                    $table->string('ifu')->nullable()->after('ville');
                }
            });
        }

        // 2. Colonnes additionnelles sur 'commandes_achat'
        if (Schema::hasTable('commandes_achat')) {
            Schema::table('commandes_achat', function (Blueprint $table) {
                if (!Schema::hasColumn('commandes_achat', 'montant_total')) {
                    $table->decimal('montant_total', 12, 2)->default(0)->after('statut');
                }
                if (!Schema::hasColumn('commandes_achat', 'montant_regle')) {
                    $table->decimal('montant_regle', 12, 2)->default(0)->after('montant_total');
                }
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('fournisseurs')) {
            Schema::table('fournisseurs', function (Blueprint $table) {
                $cols = ['nom', 'telephone', 'email', 'ville', 'ifu'];
                foreach ($cols as $c) {
                    if (Schema::hasColumn('fournisseurs', $c)) {
                        $table->dropColumn($c);
                    }
                }
            });
        }

        if (Schema::hasTable('commandes_achat')) {
            Schema::table('commandes_achat', function (Blueprint $table) {
                $cols = ['montant_total', 'montant_regle'];
                foreach ($cols as $c) {
                    if (Schema::hasColumn('commandes_achat', $c)) {
                        $table->dropColumn($c);
                    }
                }
            });
        }
    }
};
