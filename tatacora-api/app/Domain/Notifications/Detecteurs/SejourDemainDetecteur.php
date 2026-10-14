<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Detecteurs;

use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Notifications\Contracts\DetecteurDeclencheurInterface;
use Illuminate\Support\Carbon;

/**
 * Déclencheur `sejour_demain` — maître : `notifications-engine.js` l.76-92.
 *
 * Toute réservation NON annulée dont l'arrivée tombe demain. `reference` =
 * l'identifiant de la réservation : une réservation modifiée (nouvelle date
 * d'arrivée) redevient une occurrence NEUVE, ce qui est le comportement
 * voulu — le message rappelait la mauvaise date.
 */
final class SejourDemainDetecteur implements DetecteurDeclencheurInterface
{
    /**
     * @return list<array{reference: string, destinataire: string, variables: array<string, string>}>
     */
    public function detecter(): array
    {
        $demain = Carbon::tomorrow();

        return Reservation::query()
            ->with('client')
            ->where('statut', '!=', 'annulee')
            ->whereDate('date_arrivee', $demain)
            ->get()
            ->map(static function (Reservation $reservation) {
                $client = $reservation->client;

                return [
                    'reference' => $reservation->id,
                    'destinataire' => $client?->nomComplet() ?? '—',
                    'email' => $client?->email,
                    'variables' => [
                        'client' => $client?->nomComplet() ?? '—',
                        'date_arrivee' => $reservation->date_arrivee->format('d/m/Y'),
                        'date_depart' => $reservation->date_depart->format('d/m/Y'),
                        'nuits' => (string) $reservation->nombreNuitees(),
                    ],
                ];
            })
            ->values()
            ->all();
    }
}
