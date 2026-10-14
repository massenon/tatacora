<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Etats;

use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;
use Illuminate\Support\Facades\DB;

/**
 * État des stocks — EF-M14-02 (bibliothèque d'états standards par module),
 * appliqué à M6.
 *
 * C'est l'exemple nommé par `DIRECTIVE_EXPORT_PDF.md` §2 : « État des stocks —
 * Magasin général ».
 *
 * ## Ce que cette classe ne fait pas, délibérément
 *
 * Elle ne construit **aucune** en-tête, ne choisit **aucun** format, n'écrit
 * **aucune** archive. `EtatInterface` ne lui en donne pas les moyens. C'est ce
 * qui rend structurellement inatteignable la non-conformité n°1 de
 * `RESPECT_TABLEAU_RAPPORT.md` §4 (« En-tête re-générée manuellement au lieu
 * d'appeler `ReportHeaderService` »).
 *
 * ## Le stock reste calculé, jamais stocké
 *
 * Les quantités viennent de `StockTheoriqueService`, c'est-à-dire de la somme
 * des mouvements — pas d'une colonne `stock_actuel` qui dériverait. Règle
 * projet : toute valeur calculable est affichée en lecture seule.
 *
 * @see EF-M14-02
 * @see EF-M14-03 Filtres dynamiques (point de stockage, articles sous seuil)
 * @see RG-07 Seuil d'alerte
 */
class EtatStocks implements EtatInterface
{
    private const PRECISION = 2;

    public function __construct(
        private readonly StockTheoriqueService $stocks,
    ) {
    }

    public function module(): string
    {
        return 'M6';
    }

    /**
     * @param  array<string, string>  $filtres
     */
    public function libelle(array $filtres): string
    {
        $point = $this->point($filtres);

        return $point === null
            ? __('stocks.etat.libelle_global')
            : __('stocks.etat.libelle_point', ['point' => $point->libelle]);
    }

    /**
     * Un état de stock est une **photographie à l'instant de l'édition**, pas
     * un intervalle : afficher « Du 01/01 au 31/12 » laisserait croire à un
     * cumul de période, ce que ce tableau n'est pas.
     *
     * @param  array<string, string>  $filtres
     */
    public function periode(array $filtres): string
    {
        return __('stocks.etat.arrete_au', ['date' => now()->format('d/m/Y à H:i')]);
    }

    /**
     * @param  array<string, string>  $filtres  `point_id`, `sous_seuil`
     */
    public function calculer(array $filtres): EtatResultat
    {
        $point = $this->point($filtres);
        $sousSeuilUniquement = filter_var($filtres['sous_seuil'] ?? false, FILTER_VALIDATE_BOOLEAN);

        $articles = DB::table('articles')->orderBy('libelle')->get();

        $lignes = [];
        $valeurTotale = '0.00';
        $nbCritiques = 0;

        foreach ($articles as $article) {
            $quantite = $point === null
                ? $this->stocks->stockTousPoints((string) $article->id)
                : $this->stocks->stock((string) $article->id, $point->id);

            $seuil = (string) $article->seuil_alerte;
            $critique = bccomp($quantite, $seuil, self::PRECISION) <= 0;

            if ($critique) {
                $nbCritiques++;
            }

            if ($sousSeuilUniquement && ! $critique) {
                continue;
            }

            // Valorisation au coût moyen pondéré — jamais au prix de vente :
            // un stock ne se valorise pas à la marge non réalisée.
            $valeur = bcmul($quantite, (string) $article->cout_moyen_pondere, self::PRECISION);
            $valeurTotale = bcadd($valeurTotale, $valeur, self::PRECISION);

            $lignes[] = [
                (string) $article->libelle,
                (string) $article->categorie,
                (string) $article->unite_mesure,
                $quantite,
                $seuil,
                $critique ? __('stocks.etat.sous_seuil') : __('stocks.etat.normal'),
                $valeur,
            ];
        }

        return new EtatResultat(
            kpis: [
                __('stocks.etat.kpi_references') => (string) count($lignes),
                __('stocks.etat.kpi_critiques') => (string) $nbCritiques,
                __('stocks.etat.kpi_valeur') => $valeurTotale,
            ],
            entetes: [
                __('stocks.etat.col_article'),
                __('stocks.etat.col_categorie'),
                __('stocks.etat.col_unite'),
                __('stocks.etat.col_quantite'),
                __('stocks.etat.col_seuil'),
                __('stocks.etat.col_statut'),
                __('stocks.etat.col_valeur'),
            ],
            lignes: $lignes,
            // Les filtres RÉELLEMENT appliqués, remontés tels quels : c'est ce
            // qui est archivé (EF-M14-06) et imprimé, jamais une valeur par
            // défaut muette (RESPECT_TABLEAU_RAPPORT.md, grille point 3).
            filtresAppliques: array_filter([
                'point' => $point?->libelle,
                'sous_seuil' => $sousSeuilUniquement ? 'oui' : null,
            ]),
        );
    }

    /**
     * @param  array<string, string>  $filtres
     */
    private function point(array $filtres): ?PointStockage
    {
        $id = $filtres['point_id'] ?? null;

        return filled($id) ? PointStockage::find($id) : null;
    }
}
