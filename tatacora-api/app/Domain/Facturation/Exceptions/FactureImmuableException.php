<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use RuntimeException;

/**
 * Tentative de modification ou de suppression d'une facture protégée — RG-03.
 *
 * Le message oriente vers le seul chemin de correction légitime plutôt que de
 * se contenter d'un refus : un utilisateur qui doit corriger une facture a un
 * besoin réel, et l'avoir est la réponse.
 */
class FactureImmuableException extends RuntimeException
{
    /**
     * @param  list<string>  $champs
     */
    public function __construct(
        public readonly string $factureId,
        public readonly array $champs = [],
    ) {
        parent::__construct(__('facturation.immuable_sans_numero'));
    }
}
