<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Services;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\ReadModels\EtatStockConsolide;
use App\Domain\Stocks\ReadModels\LigneStockArticle;
use Illuminate\Database\Query\Builder as QueryBuilder;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

/**
 * Projection de LECTURE du stock — l'écran des stocks et l'état consolidé.
 *
 * @see EF-M6-01 Référentiel articles
 * @see EF-M6-03 Valorisation au coût moyen pondéré
 * @see EF-M6-05 Alerte de sous-stock par article et par point
 * @see EF-M14-02 État des stocks
 *
 * ## Ce service ne calcule aucune règle : il PROJETTE
 *
 * Aucune décision métier n'est prise ici — ni disponibilité (RG-06), ni
 * franchissement de seuil déclenchant une notification (RG-07). Ces deux-là
 * restent chez `MouvementStockService` et `VerificationSeuilService`. Ce
 * service répond à une seule question : « qu'y a-t-il en rayon, et combien ça
 * vaut », pour un écran.
 *
 * ## La convention de signe n'est PAS réécrite ici
 *
 * `StockTheoriqueService::EXPRESSION_SOLDE` est réutilisée telle quelle, à la
 * constante près. Recopier `CASE WHEN type_mouvement IN ('entree','inventaire')`
 * dans un second endroit aurait produit exactement le défaut nommé en PA-121 :
 * le jour où la convention change — un cinquième type de mouvement, par
 * exemple — la liste et la fiche afficheraient deux stocks différents pour le
 * même article, et rien ne le signalerait. Un test compare ligne à ligne cette
 * projection groupée au calcul unitaire de `StockTheoriqueService`.
 *
 * ## Pourquoi une agrégation groupée et non une boucle d'appels
 *
 * `EtatStocks` appelle `StockTheoriqueService::stock()` une fois par article :
 * sur un référentiel de 200 articles, c'est 200 requêtes pour une seule page.
 * C'est tolérable pour un PDF édité à la demande, pas pour un écran rafraîchi
 * à chaque frappe dans le champ de recherche. La jointure ci-dessous fait le
 * même calcul en **une** requête, sur l'index composite `(article_id, point_id)`
 * qui existe déjà au schéma.
 */
class ConsultationStockService
{
    private const PRECISION = 2;

    /** Filtres d'état reconnus par la liste — registre FERMÉ. */
    public const ETATS = ['rupture', 'sous_seuil'];

    /**
     * Le mode de suivi qui, seul, donne un stock à l'article.
     *
     * Écrit ici plutôt que répété : un article `journalier` n'a pas de solde à
     * comparer à un seuil, et l'inclure dans un filtre « sous seuil »
     * produirait une alerte permanente sur une marchandise achetée le matin
     * pour le service du midi (maître, `m6-stocks.html` l.148-151).
     */
    public const SUIVI_AVEC_STOCK = 'permanent';

    public const PAR_PAGE_DEFAUT = 50;

    public const PAR_PAGE_MAX = 200;

    /** Fenêtre du compteur de mouvements récents, en jours. */
    private const FENETRE_MOUVEMENTS = 30;

    public function __construct(
        private readonly StockTheoriqueService $stocks,
    ) {
    }

    /**
     * Liste paginée de l'écran Stocks — EF-M6-01.
     *
     * @param  string|null  $etat  self::ETATS, ou null
     * @param  string|null  $suivi  `Article::SUIVIS`, ou null pour « tous les suivis »
     * @return LengthAwarePaginator<int, LigneStockArticle>
     */
    public function listerArticles(
        ?string $recherche = null,
        ?string $categorie = null,
        ?string $pointId = null,
        ?string $etat = null,
        ?string $suivi = null,
        int $parPage = self::PAR_PAGE_DEFAUT,
    ): LengthAwarePaginator {
        $page = $this->requete($recherche, $categorie, $pointId, $etat, $suivi)->paginate($parPage);

        // La pagination est reconstruite autour des PROJECTIONS : ce qui sort
        // d'ici n'est jamais une collection d'entités `Article`, sans quoi un
        // appelant pourrait sérialiser le modèle — et faire ressortir
        // `solde_calcule` comme s'il s'agissait d'une colonne de la table.
        $lignes = array_map(
            fn (Article $article): LigneStockArticle => $this->projeter($article, $pointId),
            $page->items(),
        );

        return new LengthAwarePaginator(
            $lignes,
            $page->total(),
            $page->perPage(),
            $page->currentPage(),
            [
                'path' => LengthAwarePaginator::resolveCurrentPath(),
                'pageName' => 'page',
            ],
        );
    }

    /**
     * État consolidé — mêmes filtres et mêmes compteurs que `EtatStocks`,
     * qui rend le même état en PDF/CSV (RG-19).
     *
     * `recherche` et `categorie` ne sont volontairement pas acceptés : l'état
     * imprimé ne les connaît pas, et les ajouter ici ferait diverger l'écran du
     * document remis au Gérant.
     */
    public function etatConsolide(
        ?string $pointId = null,
        bool $sousSeuilUniquement = false,
        ?string $suivi = null,
    ): EtatStockConsolide {
        /** @var \Illuminate\Database\Eloquent\Collection<int, Article> $articles */
        $articles = $this->requete(null, null, $pointId, null, $suivi)->get();

        $lignes = [];
        $valeurTotale = '0.00';
        $sousSeuil = 0;
        $rupture = 0;
        $permanents = 0;
        $journaliers = 0;

        foreach ($articles as $article) {
            $ligne = $this->projeter($article, $pointId);

            // Les deux compteurs de suivi sont relevés sur TOUT le référentiel
            // de la portée, comme les alarmes : le maître les affiche en
            // détail de la carte « Références » et en carte « Gros / petit
            // stock » (l.170 et l.174), qui portent sur le référentiel.
            if ($article->estSuiviEnStock()) {
                $permanents++;
            } else {
                $journaliers++;
            }

            // Les compteurs d'alarme sont relevés AVANT le filtre d'affichage :
            // masquer les articles sains ne doit pas changer le nombre
            // d'articles à réapprovisionner. Même convention que `EtatStocks`.
            // ⚠ Un article journalier n'entre dans AUCUNE alarme : son stock
            // n'est pas tenu, donc son solde vaut zéro et il serait compté en
            // rupture à perpétuité. Le maître l'écarte de la même façon
            // (l.148-151).
            if ($article->estSuiviEnStock() && $ligne->sousSeuil) {
                $sousSeuil++;
            }

            if ($article->estSuiviEnStock() && $ligne->rupture) {
                $rupture++;
            }

            // Même écart que les alarmes ci-dessus : un article journalier ne
            // se réapprovisionne pas depuis cette liste, il s'achète le matin.
            // L'y laisser mettrait en tête des suggestions de commande une
            // marchandise dont personne ne tient le stock.
            if ($sousSeuilUniquement && ! ($article->estSuiviEnStock() && $ligne->sousSeuil)) {
                continue;
            }

            $lignes[] = $ligne;
            $valeurTotale = bcadd($valeurTotale, $ligne->valeur, self::PRECISION);
        }

        // Le libellé du point, pour que l'état DISE son filtre en clair. Si
        // l'identifiant ne correspond à rien, il est remonté tel quel plutôt
        // qu'effacé : un filtre appliqué mais illisible reste un filtre, et le
        // taire ferait passer un état partiel pour un état complet.
        $libellePoint = null;

        if ($pointId !== null) {
            $point = PointStockage::find($pointId);
            $libellePoint = $point instanceof PointStockage ? $point->libelle : $pointId;
        }

        return new EtatStockConsolide(
            lignes: $lignes,
            references: count($lignes),
            sousSeuil: $sousSeuil,
            rupture: $rupture,
            valeurTotale: $valeurTotale,
            mouvements30Jours: $this->mouvementsRecents($pointId),
            permanents: $permanents,
            journaliers: $journaliers,
            // Les filtres RÉELLEMENT appliqués, remontés tels quels : un état
            // qui ne dit pas son filtre laisse croire qu'il porte sur tout
            // (PA-119, RESPECT_TABLEAU_RAPPORT.md grille point 3).
            filtresAppliques: array_filter([
                'point' => $libellePoint,
                'sous_seuil' => $sousSeuilUniquement ? 'oui' : null,
            ], fn (?string $valeur): bool => $valeur !== null),
            arreteAu: now()->toIso8601String(),
        );
    }

    /**
     * Ventilation du stock d'un article sur TOUS les points de stockage.
     *
     * Les points sans mouvement sont rendus à `0.00`, pas omis : un point
     * absent de la liste laisserait croire que l'article ne peut pas y être
     * stocké, alors qu'il y est simplement à zéro.
     *
     * @return list<array{point: PointStockage, stock: string, valeur: string}>
     */
    public function ventilationParPoint(Article $article): array
    {
        $soldes = $this->stocks->stockParPoint($article->id);
        $cmp = (string) $article->cout_moyen_pondere;

        $ventilation = [];

        foreach (PointStockage::query()->orderBy('libelle')->orderBy('id')->get() as $point) {
            $stock = bcadd((string) $soldes->get($point->id, '0'), '0', self::PRECISION);

            $ventilation[] = [
                'point' => $point,
                'stock' => $stock,
                'valeur' => bcmul($stock, $cmp, self::PRECISION),
            ];
        }

        return $ventilation;
    }

    /**
     * Requête de base : les articles, joints à leur solde agrégé.
     *
     * @return \Illuminate\Database\Eloquent\Builder<Article>
     */
    private function requete(
        ?string $recherche,
        ?string $categorie,
        ?string $pointId,
        ?string $etat,
        ?string $suivi = null,
    ): \Illuminate\Database\Eloquent\Builder {
        $soldes = DB::table('mouvements_stock')
            ->when($pointId !== null, fn (QueryBuilder $q): QueryBuilder => $q->where('point_id', $pointId))
            ->groupBy('article_id')
            ->select([
                'article_id',
                DB::raw(StockTheoriqueService::EXPRESSION_SOLDE . ' AS solde'),
            ]);

        return Article::query()
            // Le point de rattachement est rendu sur chaque ligne du tableau :
            // sans ce chargement, vingt-cinq lignes valent vingt-cinq requêtes
            // de plus, à chaque frappe dans le champ de recherche.
            ->with('pointStockage')
            ->leftJoinSub($soldes, 'soldes', 'soldes.article_id', '=', 'articles.id')
            ->select(['articles.*', DB::raw('COALESCE(soldes.solde, 0) AS solde_calcule')])
            ->when(
                $recherche !== null && $recherche !== '',
                fn ($q) => $q->where('articles.libelle', 'like', '%' . $recherche . '%'),
            )
            ->when($categorie !== null && $categorie !== '', fn ($q) => $q->where('articles.categorie', $categorie))
            ->when($suivi !== null && $suivi !== '', fn ($q) => $q->where('articles.suivi', $suivi))
            // ⚠ Le filtre d'état écarte TOUJOURS les articles journaliers,
            // quel que soit le filtre de suivi choisi : un article dont le
            // stock n'est pas tenu a un solde de zéro, donc apparaîtrait en
            // rupture en permanence. C'est le comportement du maître
            // (`m6-stocks.html` l.148-151), et le taire ferait de la liste
            // « En rupture » une liste de faux positifs qu'on cesserait de
            // lire (PA-135).
            ->when(
                $etat === 'rupture',
                fn ($q) => $q->where('articles.suivi', self::SUIVI_AVEC_STOCK)
                    ->whereRaw('COALESCE(soldes.solde, 0) <= 0'),
            )
            ->when(
                $etat === 'sous_seuil',
                fn ($q) => $q->where('articles.suivi', self::SUIVI_AVEC_STOCK)
                    ->whereRaw('COALESCE(soldes.solde, 0) <= articles.seuil_alerte'),
            )
            ->orderBy('articles.libelle')
            // Départage STABLE : sans lui, deux articles homonymes se
            // partagent un rang indéterminé et MySQL est libre de rendre le
            // même en page 1 et en page 2 — ou aucun des deux. Un article
            // disparu d'une pagination ne se voit pas.
            ->orderBy('articles.id');
    }

    /**
     * Lève l'agrégat hors du modèle immédiatement : `solde_calcule` a beau
     * arriver comme un attribut d'`Article`, il n'en est pas un et ne doit
     * jamais ressortir comme tel (aucune colonne de stock n'existe sur
     * `articles`).
     */
    private function projeter(Article $article, ?string $pointId): LigneStockArticle
    {
        $stock = bcadd((string) $article->getAttribute('solde_calcule'), '0', self::PRECISION);
        $cmp = (string) $article->cout_moyen_pondere;

        return new LigneStockArticle(
            article: $article,
            stock: $stock,
            // Valorisation au coût moyen pondéré, jamais au prix de vente :
            // un stock ne se valorise pas à la marge non réalisée.
            valeur: bcmul($stock, $cmp, self::PRECISION),
            portee: $pointId === null
                ? LigneStockArticle::PORTEE_TOUS_POINTS
                : LigneStockArticle::PORTEE_POINT,
            pointId: $pointId,
            // `bccomp`, jamais une égalité flottante (règle projet).
            // Seuil franchi quand le stock lui est inférieur OU ÉGAL, comme
            // `VerificationSeuilService` : alerter seulement en dessous
            // laisserait passer le moment exact où le seuil est atteint.
            sousSeuil: bccomp($stock, (string) $article->seuil_alerte, self::PRECISION) <= 0,
            rupture: bccomp($stock, '0', self::PRECISION) <= 0,
        );
    }

    private function mouvementsRecents(?string $pointId): int
    {
        return DB::table('mouvements_stock')
            ->when($pointId !== null, fn (QueryBuilder $q): QueryBuilder => $q->where('point_id', $pointId))
            ->where('date_mouvement', '>=', now()->subDays(self::FENETRE_MOUVEMENTS))
            ->count();
    }
}
