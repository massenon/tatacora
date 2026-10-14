<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\BalanceGenerale;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'ecran « Balance Generale » d'un seul parcours — EF-M10-06.
 *
 * ## `equilibree` porte sur DEUX egalites
 *
 * Total debit = total credit ET total solde debiteur = total solde crediteur,
 * les deux en `bccomp` (`MODULE_COMPTABILITE_COMPLET.md` §4). Ne verifier que
 * la premiere laisserait passer une erreur de repartition des soldes.
 *
 * ## Ce que la ressource NE FAIT PAS : bloquer une cloture
 *
 * §4 fait de l'equilibre la condition sine qua non de la production des etats
 * financiers, et le maitre l'ecrit en toutes lettres (l.57 : « production des
 * etats financiers bloquee tant que non resolu »). Cette API rend le CONSTAT ;
 * elle ne fait rien appliquer, le verrou de cloture vivant en Partie 4, non
 * implementee. Annoncer ici un blocage qu'aucun code n'exerce serait PA-61.
 *
 * ## Et rien sur l'equilibre PAR PIECE
 *
 * `ecritures_comptables` n'a aucun identifiant de piece (PA-52). Une balance
 * equilibree globalement peut contenir deux pieces fausses qui se compensent.
 *
 * @property-read BalanceGenerale $resource
 */
class BalanceGeneraleResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'exercice_id' => $this->resource->exerciceId,
            'totaux' => [
                'debit' => $this->resource->totalDebit,
                'credit' => $this->resource->totalCredit,
                'solde_debiteur' => $this->resource->totalSoldeDebiteur,
                'solde_crediteur' => $this->resource->totalSoldeCrediteur,
            ],
            'equilibree' => $this->resource->equilibree,
            'repartition_statuts' => (new RepartitionStatutsResource($this->resource->statuts))->resolve($request),
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'lignes' => LigneBalanceResource::collection($this->resource->lignes)->resolve($request),
        ];
    }
}
