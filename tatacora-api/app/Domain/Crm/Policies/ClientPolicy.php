<?php

declare(strict_types=1);

namespace App\Domain\Crm\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine CRM (M3) — 2e niveau, cf. 00_MASTER_INSTRUCTIONS.md §3.2.
 *
 * `delete()` reste refuse par defaut (BasePolicy) : une fiche client est
 * referencee par des factures et des reservations, sa suppression physique
 * casserait l'historique (ON DELETE RESTRICT, 03_DATABASE_ENGINEERING.md §15).
 */
final class ClientPolicy extends BasePolicy
{
    protected string $module = 'M3';
}
