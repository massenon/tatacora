<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Resources;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Fiche d'un article : son signalétique et la ventilation de son stock point
 * par point — EF-M6-01, EF-M6-05.
 *
 * ## Pourquoi la ventilation, et pas seulement un total
 *
 * Le stock se raisonne TOUJOURS par couple (article, point). « 10 bouteilles
 * au bar et 0 au magasin » n'est pas la même situation que l'inverse, même
 * total : dans le second cas, le barman est en rupture. Un écran qui
 * n'afficherait que le total ferait refuser une sortie sans que personne
 * comprenne pourquoi.
 *
 * Le total est rendu **en plus**, pour le réapprovisionnement (M7) — jamais
 * pour décider d'une sortie.
 *
 * @property-read array{
 *     article: Article,
 *     ventilation: list<array{point: PointStockage, stock: string, valeur: string}>,
 *     stock_total: string,
 *     valeur_totale: string
 * } $resource
 */
class ArticleVentilationResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        /** @var Article $article */
        $article = $this->resource['article'];

        return [
            'id' => $article->id,
            'libelle' => $article->libelle,
            'categorie' => $article->categorie,
            'unite_mesure' => $article->unite_mesure,
            'seuil_alerte' => (string) $article->seuil_alerte,
            'seuil_reappro' => $article->seuil_reappro === null ? null : (string) $article->seuil_reappro,
            'cout_moyen_pondere' => (string) $article->cout_moyen_pondere,

            'stock_total' => $this->resource['stock_total'],
            'valeur_totale' => $this->resource['valeur_totale'],
            'stock_lecture_seule' => true,

            'ventilation' => array_map(
                fn (array $ligne): array => [
                    'point_id' => $ligne['point']->id,
                    'point_libelle' => $ligne['point']->libelle,
                    'point_type' => $ligne['point']->type,
                    'stock' => $ligne['stock'],
                    'valeur' => $ligne['valeur'],
                ],
                $this->resource['ventilation'],
            ),
        ];
    }
}
