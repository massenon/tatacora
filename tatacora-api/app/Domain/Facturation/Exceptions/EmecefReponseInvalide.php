<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use App\Domain\Facturation\Services\StatutNormalisation;

/**
 * La DGI a répondu 2xx mais sans les éléments attendus (uid, code MECeF, QR) : la facture
 * n'est PAS normalisée. Après une confirmation envoyée, l'issue est incertaine : « à vérifier ».
 */
final class EmecefReponseInvalide extends EmecefErreur
{
    public function __construct(private readonly bool $apresConfirmation)
    {
        parent::__construct(__($apresConfirmation ? 'facturation.emecef.reponse_invalide_apres_confirmation' : 'facturation.emecef.reponse_invalide'));
    }

    public function statut(): StatutNormalisation
    {
        return $this->apresConfirmation ? StatutNormalisation::AVerifier : StatutNormalisation::EnAttente;
    }
}
