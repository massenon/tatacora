<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Fiche de stock d'un article sur une période — EF-M6-04.
 *
 * ## Ce document justifie un solde ; l'état des stocks, lui, le photographie
 *
 *     Stock initial + Entrées − Sorties − Pertes ± Régularisations = Stock final
 *
 * `FicheStockService` **vérifie** cette égalité au lieu de l'afficher : le
 * drapeau `coherent` tombe à `false` si un mouvement a été écrit hors de
 * `MouvementStockService`. Il est remonté tel quel au client, et il doit
 * l'être — un document de justification qui tairait son propre doute vaut
 * moins que pas de document du tout. C'est la même famille que PA-59/60/61 :
 * un indicateur qui affirme « tout va bien » sans l'avoir vérifié.
 *
 * @property-read array{fiche: array<string, mixed>, point_id: string|null} $resource
 */
class FicheStockResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        // Les champs de la fiche viennent tels quels de `FicheStockService` :
        // les recopier un par un ici ferait deux contrats à tenir au lieu d'un,
        // et le jour où le service en ajouterait un, le client ne le verrait
        // jamais.
        return $this->resource['fiche'] + [
            // Le filtre RÉELLEMENT appliqué. Une fiche restreinte à un point
            // qui ne le dirait pas serait lue comme la fiche complète de
            // l'article, et son solde final passerait pour le stock total
            // (PA-119).
            'point_id' => $this->resource['point_id'],
        ];
    }
}
