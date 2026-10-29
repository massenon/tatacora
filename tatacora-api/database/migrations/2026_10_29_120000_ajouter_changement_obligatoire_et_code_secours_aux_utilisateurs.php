<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Réinitialisation du mot de passe PAR UN ADMINISTRATEUR et code de secours
 * (décision du PO du 29/10/2026, option A : aucun envoi automatique d'e-mail).
 *
 * Colonnes ADDITIVES et NULLABLES (ou à défaut neutre) sur `utilisateurs` :
 *
 *  - `must_change_password` : le compte doit définir un nouveau mot de passe
 *    avant tout accès aux modules (vrai après une réinitialisation) ;
 *  - `temp_expires_at` : l'instant où le mot de passe TEMPORAIRE cesse d'ouvrir
 *    quoi que ce soit (24 h) ; `null` : pas de temporaire en cours ;
 *  - `previous_password_hash` : l'empreinte de l'ANCIEN mot de passe, gardée le
 *    temps du changement forcé pour refuser sa réutilisation (« différent de
 *    l'ancien »), puis effacée ;
 *  - `recovery_code_hash` : l'empreinte du code de secours de l'administrateur
 *    (jamais le code) ; `null` : pas de code (comptes d'avant ce lot, comptes
 *    non administrateurs) ;
 *  - `recovery_code_generated_at` : quand ce code a été posé.
 *
 * Aucune valeur n'est déduite pour les lignes existantes : un ancien compte
 * fonctionne sans changement et n'a pas de code de secours. Ajouts
 * CONDITIONNELS : rejouable sur une base qui porte déjà une colonne.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::table('utilisateurs', function (Blueprint $table): void {
            if (! Schema::hasColumn('utilisateurs', 'must_change_password')) {
                $table->boolean('must_change_password')->default(false);
            }
            if (! Schema::hasColumn('utilisateurs', 'temp_expires_at')) {
                $table->timestamp('temp_expires_at')->nullable();
            }
            if (! Schema::hasColumn('utilisateurs', 'previous_password_hash')) {
                $table->string('previous_password_hash')->nullable();
            }
            if (! Schema::hasColumn('utilisateurs', 'recovery_code_hash')) {
                $table->string('recovery_code_hash')->nullable();
            }
            if (! Schema::hasColumn('utilisateurs', 'recovery_code_generated_at')) {
                $table->timestamp('recovery_code_generated_at')->nullable();
            }
        });
    }

    public function down(): void
    {
        foreach ([
            'must_change_password',
            'temp_expires_at',
            'previous_password_hash',
            'recovery_code_hash',
            'recovery_code_generated_at',
        ] as $colonne) {
            if (Schema::hasColumn('utilisateurs', $colonne)) {
                Schema::table('utilisateurs', function (Blueprint $table) use ($colonne): void {
                    $table->dropColumn($colonne);
                });
            }
        }
    }
};
