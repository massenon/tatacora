<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\Models\CompteComptable;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un compte du plan comptable — les quatre colonnes de
 * `m10-plan-comptable.html` (l.37) et le selecteur du Grand Livre.
 *
 * ## `nature` peut etre NULLE, et elle descend nulle
 *
 * La colonne est `nullable` au schema. Le maitre indexe un badge de couleur
 * dessus (l.80) : `NATURE_BADGE[undefined]` ne produit rien, donc une cellule
 * vide sans explication. Rendre une valeur par defaut — « actif », ou la
 * deduire de la classe — serait inventer une donnee reglementaire, ce que la
 * premiere des six regles sans exception interdit. Elle descend `null`, et le
 * decompte `sans_nature` du plan la rend visible.
 *
 * ## Une seule ecriture pour DEUX ecrans
 *
 * La meme ressource sert le tableau du plan comptable et le selecteur de comptes
 * mouvementes du Grand Livre. Deux formes distinctes du meme compte
 * divergeraient ; le maitre les affiche d'ailleurs pareil (`libelleCompte()`
 * concatene numero et libelle dans les deux ecrans).
 *
 * @property-read CompteComptable $resource
 */
class CompteComptableResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->id,
            'numero_compte' => $this->resource->numero_compte,
            'libelle' => $this->resource->libelle,
            'classe' => $this->resource->classe,
            'nature' => $this->resource->nature,
        ];
    }
}
