<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Tourisme\Http\Requests\ReserverCircuitRequest;
use App\Domain\Tourisme\Models\ReservationTour;
use App\Domain\Tourisme\Services\ReservationTourService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Réservations de circuits (M9) prises sur un poste — lot F4 (17/10/2026).
 *
 * ## Par `ReservationTourService`, et lui seul
 *
 * C'est lui qui porte, sous verrou, la CAPACITÉ cumulée du départ et
 * l'EXCLUSIVITÉ du guide (un guide, un départ, un jour). Deux postes qui
 * vendent hors ligne les dernières places du même départ : le second est
 * refusé ici, avec la phrase du service, et le poste le montre dans
 * « À traiter ».
 *
 * ## Modification : trois gestes, chacun par son service
 *
 * - `statut: annulee` → `annuler()` (libère la place) ;
 * - `statut: terminee` → `cloturer()` ;
 * - `guide_id` → `affecterGuide()` (réaffectation du DÉPART entier, comme
 *   l'écran en ligne).
 * Tout autre champ est refusé : l'API n'offre pas de modification générique.
 */
final class GestionnaireReservationsTour extends GestionnaireAbstrait
{
    public function __construct(
        private readonly ReservationTourService $reservations,
        private readonly ResolveurCorrespondances $correspondances,
    ) {
    }

    public function table(): string
    {
        return 'reservations_tour';
    }

    public function module(): string
    {
        return 'M9';
    }

    public function serviceDomaine(): string
    {
        return ReservationTourService::class;
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
        foreach (['circuit_id' => 'circuits', 'client_id' => 'clients', 'guide_id' => 'guides'] as $champ => $table) {
            if (isset($payload[$champ]) && is_string($payload[$champ])) {
                $payload[$champ] = $this->correspondances->resoudre($table, $payload[$champ]);
            }
        }

        unset($payload['id'], $payload['statut']);
        $donnees = $this->valider($payload, $this->reglesDeLApi(ReserverCircuitRequest::class), ReserverCircuitRequest::class);

        $this->reservations->reserver([...$donnees, 'id' => $entiteId]);

        return new EcritureSynchronisee($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $reservation = ReservationTour::query()->findOrFail($entiteId);
        $statut = $payload['statut'] ?? null;
        $guide = isset($payload['guide_id']) && is_string($payload['guide_id'])
            ? $this->correspondances->resoudre('guides', $payload['guide_id'])
            : null;

        unset($payload['statut'], $payload['guide_id']);

        if ($payload !== [] || ($statut === null && $guide === null)) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        if ($guide !== null) {
            $reservation = $this->reservations->affecterGuide($reservation, $guide);
        }

        match ($statut) {
            null => null,
            'annulee' => $reservation->estAnnulee() ? null : $this->reservations->annuler($reservation),
            'terminee' => $reservation->estTerminee() ? null : $this->reservations->cloturer($reservation),
            default => throw new RuntimeException(__('sync.modification_non_synchronisable')),
        };

        return new EcritureSynchronisee($entiteId);
    }
}
