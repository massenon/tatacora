<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine Hebergement (M1) — 2e niveau.
 *
 * `delete()` reste refuse (BasePolicy) : une reservation ne se supprime pas,
 * elle s'annule (RG-02). La distinction n'est pas cosmetique — une suppression
 * effacerait la trace d'une annulation, dont l'historique est necessaire aux
 * litiges sur acompte.
 */
final class ReservationPolicy extends BasePolicy
{
    protected string $module = 'M1';
}
