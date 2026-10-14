<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\PosteBilan;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un poste du Bilan — trois montants cote actif (« Brut », « Amort./Depr. »,
 * « Net »), un seul lu cote passif.
 *
 * @property-read PosteBilan $resource
 */
class PosteBilanResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'section' => $this->resource->section,
            'code' => $this->resource->code,
            'libelle' => $this->resource->libelle,
            'brut' => $this->resource->brut,
            'amortissement' => $this->resource->amortissement,
            'net' => $this->resource->net,
            'prefixes' => $this->resource->prefixes,
        ];
    }
}
