<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Etats;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;
use RuntimeException;

/**
 * État Balance Générale — EF-M14-02 appliqué à M10.
 *
 * RÉUTILISE `BalanceGeneraleService::genererPourExercice()` — LA MÊME
 * agrégation que `m10-balance.html` — jamais une seconde requête sur
 * `ecritures_comptables`. Les deux égalités qui font `equilibree` (débit =
 * crédit, et solde débiteur cumulé = solde créditeur cumulé) restent
 * calculées là-bas, en `bccomp` : ce fichier ne fait que mettre en forme
 * `BalanceGenerale` pour `EtatResultat`.
 *
 * @see EF-M10-06 Édition des états réglementaires SYSCOHADA
 * @see EF-M14-02 Bibliothèque d'états standards par module
 */
class EtatBalance implements EtatInterface
{
    public function __construct(private readonly BalanceGeneraleService $balances)
    {
    }

    public function module(): string
    {
        return 'M10';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        $exercice = $this->exercice($filtres);

        return $exercice === null
            ? __('etats_m14.balance.libelle_sans_exercice')
            : __('etats_m14.balance.libelle', ['annee' => $exercice->annee]);
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        $exercice = $this->exercice($filtres);

        return $exercice === null
            ? __('etats_m14.balance.aucun_exercice')
            : __('etats_m14.periode_du_au', [
                'debut' => $exercice->date_debut->format('d/m/Y'),
                'fin' => $exercice->date_fin->format('d/m/Y'),
            ]);
    }

    /**
     * @param  array<string, string>  $filtres  `exercice_annee`, `statut` (`toutes`|`brouillon`|`validee`)
     */
    public function calculer(array $filtres): EtatResultat
    {
        $exercice = $this->exercice($filtres);

        if ($exercice === null) {
            throw new RuntimeException(__('etats_m14.balance.aucun_exercice'));
        }

        $filtreStatut = in_array($filtres['statut'] ?? '', EcritureComptable::FILTRES_STATUT, true)
            ? $filtres['statut']
            : EcritureComptable::FILTRE_STATUT_TOUTES;

        $statuts = $filtreStatut === EcritureComptable::FILTRE_STATUT_TOUTES
            ? EcritureComptable::STATUTS
            : [$filtreStatut];

        $balance = $this->balances->genererPourExercice($exercice->id, $statuts, $filtreStatut);

        $lignes = array_map(static fn ($ligne): array => [
            $ligne->numeroCompte,
            $ligne->libelle,
            $ligne->totalDebit,
            $ligne->totalCredit,
            $ligne->soldeDebiteur,
            $ligne->soldeCrediteur,
        ], $balance->lignes);

        return new EtatResultat(
            kpis: [
                __('etats_m14.balance.kpi_comptes') => (string) count($lignes),
                __('etats_m14.balance.kpi_total_debit') => $balance->totalDebit,
                __('etats_m14.balance.kpi_total_credit') => $balance->totalCredit,
                __('etats_m14.balance.kpi_equilibree') => $balance->equilibree
                    ? __('etats_m14.balance.oui')
                    : __('etats_m14.balance.non'),
            ],
            entetes: [
                __('etats_m14.balance.col_compte'),
                __('etats_m14.balance.col_libelle'),
                __('etats_m14.balance.col_debit'),
                __('etats_m14.balance.col_credit'),
                __('etats_m14.balance.col_solde_debiteur'),
                __('etats_m14.balance.col_solde_crediteur'),
            ],
            lignes: $lignes,
            filtresAppliques: [
                'exercice' => (string) $exercice->annee,
                'statut' => $filtreStatut,
            ],
        );
    }

    /**
     * L'exercice demandé (`exercice_annee`), ou le plus récent — `null` si
     * aucun exercice n'a jamais été ouvert (l'écran de démarrage du dépôt).
     *
     * @param  array<string, string>  $filtres
     */
    private function exercice(array $filtres): ?ExerciceComptable
    {
        $annee = $filtres['exercice_annee'] ?? null;

        if (filled($annee)) {
            $exercice = ExerciceComptable::query()->where('annee', (int) $annee)->first();
            if ($exercice !== null) {
                return $exercice;
            }
        }

        return ExerciceComptable::query()->orderByDesc('annee')->first();
    }
}
