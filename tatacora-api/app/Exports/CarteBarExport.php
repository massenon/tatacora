<?php

declare(strict_types=1);

namespace App\Exports;

/**
 * Export tableur de la carte du bar (M5).
 *
 * Tout le comportement vit dans `CarteExport` : le maître n'a qu'un état pour
 * les deux rayons (`carte-module.js` l.393-406), et le nom de la feuille est
 * la seule chose qui les distingue. Deux implémentations jumelles auraient
 * divergé au premier ajustement — c'est ce que le maître écrit lui-même l.7.
 *
 * @see EF-M5-02 Carte des boissons
 * @see PA-119 Un export porte sur ce qui est affiché, et il DIT son filtre
 */
final class CarteBarExport extends CarteExport
{
    public function title(): string
    {
        return __('carte_pwa.bar.titre');
    }
}
