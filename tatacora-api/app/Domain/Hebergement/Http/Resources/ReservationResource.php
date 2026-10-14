<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Représentation API d'une réservation, consommée par le client Flutter.
 *
 * @property-read \App\Domain\Hebergement\Models\Reservation $resource
 */
class ReservationResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->id,
            'client_id' => $this->resource->client_id,
            'unite_id' => $this->resource->unite_id,
            'date_arrivee' => $this->resource->date_arrivee->toDateString(),
            'date_depart' => $this->resource->date_depart->toDateString(),
            // Valeur CALCULÉE, exposée en lecture seule : le client ne la
            // soumet jamais et ne peut pas la contredire (A1_MASTER_PROMPT.md §2.2).
            'nb_nuitees' => $this->resource->nombreNuitees(),
            'statut' => $this->resource->statut,
            'acompte' => $this->resource->acompte,
            'client' => $this->whenLoaded('client', fn (): array => [
                'id' => $this->resource->client->id,
                'nom_complet' => $this->resource->client->nomComplet(),
                'telephone' => $this->resource->client->telephone,
            ]),
        ];
    }
}
