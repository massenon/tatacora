<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Etats;

use App\Domain\Hebergement\Models\Reservation;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * État des réservations — EF-M14-02 appliqué à M1.
 *
 * Registre des réservations sur une plage d'arrivée, montants CALCULÉS depuis
 * `Reservation::montantTotal()`/`resteAPayer()` (mêmes formules que
 * `m1-reservations.html`, jamais une seconde somme) — une réservation sans
 * `tarif_nuit` figé (antérieure à PA-163) rend `null` et est exclue de la
 * valorisation plutôt que comptée pour zéro (Article 7).
 *
 * @see EF-M1-02 Création, modification et annulation de réservation
 * @see EF-M14-02 Bibliothèque d'états standards par module
 */
class EtatReservations implements EtatInterface
{
    public function module(): string
    {
        return 'M1';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        return __('etats_m14.reservations.libelle');
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

        return __('etats_m14.reservations.periode_toutes');
    }

    /**
     * @param  array<string, string>  $filtres  `date_debut`, `date_fin`, `toutes` (inclure les annulées)
     */
    public function calculer(array $filtres): EtatResultat
    {
        $inclureAnnulees = filter_var($filtres['toutes'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $debut = $filtres['date_debut'] ?? null;
        $fin = $filtres['date_fin'] ?? null;

        $requete = Reservation::query()->with(['client', 'unite'])->orderByDesc('date_arrivee');

        if (! $inclureAnnulees) {
            $requete->where('statut', '!=', 'annulee');
        }
        if (filled($debut)) {
            $requete->whereDate('date_arrivee', '>=', $debut);
        }
        if (filled($fin)) {
            $requete->whereDate('date_arrivee', '<=', $fin);
        }

        $lignes = [];
        $montantCumule = '0.00';
        $resteCumule = '0.00';
        $nbSansValorisation = 0;

        foreach ($requete->get() as $reservation) {
            $montant = $reservation->montantTotal();
            $reste = $reservation->resteAPayer();

            if ($montant === null || $reste === null) {
                $nbSansValorisation++;
            } else {
                $montantCumule = bcadd($montantCumule, $montant, 2);
                $resteCumule = bcadd($resteCumule, $reste, 2);
            }

            $lignes[] = [
                (string) $reservation->client?->nomComplet(),
                (string) $reservation->unite?->numero,
                $reservation->date_arrivee->format('d/m/Y'),
                $reservation->date_depart->format('d/m/Y'),
                (string) $reservation->nombreNuitees(),
                self::libelleStatut($reservation->statut),
                $montant ?? '—',
                $reste ?? '—',
            ];
        }

        $kpis = [
            __('etats_m14.reservations.kpi_nombre') => (string) count($lignes),
            __('etats_m14.reservations.kpi_montant') => $montantCumule,
            __('etats_m14.reservations.kpi_reste_du') => $resteCumule,
        ];

        if ($nbSansValorisation > 0) {
            $kpis[__('etats_m14.reservations.kpi_sans_tarif')] = (string) $nbSansValorisation;
        }

        return new EtatResultat(
            kpis: $kpis,
            entetes: [
                __('etats_m14.reservations.col_client'),
                __('etats_m14.reservations.col_unite'),
                __('etats_m14.reservations.col_arrivee'),
                __('etats_m14.reservations.col_depart'),
                __('etats_m14.reservations.col_nuits'),
                __('etats_m14.reservations.col_statut'),
                __('etats_m14.reservations.col_montant'),
                __('etats_m14.reservations.col_reste_du'),
            ],
            lignes: $lignes,
            filtresAppliques: array_filter([
                'date_debut' => $debut,
                'date_fin' => $fin,
                'toutes' => $inclureAnnulees ? 'oui' : null,
            ]),
        );
    }

    /**
     * Registre FERMÉ — les cinq valeurs de l'`enum` `reservations.statut`
     * (`2026_08_01_000100_create_hebergement.php`). Une valeur hors registre
     * est rendue EN CLAIR, jamais un libellé deviné.
     */
    private static function libelleStatut(string $statut): string
    {
        return match ($statut) {
            'en_attente' => __('etats_m14.reservations.statut.en_attente'),
            'confirmee' => __('etats_m14.reservations.statut.confirmee'),
            'en_cours' => __('etats_m14.reservations.statut.en_cours'),
            'terminee' => __('etats_m14.reservations.statut.terminee'),
            'annulee' => __('etats_m14.reservations.statut.annulee'),
            default => $statut,
        };
    }
}
