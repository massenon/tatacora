<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Facturation\Models\Avoir;

/**
 * Un client de certification qui sait aussi normaliser un AVOIR (type `FA`, avec la
 * référence de la facture d'origine). Interface à part : le contrat de base
 * ({@see MecefClientInterface}) n'a pas à changer pour les clients qui ne le savent pas.
 */
interface CertifieLesAvoirsInterface
{
    public function certifierAvoir(Avoir $avoir): CertificationMecefResultat;
}
