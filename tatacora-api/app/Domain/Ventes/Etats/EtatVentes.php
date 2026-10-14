<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Etats;

use App\Domain\Ventes\Models\Vente;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * État des ventes — EF-M14-02 appliqué à M5 (points de vente comptant et
 * hébergés — `Vente::point_vente`).
 *
 * Une vente ANNULÉE reste HORS de ce document par défaut : `Vente::STATUTS`
 * porte `annulee`, et une vente annulée n'a jamais été un chiffre d'affaires
 * réel — la compter fausserait le total dans le sens de la surestimation.
 *
 * @see EF-M14-02 Bibliothèque d'états standards par module
 */
class EtatVentes implements EtatInterface
{
    public function module(): string
    {
        return 'M5';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('etats_m14.ventes.libelle');
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

        return __('etats_m14.ventes.periode_toutes');
    }

    /**
     * @param  array<string, string>  $filtres  `date_debut`, `date_fin`, `toutes` (inclure les annulées)
     */
    public function calculer(array $filtres): EtatResultat
    {
        $inclureAnnulees = filter_var($filtres['toutes'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        $requete = Vente::query()->with('client')->orderByDesc('created_at');

        if (! $inclureAnnulees) {
            $requete->where('statut', '!=', 'annulee');
        }
        if (filled($debut)) {
            $requete->whereDate('created_at', '>=', $debut);
        }
        if (filled($fin)) {
            $requete->whereDate('created_at', '<=', $fin);
        }

        $lignes = [];
        $montantCumule = '0.00';
        $nbEncaissees = 0;

        foreach ($requete->get() as $vente) {
            $montantCumule = bcadd($montantCumule, (string) $vente->montant_total, 2);
            if ($vente->encaisse) {
                $nbEncaissees++;
            }

            $lignes[] = [
                $vente->numero,
                (string) $vente->created_at?->format('d/m/Y H:i'),
                $vente->point_vente,
                (string) ($vente->client?->nomComplet() ?? '—'),
                $vente->mode_paiement,
                $vente->encaisse ? __('etats_m14.ventes.encaisse_oui') : __('etats_m14.ventes.encaisse_non'),
                (string) $vente->montant_total,
            ];
        }

        return new EtatResultat(
            kpis: [
                __('etats_m14.ventes.kpi_nombre') => (string) count($lignes),
                __('etats_m14.ventes.kpi_encaissees') => $nbEncaissees . ' / ' . count($lignes),
                __('etats_m14.ventes.kpi_montant') => $montantCumule,
            ],
            entetes: [
                __('etats_m14.ventes.col_numero'),
                __('etats_m14.ventes.col_date'),
                __('etats_m14.ventes.col_point_vente'),
                __('etats_m14.ventes.col_client'),
                __('etats_m14.ventes.col_mode_paiement'),
                __('etats_m14.ventes.col_encaisse'),
                __('etats_m14.ventes.col_montant'),
            ],
            lignes: $lignes,
            filtresAppliques: array_filter([
                'date_debut' => $debut,
                'date_fin' => $fin,
                'toutes' => $inclureAnnulees ? 'oui' : null,
            ]),
        );
    }
}
