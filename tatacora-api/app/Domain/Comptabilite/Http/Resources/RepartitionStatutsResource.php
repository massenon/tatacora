<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\RepartitionStatuts;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Ce que l'etat a retenu, et ce qu'il a laisse de cote.
 *
 * ## Une seule ecriture de ce bloc, partagee par les trois etats
 *
 * Journal, Grand Livre et Balance le portent tous. Recopie trois fois, il
 * finirait par diverger — et deux ecrans afficheraient deux decomptes pour la
 * meme donnee (Article 10 : une seule source de verite par donnee).
 *
 * `comporte_des_exclusions` est le champ qui compte : sans lui, un client
 * devrait comparer les compteurs lui-meme pour savoir si son etat est complet,
 * et la moitie des clients ne le ferait pas.
 *
 * @property-read RepartitionStatuts $resource
 */
class RepartitionStatutsResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'statuts_retenus' => $this->resource->statutsRetenus,
            // Decomptes sur la portee de l'etat, SANS son filtre de statut :
            // ils disent ce qui existe, pas ce qui a ete retenu.
            'brouillon' => $this->resource->brouillon,
            'validee' => $this->resource->validee,
            'comporte_des_exclusions' => $this->resource->comporteDesExclusions(),
        ];
    }
}
