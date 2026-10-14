<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Models;

use App\Domain\Restaurant\Observers\PlatObserver;
use App\Domain\Stocks\Models\Article;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Attributes\ObservedBy;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Plat proposé à la carte (M4).
 *
 * ## Deux chemins de décrémentation, jamais les deux à la fois
 *
 * Le chemin normal est la **fiche technique** (EF-M4-02) : un « Poulet DG »
 * n'est pas un article de stock, c'est une recette, et sa décrémentation passe
 * par `ingredients_recette` — `DeductionStockCuisineService`.
 *
 * Le second chemin est le **lien direct** (`article_id`), pour ce qui se
 * revend en l'état : une bouteille d'eau servie à table. Le maître l'admet
 * explicitement (`carte-engine.js` l.22-26). Il exige alors le
 * conditionnement, `unites_vendables_par_unite_stock` — nombre d'unités
 * VENDABLES contenues dans une unité de stock (24 pour un pack de 24).
 *
 * `article_id` était déclaré ici depuis longtemps, avec sa relation, mais la
 * colonne n'existait dans AUCUNE migration : Eloquent lit un attribut absent
 * comme `null`, donc la relation ne ramenait jamais rien et personne ne le
 * voyait. Créée par `2026_09_01_110000_ajouter_conversion_stock_carte`.
 *
 * ## Les deux marques de prix qualifient le TARIF, pas le plat
 *
 * Même paire que `CarteBoisson`, même sens, même rendu — la carte du
 * restaurant et celle du bar sont le même écran (`carte-module.js`). Six
 * lignes de sandwicherie du maître portent `prix_corrige_main` SANS
 * `prix_provisoire` : une étiquette manuscrite a remplacé l'imprimé, et « ce
 * sont les prix MANUSCRITS qui font foi » (`referentiel-carte.js` l.14-20).
 * C'est pourquoi ce sont deux colonnes et non un seul drapeau « tarif à
 * revalider » : c'est la raison qui dit quoi faire — aller relever l'ardoise,
 * ou faire réimprimer la carte.
 *
 * ## Chaque changement de `prix_vente`/`prix_corrige_main` est tracé (01/09/2026)
 *
 * `PlatObserver` écrit une ligne dans `historique_prix_carte` à chaque
 * sauvegarde qui change réellement l'un des deux — demande du Product Owner :
 * « on doit retracer les changements de prix ». Aucune vente passée n'en
 * dépend : `VenteService` fige prix et libellé sur `lignes_vente` À LA VENTE
 * (PA-98), avant cette table, avant même la transaction.
 *
 * @property string $id
 * @property string $menu_id
 * @property string|null $recette_id
 * @property string|null $article_id
 * @property string|null $unites_vendables_par_unite_stock
 * @property string $libelle
 * @property string $prix_vente
 * @property bool $prix_provisoire
 * @property bool $prix_corrige_main
 */
#[ObservedBy(PlatObserver::class)]
class Plat extends Model
{
    use Auditable;
    use HasUuids;

    public const PAR_PAGE_DEFAUT = 50;

    public const PAR_PAGE_MAX = 200;

    protected $table = 'plats';

    protected $fillable = [
        'id', 'menu_id', 'recette_id', 'article_id',
        'unites_vendables_par_unite_stock', 'libelle', 'prix_vente', 'categorie',
        'prix_provisoire', 'prix_corrige_main',
    ];

    protected function casts(): array
    {
        return [
            'prix_vente' => 'decimal:2',
            'unites_vendables_par_unite_stock' => 'decimal:4',
            // `boolean`, jamais laissé au `tinyint(1)` brut : sans le cast,
            // `0` arrive comme la chaîne « 0 », qui est VRAIE dans un `@if`
            // Blade. La marque s'afficherait sur toute la carte.
            'prix_provisoire' => 'boolean',
            'prix_corrige_main' => 'boolean',
        ];
    }

    /**
     * Vrai quand le plat se décrémente par un article unique plutôt que par sa
     * recette. Les deux conditions comptent : un `article_id` sans
     * conditionnement ne dit pas COMBIEN sortir du stock, et sortir « une
     * unité » par défaut serait un chiffre inventé sur une donnée de stock.
     */
    public function aUnLienDirectAuStock(): bool
    {
        return $this->article_id !== null
            && $this->unites_vendables_par_unite_stock !== null;
    }

    /**
     * Quantité d'unités de STOCK consommée par une quantité de plats vendus.
     *
     * Une seule division, sur la quantité totale — voir la note jumelle de
     * `CarteBoisson::stockConsommePour()`. L'arrondi à la précision de
     * `mouvements_stock` est fait par `MouvementStockService`, point unique.
     *
     * @throws \RuntimeException si le plat n'a pas de lien direct exploitable
     */
    public function stockConsommePour(string $quantiteVendue): string
    {
        if (! $this->aUnLienDirectAuStock()) {
            throw new \RuntimeException(__('carte.conversion_absente', [
                'article' => $this->libelle,
            ]));
        }

        $unites = (string) $this->unites_vendables_par_unite_stock;

        if (bccomp($unites, '0', 4) <= 0) {
            throw new \RuntimeException(__('carte.conversion_invalide', [
                'article' => $this->libelle,
            ]));
        }

        return bcdiv($quantiteVendue, $unites, 4);
    }

    /**
     * Relation Fiche Technique / Recette composée.
     *
     * @return BelongsTo<Recette, $this>
     */
    public function recette(): BelongsTo
    {
        return $this->belongsTo(Recette::class, 'recette_id');
    }

    /**
     * Relation Menu.
     *
     * @return BelongsTo<Menu, $this>
     */
    public function menu(): BelongsTo
    {
        return $this->belongsTo(Menu::class, 'menu_id');
    }

    /**
     * Relation Article de stock unique (ex. bouteille d'eau, canette).
     *
     * @return BelongsTo<Article, $this>
     */
    public function article(): BelongsTo
    {
        return $this->belongsTo(Article::class, 'article_id');
    }
}
