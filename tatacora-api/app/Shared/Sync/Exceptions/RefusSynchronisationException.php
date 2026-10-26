<?php

declare(strict_types=1);

namespace App\Shared\Sync\Exceptions;

use RuntimeException;

/**
 * Le droit manque pour corriger, relancer ou ignorer une opération reçue :
 * rôle non autorisé (`module` vide) ou niveau d'écriture manquant sur
 * `module`. L'écran la traduit en 403.
 */
final class RefusSynchronisationException extends RuntimeException
{
    public function __construct(string $message, public readonly string $module = '')
    {
        parent::__construct($message);
    }
}
