<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine Restaurant (M4) — 2e niveau.
 *
 * Supprimer une recette casserait `plats.recette_id`, NOT NULL : un plat sans
 * fiche technique ne peut pas exister au schema.
 *
 * @see RG-16
 */
final class RecettePolicy extends BasePolicy
{
    protected string $module = 'M4';
}
