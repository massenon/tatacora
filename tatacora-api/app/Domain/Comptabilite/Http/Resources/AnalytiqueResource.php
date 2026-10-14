<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\Analytique;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Comptabilite Analytique » — EF-M10-03.
 *
 * ## `repartition_structure_effectuee` est a `false`, et il faut le lire
 *
 * Aucune cle de repartition des charges de structure n'existe dans ce depot.
 * Les montants rendus sont donc des MARGES SUR COUTS DIRECTS, jamais des
 * resultats nets par filiere — le maitre l'ecrit sous son tableau
 * (`m10-syscohada-etats.js` l.191-195), et `motif_nature_des_marges` porte le
 * code correspondant.
 *
 * ## Pas de compteur de lignes non ventilees, et c'est deliberé
 *
 * `ecritures_comptables.centre_id` est NOT NULL (RG-12 tenue par la base) : un
 * tel compteur serait bloque a zero par construction et rassurerait sans jamais
 * rien mesurer (PA-59/60/61). `ventilation_garantie_par_schema` nomme la raison
 * a sa place.
 *
 * @property-read Analytique $resource
 */
class AnalytiqueResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'totaux' => [
                'produits' => $this->resource->totalProduits,
                'charges' => $this->resource->totalCharges,
                'resultat' => $this->resource->totalResultat,
            ],
            'repartition_structure_effectuee' => $this->resource->repartitionStructureEffectuee,
            'motif_nature_des_marges' => $this->resource->motifNatureDesMarges,
            'ventilation_garantie_par_schema' => $this->resource->ventilationGarantieParSchema,
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'centres' => LigneAnalytiqueResource::collection($this->resource->centres)->resolve($request),
        ];
    }
}
