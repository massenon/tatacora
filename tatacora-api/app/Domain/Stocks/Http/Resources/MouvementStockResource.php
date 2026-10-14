<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Resources;

use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Services\StockTheoriqueService;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une ligne de `mouvements_stock` — EF-M6-02, EF-M6-06.
 *
 * ## Le SENS est dérivé du type, jamais stocké
 *
 * `quantite` est toujours positive au schéma ; c'est `type_mouvement` qui dit
 * si elle ajoute ou retranche, selon la convention de `StockTheoriqueService`.
 * La constante `TYPES_ENTRANTS` est relue ici plutôt que recopiée : une
 * convention de signe écrite à deux endroits finit par diverger, et le stock
 * afficherait alors l'inverse de ce qu'il vaut.
 *
 * ## Traçabilité : qui, quoi, quand, pourquoi (EF-M6-06)
 *
 * `utilisateur` et `motif` sortent systématiquement. Un mouvement sans auteur
 * lisible rend l'historique de stock inopposable lors d'un inventaire, ce qui
 * est précisément ce que cette table existe pour permettre.
 *
 * @property-read MouvementStock $resource
 */
class MouvementStockResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $entrant = in_array(
            $this->resource->type_mouvement,
            StockTheoriqueService::TYPES_ENTRANTS,
            true,
        );

        return [
            'id' => $this->resource->id,
            'article_id' => $this->resource->article_id,
            'point_id' => $this->resource->point_id,
            'type_mouvement' => $this->resource->type_mouvement,
            // Chaîne, jamais float : un cumul de mouvements réarrondis côté
            // client dérive, et l'écart serait imputé à tort à une perte
            // physique lors de l'inventaire suivant.
            'quantite' => (string) $this->resource->quantite,
            'sens' => $entrant ? 'entree' : 'sortie',
            'motif' => $this->resource->motif,
            'utilisateur_id' => $this->resource->utilisateur_id,
            'date_mouvement' => $this->resource->date_mouvement->toIso8601String(),

            'article' => $this->whenLoaded('article', fn (): array => [
                'id' => $this->resource->article->id,
                'libelle' => $this->resource->article->libelle,
                'unite_mesure' => $this->resource->article->unite_mesure,
            ]),
            'point' => $this->whenLoaded('point', fn (): array => [
                'id' => $this->resource->point->id,
                'libelle' => $this->resource->point->libelle,
            ]),
            'utilisateur' => $this->whenLoaded('utilisateur', fn (): ?array => $this->resource->utilisateur === null
                ? null
                : [
                    'id' => $this->resource->utilisateur->id,
                    'login' => $this->resource->utilisateur->login,
                ]),
        ];
    }
}
