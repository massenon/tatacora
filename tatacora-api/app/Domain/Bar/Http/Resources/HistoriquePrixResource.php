<?php

declare(strict_types=1);

namespace App\Domain\Bar\Http\Resources;

use App\Domain\Carte\Models\HistoriquePrixCarte;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Une trace de l'historique des prix d'une boisson, telle que l'API la rend.
 *
 * Les valeurs sortent BRUTES — codes et chaînes `decimal:2` —, jamais mises
 * en forme : c'est au client de les dire (« Oui » / « Non » pour la marque
 * « corrigé à la main », montant en FCFA pour le prix), comme la modale de la
 * PWA le fait à l'affichage. Une mise en forme ici figerait un libellé dans
 * un contrat d'API.
 *
 * @property-read HistoriquePrixCarte $resource
 */
class HistoriquePrixResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->id,
            'date' => $this->resource->created_at?->toIso8601String(),
            // `prix_vente` ou `prix_corrige_main` — `HistoriquePrixCarte::CHAMP_*`.
            'champ' => $this->resource->champ,
            // `null` quand il n'y avait pas de valeur : « — », jamais « 0 ».
            'ancien_prix' => $this->resource->ancien_prix,
            'nouveau_prix' => $this->resource->nouveau_prix,
            // L'identifiant de connexion de l'auteur, comme la colonne « Par »
            // de la PWA ; `null` si la trace n'a pas d'auteur connu.
            'par' => $this->resource->utilisateurCreation?->login,
        ];
    }
}
