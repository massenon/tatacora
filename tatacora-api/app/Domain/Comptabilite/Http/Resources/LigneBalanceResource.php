<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\LigneBalance;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une ligne de Balance Generale — les six colonnes de `m10-balance.html`
 * (l.21-23).
 *
 * Les quatre montants descendent en CHAINE, et les deux colonnes de solde sont
 * exclusives : un compte au solde nul porte `0.00` aux deux. C'est un zero
 * CALCULE — le compte a ete mouvemente, ses mouvements se compensent — a ne pas
 * confondre avec une donnee absente.
 *
 * Le maitre rend une chaine vide plutot que `0 F` dans la colonne inactive
 * (l.66-67) : c'est du rendu, le client le compose. Envoyer une chaine vide
 * depuis le serveur ferait perdre la distinction entre « zero » et « non
 * calcule ».
 *
 * @property-read LigneBalance $resource
 */
class LigneBalanceResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'compte_id' => $this->resource->compteId,
            'numero_compte' => $this->resource->numeroCompte,
            'libelle' => $this->resource->libelle,
            'classe' => $this->resource->classe,
            'total_debit' => $this->resource->totalDebit,
            'total_credit' => $this->resource->totalCredit,
            'solde_debiteur' => $this->resource->soldeDebiteur,
            'solde_crediteur' => $this->resource->soldeCrediteur,
        ];
    }
}
