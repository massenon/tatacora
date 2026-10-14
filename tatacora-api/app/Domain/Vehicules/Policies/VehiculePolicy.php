<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * 2e niveau RBAC sur le referentiel vehicules — RG-16.
 */
final class VehiculePolicy extends BasePolicy
{
    protected string $module = 'M8';
}
