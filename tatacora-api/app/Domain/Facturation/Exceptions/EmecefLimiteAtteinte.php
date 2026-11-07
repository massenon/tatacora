<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use App\Domain\Facturation\Services\StatutNormalisation;

/** 429 : la DGI limite les envois ; `Retry-After` est RESPECTÉ. */
final class EmecefLimiteAtteinte extends EmecefErreur
{
    public function __construct(private readonly int $secondes)
    {
        parent::__construct(__('facturation.emecef.limite', ['secondes' => $secondes]));
    }

    public function statut(): StatutNormalisation
    {
        return StatutNormalisation::EnAttente;
    }

    public function secondesAvantRejeu(): ?int
    {
        return $this->secondes;
    }
}
