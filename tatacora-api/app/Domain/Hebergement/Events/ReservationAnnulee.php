<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Events;

use Illuminate\Foundation\Events\Dispatchable;

/**
 * Émis à l'annulation d'une réservation — RG-02.
 *
 * Ne porte que des identifiants, jamais le modèle Eloquent : l'événement peut
 * être sérialisé en file d'attente, et un modèle sérialisé transporterait un
 * état périmé au moment où le Listener s'exécute.
 *
 * Listeners attendus dans les sprints ultérieurs : notification d'annulation
 * (M12), avoir sur acompte le cas échéant (M2). Aucun n'est câblé aujourd'hui —
 * ces domaines ne sont pas implémentés.
 */
class ReservationAnnulee
{
    use Dispatchable;

    public function __construct(
        public readonly string $reservationId,
        public readonly string $uniteId,
    ) {
    }
}
