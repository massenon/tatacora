<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\Models\CentreCout;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un centre de cout — le selecteur « Tous les centres » de la barre de filtres
 * du hub (`m10-syscohada.html` l.77).
 *
 * Le maitre ecrit ses six centres EN DUR (`plan-comptable-syscohada.js`
 * l.76-83) la ou `ATELIER_PLAN_COMPTABLE.md` en pose SEPT — « RH » manque a sa
 * liste. Deux referentiels ecrits a la main finissent toujours par diverger :
 * celui-ci vient de la table `centres_cout`, seule source de verite, et un
 * centre ajoute demain apparaitra au selecteur sans livraison cliente.
 *
 * `type` est nullable au schema et descend tel quel — un centre sans type n'en
 * a pas, il n'en a pas un vide (Article 7).
 *
 * @property-read CentreCout $resource
 */
class CentreCoutResource extends JsonResource
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
