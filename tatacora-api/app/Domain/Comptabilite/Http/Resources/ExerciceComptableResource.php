<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\Models\ExerciceComptable;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un exercice comptable — la source du selecteur exige par
 * `MODULE_COMPTABILITE_COMPLET.md` §1.
 *
 * ## `saisie_refusee` DERIVE de l'Observer, jamais de la documentation
 *
 * §1 annonce la saisie bloquee des le statut `en_cloture`.
 * `EcritureComptableObserver`, seule garde reelle (RG-11), ne ferme que
 * `cloture`. Ce champ rend ce que le systeme REFUSE REELLEMENT.
 *
 * Annoncer ici le comportement documente pendant que l'Observer laisse passer
 * l'ecriture serait PA-61 : un indicateur qui affirme un etat qu'il n'a pas
 * verifie. L'ecart entre le document et le code est reel et il est pose en
 * question a l'Architecte — il ne se referme pas en maquillant l'API.
 *
 * @property-read ExerciceComptable $resource
 */
class ExerciceComptableResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->id,
            'annee' => $this->resource->annee,
            'date_debut' => $this->resource->date_debut->toDateString(),
            'date_fin' => $this->resource->date_fin->toDateString(),
            'statut' => $this->resource->statut,
            'date_cloture' => $this->resource->date_cloture?->toIso8601String(),
            'saisie_refusee' => $this->resource->saisieRefuseeParObserver(),
        ];
    }
}
