<?php

declare(strict_types=1);

namespace App\Domain\Bar\Observers;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\HistoriquePrixCarte;
use App\Domain\Carte\TraceurHistoriquePrix;

/**
 * Trace les changements de prix d'une boisson — demande du Product Owner du
 * 01/09/2026 : « on doit retracer les changements de prix » (M5).
 *
 * ## Pourquoi un Observer, et pas `CarteBoissonService::modifier()`
 *
 * `CarteBoissonService` n'est pas le seul chemin d'écriture sur `CarteBoisson`
 * — un seeder ou un futur import passent aussi par `update()`/`save()`
 * Eloquent. Un appel explicite dans le Service serait oublié par ces autres
 * chemins, exactement le défaut que `EcritureComptableObserver` documente
 * pour RG-11 : la garde doit couvrir l'ÉVÉNEMENT, pas un point d'entrée.
 *
 * ## Ce qui se passe RÉELLEMENT ici
 *
 * Toute la comparaison vit dans `TraceurHistoriquePrix`, partagée avec
 * `PlatObserver` — le bar et le restaurant sont le même écran de carte chez
 * le maître (`carte-module.js`), et cette classe applique la même règle que
 * `MarquesDePrix` : ne jamais recopier une logique entre les deux rayons.
 *
 * @see EF-M5-02 Carte des boissons
 * @see \App\Domain\Restaurant\Observers\PlatObserver le jumeau côté M4
 * @see \App\Domain\Carte\Models\HistoriquePrixCarte
 */
class CarteBoissonObserver
{
    public function updated(CarteBoisson $boisson): void
    {
        TraceurHistoriquePrix::tracer(HistoriquePrixCarte::SOURCE_BOISSON, $boisson);
    }
}
