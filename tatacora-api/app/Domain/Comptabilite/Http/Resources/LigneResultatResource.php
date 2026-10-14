<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\LigneResultat;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une ligne du Compte de Resultat — rubrique ou solde intermediaire.
 *
 * `montant` descend SIGNE (positif = produit, negatif = charge). Le maitre
 * affiche sa valeur absolue dans l'une ou l'autre colonne selon `sens` ; c'est
 * une decision de rendu, et la refaire au serveur obligerait le client a
 * reconstituer le signe pour additionner quoi que ce soit.
 *
 * @property-read LigneResultat $resource
 */
class LigneResultatResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'code' => $this->resource->code,
            'libelle' => $this->resource->libelle,
            'sens' => $this->resource->sens,
            'montant' => $this->resource->montant,
            'est_solde' => $this->resource->estSolde,
            'prefixes' => $this->resource->prefixes,
            'composants' => $this->resource->composants,
        ];
    }
}
