<?php

declare(strict_types=1);

namespace App\Shared\Integrite\Exceptions;

use RuntimeException;

/**
 * Levée quand une plage de dates chevauche une plage existante sur la même
 * ressource — RG-01 (hébergement), RG-08 (véhicules), RG-13 (plannings RH).
 *
 * Porte un message destiné à l'utilisateur final : le client Flutter qui
 * synchronise une réservation créée hors connexion doit pouvoir l'afficher
 * tel quel. Une erreur technique brute sur un conflit de synchronisation
 * différée est incompréhensible pour un réceptionniste (07_TESTING_QA.md §3).
 */
class ChevauchementDetecteException extends RuntimeException
{
    /**
     * @param  list<string>  $identifiantsEnConflit
     */
    public function __construct(
        string $message,
        public readonly string $ressourceId,
        public readonly array $identifiantsEnConflit = [],
    ) {
        parent::__construct($message);
    }
}
