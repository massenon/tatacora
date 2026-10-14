<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Services;

use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\ReadModels\CarteRestaurant;
use App\Domain\Restaurant\ReadModels\LignePlatCarte;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\StockTheoriqueService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Projection de LECTURE de la carte du restaurant — l'écran
 * `prototype_v2/pages/m4-restaurant-carte.html`.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M4-02 Fiches techniques (coût matière)
 * @see RG-05 Sortie de stock automatique
 *
 * ## Ce service ne décide rien : il projette
 *
 * Aucune règle de gestion ici. RG-05 et RG-06 restent chez
 * `DeductionStockCuisineService` et `MouvementStockService`. Ce service répond
 * à une seule question : « qu'y a-t-il à la carte, et combien de portions le
 * stock permet-il encore d'en servir ».
 *
 * ## Le stock est lu AU POINT CUISINE, jamais tous points confondus
 *
 * `DeductionStockCuisineService` sort les denrées du point de type `cuisine`.
 * Compter les portions sur le stock consolidé annoncerait des assiettes que la
 * cuisine ne peut pas produire — la marchandise étant au magasin général — et
 * la commande serait refusée au comptoir après avoir été annoncée disponible.
 * La constante du type de point est **partagée** avec le service de déduction,
 * jamais recopiée : deux définitions divergeraient au premier renommage, et
 * l'écran promettrait alors des portions puisées ailleurs que là où la cuisine
 * se sert.
 *
 * ## « Lié au stock » veut dire quelque chose de précis
 *
 * `plats.recette_id` étant NOT NULL, tout plat a une fiche technique. Ce qui
 * varie, c'est qu'elle soit **remplie** : une recette sans ligne se vend sans
 * rien décrémenter, et c'est le cas exact que `RecetteManquanteException`
 * refuse à la transmission en cuisine. L'écran le montre donc AVANT la vente,
 * plutôt que de laisser le serveur découvrir le refus devant le client.
 *
 * ## UN filtre du maître reste refusé — l'autre ne l'est plus
 *
 * `m4-restaurant-carte.html` l.75-76 propose « Retirés du jour » et « Prix
 * provisoire ».
 *
 * ⚠ **Le motif écrit ici jusqu'au 02/09/2026 — « aucune colonne du schéma ne
 * porte […] le caractère provisoire d'un prix » — a CESSÉ D'ÊTRE VRAI** avec
 * la migration `2026_09_02_200000_ajouter_marques_de_prix_carte` : `plats`
 * porte `prix_provisoire` et `prix_corrige_main`, NOT NULL, semés par le
 * référentiel de démonstration. Un motif de refus périmé transforme une
 * décision en oubli (PA-144), et c'était ici la quatrième occurrence de cette
 * phrase dans le dépôt. `provisoire` est donc un filtre RÉEL, calculé sur la
 * vraie colonne, et l'indicateur « Prix provisoires » se compte.
 *
 * « Retirés du jour » (`indisponible`), lui, reste refusé, et son motif tient
 * toujours : aucune colonne ne porte la disponibilité du jour. L'accepter en
 * l'ignorant rendrait la carte ENTIÈRE sous un intitulé qui promet le
 * contraire — c'est PA-119. Il est rejeté en validation, avec sa raison.
 */
class CarteRestaurantService
{
    /**
     * Filtres d'état RÉELLEMENT calculables — registre fermé.
     *
     * @var list<string>
     */
    public const ETATS = ['lie', 'sans_lien', 'rupture_stock', 'provisoire'];

    /**
     * Filtres d'état du maître qu'aucune colonne ne permet de calculer.
     *
     * `provisoire` en est SORTI le 02/09/2026 : voir la note de classe.
     *
     * @var list<string>
     */
    public const ETATS_SANS_SCHEMA = ['indisponible'];

    private const PRECISION_QUANTITE = 2;

    private const PRECISION_RECETTE = 3;

    public function __construct(
        private readonly CompositionRecetteService $compositions,
    ) {
    }

    /**
     * La carte entière : lignes filtrées, indicateurs et couverture sur le tout.
     *
     * Non paginée, délibérément, et pour la même raison que `/stocks/etat` :
     * la bande d'indicateurs surplombe le tableau, et un total posé au-dessus
     * d'une seule page se lirait comme le total de ce qu'on voit. Une carte de
     * restaurant se compte en dizaines de plats, pas en milliers.
     */
    public function carte(?string $recherche = null, ?string $categorie = null, ?string $etat = null): CarteRestaurant
    {
        $pointCuisine = PointStockage::query()
            ->where('type', DeductionStockCuisineService::TYPE_POINT_CUISINE)
            ->first();

        /** @var \Illuminate\Database\Eloquent\Collection<int, Plat> $plats */
        $plats = Plat::query()
            ->with(['menu', 'recette'])
            ->when(
                $recherche !== null && $recherche !== '',
                fn (Builder $q): Builder => $q->where('plats.libelle', 'like', '%' . $recherche . '%'),
            )
            ->when(
                $categorie !== null && $categorie !== '',
                fn (Builder $q): Builder => $q->whereHas('menu', fn (Builder $m): Builder => $m->where('type', $categorie)),
            )
            ->orderBy('plats.libelle')
            // Départage STABLE : deux plats homonymes se partageraient sinon un
            // rang indéterminé, et l'ordre changerait d'un appel à l'autre.
            ->orderBy('plats.id')
            ->get();

        $compositions = $this->compositionsParRecette($plats);
        $articles = $this->articles($compositions);
        $soldes = $this->soldesAuPointCuisine($pointCuisine, $articles);

        $lignes = [];

        foreach ($plats as $plat) {
            $lignes[] = $this->projeter($plat, $compositions, $articles, $soldes, $pointCuisine);
        }

        return new CarteRestaurant(
            // Les compteurs sont relevés sur TOUTES les lignes, le filtre
            // d'état ne s'applique qu'à l'affichage. Même convention que
            // `ConsultationStockService::etatConsolide()`.
            lignes: $this->filtrerParEtat($lignes, $etat),
            indicateurs: $this->indicateurs($lignes),
            couverture: $this->couverture($lignes),
            filtresAppliques: array_filter([
                'recherche' => $recherche,
                'categorie' => $categorie,
                'etat' => $etat,
            ], fn (?string $valeur): bool => $valeur !== null && $valeur !== ''),
            pointCuisineId: $pointCuisine instanceof PointStockage ? $pointCuisine->id : null,
            arreteAu: now()->toIso8601String(),
        );
    }

    /**
     * Une ligne de carte pour un plat isolé — la fiche détail.
     */
    public function ligne(Plat $plat): LignePlatCarte
    {
        $pointCuisine = PointStockage::query()
            ->where('type', DeductionStockCuisineService::TYPE_POINT_CUISINE)
            ->first();

        $plat->loadMissing(['menu', 'recette']);

        $compositions = $this->compositionsParRecette(collect([$plat]));
        $articles = $this->articles($compositions);

        return $this->projeter(
            $plat,
            $compositions,
            $articles,
            $this->soldesAuPointCuisine($pointCuisine, $articles),
            $pointCuisine,
        );
    }

    /**
     * Compositions de toutes les recettes portées par une liste de plats, en
     * UNE requête.
     *
     * Une boucle d'appels à `CompositionRecetteService::lignes()` ferait une
     * requête par plat : sur une carte de soixante plats, soixante requêtes
     * pour un écran rafraîchi à chaque frappe dans le champ de recherche.
     *
     * @param  Collection<int, Plat>  $plats
     * @return array<string, list<array{article_id: string, quantite_unitaire: string}>>
     */
    private function compositionsParRecette(Collection $plats): array
    {
        $recetteIds = $plats->pluck('recette_id')->filter()->unique()->values()->all();

        if ($recetteIds === []) {
            return [];
        }

        $compositions = [];

        $brutes = DB::table('ingredients_recette')
            ->whereIn('recette_id', $recetteIds)
            ->orderBy('article_id')
            ->get(['recette_id', 'article_id', 'quantite_unitaire']);

        foreach ($brutes as $brute) {
            $compositions[(string) $brute->recette_id][] = [
                'article_id' => (string) $brute->article_id,
                'quantite_unitaire' => bcadd((string) $brute->quantite_unitaire, '0', self::PRECISION_RECETTE),
            ];
        }

        return $compositions;
    }

    /**
     * @param  array<string, list<array{article_id: string, quantite_unitaire: string}>>  $compositions
     * @return Collection<string, Article>
     */
    private function articles(array $compositions): Collection
    {
        $ids = [];

        foreach ($compositions as $lignes) {
            foreach ($lignes as $ligne) {
                $ids[$ligne['article_id']] = true;
            }
        }

        if ($ids === []) {
            /** @var Collection<string, Article> $vide */
            $vide = collect();

            return $vide;
        }

        /** @var Collection<string, Article> $articles */
        $articles = Article::query()->whereIn('id', array_keys($ids))->get()->keyBy('id');

        return $articles;
    }

    /**
     * Soldes des ingrédients au point cuisine, en UNE agrégation.
     *
     * L'expression de signe est celle de `StockTheoriqueService`, reprise à la
     * constante près et jamais recopiée : le jour où la convention change, la
     * carte et la fiche de stock afficheraient sinon deux chiffres différents
     * pour le même article (PA-121).
     *
     * @param  Collection<string, Article>  $articles
     * @return Collection<string, string>
     */
    private function soldesAuPointCuisine(?PointStockage $point, Collection $articles): Collection
    {
        if (! $point instanceof PointStockage || $articles->isEmpty()) {
            /** @var Collection<string, string> $vide */
            $vide = collect();

            return $vide;
        }

        /** @var Collection<string, string> $soldes */
        $soldes = DB::table('mouvements_stock')
            ->where('point_id', $point->id)
            ->whereIn('article_id', $articles->keys()->all())
            ->groupBy('article_id')
            ->pluck(DB::raw(StockTheoriqueService::EXPRESSION_SOLDE . ' AS solde'), 'article_id')
            ->map(fn (mixed $solde): string => bcadd((string) $solde, '0', self::PRECISION_QUANTITE));

        return $soldes;
    }

    /**
     * @param  array<string, list<array{article_id: string, quantite_unitaire: string}>>  $compositions
     * @param  Collection<string, Article>  $articles
     * @param  Collection<string, string>  $soldes
     */
    private function projeter(
        Plat $plat,
        array $compositions,
        Collection $articles,
        Collection $soldes,
        ?PointStockage $pointCuisine,
    ): LignePlatCarte {
        $menu = $plat->menu;
        $composition = $compositions[(string) $plat->recette_id] ?? [];
        $lie = $composition !== [];

        $portions = null;
        $limitant = null;
        $sousSeuil = false;

        $motif = match (true) {
            ! $lie => LignePlatCarte::MOTIF_RECETTE_VIDE,
            ! $pointCuisine instanceof PointStockage => LignePlatCarte::MOTIF_POINT_CUISINE_ABSENT,
            default => null,
        };

        if ($motif === null) {
            [$portions, $limitant, $sousSeuil] = $this->portions($composition, $articles, $soldes);
        }

        $recette = $plat->recette;

        return new LignePlatCarte(
            plat: $plat,
            categorie: $menu instanceof Menu ? (string) $menu->type : '',
            nbIngredients: count($composition),
            lieAuStock: $lie,
            motifSansStock: $motif,
            portionsVendables: $portions,
            ingredientLimitant: $limitant,
            // Une rupture ne se déclare que si le chiffre existe : sans point
            // cuisine, `0` se lirait comme « plus rien en réserve » alors que
            // personne n'a rien consulté (Article 7 de la directive).
            rupture: $portions !== null && $portions === 0,
            sousSeuil: $sousSeuil,
            coutMatiere: $recette !== null
                ? $this->compositions->coutMatiere($recette)
                : \App\Domain\Restaurant\ReadModels\CoutMatiere::compositionVide(),
        );
    }

    /**
     * Portions encore servables : le MINIMUM sur tous les ingrédients.
     *
     * Le maillon faible commande — avoir dix kilos de riz ne sert à rien s'il
     * ne reste pas de poulet. L'ingrédient limitant est remonté avec le
     * chiffre : « 4 portions » sans dire ce qui manque n'indique pas quoi
     * racheter.
     *
     * @param  list<array{article_id: string, quantite_unitaire: string}>  $composition
     * @param  Collection<string, Article>  $articles
     * @param  Collection<string, string>  $soldes
     * @return array{0: int, 1: Article|null, 2: bool}
     */
    private function portions(array $composition, Collection $articles, Collection $soldes): array
    {
        $minimum = null;
        $limitant = null;
        $sousSeuil = false;

        foreach ($composition as $ligne) {
            $article = $articles->get($ligne['article_id']);

            if (! $article instanceof Article) {
                continue;
            }

            $stock = (string) $soldes->get($article->id, '0.00');
            $quantite = $ligne['quantite_unitaire'];

            if (bccomp($stock, (string) $article->seuil_alerte, self::PRECISION_QUANTITE) <= 0) {
                $sousSeuil = true;
            }

            // Une quantité nulle ne consomme rien : elle ne borne donc aucune
            // portion. La division serait par ailleurs impossible.
            if (bccomp($quantite, '0', self::PRECISION_RECETTE) <= 0) {
                continue;
            }

            // Stock négatif — une rupture forcée l'autorise (RG-06) : zéro
            // portion, jamais un nombre négatif de plats.
            $portions = bccomp($stock, '0', self::PRECISION_QUANTITE) <= 0
                ? 0
                : (int) bcdiv($stock, $quantite, 0);

            if ($minimum === null || $portions < $minimum) {
                $minimum = $portions;
                $limitant = $article;
            }
        }

        return [$minimum ?? 0, $limitant, $sousSeuil];
    }

    /**
     * @param  list<LignePlatCarte>  $lignes
     * @return list<LignePlatCarte>
     */
    private function filtrerParEtat(array $lignes, ?string $etat): array
    {
        if ($etat === null || $etat === '') {
            return $lignes;
        }

        return array_values(array_filter($lignes, fn (LignePlatCarte $ligne): bool => match ($etat) {
            'lie' => $ligne->lieAuStock,
            'sans_lien' => ! $ligne->lieAuStock,
            'rupture_stock' => $ligne->rupture,
            'provisoire' => $ligne->plat->prix_provisoire,
            default => true,
        }));
    }

    /**
     * @param  list<LignePlatCarte>  $lignes
     * @return array{plats: int, lies: int, sans_lien: int, taux_couverture: string|null, en_rupture: int, sous_seuil: int, cout_matiere_inconnu: int, prix_provisoires: int}
     */
    private function indicateurs(array $lignes): array
    {
        $lies = 0;
        $rupture = 0;
        $sousSeuil = 0;
        $coutInconnu = 0;
        $provisoires = 0;

        foreach ($lignes as $ligne) {
            $lies += $ligne->lieAuStock ? 1 : 0;
            $rupture += $ligne->rupture ? 1 : 0;
            $sousSeuil += $ligne->sousSeuil ? 1 : 0;
            $coutInconnu += $ligne->coutMatiere->montant === null ? 1 : 0;
            $provisoires += $ligne->plat->prix_provisoire ? 1 : 0;
        }

        $total = count($lignes);

        return [
            'plats' => $total,
            'lies' => $lies,
            'sans_lien' => $total - $lies,
            'taux_couverture' => $this->taux($lies, $total),
            'en_rupture' => $rupture,
            'sous_seuil' => $sousSeuil,
            'cout_matiere_inconnu' => $coutInconnu,
            // Compté sur la vraie colonne depuis le 02/09/2026 — jusque-là il
            // était rangé parmi les indicateurs ABSENTS, sur un motif devenu
            // faux (PA-144). C'est le chiffre qui dit combien de tarifs
            // remis à un client n'ont jamais été confrontés à l'ardoise.
            'prix_provisoires' => $provisoires,
        ];
    }

    /**
     * Couverture catégorie par catégorie — l'onglet « Couverture du stock ».
     *
     * @param  list<LignePlatCarte>  $lignes
     * @return list<array{categorie: string, plats: int, lies: int, sans_lien: int, taux: string|null}>
     */
    private function couverture(array $lignes): array
    {
        $parCategorie = [];

        foreach ($lignes as $ligne) {
            $cle = $ligne->categorie;
            $parCategorie[$cle] ??= ['plats' => 0, 'lies' => 0];
            $parCategorie[$cle]['plats']++;
            $parCategorie[$cle]['lies'] += $ligne->lieAuStock ? 1 : 0;
        }

        ksort($parCategorie);

        $couverture = [];

        foreach ($parCategorie as $categorie => $compte) {
            $couverture[] = [
                'categorie' => (string) $categorie,
                'plats' => $compte['plats'],
                'lies' => $compte['lies'],
                'sans_lien' => $compte['plats'] - $compte['lies'],
                'taux' => $this->taux($compte['lies'], $compte['plats']),
            ];
        }

        return $couverture;
    }

    /**
     * Taux de couverture en pourcentage, ou `null` sur un ensemble vide.
     *
     * `0.0` sur une carte sans plat se lirait comme « aucun plat n'est rattaché
     * au stock », donc comme un défaut à corriger, alors qu'il n'y a rien à
     * rattacher. « — » et « 0 » ne disent pas la même chose (Article 7).
     */
    private function taux(int $numerateur, int $total): ?string
    {
        if ($total === 0) {
            return null;
        }

        return bcdiv(bcmul((string) $numerateur, '100', 3), (string) $total, 1);
    }
}
