<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

use App\Domain\Comptabilite\Models\Immobilisation;

/**
 * Une ligne du tableau des immobilisations d'un exercice — maître :
 * `m10-syscohada-etats.js` `tableauImmobilisations()`.
 */
final readonly class LigneTableauImmobilisations
{
    public function __construct(
        public Immobilisation $immobilisation,
        public string $brut,
        public string $dotation,
        public string $cumul,
        public string $vnc,
    ) {
    }
}
