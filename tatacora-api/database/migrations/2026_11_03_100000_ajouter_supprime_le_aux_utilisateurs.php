<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * SUPPRIMER UN COMPTE UTILISATEUR (décision du PO du 03/11/2026) : suppression
 * LOGIQUE, jamais un DELETE.
 *
 * Une colonne NULLABLE, `supprime_le`, sans valeur déduite : aucun compte
 * existant n'est supprimé. Les ventes, dépenses, écritures et le journal
 * d'audit gardent leur auteur (les clés étrangères restent valides) ; la ligne
 * garde son `login` sous l'index unique, donc l'identifiant n'est PAS
 * réutilisable.
 *
 * Ajout CONDITIONNEL : rejouable sur une base qui porte déjà la colonne.
 */
return new class () extends Migration {
    public function up(): void
    {
        if (Schema::hasTable('utilisateurs') && ! Schema::hasColumn('utilisateurs', 'supprime_le')) {
            Schema::table('utilisateurs', function (Blueprint $table): void {
                $table->timestamp('supprime_le')->nullable();
                $table->index('supprime_le');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('utilisateurs') && Schema::hasColumn('utilisateurs', 'supprime_le')) {
            Schema::table('utilisateurs', function (Blueprint $table): void {
                $table->dropIndex(['supprime_le']);
                $table->dropColumn('supprime_le');
            });
        }
    }
};
