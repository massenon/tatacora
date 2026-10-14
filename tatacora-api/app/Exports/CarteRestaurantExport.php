<?php

declare(strict_types=1);

namespace App\Exports;

/**
 * Export tableur de la carte du restaurant (M4).
 *
 * Tout le comportement vit dans `CarteExport` : le maître n'a qu'un état pour
 * les deux rayons (`carte-module.js` l.393-406), et le nom de la feuille est
 * la seule chose qui les distingue.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see PA-119 Un export porte sur ce qui est affiché, et il DIT son filtre
 */
final class CarteRestaurantExport extends CarteExport
{
    public function title(): string
    {
        return __('carte_pwa.restaurant.titre');
    }
}
