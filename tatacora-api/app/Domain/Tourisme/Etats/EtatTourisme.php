<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Etats;

use App\Domain\Tourisme\Models\ReservationTour;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * État des réservations de circuits touristiques — EF-M14-02 appliqué à M9.
 *
 * `ReservationTour::montant()` est CALCULÉ (`circuits.prix × nb_participants`)
 * — jamais une seconde formule. Une réservation ANNULÉE (`STATUTS_INACTIFS`)
 * reste HORS de ce document par défaut, comme elle est déjà hors de la
 * capacité cumulée du départ (RG-04, PA-51).
 *
 * @see EF-M9-03 Réservation avec affectation de guide
 * @see EF-M14-02 Bibliothèque d'états standards par module
 */
class EtatTourisme implements EtatInterface
{
    public function module(): string
    {
        return 'M9';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('etats_m14.tourisme.libelle');
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

        return __('etats_m14.tourisme.periode_toutes');
    }

    /**
     * @param  array<string, string>  $filtres  `date_debut`, `date_fin`, `toutes` (inclure les annulées)
     */
    public function calculer(array $filtres): EtatResultat
    {
        $inclureAnnulees = filter_var($filtres['toutes'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        $requete = ReservationTour::query()
            ->with(['client', 'guide', 'circuit'])
            ->orderByDesc('date_circuit');

        if (! $inclureAnnulees) {
            $requete->whereNotIn('statut', ReservationTour::STATUTS_INACTIFS);
        }
        if (filled($debut)) {
            $requete->whereDate('date_circuit', '>=', $debut);
        }
        if (filled($fin)) {
            $requete->whereDate('date_circuit', '<=', $fin);
        }

        $lignes = [];
        $montantCumule = '0.00';
        $totalParticipants = 0;

        foreach ($requete->get() as $reservation) {
            $montant = $reservation->montant();
            $montantCumule = bcadd($montantCumule, $montant, 2);
            $totalParticipants += $reservation->nb_participants;

            $lignes[] = [
                (string) $reservation->circuit->nom,
                (string) $reservation->client?->nomComplet(),
                (string) $reservation->guide?->nom,
                $reservation->date_circuit->format('d/m/Y'),
                (string) $reservation->nb_participants,
                $reservation->statut,
                $montant,
            ];
        }

        return new EtatResultat(
            kpis: [
                __('etats_m14.tourisme.kpi_nombre') => (string) count($lignes),
                __('etats_m14.tourisme.kpi_participants') => (string) $totalParticipants,
                __('etats_m14.tourisme.kpi_montant') => $montantCumule,
            ],
            entetes: [
                __('etats_m14.tourisme.col_circuit'),
                __('etats_m14.tourisme.col_client'),
                __('etats_m14.tourisme.col_guide'),
                __('etats_m14.tourisme.col_date'),
                __('etats_m14.tourisme.col_participants'),
                __('etats_m14.tourisme.col_statut'),
                __('etats_m14.tourisme.col_montant'),
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
