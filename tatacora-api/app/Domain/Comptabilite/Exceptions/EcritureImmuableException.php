<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Exceptions;

use RuntimeException;

/**
 * Tentative de modification ou de suppression d'une écriture protégée — RG-11.
 *
 * Même intention que `FactureImmuableException` : le message oriente vers le
 * seul chemin de correction légitime — la contre-passation — plutôt que de se
 * contenter d'un refus. Un comptable qui doit corriger une écriture a un
 * besoin réel, et SYSCOHADA a une réponse pour lui.
 *
 * @see RG-11
 */
class EcritureImmuableException extends RuntimeException
{
    /**
     * @param  list<string>  $champs
     */
    public function __construct(
        public readonly string $ecritureId,
        public readonly array $champs = [],
        ?string $message = null,
    ) {
        parent::__construct($message ?? __('comptabilite.ecriture_immuable'));
    }
}
