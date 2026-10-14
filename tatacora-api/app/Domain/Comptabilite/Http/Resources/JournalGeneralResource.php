<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\JournalGeneral;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Journal Comptable » d'un seul parcours — EF-M10-06.
 *
 * ## Les totaux et le bandeau voyagent AVEC les lignes
 *
 * `MODULE_COMPTABILITE_COMPLET.md` §2 : le controle d'equilibre est « calcule
 * et affiche en permanence, jamais une verification ponctuelle a la demande ».
 * Deux appels distincts finiraient par afficher un bandeau qui ne correspond
 * plus aux lignes en dessous.
 *
 * ## Ce que `equilibre` n'affirme PAS
 *
 * L'egalite porte sur l'ENSEMBLE affiche, jamais sur chaque piece :
 * `ecritures_comptables` n'a aucun identifiant de piece (PA-52), donc aucune
 * piece n'est reconstituable a posteriori. Deux pieces fausses en sens
 * contraire rendraient ici `true`. Le maitre dit exactement cela (« Total Debit
 * = Total Credit »), et cette ressource ne dit rien de plus.
 *
 * @property-read JournalGeneral $resource
 */
class JournalGeneralResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'totaux' => [
                // En chaine : ce sont des montants, jamais des flottants.
                'debit' => $this->resource->totalDebit,
                'credit' => $this->resource->totalCredit,
            ],
            // Portee : l'ensemble affiche. Voir le bloc ci-dessus.
            'equilibre' => $this->resource->equilibre,
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            // Un etat DIT son filtre (PA-119) : qui filtre puis lit attend son
            // filtre, et doit pouvoir verifier lequel a ete applique.
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'lignes' => LigneJournalResource::collection($this->resource->lignes)->resolve($request),
        ];
    }
}
