<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Le contrôle de cohérence (P1-1 de la spécification de synchronisation) :
 * par table et par JOUR MÉTIER, le nombre de documents actifs et leur total
 * (en centimes), tels que le serveur les détient. Le poste fait le même
 * compte chez lui et affiche les écarts : « ce poste a tout reçu jusqu'au… ».
 *
 * Seules les tables que le compte LIT entrent (même règle que le flux
 * descendant). Les totaux comparables sont ceux dont les deux côtés tiennent
 * la même colonne ; ailleurs, seul le nombre se compare (`total` nul).
 */
class CoherenceService
{
    /** La fenêtre maximale d'un contrôle, en jours. */
    public const JOURS_MAX = 31;

    /**
     * table → [requête de base, expression du jour, expression du total (ou null), module]
     *
     * @var array<string, array{0: string, 1: string, 2: ?string, 3: string}>
     */
    public const INDICATEURS = [
        // `created_at` : la date MÉTIER de la vente (la clôture du poste) ;
        // `date_creation` est sa réception au serveur.
        'ventes' => ["statut = 'validee'", 'DATE(created_at)', 'ROUND(montant_total * 100)', 'M5'],
        'depenses' => ['1 = 1', 'date_transaction', 'ROUND(montant_total * 100)', 'M10'],
        'paiements' => ["statut <> 'annule'", 'DATE(date_paiement)', 'ROUND(montant * 100)', 'M2'],
        'factures' => ['1 = 1', 'date_emission', null, 'M2'],
        'reservations' => ["statut <> 'annulee'", 'date_arrivee', null, 'M1'],
        'reglements_fournisseur' => ["statut <> 'annule'", 'date_reglement', 'ROUND(montant * 100)', 'M7'],
        'mouvements_stock' => ['1 = 1', 'DATE(date_mouvement)', 'ROUND(quantite * 100)', 'M6'],
    ];

    /**
     * @return array<string, array<string, array{nombre: int, total: ?int}>>
     */
    public function comptes(User $utilisateur, string $du, string $au): array
    {
        $comptes = [];

        foreach (self::INDICATEURS as $table => [$filtre, $jour, $total, $module]) {
            if (! in_array($utilisateur->niveauSurModule($module), ['L', 'C'], true)) {
                continue;
            }

            $lignes = DB::table($table)
                ->selectRaw("{$jour} AS jour, COUNT(*) AS nombre" . ($total !== null ? ", SUM({$total}) AS total" : ''))
                ->whereRaw($filtre)
                ->whereRaw("{$jour} BETWEEN ? AND ?", [$du, $au])
                ->groupByRaw($jour)
                ->get();

            $comptes[$table] = [];

            foreach ($lignes as $l) {
                $comptes[$table][(string) $l->jour] = [
                    'nombre' => (int) $l->nombre,
                    'total' => $total !== null ? (int) $l->total : null,
                ];
            }
        }

        return $comptes;
    }
}
