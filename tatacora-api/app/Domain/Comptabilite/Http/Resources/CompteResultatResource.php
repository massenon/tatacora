<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\CompteResultat;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Compte de Resultat » d'un seul parcours — EF-M10-06.
 *
 * Sert `m10-resultat.html` ET l'onglet « Compte de resultat » du hub : le
 * premier n'affiche que les soldes, le second toute la cascade. Deux routes
 * auraient produit deux agregations paralleles pour le meme exercice (PA-121).
 *
 * ## `impot_non_comptabilise` est la cle qu'il ne faut pas ignorer (PA-19)
 *
 * Quand elle vaut `true`, `resultat_net` est un resultat AVANT impot. Le maitre
 * ne rend alors PAS de ligne « Resultat net » : il titre « RÉSULTAT AVANT IMPÔT
 * SUR LES SOCIÉTÉS » (`m10-resultat.html` l.103) et affiche « XI — avant impôt »
 * au bandeau (`m10-syscohada-init.js` l.44).
 *
 * L'API, elle, descend les DEUX montants et le drapeau, plutot que d'omettre
 * une ligne : un client qui ne recevrait que `resultat_avant_impot` ne pourrait
 * pas savoir s'il manque une donnee ou si elle n'existe pas. L'omission est une
 * decision de RENDU, prise par l'ecran ; le serveur, lui, dit tout ce qu'il
 * sait et nomme ce qui manque (Article 7).
 *
 * `impot_comptabilise` reste emis a `0.00` — c'est un zero CALCULE sur la
 * classe 89 reellement balayee, pas une absence de calcul.
 *
 * @property-read CompteResultat $resource
 */
class CompteResultatResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'resultat_avant_impot' => $this->resource->resultatAvantImpot,
            'impot_comptabilise' => $this->resource->impotComptabilise,
            'resultat_net' => $this->resource->resultatNet,
            'impot_non_comptabilise' => $this->resource->impotNonComptabilise,
            'motif_resultat_avant_impot' => $this->resource->motifResultatAvantImpot,
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'lignes' => LigneResultatResource::collection($this->resource->lignes)->resolve($request),
        ];
    }
}
