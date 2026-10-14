<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Resources;

use App\Domain\Achats\Models\BonReception;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un bon de réception — EF-M7-03, RG-10.
 *
 * ## Ce que l'écran attend et que le schéma ne porte pas — dit, pas comblé
 *
 * L'onglet « Réceptions » du prototype affiche sept colonnes. Trois d'entre
 * elles n'ont aucune source (PA-39) :
 *
 * - **le numéro** — `bons_reception` n'a pas de séquence, seulement un UUID.
 *   Fabriquer un « BR-0001 » à l'affichage donnerait un numéro qui changerait
 *   au prochain tri ;
 * - **le point de stockage** — il est passé à la réception, utilisé pour
 *   imputer l'entrée de stock, et **jamais conservé** sur le bon ;
 * - **le nombre d'articles reçus** — la table n'a pas de lignes.
 *
 * Aucune des trois n'est rendue, et le drapeau `lignes_non_stockees` dit
 * pourquoi. Les inventer ferait un écran plausible et faux ; les omettre en
 * silence empêcherait de savoir si la donnée manque ou si l'écran est cassé.
 *
 * `conformite` descend avec ses trois valeurs réelles : `partielle` (livraison
 * incomplète, créance sur le fournisseur) et `non_conforme` (article hors
 * commande, ou excédent hors tolérance) ne sont pas la même situation.
 *
 * @property-read BonReception $resource
 */
class BonReceptionResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $bon = $this->resource;

        return [
            'id' => $bon->id,
            'commande_id' => $bon->commande_id,
            'date_reception' => $bon->date_reception->toDateString(),
            'conformite' => $bon->conformite,
            'utilisateur_id' => $bon->utilisateur_id,

            'fournisseur' => $bon->relationLoaded('commande') && $bon->commande?->fournisseur !== null
                ? [
                    'id' => $bon->commande->fournisseur->id,
                    'raison_sociale' => $bon->commande->fournisseur->raison_sociale,
                ]
                : null,

            // Aveu porté jusqu'à l'écran : ni les quantités reçues, ni le point
            // d'imputation ne sont conservés par cette table (PA-39). Le détail
            // d'une réception se relit des mouvements de stock qu'elle a
            // générés, pas d'ici.
            'lignes_non_stockees' => true,
        ];
    }
}
