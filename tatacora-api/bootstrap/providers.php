<?php

declare(strict_types=1);

use App\Domain\Facturation\Providers\MecefServiceProvider;
use App\Providers\AppServiceProvider;

return [
    AppServiceProvider::class,
    // Bascule Fake/Reel de la certification MECeF — MECEF_INTEGRATION_SPEC.md §7.3
    MecefServiceProvider::class,
];
