<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use App\Domain\Facturation\Services\StatutNormalisation;

/**
 * La facture n'est pas transmissible TELLE QUELLE (totaux incohérents, avoir sans
 * origine normalisée) : refusée AVANT tout envoi, par nous — la DGI n'a rien vu. La
 * pièce reste « en attente » (corrigible), avec la phrase qui dit quoi corriger.
 */
final class EmecefDonneesInvalides extends EmecefErreur
{
    public function statut(): StatutNormalisation
    {
        return StatutNormalisation::EnAttente;
    }

    public function secondesAvantRejeu(): ?int
    {
        return 900;
    }
}
