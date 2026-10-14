<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Controllers;

use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Domain\Stocks\Http\Requests\ConsulterEtatStockRequest;
use App\Domain\Stocks\Http\Requests\ConsulterFicheStockRequest;
use App\Domain\Stocks\Http\Requests\EnregistrerArticleRequest;
use App\Domain\Stocks\Http\Requests\EnregistrerMouvementRequest;
use App\Domain\Stocks\Http\Requests\FiltrerArticlesRequest;
use App\Domain\Stocks\Http\Requests\FiltrerMouvementsRequest;
use App\Domain\Stocks\Http\Resources\ArticleStockResource;
use App\Domain\Stocks\Http\Resources\ArticleVentilationResource;
use App\Domain\Stocks\Http\Resources\EtatStockResource;
use App\Domain\Stocks\Http\Resources\FicheStockResource;
use App\Domain\Stocks\Http\Resources\MouvementStockResource;
use App\Domain\Stocks\Http\Resources\PointStockageResource;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ConsultationStockService;
use App\Domain\Stocks\Services\FicheStockService;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\ReferentielArticleService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * API du module M6 — Gestion des stocks.
 *
 * @see EF-M6-01 Référentiel articles
 * @see EF-M6-02 Entrées et sorties
 * @see EF-M6-03 Valorisation au coût moyen pondéré
 * @see EF-M6-04 Fiche de stock et historique
 * @see EF-M6-05 Alerte de sous-stock par article et par point
 * @see EF-M6-06 Traçabilité intégrale
 *
 * ## Simple orchestrateur (06_DEVELOPMENT_STANDARDS.md §2.2)
 *
 * Aucune règle de gestion n'est écrite ici. Les écritures passent **toutes**
 * par `MouvementStockService`, unique point d'entrée sur `mouvements_stock` :
 * une insertion directe contournerait à la fois le contrôle de disponibilité
 * (RG-06), le verrou pessimiste qui empêche deux ventes simultanées de faire
 * passer le stock à négatif, et la vérification de seuil synchrone (RG-07) —
 * sans lever la moindre erreur.
 *
 * ## Aucune route de suppression, et aucune de modification de mouvement
 *
 * `mouvements_stock` est en ajout seul : un mouvement erroné se corrige par un
 * mouvement inverse, jamais par une réécriture. Un `DELETE` sur ces URL rend
 * donc 405 — le verbe n'est routé nulle part, ce qui est la seule preuve
 * solide qu'il n'existe pas (`MouvementStockPolicy` le refuse aussi, en second
 * niveau).
 */
class StockController
{
    public function __construct(
        private readonly ConsultationStockService $consultation,
        private readonly MouvementStockService $mouvements,
        private readonly FicheStockService $fiches,
        private readonly ReferentielArticleService $referentiel,
    ) {
    }

    /**
     * Liste des articles avec leur stock calculé — l'écran Stocks.
     *
     * Ce que le client en fait : il affiche le tableau principal de
     * `m6-stocks.html` (article, catégorie, stock, seuil, CMP, valeur) et ses
     * quatre filtres. Le stock arrive **déjà calculé** ; le client ne le
     * recalcule pas et ne le soumet jamais.
     */
    public function articles(FiltrerArticlesRequest $request): AnonymousResourceCollection
    {
        return ArticleStockResource::collection(
            $this->consultation->listerArticles(
                recherche: $request->filtre('recherche'),
                categorie: $request->filtre('categorie'),
                pointId: $request->filtre('point_id'),
                etat: $request->filtre('etat'),
                suivi: $request->filtre('suivi'),
                parPage: $request->parPage(),
            ),
        );
    }

    /**
     * Fiche signalétique d'un article et ventilation de son stock point par
     * point — c'est la réponse à « où est la marchandise », que le total seul
     * ne donne pas.
     */
    public function article(Article $article): ArticleVentilationResource
    {
        return new ArticleVentilationResource($this->ventilation($article));
    }

    /**
     * Création d'un article au référentiel — EF-M6-01.
     *
     * L'article naît sans stock : la seule façon d'en poser est un mouvement
     * `entree` daté et motivé (voir `EnregistrerArticleRequest`).
     */
    public function creerArticle(EnregistrerArticleRequest $request): JsonResponse
    {
        // La relecture après création (défaut de base sur le coût moyen
        // pondéré) vit dans le service, commun à l'API et à la PWA (PA-159).
        $article = $this->referentiel->creer($request->validated());

        return (new ArticleVentilationResource($this->ventilation($article)))
            ->response()
            ->setStatusCode(201);
    }

    /**
     * Modification d'un article — libellé, catégorie, unité, seuils.
     *
     * Ni le stock ni le coût moyen pondéré ne peuvent être touchés par cette
     * route : ce sont des calculs, pas des champs.
     */
    public function modifierArticle(EnregistrerArticleRequest $request, Article $article): ArticleVentilationResource
    {
        return new ArticleVentilationResource(
            $this->ventilation($this->referentiel->modifier($article, $request->validated())),
        );
    }

    /**
     * Référentiel des points de stockage — magasin, cuisine, bar, garage.
     *
     * Ce que le client en fait : il remplit le sélecteur « Point de stockage »
     * de tout formulaire de mouvement, et le filtre de la liste. **Aucune
     * pagination** : le Gîte en compte une poignée, et le client en a besoin
     * ENTIER — un point resté sur une page non demandée n'apparaîtrait pas au
     * sélecteur, et le mouvement serait imputé au mauvais endroit. L'erreur ne
     * se verrait qu'à l'inventaire.
     */
    public function points(): AnonymousResourceCollection
    {
        return PointStockageResource::collection(
            PointStockage::query()->orderBy('libelle')->orderBy('id')->get(),
        );
    }

    /**
     * État des stocks consolidé — EF-M14-02.
     *
     * Ce que le client en fait : la bande de KPI de l'écran Stocks, et le
     * tableau qu'il exporte. **Aucune pagination non plus**, mais pour une
     * autre raison que les points : les compteurs sont des totaux sur
     * l'ensemble filtré. Servir une page de lignes sous un total calculé sur
     * tout afficherait deux vérités sur le même écran.
     */
    public function etat(ConsulterEtatStockRequest $request): EtatStockResource
    {
        return new EtatStockResource(
            $this->consultation->etatConsolide(
                pointId: $request->pointId(),
                sousSeuilUniquement: $request->boolean('sous_seuil'),
            ),
        );
    }

    /**
     * Fiche de stock d'un article sur une période — EF-M6-04.
     *
     * Ce que le client en fait : l'onglet « Fiche de stock » de
     * `m6-inventaires.html`. C'est le seul document qui justifie un solde
     * (initial + entrées − sorties − pertes ± régularisations), et il porte un
     * drapeau `coherent` que le client doit afficher : à `false`, un mouvement
     * a été écrit hors du service dédié et la fiche ne vaut pas justificatif.
     */
    public function fiche(ConsulterFicheStockRequest $request, Article $article): FicheStockResource
    {
        $pointId = $request->pointId();

        return new FicheStockResource([
            'fiche' => $this->fiches->pourArticle(
                $article,
                (string) $request->input('debut'),
                (string) $request->input('fin'),
                $pointId,
            ),
            'point_id' => $pointId,
        ]);
    }

    /**
     * Journal des mouvements — EF-M6-04, EF-M6-06.
     *
     * Ce que le client en fait : l'historique « qui, quoi, quand, pourquoi »
     * d'un article ou d'un point. Paginé, et **sans danger** : c'est un journal
     * qu'on parcourt, jamais une base de calcul. Le stock, lui, ne se
     * reconstitue pas côté client à partir de ces pages — il arrive calculé
     * par `/stocks/articles` et `/stocks/etat`. Une page manquante ferait donc
     * un trou dans une consultation, jamais un chiffre faux.
     */
    public function mouvements(FiltrerMouvementsRequest $request): AnonymousResourceCollection
    {
        $requete = MouvementStock::query()
            ->with(['article:id,libelle,unite_mesure', 'point:id,libelle', 'utilisateur:id,login'])
            ->when(
                $request->filtre('article_id'),
                fn (Builder $q, string $id): Builder => $q->where('article_id', $id),
            )
            ->when(
                $request->filtre('point_id'),
                fn (Builder $q, string $id): Builder => $q->where('point_id', $id),
            )
            ->when(
                $request->filtre('type_mouvement'),
                fn (Builder $q, string $type): Builder => $q->where('type_mouvement', $type),
            )
            ->when(
                $request->filtre('date_debut'),
                fn (Builder $q, string $date): Builder => $q->where('date_mouvement', '>=', $date . ' 00:00:00'),
            )
            ->when(
                $request->filtre('date_fin'),
                fn (Builder $q, string $date): Builder => $q->where('date_mouvement', '<=', $date . ' 23:59:59'),
            )
            // Le plus récent d'abord — c'est ce qu'on vient vérifier. Le
            // départage par `id` rend la pagination déterministe : plusieurs
            // mouvements partagent la même seconde dès qu'une vente en génère
            // deux, et un ordre indéterminé ferait apparaître ou disparaître
            // une ligne entre deux pages.
            ->orderByDesc('date_mouvement')
            ->orderByDesc('id');

        return MouvementStockResource::collection($requete->paginate($request->parPage()));
    }

    /**
     * Enregistrement d'un mouvement — EF-M6-02.
     *
     * Ce que le client en fait : la modale « Mouvement de stock » de
     * `m6-stocks.html` (entrée, sortie, perte).
     *
     * Une rupture rend **422 avec `necessite_validation_rupture`**, jamais un
     * 500 : RG-06 veut que la rupture soit une demande de confirmation adressée
     * à un utilisateur habilité, pas une erreur définitive. Le client réaffiche
     * la même requête avec `validation_rupture`, et le forçage laisse alors une
     * trace nominative au journal d'audit — une rupture assumée est une
     * décision de gestion, elle doit être imputable.
     */
    public function enregistrerMouvement(EnregistrerMouvementRequest $request): JsonResponse
    {
        $valide = $request->validated();
        $quantite = (string) $valide['quantite'];
        // `isset` couvre le champ absent ET le champ envoyé à `null` : le
        // second est le cas nominal d'un transfert entre points, qui ne
        // revalorise rien.
        $cout = isset($valide['cout_unitaire']) ? (string) $valide['cout_unitaire'] : null;
        $forcage = (bool) ($valide['validation_rupture'] ?? false);

        try {
            $mouvement = match ($valide['type_mouvement']) {
                'entree' => $this->mouvements->entree(
                    articleId: $valide['article_id'],
                    pointId: $valide['point_id'],
                    quantite: $quantite,
                    motif: $valide['motif'],
                    coutUnitaire: $cout,
                ),
                'perte' => $this->mouvements->perte(
                    articleId: $valide['article_id'],
                    pointId: $valide['point_id'],
                    quantite: $quantite,
                    motif: $valide['motif'],
                    validationRupture: $forcage,
                ),
                default => $this->mouvements->sortie(
                    articleId: $valide['article_id'],
                    pointId: $valide['point_id'],
                    quantite: $quantite,
                    motif: $valide['motif'],
                    validationRupture: $forcage,
                ),
            };
        } catch (RuptureStockException $e) {
            return response()->json($e->versReponse(), 422);
        }

        return (new MouvementStockResource($mouvement->load(['article', 'point'])))
            ->response()
            ->setStatusCode(201);
    }

    /**
     * @return array{
     *     article: Article,
     *     ventilation: list<array{point: PointStockage, stock: string, valeur: string}>,
     *     stock_total: string,
     *     valeur_totale: string
     * }
     */
    private function ventilation(Article $article): array
    {
        $ventilation = $this->consultation->ventilationParPoint($article);

        $total = '0.00';
        $valeur = '0.00';

        foreach ($ventilation as $ligne) {
            $total = bcadd($total, $ligne['stock'], 2);
            $valeur = bcadd($valeur, $ligne['valeur'], 2);
        }

        return [
            'article' => $article,
            'ventilation' => $ventilation,
            'stock_total' => $total,
            'valeur_totale' => $valeur,
        ];
    }
}
