<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Services;

use App\Domain\Restaurant\Models\Plat;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Domain\Stocks\Services\ReferentielPointStockageService;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Le RAPPROCHEMENT des plats et du stock de la cuisine (PO, 09/11/2026).
 *
 * ## Le défaut
 *
 * Après l'import des trois modèles, les 81 plats affichaient « Article de
 * stock » vide, « Stock vendable : non suivi », « Réserve — » et la modale
 * « Lier au stock » ne proposait rien d'utile. Au bar, la boisson est reliée
 * parce que `cartes_boisson.article_id` est NOT NULL ; un plat n'a aucun lien
 * obligatoire, et l'import m4 ne posait aucun lien ni aucun article de cuisine.
 *
 * ## La doctrine (la même que celle du bar)
 *
 * Un plat vendu EN L'ÉTAT se relie à l'article de stock DE MÊME NOM, au point
 * « Cuisine » (suivi permanent, une unité vendable par unité de stock, SOLDE
 * À ZÉRO tant qu'aucune entrée n'a été saisie). Un plat décomposé en
 * INGRÉDIENTS (fiche technique non vide) garde sa fiche : il n'est JAMAIS relié
 * ici. Aucune donnée n'est inventée : ni prix, ni quantité, ni ingrédient.
 *
 * ## Ce que le service ne fait jamais
 *
 *  - remplacer un lien existant (posé à la main ou par un passage précédent) ;
 *  - écrire un prix ou un mouvement de stock ;
 *  - rapprocher à un article du bar ou du magasin : seuls les articles du point
 *    cuisine, ou sans point, sont candidats, et jamais un article déjà vendu par
 *    une boisson ou un autre plat ;
 *  - créer un doublon : un article de même nom (sans casse ni accents) est
 *    repris, un nouveau n'est créé qu'à défaut.
 *
 * IDEMPOTENT : un second passage ne trouve plus aucun plat à relier.
 *
 * @see RG-05 Sortie de stock automatique
 * @see EF-M4-02 Fiches techniques
 */
class RapprochementPlatsStockService
{
    public const LIBELLE_POINT = 'Cuisine';

    public const TYPE_POINT = 'cuisine';

    /** Une assiette vendue = une unité de stock : la seule valeur qui n'invente rien. */
    public const CONVERSION = '1';

    /**
     * @param  iterable<Plat>|null  $plats  les plats à examiner — tous quand `null`
     * @param  bool  $creerLesArticles  `true` : rattrapage (crée les articles manquants) ;
     *                                  `false` : import m4 (ne relie qu'à un article déjà là)
     * @param  array<string, array{point_id?: string|null, seuil?: string|null, valeur?: string|null}>  $parametres
     *                                                                                                              par identifiant de plat (colonnes « Point Stock », « Seuil », « Valeur d'achat » du modèle m4) :
     *                                                                                                              appliqués à l'article CRÉÉ ; sur un article existant, seuls les champs VIDES sont complétés
     * @return array{rapproches: int, articles_crees: int, deja_lies: int, avec_fiche: int, sans_article: int, point_cree: bool, examines: int}
     */
    public function rapprocher(?iterable $plats = null, bool $creerLesArticles = true, array $parametres = []): array
    {
        $plats = $plats === null
            ? Plat::query()->orderBy('libelle')->get()
            : collect($plats);

        return DB::transaction(function () use ($plats, $creerLesArticles, $parametres): array {
            $bilan = ['rapproches' => 0, 'articles_crees' => 0, 'deja_lies' => 0, 'avec_fiche' => 0, 'sans_article' => 0, 'point_cree' => false, 'examines' => $plats->count()];

            $point = $this->pointCuisine();
            $articles = $this->candidats($point, array_values(array_filter(array_map(
                static fn (array $p): ?string => $p['point_id'] ?? null,
                $parametres,
            ))));
            $dejaPris = $this->articlesDejaVendus();

            foreach ($plats as $plat) {
                if ($plat->aUnLienDirectAuStock()) {
                    $bilan['deja_lies']++;

                    continue;
                }

                if ($this->aUneFicheComposee($plat)) {
                    $bilan['avec_fiche']++;

                    continue;
                }

                $cle = self::cle((string) $plat->libelle);
                $article = $articles->get($cle);

                if ($article === null || isset($dejaPris[$article->id])) {
                    if (! $creerLesArticles) {
                        $bilan['sans_article']++;

                        continue;
                    }

                    if ($point === null) {
                        $point = $this->creerPointCuisine();
                        $bilan['point_cree'] = true;
                    }

                    $voulu = $parametres[(string) $plat->id] ?? [];
                    $article = app(ReferentielArticleService::class)->creer([
                        'libelle' => $plat->libelle,
                        'categorie' => 'Denrées',
                        'unite_mesure' => 'unité',
                        'seuil_alerte' => $voulu['seuil'] ?? '0',
                        'suivi' => 'permanent',
                        'point_stockage_id' => $voulu['point_id'] ?? $point->id,
                    ]);
                    $articles->put($cle, $article);
                    $bilan['articles_crees']++;
                }

                // Un article repris : seuls ses champs VIDES sont complétés.
                $voulu = $parametres[(string) $plat->id] ?? [];
                app(ReferentielArticleService::class)->completer($article, $voulu['point_id'] ?? null, $voulu['valeur'] ?? null);

                app(CartePlatMenuService::class)->lierAuStock($plat, (string) $article->id, self::CONVERSION);
                $dejaPris[$article->id] = true;
                $bilan['rapproches']++;
            }

            return $bilan;
        });
    }

    /** Le point cuisine, ou `null` quand le Gîte n'en a déclaré aucun. */
    private function pointCuisine(): ?PointStockage
    {
        return PointStockage::query()
            ->whereIn('type', [self::TYPE_POINT, 'restaurant'])
            ->orderBy('libelle')
            ->first();
    }

    /**
     * Le point « Cuisine », créé par le chemin du domaine (audit RG-15) quand
     * aucun n'existe : sans lui, « Stock vendable » resterait « non consulté ».
     */
    public function assurerLePointCuisine(): PointStockage
    {
        return $this->pointCuisine() ?? $this->creerPointCuisine();
    }

    private function creerPointCuisine(): PointStockage
    {
        return app(ReferentielPointStockageService::class)->creer([
            'libelle' => self::LIBELLE_POINT,
            'type' => self::TYPE_POINT,
        ]);
    }

    /**
     * Les articles qu'un plat peut reprendre, par nom normalisé : permanents,
     * actifs, au point cuisine ou sans point. Au point cuisine d'abord.
     *
     * @param  list<string>  $autresPoints  points nommés par le fichier (colonne « Point Stock »)
     * @return Collection<string, Article>
     */
    private function candidats(?PointStockage $point, array $autresPoints = []): Collection
    {
        $points = array_values(array_unique(array_filter([$point?->id, ...$autresPoints])));

        $requete = Article::query()
            ->where('suivi', 'permanent')
            ->where('actif', true)
            ->where(function ($q) use ($points): void {
                $q->whereNull('point_stockage_id');

                if ($points !== []) {
                    $q->orWhereIn('point_stockage_id', $points);
                }
            })
            ->orderBy('libelle');

        $par = new Collection();

        foreach ($requete->get() as $article) {
            $cle = self::cle((string) $article->libelle);
            $actuel = $par->get($cle);

            // Un article du point cuisine l'emporte sur un article sans point.
            if ($actuel === null || ($point !== null && $article->point_stockage_id === $point->id && $actuel->point_stockage_id !== $point->id)) {
                $par->put($cle, $article);
            }
        }

        return $par;
    }

    /**
     * @return array<string, true> articles déjà vendus par une boisson ou un plat
     */
    private function articlesDejaVendus(): array
    {
        $ids = DB::table('cartes_boisson')->whereNotNull('article_id')->pluck('article_id')
            ->merge(DB::table('plats')->whereNotNull('article_id')->pluck('article_id'));

        return $ids->mapWithKeys(static fn ($id): array => [(string) $id => true])->all();
    }

    private function aUneFicheComposee(Plat $plat): bool
    {
        return DB::table('ingredients_recette')->where('recette_id', $plat->recette_id)->exists();
    }

    /** La clé de comparaison des noms : sans casse ni accents (comme le bar). */
    public static function cle(string $nom): string
    {
        $translit = transliterator_transliterate('NFD; [:Nonspacing Mark:] Remove; NFC; Lower()', trim($nom));

        return preg_replace('/\s+/u', ' ', is_string($translit) ? $translit : mb_strtolower(trim($nom))) ?? $nom;
    }

    /** La phrase du bilan, partagée par l'import, le bouton et la commande. */
    public static function phrase(array $bilan): string
    {
        $morceaux = [trans_choice('imports.rapprochement.rapproches', $bilan['rapproches'], ['nombre' => $bilan['rapproches']])];

        if ($bilan['articles_crees'] > 0) {
            $morceaux[] = trans_choice('imports.rapprochement.crees', $bilan['articles_crees'], ['nombre' => $bilan['articles_crees']]);
        }

        if ($bilan['deja_lies'] > 0) {
            $morceaux[] = __('imports.rapprochement.deja_lies', ['nombre' => $bilan['deja_lies']]);
        }

        if ($bilan['avec_fiche'] > 0) {
            $morceaux[] = __('imports.rapprochement.avec_fiche', ['nombre' => $bilan['avec_fiche']]);
        }

        if ($bilan['sans_article'] > 0) {
            $morceaux[] = __('imports.rapprochement.sans_article', ['nombre' => $bilan['sans_article']]);
        }

        return implode(' ', $morceaux);
    }
}
