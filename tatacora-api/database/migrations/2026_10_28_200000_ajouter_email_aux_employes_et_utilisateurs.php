<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * L'ADRESSE E-MAIL, FACULTATIVE, d'un employé et d'un compte (décision du PO du
 * 28/10/2026).
 *
 * Deux colonnes NULLABLES, sans index ni unicité : deux salariés d'une même
 * famille peuvent partager une boîte, et le `login` reste la seule clé d'un
 * compte. Aucune adresse n'est déduite ni inventée pour les lignes d'avant
 * (`null` = « non renseignée »). Elles servent de destinataire aux
 * notifications e-mail (`bulletin_disponible`, `echeance_vps`) ; sans adresse,
 * le message est composé mais ne part pas, sans erreur.
 *
 * Ajouts CONDITIONNELS : rejouable sur une base qui porte déjà la colonne.
 */
return new class () extends Migration {
    public function up(): void
    {
        if (! Schema::hasColumn('employes', 'email')) {
            Schema::table('employes', function (Blueprint $table): void {
                $table->string('email')->nullable()->after('prenom');
            });
        }

        if (! Schema::hasColumn('utilisateurs', 'email')) {
            Schema::table('utilisateurs', function (Blueprint $table): void {
                $table->string('email')->nullable()->after('login');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('employes', 'email')) {
            Schema::table('employes', function (Blueprint $table): void {
                $table->dropColumn('email');
            });
        }

        if (Schema::hasColumn('utilisateurs', 'email')) {
            Schema::table('utilisateurs', function (Blueprint $table): void {
                $table->dropColumn('email');
            });
        }
    }
};
