<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine Restaurant (M4) — 2e niveau.
 *
 * Un plat est reference par des lignes de commande : sa disparition rendrait
 * illisible l'historique des ventes, et la cle etrangere est en
 * `restrictOnDelete()`.
 *
 * @see RG-16
 */
final class PlatPolicy extends BasePolicy
{
    protected string $module = 'M4';
}
