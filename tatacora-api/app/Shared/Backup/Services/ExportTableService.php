<?php

declare(strict_types=1);

namespace App\Shared\Backup\Services;

use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * « Exporter une table existante » — `import-export.html`, modale
 * `modale-export-table` (l.342-358), portée le 02/09/2026 sur directive du
 * Product Owner (le refus antérieur `maitre-refuse:…#modale-export-table` est
 * levé par cette directive, pas contourné).
 *
 * ## LECTURE seule, sur une liste FERMÉE par exclusion nommée
 *
 * Le contenu actuel de la table, au format JSON — rien n'est écrit. Les
 * tables SENSIBLES et TECHNIQUES sont exclues une par une :
 * `utilisateurs` et `personal_access_tokens` (dérivés de mots de passe et
 * jetons — un export téléchargeable serait une surface d'exfiltration),
 * les tables du framework (cache, files d'attente, migrations) qui ne sont
 * pas des données de l'entreprise.
 *
 * L'exclusion est une liste de NOMS, pas un motif : une table ajoutée demain
 * est exportable par défaut — c'est le comportement du maître
 * (`tablesApplicatives()`, engine l.377-383), et une donnée métier qui
 * n'apparaîtrait pas au sélecteur passerait pour absente de la base.
 */
class ExportTableService
{
    /**
     * @var list<string>
     */
    public const TABLES_EXCLUES = [
        // Secrets et authentification — jamais exportables, quel que soit le rôle.
        'utilisateurs',
        'personal_access_tokens',
        // Technique framework — pas une donnée de l'entreprise.
        'migrations',
        'cache',
        'cache_locks',
        'jobs',
        'job_batches',
        'failed_jobs',
        'sessions',
    ];

    /**
     * @return list<string>
     */
    public function tablesExportables(): array
    {
        // `information_schema` filtré par `DATABASE()`, jamais
        // `Schema::getTables()` : mesuré le 02/09/2026, ce dernier remonte
        // les tables de TOUTES les bases accessibles au compte MySQL — le
        // sélecteur aurait offert des bases étrangères à l'export.
        $lignes = DB::select(
            "SELECT TABLE_NAME AS nom FROM information_schema.TABLES"
            ." WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'",
        );

        $exportables = array_values(array_filter(
            array_map(static fn (object $ligne): string => (string) $ligne->nom, $lignes),
            static fn (string $table): bool => ! in_array($table, self::TABLES_EXCLUES, true),
        ));

        sort($exportables);

        return $exportables;
    }

    /**
     * Le contenu RÉEL de la table, sérialisé en JSON — le format de la modale
     * du maître (« Le contenu actuel de la table, au format JSON. »).
     */
    public function exporterJson(string $table): string
    {
        if (! in_array($table, $this->tablesExportables(), true)) {
            // Nom hors liste : une erreur d'appel (sélecteur contourné),
            // jamais une saisie légitime.
            throw new RuntimeException(__('pwa.import_export.export_table_refusee'));
        }

        $lignes = DB::table($table)->get();

        return (string) json_encode([
            'table' => $table,
            'genere_le' => now()->toIso8601String(),
            'nombre_lignes' => $lignes->count(),
            'lignes' => $lignes,
        ], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
}
