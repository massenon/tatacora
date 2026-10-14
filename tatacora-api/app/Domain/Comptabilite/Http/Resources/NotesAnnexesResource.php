<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\NotesAnnexes;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Notes Annexes » — EF-M10-06.
 *
 * Les SEPT notes descendent toujours, y compris celles qu'on ne sait pas
 * remplir : « sans les Notes Annexes, les etats financiers sont incomplets au
 * sens SYSCOHADA » (`MODULE_COMPTABILITE_COMPLET_PART4.md` §1). Une note omise
 * se lirait comme une note sans objet, alors qu'elle est obligatoire.
 *
 * @property-read NotesAnnexes $resource
 */
class NotesAnnexesResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'notes' => NoteResource::collection($this->resource->notes)->resolve($request),
        ];
    }
}
