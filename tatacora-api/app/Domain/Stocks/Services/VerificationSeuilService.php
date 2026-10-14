<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Services;

use App\Domain\Stocks\Events\SeuilStockAtteint;
use App\Domain\Stocks\Models\Article;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Détection du franchissement de seuil d'alerte — RG-07.
 *
 * Double mécanisme voulu par ALERTES_CRITIQUES_DE_STOCK.md §54-55 :
 * 1. **synchrone**, immédiatement après tout mouvement sortant ;
 * 2. **planifié** (`VerifierSeuilsStockJob`, toutes les 15 min), filet de
 *    sécurité pour les cas où le seuil devient franchi sans mouvement — par
 *    exemple après relèvement du seuil par un gestionnaire.
 *
 * Le mécanisme planifié n'est pas une redondance : sans lui, un seuil relevé
 * à midi ne déclencherait aucune alerte avant la prochaine sortie de stock,
 * c'est-à-dire potentiellement jamais sur un article à rotation lente.
 */
class VerificationSeuilService
{
    public function __construct(
        private readonly StockTheoriqueService $stock,
    ) {
    }

    /**
     * Vérification synchrone, sur le seul couple (article, point) touché.
     * Balayer tout le référentiel après chaque vente serait inutilement coûteux
     * en caisse, où la contrainte est « < 10 s par opération ».
     */
    public function verifierApresMouvement(string $articleId, string $pointId): bool
    {
        $article = Article::find($articleId);

        if ($article === null) {
            return false;
        }

        $stockActuel = $this->stock->stock($articleId, $pointId);

        if (! $this->estSousSeuil($stockActuel, (string) $article->seuil_alerte)) {
            return false;
        }

        SeuilStockAtteint::dispatch($articleId, $pointId, $stockActuel, (string) $article->seuil_alerte);

        return true;
    }

    /**
     * Balayage complet, appelé par le job planifié.
     *
     * @return Collection<int, array{article_id: string, point_id: string, stock: string, seuil: string}>
     */
    public function articlesCritiques(): Collection
    {
        // Une seule requête, et non une par couple (article, point).
        //
        // La version initiale bouclait sur tous les articles × tous les points
        // en interrogeant le stock à chaque itération : sur un référentiel de
        // 200 articles et 4 points de stockage, cela faisait 800 requêtes —
        // chacune chargeant l'historique complet des mouvements. Ce service
        // étant destiné au job planifié toutes les 15 minutes
        // (ALERTES_CRITIQUES_DE_STOCK.md §55), il aurait saturé le serveur
        // mutualisé cPanel sans que personne ne comprenne pourquoi.
        //
        // Reprend la forme de la vue `v_stock_critique` esquissée dans
        // ALERTES_CRITIQUES_DE_STOCK.md : agrégation des mouvements par couple,
        // puis comparaison au seuil de l'article.
        $lignes = DB::table('mouvements_stock as m')
            ->join('articles as a', 'a.id', '=', 'm.article_id')
            ->groupBy('m.article_id', 'm.point_id', 'a.seuil_alerte')
            ->havingRaw(StockTheoriqueService::EXPRESSION_SOLDE . ' <= a.seuil_alerte')
            ->get([
                'm.article_id',
                'm.point_id',
                'a.seuil_alerte',
                DB::raw(StockTheoriqueService::EXPRESSION_SOLDE . ' AS solde'),
            ]);

        return $lignes->map(fn (object $ligne): array => [
            'article_id' => (string) $ligne->article_id,
            'point_id' => (string) $ligne->point_id,
            'stock' => bcadd((string) $ligne->solde, '0', 2),
            'seuil' => bcadd((string) $ligne->seuil_alerte, '0', 2),
        ])->values();
    }

    /**
     * Comparaison décimale : `bccomp`, jamais une égalité flottante.
     * Le seuil est franchi quand le stock lui est inférieur OU ÉGAL
     * (ALERTES_CRITIQUES_DE_STOCK.md : `stock <= seuil_alerte`) — alerter
     * seulement en dessous laisserait passer le cas où le stock atteint
     * exactement le seuil, qui est précisément le moment utile.
     */
    private function estSousSeuil(string $stock, string $seuil): bool
    {
        return bccomp($stock, $seuil, 2) <= 0;
    }
}
