<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Facturation\Exceptions\EmecefConfigurationIncomplete;
use App\Domain\Facturation\Models\Facture;

/**
 * Le client lié quand le mode e-MECeF est choisi mais que la configuration est
 * INCOMPLÈTE (IFU, adresse https, opérateur ou jeton manquants) : il refuse, en
 * français, SANS aucune requête. Jamais un repli silencieux sur la démonstration.
 */
final class MecefClientRefus implements MecefClientInterface
{
    /** @param list<string> $manques */
    public function __construct(private readonly array $manques)
    {
    }

    public function certifier(Facture $facture): CertificationMecefResultat
    {
        throw new EmecefConfigurationIncomplete($this->manques);
    }

    public function estModeReel(): bool
    {
        return false;
    }
}
