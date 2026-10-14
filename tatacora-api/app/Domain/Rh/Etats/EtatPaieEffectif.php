<?php

declare(strict_types=1);

namespace App\Domain\Rh\Etats;

use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Services\LivreDePaieService;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;
use Carbon\CarbonImmutable;

/**
 * État Paie & Effectif — EF-M14-02 appliqué à M13.
 *
 * Deux matières RÉUTILISÉES, aucune recalculée : l'effectif vient du
 * référentiel `employes`, la masse salariale de la période vient de
 * `LivreDePaieService::totaux()` — LE MÊME service que l'onglet « Livre de
 * paie » de `m13-paie.html`, jamais une seconde addition. Les KPI portent
 * donc les MÊMES nuances que ce service : CNSS incomplète (risques
 * professionnels non confirmés, PA-53), VPS et ITS seuls arrêtés.
 *
 * @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
 * @see EF-M14-02 Bibliothèque d'états standards par module
 */
class EtatPaieEffectif implements EtatInterface
{
    public function __construct(private readonly LivreDePaieService $livreDePaie)
    {
    }

    public function module(): string
    {
        return 'M13';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('etats_m14.paie.libelle');
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        return __('etats_m14.paie.periode', ['periode' => $this->periodeValide($filtres)]);
    }

    /**
     * @param  array<string, string>  $filtres  `periode` (AAAA-MM, défaut : mois courant)
     */
    public function calculer(array $filtres): EtatResultat
    {
        $periode = $this->periodeValide($filtres);
        $totauxPaie = $this->livreDePaie->totaux($periode);

        $employes = Employe::query()->with('service')->orderBy('nom')->get();

        $lignes = array_map(static fn (Employe $employe): array => [
            trim($employe->nom . ' ' . ($employe->prenom ?? '')),
            $employe->matricule ?? '—',
            $employe->poste,
            (string) $employe->service?->libelle,
            $employe->date_embauche->format('d/m/Y'),
            $employe->statut,
            (string) $employe->salaire_base,
        ], $employes->all());

        $effectifParStatut = [];
        foreach (Employe::STATUTS as $statut) {
            $effectifParStatut[$statut] = $employes->where('statut', $statut)->count();
        }

        return new EtatResultat(
            kpis: [
                __('etats_m14.paie.kpi_effectif') => (string) $employes->count(),
                __('etats_m14.paie.kpi_actifs') => (string) $effectifParStatut['actif'],
                __('etats_m14.paie.kpi_masse_brute') => $totauxPaie['brut'],
                __('etats_m14.paie.kpi_net_periode') => $totauxPaie['net'],
                __('etats_m14.paie.kpi_bulletins_periode') => (string) $totauxPaie['effectif'],
            ],
            entetes: [
                __('etats_m14.paie.col_nom'),
                __('etats_m14.paie.col_matricule'),
                __('etats_m14.paie.col_poste'),
                __('etats_m14.paie.col_service'),
                __('etats_m14.paie.col_embauche'),
                __('etats_m14.paie.col_statut'),
                __('etats_m14.paie.col_salaire_base'),
            ],
            lignes: $lignes,
            filtresAppliques: ['periode' => $periode],
        );
    }

    /**
     * @param  array<string, string>  $filtres
     */
    private function periodeValide(array $filtres): string
    {
        $periode = $filtres['periode'] ?? '';

        return preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $periode) === 1
            ? $periode
            : CarbonImmutable::now()->format('Y-m');
    }
}
