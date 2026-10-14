<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\Bilan;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Bilan de l'Entreprise » d'un seul parcours — EF-M10-06.
 *
 * ## `resultat_exercice` porte son drapeau, et ce n'est pas un detail
 *
 * Le poste « Capitaux propres » du maitre est sous-titre « Capital + Résultat
 * net de l'exercice » (`m10-bilan.html` l.96). Tant que rien n'est
 * comptabilise en classe 89, ce resultat est un resultat AVANT impot :
 * `impot_non_comptabilise` le dit. Le libelle reste celui du maitre — c'est le
 * drapeau qui porte la verite, pas une reformulation (Article 1 interdit de
 * changer un libelle, PA-49 interdit de mentir sur le calcul ; les deux se
 * tiennent par cette cle).
 *
 * ## `comptes_hors_rubrique` est vide, et doit le rester
 *
 * Non vide, il nomme les comptes mouvementes qu'aucune rubrique ne capte —
 * seule explication possible d'un `equilibre` a `false` qui ne viendrait pas
 * des ecritures elles-memes. Voir l'entete de `Bilan`.
 *
 * ## `equilibre` est un constat, pas une garantie (PA-52)
 *
 * Il compare deux totaux. Il n'affirme rien sur l'equilibre de chaque piece :
 * `ecritures_comptables` n'a aucun identifiant de piece, et deux pieces fausses
 * en sens contraire rendraient `true`.
 *
 * @property-read Bilan $resource
 */
class BilanResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'totaux' => [
                'actif_brut' => $this->resource->totalActifBrut,
                'actif_amortissement' => $this->resource->totalActifAmortissement,
                'actif' => $this->resource->totalActif,
                'passif' => $this->resource->totalPassif,
            ],
            'equilibre' => $this->resource->equilibre,
            'ecart' => $this->resource->ecart,
            'resultat_exercice' => $this->resource->resultatExercice,
            'impot_non_comptabilise' => $this->resource->impotNonComptabilise,
            'motif_resultat_avant_impot' => $this->resource->motifResultatAvantImpot,
            'comptes_hors_rubrique' => $this->resource->comptesHorsRubrique,
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'actif' => PosteBilanResource::collection($this->resource->actif)->resolve($request),
            'passif' => PosteBilanResource::collection($this->resource->passif)->resolve($request),
        ];
    }
}
