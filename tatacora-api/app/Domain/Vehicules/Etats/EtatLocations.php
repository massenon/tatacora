<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Etats;

use App\Domain\Vehicules\Models\ContratLocation;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * État des locations de véhicules — EF-M14-02 appliqué à M8.
 *
 * `montant()` est CALCULÉ (`tarif_jour × nombreJours()`, `ContratLocation`) —
 * jamais une seconde formule. Les contrats ANNULÉS (`statut = annule`,
 * `ContratLocationService::annuler`) sont exclus des lignes, du nombre et du
 * montant : ils ne sont pas du chiffre d'affaires. Ce document ne prétend à
 * aucun « reste dû » (pas de suivi de règlement ici), à la différence de M7
 * où `montant_regle` existe réellement.
 *
 * @see EF-M14-02 Bibliothèque d'états standards par module
 * @see PA-50 historique : le statut n'existait pas encore
 */
class EtatLocations implements EtatInterface
{
    public function module(): string
    {
        return 'M8';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('etats_m14.locations.libelle');
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

        return __('etats_m14.locations.periode_toutes');
    }

    /**
     * @param  array<string, string>  $filtres  `date_debut`, `date_fin`
     */
    public function calculer(array $filtres): EtatResultat
    {
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        $requete = ContratLocation::query()->with(['client', 'vehicule'])
            ->where('statut', '!=', 'annule')
            ->orderByDesc('date_debut');

        if (filled($debut)) {
            $requete->whereDate('date_debut', '>=', $debut);
        }
        if (filled($fin)) {
            $requete->whereDate('date_debut', '<=', $fin);
        }

        $lignes = [];
        $montantCumule = '0.00';

        foreach ($requete->get() as $contrat) {
            $montant = $contrat->montant();
            $montantCumule = bcadd($montantCumule, $montant, 2);

            $lignes[] = [
                (string) $contrat->client?->nomComplet(),
                $contrat->vehicule->categorie . ' — ' . $contrat->vehicule->immatriculation,
                $contrat->date_debut->format('d/m/Y'),
                $contrat->date_fin->format('d/m/Y'),
                (string) $contrat->nombreJours(),
                $montant,
            ];
        }

        return new EtatResultat(
            kpis: [
                __('etats_m14.locations.kpi_nombre') => (string) count($lignes),
                __('etats_m14.locations.kpi_montant') => $montantCumule,
            ],
            entetes: [
                __('etats_m14.locations.col_client'),
                __('etats_m14.locations.col_vehicule'),
                __('etats_m14.locations.col_debut'),
                __('etats_m14.locations.col_fin'),
                __('etats_m14.locations.col_jours'),
                __('etats_m14.locations.col_montant'),
            ],
            lignes: $lignes,
            filtresAppliques: array_filter([
                'date_debut' => $debut,
                'date_fin' => $fin,
            ]),
        );
    }
}
