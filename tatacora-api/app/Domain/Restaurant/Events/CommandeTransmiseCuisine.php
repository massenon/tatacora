<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Events;

use Illuminate\Foundation\Events\Dispatchable;

/**
 * Commande transmise en cuisine, stock deja decremente — RG-05.
 *
 * Emis APRES succes de la deduction : les consommateurs de cet evenement
 * (bon de cuisine EF-M4-05, notifications M12) n'ont aucun droit de veto sur
 * la vente. Le veto de RG-06 appartient a la transaction, pas a un listener.
 *
 * Aucun listener n'est cable a ce stade : M12 n'est pas implemente.
 */
class CommandeTransmiseCuisine
{
    use Dispatchable;

    /**
     * @param  list<array{article_id: string, quantite: string, plat: string}>  $sorties
     */
    public function __construct(
        public readonly string $commandeId,
        public readonly array $sorties = [],
    ) {
    }
}
