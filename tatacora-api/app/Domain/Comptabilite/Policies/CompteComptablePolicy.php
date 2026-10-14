<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du plan comptable (M10) — 2e niveau, au niveau de l'entite.
 *
 * Un compte est reference par des ecritures en `restrictOnDelete()` : sa
 * disparition rendrait illisible tout le grand livre. `delete()` reste a
 * `false` par heritage.
 *
 * @see RG-16
 */
final class CompteComptablePolicy extends BasePolicy
{
    protected string $module = 'M10';
}
