<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Resources;

use App\Domain\Stocks\Models\PointStockage;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un point de stockage — magasin général, cuisine, bar, garage.
 *
 * `type` descend TEL QUEL, `null` compris. C'est lui que `BoissonResource`
 * interroge pour trouver le point « bar » ; le remplacer par une valeur par
 * défaut ferait imputer une sortie au mauvais endroit, et l'erreur ne se
 * verrait qu'à l'inventaire.
 *
 * @property-read PointStockage $resource
 */
class PointStockageResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->id,
            'libelle' => $this->resource->libelle,
            'type' => $this->resource->type,
        ];
    }
}
