<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

use App\Domain\Comptabilite\Models\Immobilisation;

/**
 * Le plan d'amortissement complet d'une immobilisation, annuité par annuité —
 * maître : `m10-syscohada-etats.js` `planAmortissement()`.
 *
 * `total` doit égaler `immobilisation.valeur_origine` : la dernière annuité
 * absorbe l'arrondi pour que ce soit toujours vrai (voir
 * `ImmobilisationService::planAmortissement()`).
 */
final readonly class PlanAmortissement
{
    /**
     * @param  list<LigneAmortissement>  $lignes
     */
    public function __construct(
        public Immobilisation $immobilisation,
        public array $lignes,
        public string $total,
    ) {
    }
}
