<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Exceptions;

use RuntimeException;

/**
 * Sortie de stock refusée faute de disponible — RG-06.
 *
 * Porte le drapeau `necessite_validation_rupture`, que le contrôleur traduit en
 * 422 et que le client Flutter affiche comme une **demande de confirmation
 * explicite**, pas comme une erreur définitive. La distinction est le cœur de
 * RG-06 : la rupture est autorisée si elle est assumée par un utilisateur
 * habilité, jamais subie en silence.
 */
class RuptureStockException extends RuntimeException
{
    public function __construct(
        public readonly string $articleId,
        public readonly string $pointId,
        public readonly string $stockDisponible,
        public readonly string $quantiteDemandee,
    ) {
        parent::__construct(__('stocks.rupture', [
            'disponible' => $stockDisponible,
            'demande' => $quantiteDemandee,
        ]));
    }

    /**
     * @return array<string, mixed>
     */
    public function versReponse(): array
    {
        return [
            'message' => $this->getMessage(),
            'necessite_validation_rupture' => true,
            'stock_disponible' => $this->stockDisponible,
            'quantite_demandee' => $this->quantiteDemandee,
        ];
    }
}
