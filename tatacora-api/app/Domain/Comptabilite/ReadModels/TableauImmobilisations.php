<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Le tableau des immobilisations d'un exercice, avec ses quatre totaux —
 * maître : `m10-syscohada-etats.js` `tableauImmobilisations()`, onglet
 * « Immobilisations » du hub.
 */
final readonly class TableauImmobilisations
{
    /**
     * @param  list<LigneTableauImmobilisations>  $lignes
     */
    public function __construct(
        public int $annee,
        public array $lignes,
        public string $totalBrut,
        public string $totalDotation,
        public string $totalCumul,
        public string $totalVnc,
    ) {
    }
}
