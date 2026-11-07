<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Exceptions;

use App\Domain\Facturation\Services\StatutNormalisation;

/** 401 ou 403 : la DGI refuse le jeton (absent, périmé, ou d'un autre IFU). */
final class EmecefJetonRefuse extends EmecefErreur
{
    public function __construct()
    {
        parent::__construct(__('facturation.emecef.jeton_refuse'));
    }

    public function statut(): StatutNormalisation
    {
        return StatutNormalisation::EnAttente;
    }

    public function secondesAvantRejeu(): ?int
    {
        // Rejouer sans changer le jeton ne sert à rien : on laisse le temps de le remplacer.
        return 900;
    }
}
