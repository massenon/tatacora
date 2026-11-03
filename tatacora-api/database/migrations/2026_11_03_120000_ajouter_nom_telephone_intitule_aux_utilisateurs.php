<?php

declare(strict_types=1);

use Database\Seeders\RolePermissionSeeder;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * « Mon profil » : le nom complet, le téléphone et l'INTITULÉ DE POSTE d'un
 * compte (décision du PO du 03/11/2026), et les trois droits qui les
 * encadrent.
 *
 * Trois colonnes NULLABLES sur `utilisateurs`, ajoutées SEULEMENT si elles
 * manquent (rejouable). Rien n'est déduit pour les lignes d'avant : `null` =
 * non renseigné (l'écran retombe, pour le nom, sur la fiche RH rattachée).
 * L'intitulé de poste est un texte LIBRE et informatif ; la FONCTION, elle,
 * reste le rôle RBAC (ou la fiche RH) et n'est pas modifiable ici.
 *
 * Les droits `PROFIL_NOM`, `PROFIL_TELEPHONE` (tous les rôles) et
 * `PROFIL_INTITULE` (rôles d'administration) sont posés aux rôles EXISTANTS
 * par `RolePermissionSeeder::completerModulesNouveaux()` — additif et
 * idempotent : un module déjà connu de `permissions` n'est JAMAIS réécrit, donc
 * un réglage fait à l'écran Rôles & Permissions prime. Sur une base neuve (pas
 * encore de rôle) le seeder fait le travail complet.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::table('utilisateurs', function (Blueprint $table): void {
            if (! Schema::hasColumn('utilisateurs', 'nom_complet')) {
                $table->string('nom_complet', 120)->nullable()->after('email');
            }
            if (! Schema::hasColumn('utilisateurs', 'telephone')) {
                $table->string('telephone', 30)->nullable()->after('email');
            }
            if (! Schema::hasColumn('utilisateurs', 'intitule_poste')) {
                $table->string('intitule_poste', 120)->nullable()->after('email');
            }
        });

        if (\App\Shared\Rbac\Models\Role::query()->exists()) {
            (new RolePermissionSeeder())->completerModulesNouveaux();
        }
    }

    public function down(): void
    {
        foreach (['nom_complet', 'telephone', 'intitule_poste'] as $colonne) {
            if (Schema::hasColumn('utilisateurs', $colonne)) {
                Schema::table('utilisateurs', function (Blueprint $table) use ($colonne): void {
                    $table->dropColumn($colonne);
                });
            }
        }
    }
};
