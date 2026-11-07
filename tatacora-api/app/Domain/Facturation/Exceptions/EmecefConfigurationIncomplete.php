<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use App\Domain\Facturation\Services\StatutNormalisation;

/** Mode e-MECeF choisi sans IFU, adresse, opérateur ou jeton : refus CLAIR, aucune requête. */
final class EmecefConfigurationIncomplete extends EmecefErreur
{
    /** @param list<string> $manques */
    public function __construct(array $manques)
    {
        parent::__construct(__('facturation.emecef.configuration_incomplete', ['manques' => implode(' ', $manques)]));
    }

    public function statut(): StatutNormalisation
    {
        return StatutNormalisation::EnAttente;
    }

    public function secondesAvantRejeu(): ?int
    {
        return 900;
    }
}
