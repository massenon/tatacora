<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\GrandLivre;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Grand Livre » d'un seul parcours — EF-M10-06.
 *
 * ## Deux montants sont NULS, et c'est le livrable
 *
 * `solde_ouverture` et `solde_cloture` descendent `null`, avec leur motif. Le
 * report a nouveau n'existe nulle part dans ce depot (Partie 4, cloture) :
 * rendre `0` affirmerait que le compte partait de zero au premier jour de
 * l'exercice, sur l'ecran meme ou un comptable lit le solde d'un compte.
 * Article 7 : « — » quand la donnee n'existe pas, « 0 » quand elle vaut zero.
 *
 * `solde_mouvements`, lui, est calcule et exact — et il est nomme pour ce qu'il
 * est : le cumul des mouvements de l'exercice, pas le solde du compte.
 *
 * ## Une liste vide est une reponse, pas une erreur
 *
 * `sans_mouvement` porte le cas nomme par le maitre (l.29 : « Ce compte n'a
 * aucun mouvement sur l'exercice. »). Le distinguer d'une liste vide pour cause
 * de filtre evite au client d'avoir a le deviner.
 *
 * @property-read GrandLivre $resource
 */
class GrandLivreResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'compte' => (new CompteComptableResource($this->resource->compte))->resolve($request),

            // INCONNUS, pas nuls — voir le bloc ci-dessus.
            'solde_ouverture' => $this->resource->soldeOuverture,
            'solde_cloture' => $this->resource->soldeCloture,
            'motif_soldes_indisponibles' => $this->resource->motifSoldesIndisponibles,

            // CALCULE et exact : le cumul des mouvements de l'exercice.
            'solde_mouvements' => $this->resource->soldeMouvements,

            'sans_mouvement' => $this->resource->estSansMouvement(),
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'lignes' => LigneGrandLivreResource::collection($this->resource->lignes)->resolve($request),
        ];
    }
}
