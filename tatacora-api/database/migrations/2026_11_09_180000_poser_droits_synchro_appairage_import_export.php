<?php

declare(strict_types=1);

use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Database\Migrations\Migration;

/**
 * Trois droits transverses, hors écran — `SYNCHRO`, `APPAIRAGE`,
 * `IMPORT_EXPORT` (décision du PO du 09/11/2026) : les entrées de menu
 * « Synchronisation », « Appairage Postes » et « Import & Export » sont
 * visibles de TOUS les rôles par défaut (lecture ; `C` pour les rôles
 * d'administration).
 *
 * ADDITIF et idempotent : `completerModulesNouveaux()` ne pose que les modules
 * absents du référentiel `permissions` et ne retire aucun droit existant. Sur
 * une base neuve (aucun rôle), le seeder fait le travail complet.
 */
return new class () extends Migration {
    public function up(): void
    {
        if (Role::query()->exists()) {
            (new RolePermissionSeeder())->completerModulesNouveaux();
        }
    }

    public function down(): void
    {
        // Rien à défaire : poser un droit en lecture ne se « dé-pose » pas sans
        // risquer de retirer un réglage d'écran fait depuis.
    }
};
