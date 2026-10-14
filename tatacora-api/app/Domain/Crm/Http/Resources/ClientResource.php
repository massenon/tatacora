<?php

declare(strict_types=1);

namespace App\Domain\Crm\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Représentation API d'une fiche client.
 *
 * @property-read \App\Domain\Crm\Models\Client $resource
 */
class ClientResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->id,
            'nom' => $this->resource->nom,
            'prenom' => $this->resource->prenom,
            // Calculé, jamais une colonne dénormalisée qui divergerait de
            // nom/prenom à la première correction de saisie.
            'nom_complet' => $this->resource->nomComplet(),
            'telephone' => $this->resource->telephone,
            'email' => $this->resource->email,
            'piece_identite' => $this->resource->piece_identite,
            'type_client' => $this->resource->type_client,
            'solde' => $this->resource->solde,
        ];
    }
}
