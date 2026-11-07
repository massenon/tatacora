<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use App\Domain\Facturation\Services\StatutNormalisation;

/** Réseau coupé, délai dépassé, ou erreur 5xx de la DGI : rien n'est enregistré, on rejoue. */
final class EmecefIndisponible extends EmecefErreur
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }

    public static function reseau(): self
    {
        return new self(__('facturation.emecef.injoignable'));
    }

    public static function serveur(int $code): self
    {
        return new self(__('facturation.emecef.erreur_serveur', ['code' => $code]));
    }

    public function statut(): StatutNormalisation
    {
        return StatutNormalisation::EnAttente;
    }

    public function secondesAvantRejeu(): ?int
    {
        return 120;
    }
}
