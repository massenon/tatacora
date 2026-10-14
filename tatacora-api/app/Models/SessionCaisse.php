<?php

declare(strict_types=1);

namespace App\Models;

use App\Domain\Caisse\Models\SessionCaisse as DomainSessionCaisse;

/**
 * Alias de compatibilité pour le modèle SessionCaisse du domaine Caisse.
 */
class SessionCaisse extends DomainSessionCaisse
{
}
