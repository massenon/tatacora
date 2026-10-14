<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\LigneAnalytique;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un centre d'analyse et sa marge sur couts directs.
 *
 * `taux_marge` est `null` — jamais `"0.0"` — quand le centre n'a aucun produit.
 * Le maitre affiche « — » (`m10-analytique.html` l.50-52) : un centre support
 * n'a pas un taux de marge nul, il n'en a pas.
 *
 * @property-read LigneAnalytique $resource
 */
class LigneAnalytiqueResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'centre_id' => $this->resource->centreId,
            'libelle' => $this->resource->libelle,
            'type' => $this->resource->type,
            'produits' => $this->resource->produits,
            'charges' => $this->resource->charges,
            'resultat' => $this->resource->resultat,
            'taux_marge' => $this->resource->tauxMarge,
            'nombre_lignes' => $this->resource->nombreLignes,
        ];
    }
}
