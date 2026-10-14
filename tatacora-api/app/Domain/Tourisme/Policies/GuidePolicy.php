<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * 2e niveau RBAC sur le referentiel guides — RG-16, EF-M9-02.
 */
final class GuidePolicy extends BasePolicy
{
    protected string $module = 'M9';
}
