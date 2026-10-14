<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * 2e niveau RBAC sur les reservations touristiques — RG-16.
 *
 * Nom aligne sur le modele (`ReservationTour` -> `ReservationTourPolicy`) :
 * la decouverte automatique de Laravel repose sur cette convention, et un
 * ecart la rend silencieusement inoperante.
 */
final class ReservationTourPolicy extends BasePolicy
{
    protected string $module = 'M9';
}
