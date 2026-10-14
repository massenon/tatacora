<?php

declare(strict_types=1);

namespace App\Domain\Bar\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine Bar (M5) — 2e niveau.
 */
final class CarteBoissonPolicy extends BasePolicy
{
    protected string $module = 'M5';
}
