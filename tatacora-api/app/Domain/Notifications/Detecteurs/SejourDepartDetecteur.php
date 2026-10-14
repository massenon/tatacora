<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Detecteurs;

use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Notifications\Contracts\DetecteurDeclencheurInterface;
use App\Domain\Notifications\Support\MontantNotification;
use Illuminate\Support\Carbon;

/**
 * Déclencheur `sejour_depart` — maître : `notifications-engine.js` l.94-109.
 *
 * Toute réservation NON annulée dont le départ tombe AUJOURD'HUI (le maître
 * lit `decalage(0)`, pas demain : c'est un remerciement au départ, pas un
 * rappel la veille).
 *
 * Une réservation sans `tarif_nuit` figé (antérieure à PA-163) rend
 * `resteAPayer()` à `null` — l'occurrence est alors OMISE plutôt que composée
 * avec un solde inventé (Article 7 : ne jamais afficher un « 0 » qui n'est
 * pas un calcul).
 */
final class SejourDepartDetecteur implements DetecteurDeclencheurInterface
{
    /**
     * @return list<array{reference: string, destinataire: string, variables: array<string, string>}>
     */
    public function detecter(): array
    {
        $aujourdhui = Carbon::today();

        $occurrences = [];

        foreach (
            Reservation::query()
                ->with('client')
                ->where('statut', '!=', 'annulee')
                ->whereDate('date_depart', $aujourdhui)
                ->get() as $reservation
        ) {
            $resteAPayer = $reservation->resteAPayer();

            if ($resteAPayer === null) {
                continue;
            }

            $client = $reservation->client;

            $occurrences[] = [
                'reference' => $reservation->id,
                'destinataire' => $client?->nomComplet() ?? '—',
                'email' => $client?->email,
                'variables' => [
                    'client' => $client?->nomComplet() ?? '—',
                    'date_depart' => $reservation->date_depart->format('d/m/Y'),
                    'reste_du' => MontantNotification::format($resteAPayer),
                ],
            ];
        }

        return $occurrences;
    }
}
