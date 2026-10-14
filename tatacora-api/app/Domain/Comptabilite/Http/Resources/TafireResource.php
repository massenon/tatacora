<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\Tafire;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Tableau des Flux de Tresorerie » — TAFIRE, EF-M10-06.
 *
 * Quatre blocs, dans l'ordre du maitre (`m10-flux-tresorerie.html`) :
 * RESSOURCES, EMPLOIS, variation du BFR, variation de tresorerie nette.
 *
 * ## `coherent` n'est pas une information de confort
 *
 * `MODULE_COMPTABILITE_COMPLET_PART3.md` §2.2 : un ecart entre variation
 * calculee et variation reelle « signale une erreur de methode, PAS une
 * "difference normale" ». `ecart` descend avec, pour que l'ecran puisse dire
 * COMBIEN — un « incoherent » sans montant n'aide personne a chercher.
 *
 * @property-read Tafire $resource
 */
class TafireResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'ressources' => [
                'resultat_exercice' => $this->resource->resultatExercice,
                'dotations_amortissements' => $this->resource->dotationsAmortissements,
                'capacite_autofinancement_globale' => $this->resource->capaciteAutofinancementGlobale,
                'augmentation_capital' => $this->resource->augmentationCapital,
                'total' => $this->resource->totalRessources,
            ],
            'emplois' => [
                'acquisitions_immobilisations' => $this->resource->acquisitionsImmobilisations,
                'total' => $this->resource->totalEmplois,
            ],
            'besoin_fonds_roulement' => [
                'variation_stocks' => $this->resource->variationStocks,
                'variation_creances' => $this->resource->variationCreances,
                'variation_dettes' => $this->resource->variationDettes,
                'total' => $this->resource->variationBesoinFondsRoulement,
            ],
            'tresorerie' => [
                'variation_calculee' => $this->resource->variationTresorerieCalculee,
                'variation_reelle' => $this->resource->variationTresorerieReelle,
                'ecart' => $this->resource->ecart,
            ],
            'coherent' => $this->resource->coherent,
            'impot_non_comptabilise' => $this->resource->impotNonComptabilise,
            'motif_resultat_avant_impot' => $this->resource->motifResultatAvantImpot,
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
        ];
    }
}
