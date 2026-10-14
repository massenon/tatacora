<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use DateTimeImmutable;

/**
 * Resultat d'une certification e-MECeF — contrat fixe des maintenant,
 * independamment du detail d'implementation DGI encore inconnu (PA-17).
 */
final class CertificationMecefResultat
{
    public function __construct(
        public readonly string $nim,
        public readonly string $cachetFiscal, // contenu du QR code
        public readonly DateTimeImmutable $dateCertification,
    ) {
    }
}
