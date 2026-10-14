<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine Restaurant (M4) — 2e niveau.
 *
 * Un menu est reference par ses plats. `BasePolicy::delete()` refuse deja
 * toute suppression ; rien ne la rouvre ici.
 *
 * @see RG-16
 */
final class MenuPolicy extends BasePolicy
{
    protected string $module = 'M4';
}
