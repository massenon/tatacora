<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Une annuité du plan d'amortissement linéaire d'une immobilisation —
 * `ImmobilisationService::planAmortissement()`.
 */
final readonly class LigneAmortissement
{
    public function __construct(
        public int $annee,
        public string $base,
        public string $dotation,
        public string $cumul,
        public string $vnc,
        public ?string $prorata = null,
    ) {
    }
}
