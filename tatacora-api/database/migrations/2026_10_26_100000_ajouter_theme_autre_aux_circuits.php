<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Le thème « Autre » du catalogue de circuits (demande du Product Owner,
 * 26/10/2026).
 *
 * `circuits.theme` est une énumération fermée : la valeur `autre` s'ajoute à
 * la colonne, à la validation (`EnregistrerCircuitRequest::THEMES`) et au
 * poste. Les valeurs existantes ne bougent pas.
 */
return new class () extends Migration {
    public function up(): void
    {
        DB::statement("ALTER TABLE circuits MODIFY theme ENUM('aventure','culture','faune','nature','autre') NOT NULL");
    }

    public function down(): void
    {
        // Une prestation « Autre » ne peut pas être perdue : elle retombe sur
        // « nature » avant que la valeur ne quitte l'énumération.
        DB::table('circuits')->where('theme', 'autre')->update(['theme' => 'nature']);
        DB::statement("ALTER TABLE circuits MODIFY theme ENUM('aventure','culture','faune','nature') NOT NULL");
    }
};
