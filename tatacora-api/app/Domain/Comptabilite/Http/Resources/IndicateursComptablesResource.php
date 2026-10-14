<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\IndicateursComptables;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Le bandeau d'indicateurs du hub `m10-syscohada.html` — six chiffres.
 *
 * Chacun est LU d'un etat deja calcule (Compte de Resultat, Bilan, Balance),
 * jamais recalcule par une agregation parallele : le bandeau et les onglets
 * qu'il surplombe doivent dire la meme chose (PA-121).
 *
 * `impot_non_comptabilise` qualifie `resultat_net` — le maitre affiche alors
 * « XI — avant impôt » (`m10-syscohada-init.js` l.44).
 *
 * `equilibre` porte sur DEUX etats : balance equilibree ET bilan equilibre.
 * Ne verifier que la balance laisserait passer une erreur de classification de
 * compte, qui n'apparait qu'au bilan.
 *
 * @property-read IndicateursComptables $resource
 */
class IndicateursComptablesResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'annee' => $this->resource->annee,
            'statut_exercice' => $this->resource->statutExercice,
            'chiffre_affaires' => $this->resource->chiffreAffaires,
            'valeur_ajoutee' => $this->resource->valeurAjoutee,
            'excedent_brut' => $this->resource->excedentBrut,
            'resultat_net' => $this->resource->resultatNet,
            'tresorerie' => $this->resource->tresorerie,
            'total_bilan' => $this->resource->totalBilan,
            'equilibre' => $this->resource->equilibre,
            'impot_non_comptabilise' => $this->resource->impotNonComptabilise,
            'motif_resultat_avant_impot' => $this->resource->motifResultatAvantImpot,
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
        ];
    }
}
