<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Facturation\Models\Facture;
use DateTimeImmutable;
use Illuminate\Support\Str;

/**
 * Implementation de demonstration, active tant que PA-17 (inscription DGI)
 * n'est pas resolue — MECEF_INTEGRATION_SPEC.md §7.3.
 *
 * Les valeurs produites sont volontairement IMPOSSIBLES a confondre avec une
 * vraie certification, meme en lecture rapide : prefixe DEMO explicite et
 * cachet fiscal disant litteralement que les donnees ne sont pas certifiees.
 * Un format vraisemblable serait dangereux — une facture de demonstration
 * pourrait etre remise a un client comme si elle avait valeur fiscale.
 */
final class MecefClientFake implements MecefClientInterface
{
    public function certifier(Facture $facture): CertificationMecefResultat
    {
        return new CertificationMecefResultat(
            nim: 'MECEF-DEMO-' . strtoupper(Str::random(8)),
            cachetFiscal: 'DONNEES-NON-CERTIFIEES-DEMO',
            dateCertification: new DateTimeImmutable(),
        );
    }

    public function estModeReel(): bool
    {
        return false;
    }
}
