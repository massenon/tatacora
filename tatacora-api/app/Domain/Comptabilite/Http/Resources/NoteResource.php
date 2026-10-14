<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\Note;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une note annexe, avec son ETAT.
 *
 * `postes` est vide — et non rempli de zeros — quand la note est
 * `indisponible` : « 0 F d'effectif » et « effectif non calculable » ne disent
 * pas la meme chose au comptable qui signe les etats (Article 7).
 *
 * `motif` est un code ferme ; sa traduction appartient au client.
 *
 * @property-read Note $resource
 */
class NoteResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'numero' => $this->resource->numero,
            'titre' => $this->resource->titre,
            'etat' => $this->resource->etat,
            'texte' => $this->resource->texte,
            'motif' => $this->resource->motif,
            'postes' => $this->resource->postes,
        ];
    }
}
