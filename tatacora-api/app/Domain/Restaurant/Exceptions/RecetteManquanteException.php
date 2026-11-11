<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Exceptions;

use RuntimeException;

/**
 * Un plat commande n'a pas de fiche technique — RG-05 ne peut pas s'appliquer.
 *
 * ⚠ N'EST PLUS LEVÉE depuis le 30/10/2026 (décision du PO : « le stock
 * s'ajoute après »). Elle disait : « refuser est le seul comportement sûr :
 * laisser passer vendrait le plat sans consommer de stock, et l'écart
 * n'apparaîtrait qu'à l'inventaire suivant, imputé à une perte physique ».
 * On s'en écarte : un plat sans fiche (ou à fiche sans ligne) se vend, sans
 * mouvement de stock, et la vente le dit (`stock_non_impacte`). La classe est
 * CONSERVÉE pour une seule raison : la cause `recette_manquante` figure dans
 * le registre des causes d'envoi (journal de synchronisation), que les
 * anciennes entrées du journal des postes continuent de citer.
 *
 * @deprecated aucune vente ne la lève plus
 */
class RecetteManquanteException extends RuntimeException
{
    public function __construct(public readonly string $plat)
    {
        parent::__construct(__('restaurant.recette_manquante', ['plat' => $plat]));
    }
}
