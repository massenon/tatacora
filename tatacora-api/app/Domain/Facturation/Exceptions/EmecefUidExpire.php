<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use RuntimeException;

/** Interne : la confirmation a répondu 404, le `uid` a expiré — on recrée la facture une fois. */
final class EmecefUidExpire extends RuntimeException
{
}
