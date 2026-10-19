<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\Sejour;
use App\Domain\Hebergement\Services\SejourService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Carbon\Carbon;
use Carbon\Exceptions\InvalidFormatException;
use RuntimeException;

/**
 * Séjours (M1) — l'ARRIVÉE et le DÉPART réels saisis sur un poste. Lot F5,
 * décision du Product Owner du 17/10/2026 (« les deux modules POS vente et
 * POS hébergés des autres postes, et en synchronisation »).
 *
 * ## Par `SejourService`, et lui seul
 *
 * Il tient, sous verrou, « une réservation ne s'enregistre qu'une fois » et
 * « une réservation annulée n'arrive pas », et fait suivre la réservation
 * (`en_cours`, `terminee`) et l'unité (`occupee`, `nettoyage`). Deux postes
 * qui pointent la même arrivée hors ligne : le second est refusé avec la
 * phrase du service (« déjà arrivé le … »).
 *
 * ## Création = arrivée, modification = départ
 *
 * Création : `reservation_id`, `date_checkin_reel` (l'heure RÉELLE du
 * poste, D246), `occupants`. Modification : `date_checkout_reel` seulement —
 * le service n'offre aucun autre geste sur un séjour.
 */
final class GestionnaireSejours extends GestionnaireAbstrait
{
    public function __construct(
        private readonly SejourService $sejours,
        private readonly ResolveurCorrespondances $correspondances,
    ) {
    }

    public function table(): string
    {
        return 'sejours';
    }

    public function module(): string
    {
        return 'M1';
    }

    public function serviceDomaine(): string
    {
        return SejourService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $reservationId = is_string($payload['reservation_id'] ?? null)
            ? $this->correspondances->resoudre('reservations', $payload['reservation_id'])
            : null;
        $reservation = $reservationId === null ? null : Reservation::find($reservationId);

        if ($reservation === null) {
            throw new RuntimeException(__('sync.sejours.reservation_inconnue'));
        }

        $occupants = is_array($payload['occupants'] ?? null) ? array_values($payload['occupants']) : [];

        $this->sejours->checkin($reservation, $occupants, $entiteId, $this->instant($payload['date_checkin_reel'] ?? null));

        return new EcritureSynchronisee($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $depart = $payload['date_checkout_reel'] ?? null;
        unset($payload['date_checkout_reel']);

        if ($depart === null || $payload !== []) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        $sejour = Sejour::query()->findOrFail($entiteId);

        // Rejeu d'un départ déjà enregistré : rien à refaire.
        if ($sejour->date_checkout_reel !== null) {
            return new EcritureSynchronisee($entiteId);
        }

        $this->sejours->checkout($sejour, $this->instant($depart));

        return new EcritureSynchronisee($entiteId);
    }

    /** L'instant saisi au poste (`AAAA-MM-JJ HH:MM:SS`, heure locale du Gîte). */
    private function instant(mixed $valeur): ?Carbon
    {
        if (! is_string($valeur) || trim($valeur) === '') {
            return null;
        }

        try {
            return Carbon::parse($valeur);
        } catch (InvalidFormatException) {
            throw new RuntimeException(__('sync.sejours.instant_illisible', ['valeur' => $valeur]));
        }
    }
}
