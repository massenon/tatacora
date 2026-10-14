<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine Facturation (M2) — 2e niveau.
 *
 * Première policy du domaine, née avec le premier writer de `paiements`
 * (PA-165) : `BasePolicy::delete()` rend `false` — un encaissement ne se
 * supprime jamais, la correction comptable passe par contre-passation.
 * Découverte par la convention `Models\Paiement` → `Policies\PaiementPolicy`,
 * la même que les 11 policies existantes (vérifiée par `Gate::getPolicyFor`
 * dans les tests RBAC).
 */
final class PaiementPolicy extends BasePolicy
{
    protected string $module = 'M2';
}
