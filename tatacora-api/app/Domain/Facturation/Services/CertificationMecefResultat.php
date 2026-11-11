<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use DateTimeImmutable;

/**
 * Resultat d'une certification MECeF — contrat fixe, independamment de la voie.
 *
 * `$nim` est l'IDENTITE FISCALE rangee dans `numero_mecef` : pour la demonstration
 * `MECEF-DEMO-XXXXXXXX`, pour e-MECeF « NIM-TC » (le NIM du serveur de la DGI et le
 * compteur de la facture). `$cachetFiscal` est le contenu du QR code. Les champs
 * facultatifs (code MECeF, compteur) ne sont donnes que par une vraie normalisation.
 */
final class CertificationMecefResultat
{
    public function __construct(
        public readonly string $nim,
        public readonly string $cachetFiscal, // contenu du QR code
        public readonly DateTimeImmutable $dateCertification,
        public readonly ?string $codeMecef = null,
        public readonly ?string $compteur = null,
    ) {
    }
}
