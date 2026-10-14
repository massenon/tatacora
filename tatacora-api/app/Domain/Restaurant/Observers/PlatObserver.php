<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Observers;

use App\Domain\Carte\Models\HistoriquePrixCarte;
use App\Domain\Carte\TraceurHistoriquePrix;
use App\Domain\Restaurant\Models\Plat;

/**
 * Trace les changements de prix d'un plat — demande du Product Owner du
 * 01/09/2026 : « on doit retracer les changements de prix » (M4).
 *
 * Jumeau exact de `CarteBoissonObserver` côté M5 — voir son docblock pour le
 * raisonnement complet (pourquoi un Observer, pourquoi la comparaison vit
 * dans `TraceurHistoriquePrix` et pas ici).
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see \App\Domain\Bar\Observers\CarteBoissonObserver le jumeau côté M5
 * @see \App\Domain\Carte\Models\HistoriquePrixCarte
 */
class PlatObserver
{
    public function updated(Plat $plat): void
    {
        TraceurHistoriquePrix::tracer(HistoriquePrixCarte::SOURCE_PLAT, $plat);
    }
}
