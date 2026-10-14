<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Exceptions;

use RuntimeException;

/**
 * Un plat commande n'a pas de fiche technique — RG-05 ne peut pas s'appliquer.
 *
 * Refuser est le seul comportement sur : laisser passer vendrait le plat sans
 * consommer de stock, et l'ecart n'apparaitrait qu'a l'inventaire suivant,
 * impute a tort a une perte physique.
 */
class RecetteManquanteException extends RuntimeException
{
    public function __construct(public readonly string $plat)
    {
        parent::__construct(__('restaurant.recette_manquante', ['plat' => $plat]));
    }
}
