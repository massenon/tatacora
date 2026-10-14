<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Resources;

use App\Domain\Restaurant\Models\Menu;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un menu — EF-M4-01 (mise à jour saisonnière), EF-M4-06 (menus spéciaux).
 *
 * `type` descend TEL QUEL (`local`, `europeen`, `special`), jamais traduit :
 * la traduction en libellés affichables (« Local », « Européen », « Spécial »)
 * appartient au client, comme pour l'évaluation d'un fournisseur en M7. Une
 * API qui traduit oblige tout consommateur à retraduire en sens inverse pour
 * filtrer.
 *
 * `date_debut` et `date_fin` sont `null` sur un menu permanent, et le rester :
 * y substituer des bornes arbitraires ferait expirer une carte que personne
 * n'a datée.
 *
 * @property-read Menu $resource
 */
class MenuResource extends JsonResource
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
            'date_debut' => $this->resource->date_debut?->toDateString(),
            'date_fin' => $this->resource->date_fin?->toDateString(),
        ];
    }
}
