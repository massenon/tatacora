<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Le registre FERMÉ des suppressions que les postes rejouent (A5, 28/10/2026).
 *
 * Deux tables, pas une de plus : `unites_hebergement` et `vehicules`, les deux
 * seules que le web purge (`ParcHebergementService::purger`,
 * `ParcVehiculeService::purger`). Ajouter une table ici, c'est décider qu'un
 * poste peut effacer ses lignes sur la foi du serveur — une décision du PO, pas
 * un détail.
 *
 * `noter()` est appelé par les services de parc APRÈS le `delete()`, dans la
 * même transaction que lui : pas de suppression sans trace, pas de trace d'une
 * suppression annulée.
 */
final class SuppressionsDescendantes
{
    /** @var list<string> */
    public const TABLES = ['unites_hebergement', 'vehicules'];

    public static function noter(string $table, string $entiteId): void
    {
        if (! in_array($table, self::TABLES, true)) {
            return;
        }

        DB::table('suppressions_synchronisation')->insertOrIgnore([
            'id' => (string) Str::uuid(),
            'table_concernee' => $table,
            'entite_id' => $entiteId,
            'created_at' => now(),
        ]);
    }
}
