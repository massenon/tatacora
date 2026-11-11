<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use App\Domain\Facturation\Services\StatutNormalisation;
use RuntimeException;

/**
 * Une erreur de l'API e-MECeF de la DGI, CLASSÉE — jamais un message brut.
 *
 * Chaque sous-classe porte sa phrase française (aucune ne cite le jeton, l'en-tête
 * `Authorization` ni l'adresse appelée), le statut de normalisation que la facture
 * garde (`en_attente` : rejouable ; `refusee` : la DGI a dit non), et — pour une limite
 * de débit ou un réseau tombé — le délai avant le prochain essai.
 */
abstract class EmecefErreur extends RuntimeException
{
    abstract public function statut(): StatutNormalisation;

    /** Secondes à attendre avant de rejouer ; `null` : sans délai particulier. */
    public function secondesAvantRejeu(): ?int
    {
        return null;
    }
}
