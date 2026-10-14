<?php

declare(strict_types=1);

namespace App\Pwa\Support;

/**
 * Libellés traduits des motifs d'indisponibilité ou d'erreur de stock restaurant.
 */
final class MotifStockRestaurant
{
    public static function libelle(?string $motif): string
    {
        return match ($motif) {
            'recette_sans_ingredient' => __('pwa.carte_restaurant.motif_recette_sans_ingredient'),
            'point_cuisine_absent' => __('pwa.carte_restaurant.motif_point_cuisine_absent'),
            default => __('pwa.carte_restaurant.motif_inconnu'),
        };
    }
}
