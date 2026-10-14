<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Events;

use Illuminate\Foundation\Events\Dispatchable;

/**
 * Le stock théorique d'un article en un point est passé sous son seuil
 * d'alerte — RG-07.
 *
 * Émis uniquement lors du **franchissement** du seuil, jamais à chaque
 * vérification tant que le stock reste bas (ALERTES_CRITIQUES_DE_STOCK.md).
 * Sans cette précaution, un article durablement en rupture génèrerait une
 * notification toutes les 15 minutes, et les destinataires apprendraient à
 * ignorer l'alerte — la rendant inutile exactement quand elle compte.
 *
 * Destinataires prévus : Magasinier et Gérant (M12). Aucun Listener n'est
 * câblé : le module Notifications n'est pas implémenté.
 */
class SeuilStockAtteint
{
    use Dispatchable;

    public function __construct(
        public readonly string $articleId,
        public readonly string $pointId,
        public readonly string $stockActuel,
        public readonly string $seuilAlerte,
    ) {
    }
}
