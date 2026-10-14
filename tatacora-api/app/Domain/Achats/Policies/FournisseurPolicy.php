<?php

declare(strict_types=1);

namespace App\Domain\Achats\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine Achats (M7) — 2e niveau.
 */
final class FournisseurPolicy extends BasePolicy
{
    protected string $module = 'M7';
}
