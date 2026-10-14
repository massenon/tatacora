<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\EtapeCloture;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une etape de la checklist de cloture.
 *
 * `etat` distingue quatre situations, et la distinction est le livrable :
 * `conforme`, `bloque`, `non_verifiable` (la donnee vit hors de M10) et
 * `non_atteint` (l'etape depend d'une precedente). Reduire les deux dernieres a
 * « bloque » accuserait les ecritures d'un manque qui n'est pas le leur ; les
 * reduire a « conforme » serait l'indicateur qui rassure sans avoir verifie
 * (PA-59/60/61).
 *
 * @property-read EtapeCloture $resource
 */
class EtapeClotureResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'groupe' => $this->resource->groupe,
            'groupe_libelle' => $this->resource->groupeLibelle,
            'libelle' => $this->resource->libelle,
            'etat' => $this->resource->etat,
            'motif' => $this->resource->motif,
            'valeur' => $this->resource->valeur,
        ];
    }
}
