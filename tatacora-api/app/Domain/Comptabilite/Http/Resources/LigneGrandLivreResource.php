<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Resources;

use App\Domain\Comptabilite\ReadModels\LigneGrandLivre;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une ligne de Grand Livre — `m10-grand-livre.html` (l.24-25).
 *
 * Elle reprend la ligne de Journal et lui ajoute la seule colonne propre a cet
 * ecran : le solde progressif. Redecrire ici les champs de l'ecriture en ferait
 * une seconde forme du meme objet, qui divergerait.
 *
 * ## Le SENS descend a part
 *
 * `solde_progressif` est signe (positif = debiteur), et `sens` le nomme. Le
 * maitre affiche la valeur absolue suivie de `(D)` ou `(C)` (l.78) : c'est du
 * rendu, et le client le compose. Lui envoyer une valeur absolue sans son sens
 * lui ferait perdre l'information ; lui envoyer « (D) » deja ecrit figerait du
 * copywriting cote serveur.
 *
 * @property-read LigneGrandLivre $resource
 */
class LigneGrandLivreResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $ecriture = (new LigneJournalResource($this->resource->ecriture))->resolve($request);

        return $ecriture + [
            'solde_progressif' => $this->resource->soldeProgressif,
            'sens' => bccomp($this->resource->soldeProgressif, '0.00', 2) < 0 ? 'crediteur' : 'debiteur',
        ];
    }
}
