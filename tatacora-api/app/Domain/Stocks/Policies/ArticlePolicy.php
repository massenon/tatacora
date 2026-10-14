<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Policies;

use App\Shared\Rbac\Policies\BasePolicy;

/**
 * RBAC du domaine Stocks (M6) — 2e niveau.
 *
 * M6 est transverse : le barman et le cuisinier y ont 'C' pour que leurs
 * ventes puissent decrementer le stock (RG-05), le receptionniste 'L'.
 */
final class ArticlePolicy extends BasePolicy
{
    protected string $module = 'M6';
}
