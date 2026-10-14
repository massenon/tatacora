<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * 2e niveau RBAC sur le catalogue de circuits — RG-16.
 */
final class CircuitPolicy extends BasePolicy
{
    protected string $module = 'M9';
}
