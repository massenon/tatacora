<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Resources;

use App\Domain\Stocks\ReadModels\EtatStockConsolide;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * L'état des stocks consolidé — EF-M14-02, version JSON.
 *
 * ## Un état DIT son filtre
 *
 * `filtres_appliques` remonte les filtres réellement retenus. Quelqu'un qui
 * filtre puis exporte attend son filtre ; lui rendre un document muet lui
 * ferait transmettre au comptable un état qu'il croit avoir vérifié (PA-119).
 *
 * ## Un état est daté
 *
 * `arrete_au` est un instant, pas une période : un état de stock est une
 * photographie. Afficher « du 01/01 au 31/12 » laisserait croire à un cumul de
 * période, ce que ce tableau n'est pas.
 *
 * @property-read EtatStockConsolide $resource
 */
class EtatStockResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'kpis' => [
                // Nombre de lignes AFFICHÉES.
                'references' => $this->resource->references,
                // Alarmes relevées sur tout le référentiel de la portée, filtre
                // d'affichage compris ou non : masquer les articles sains ne
                // change pas le nombre d'articles à réapprovisionner.
                'sous_seuil' => $this->resource->sousSeuil,
                'rupture' => $this->resource->rupture,
                // Valorisation au coût moyen pondéré, en chaîne.
                'valeur_stock' => $this->resource->valeurTotale,
                'mouvements_30_jours' => $this->resource->mouvements30Jours,
                // PA-161 (a) — la répartition du référentiel entre gros stock
                // suivi et petit stock journalier. Même portée que les
                // alarmes : tout le référentiel, jamais la page.
                'permanents' => $this->resource->permanents,
                'journaliers' => $this->resource->journaliers,
            ],
            'filtres_appliques' => (object) $this->resource->filtresAppliques,
            'arrete_au' => $this->resource->arreteAu,
            'lignes' => ArticleStockResource::collection($this->resource->lignes)->resolve($request),
        ];
    }
}
