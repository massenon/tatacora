<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC des exercices comptables (M10) — 2e niveau.
 *
 * @see RG-16
 */
final class ExerciceComptablePolicy extends BasePolicy
{
    protected string $module = 'M10';
}
