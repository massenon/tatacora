<?php

declare(strict_types=1);

namespace App\Domain\Rh\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine RH (M13) — 2e niveau.
 *
 * Domaine particulierement sensible : la matrice n'accorde 'C' qu'aux roles
 * rh, gerant et administrateur ; le comptable est en lecture seule (paie).
 */
final class EmployePolicy extends BasePolicy
{
    protected string $module = 'M13';
}
