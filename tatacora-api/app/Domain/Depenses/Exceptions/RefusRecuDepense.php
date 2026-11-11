<?php

declare(strict_types=1);

namespace App\Domain\Depenses\Exceptions;

use RuntimeException;

/**
 * Le dépôt du reçu d'une dépense est REFUSÉ (lot L4, 27/10/2026).
 *
 * Un refus métier, jamais une panne : le message est rendu au poste tel quel,
 * en français, et `codeMotif` (registre fermé, voir `synchronisation_journal`)
 * dit POURQUOI au journal de réception. `statutHttp` est celui que le contrôleur
 * rend : 404 (dépense pas encore connue : le poste réessaiera), 409 (un autre
 * reçu est déjà rattaché), 413 (trop lourd), 422 (contenu invalide).
 */
final class RefusRecuDepense extends RuntimeException
{
    public function __construct(
        public readonly string $codeMotif,
        string $message,
        public readonly int $statutHttp = 422,
    ) {
        parent::__construct($message);
    }
}
