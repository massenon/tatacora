<?php

declare(strict_types=1);

namespace App\Domain\Bar\Http\Resources;

use App\Domain\Ventes\Models\LigneVente;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une ligne de vente du rayon, telle que l'API la rend (« Ventes du Bar »).
 *
 * Valeurs BRUTES — chaînes `decimal:2`, date ISO —, jamais mises en forme :
 * c'est au client de les dire, comme `HistoriquePrixResource`.
 *
 * ⚠ Le STOCK n'est pas rendu ici. La colonne « Stock actuel » de la PWA le
 * lit dans la carte du jour, par le `code` figé de la ligne (l'identifiant de
 * l'article de carte) ; le client Flutter dispose déjà de cette carte et fait
 * le même rapprochement. Un stock rendu par cette route serait une seconde
 * lecture du stock vendable, qui finirait par diverger de la colonne voisine.
 *
 * @property-read LigneVente $resource
 */
class LigneVenteRayonResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $vente = $this->resource->vente;
        $auteur = $vente?->utilisateur;
        $annulee = $vente !== null && $vente->estAnnulee();

        return [
            'id' => (string) $this->resource->id,
            // L'identifiant de l'article de carte FIGÉ à la vente — c'est par
            // lui qu'une ligne retrouve son article, jamais par le libellé.
            'code' => $this->resource->code,
            'nom' => (string) $this->resource->nom,
            'numero' => $vente?->numero,
            'date' => $vente?->created_at?->toIso8601String(),
            'prix_unitaire' => (string) $this->resource->prix_unitaire,
            'quantite' => (int) $this->resource->quantite,
            'montant' => (string) $this->resource->montant,
            'annulee' => $annulee,
            'motif_annulation' => $annulee ? (string) ($vente->motif_annulation ?? '') : null,
            // RG-15 : `null` quand la vente n'a pas d'auteur — jamais un
            // « système » inventé. `instanceof` : la colonne est NULLABLE.
            'utilisateur' => $auteur instanceof User ? $auteur->login : null,
        ];
    }
}
