<?php

declare(strict_types=1);

namespace App\Domain\Depenses\Etats;

use App\Domain\Depenses\Models\Depense;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * État des dépenses — EF-M14-02 appliqué à M10.
 *
 * `ecriture_id` distingue une dépense dont la pièce comptable a été passée
 * (règle du dépôt : tout mouvement d'argent produit son écriture dans la
 * MÊME transaction, sinon rien n'est écrit — `DepenseService`) : une ligne
 * sans écriture n'existerait donc que si l'enregistrement lui-même avait
 * échoué, ce que la colonne « Écriture » rend visible plutôt que de le taire.
 *
 * @see EF-M14-02 Bibliothèque d'états standards par module
 */
class EtatDepenses implements EtatInterface
{
    public function module(): string
    {
        return 'M10';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('etats_m14.depenses.libelle');
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        if (filled($debut) && filled($fin)) {
            return __('etats_m14.periode_du_au', ['debut' => $debut, 'fin' => $fin]);
        }

        return __('etats_m14.depenses.periode_toutes');
    }

    /**
     * @param  array<string, string>  $filtres  `date_debut`, `date_fin`
     */
    public function calculer(array $filtres): EtatResultat
    {
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        $requete = Depense::query()->orderByDesc('date_transaction');

        if (filled($debut)) {
            $requete->whereDate('date_transaction', '>=', $debut);
        }
        if (filled($fin)) {
            $requete->whereDate('date_transaction', '<=', $fin);
        }

        $lignes = [];
        $montantCumule = '0.00';

        foreach ($requete->get() as $depense) {
            $montantCumule = bcadd($montantCumule, (string) $depense->montant_total, 2);

            $lignes[] = [
                $depense->numero,
                $depense->date_transaction->format('d/m/Y'),
                $depense->libelle,
                $depense->tresorerie,
                (string) $depense->montant_total,
                $depense->ecriture_id !== null
                    ? __('etats_m14.depenses.ecriture_passee')
                    : __('etats_m14.depenses.ecriture_absente'),
            ];
        }

        return new EtatResultat(
            kpis: [
                __('etats_m14.depenses.kpi_nombre') => (string) count($lignes),
                __('etats_m14.depenses.kpi_montant') => $montantCumule,
            ],
            entetes: [
                __('etats_m14.depenses.col_numero'),
                __('etats_m14.depenses.col_date'),
                __('etats_m14.depenses.col_libelle'),
                __('etats_m14.depenses.col_tresorerie'),
                __('etats_m14.depenses.col_montant'),
                __('etats_m14.depenses.col_ecriture'),
            ],
            lignes: $lignes,
            filtresAppliques: array_filter([
                'date_debut' => $debut,
                'date_fin' => $fin,
            ]),
        );
    }
}
