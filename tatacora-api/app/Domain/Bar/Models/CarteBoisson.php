<?php

declare(strict_types=1);

namespace App\Domain\Bar\Models;

use App\Domain\Bar\Observers\CarteBoissonObserver;
use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Stocks\Models\Article;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Attributes\ObservedBy;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

/**
 * Boisson proposee a la carte du bar (M5).
 *
 * **Aucune colonne de stock, et il ne faut jamais en ajouter.** Le prototype
 * affichait un champ « Stock disponible » EDITABLE sur la fiche boisson
 * (PA-24) : porte tel quel, une vente ne l'aurait jamais decremente et le
 * chiffre affiche serait reste faux indefiniment. Le schema interdit deja cet
 * anti-pattern — la table n'a pas la colonne. Le stock reel se lit via
 * StockTheoriqueService sur l'article lie.
 *
 * `article_id` est NOT NULL : une boisson vendue au bar est toujours un
 * article du referentiel Stocks, jamais une designation libre. C'est ce lien
 * qui rend RG-05 applicable sans fiche technique.
 *
 * ## Le « 1 pour 1 » n'etait vrai que par defaut d'information
 *
 * Jusqu'au 31/08/2026, une vente sortait une unite de stock par unite vendue.
 * C'est juste pour une bouteille achetee a l'unite, et faux d'un facteur 24
 * pour une bouteille tiree d'un casier. La modale « Lier au stock » demandait
 * pourtant deja le conditionnement, en champ obligatoire — et jetait la
 * reponse. `unites_vendables_par_unite_stock` la conserve.
 *
 * **Sens de la colonne** : le nombre d'unites VENDABLES contenues dans une
 * unite de stock (24 pour un casier de 24). La deduction vaut donc
 * `quantite_vendue / unites_vendables_par_unite_stock`. Le maitre avertit que
 * se tromper de sens « vide le stock 24 fois trop vite, ou 24 fois trop
 * lentement » (`carte-engine.js` l.119-126) : le nom porte le sens pour que
 * l'inversion ne puisse pas se glisser a la lecture.
 *
 * ## Les deux marques de prix qualifient le TARIF, pas la boisson
 *
 * `prix_provisoire` dit que le montant a ete POSE faute de releve — six
 * boissons du maitre sont dans ce cas, et « ce sont des prix de vente
 * INVENTES : ils sont appliques a de vrais clients a chaque service »
 * (`referentiel-carte.js` l.22-31). `prix_corrige_main` dit que le tarif
 * imprime a ete remplace a la main, donc que la carte est instable.
 *
 * Les deux se rendent A COTE DU PRIX, y compris sur la fiche des prix remise
 * au client : un prix provisoire imprime sans sa marque devient un tarif ferme
 * (PA-161 (b)). Elles n'ont AUCUN effet sur la vente — le point de vente
 * encaisse, c'est le comportement demande ; elles disent seulement ce qui
 * reste a confronter a l'ardoise.
 *
 * ## Chaque changement de `prix_vente`/`prix_corrige_main` est tracé (01/09/2026)
 *
 * `CarteBoissonObserver` écrit une ligne dans `historique_prix_carte` à
 * chaque sauvegarde qui change réellement l'un des deux — demande du Product
 * Owner : « on doit retracer les changements de prix ». Aucune vente passée
 * n'en dépend : `VenteService` fige prix et libellé sur `lignes_vente` À LA
 * VENTE (PA-98), avant cette table, avant même la transaction.
 *
 * @property string $id
 * @property string $article_id
 * @property string $unites_vendables_par_unite_stock
 * @property string $libelle
 * @property string $categorie
 * @property string $prix_vente
 * @property bool $prix_provisoire
 * @property bool $prix_corrige_main
 */
#[ObservedBy(CarteBoissonObserver::class)]
class CarteBoisson extends Model
{
    use Auditable;
    use HasUuids;

    /**
     * Les libellés français de l'`enum` `categorie` — SOURCE UNIQUE, lue par
     * `CarteBar` (fiche de la carte) et `ComposePanier` (chips du point de
     * vente, PA du 02/09/2026 : les deux écrans rendaient le code brut de
     * l'enum — « locale », « maison », « importee » — au lieu de son
     * libellé, POS et Carte du bar auraient fini par diverger sur ce
     * qu'affiche la même colonne.
     *
     * @var array<string, string>
     */
    public const CATEGORIES = [
        'locale' => 'Locale',
        'maison' => 'Maison',
        'importee' => 'Importée',
    ];

    protected $table = 'cartes_boisson';

    protected $fillable = [
        'id', 'article_id', 'unites_vendables_par_unite_stock',
        'libelle', 'categorie', 'prix_vente',
        'prix_provisoire', 'prix_corrige_main',
    ];

    protected function casts(): array
    {
        return [
            'prix_vente' => 'decimal:2',
            // Quatre decimales : un conditionnement se compte en entier, mais
            // la conversion inverse (1/24 = 0,0417) a besoin de la place.
            'unites_vendables_par_unite_stock' => 'decimal:4',
            // `boolean`, jamais laisse au `tinyint(1)` brut : sans le cast,
            // `0` arrive comme la chaine « 0 », qui est VRAIE dans un `@if`
            // Blade. La marque s'afficherait sur toute la carte.
            'prix_provisoire' => 'boolean',
            'prix_corrige_main' => 'boolean',
        ];
    }

    /**
     * Quantite d'unites de STOCK consommee par une quantite vendue.
     *
     * Une seule division, sur la quantite totale : `24 / 24 = 1,0000`. Passer
     * par le facteur unitaire (`1/24 = 0,0417`) puis multiplier donnerait
     * 1,0008 pour un casier entier — un residu qui n'existe pas.
     *
     * Rendu en chaine au dix-milliemme, jamais en flottant : c'est un facteur
     * de mouvement de stock, soumis a la meme regle que les montants
     * (`bccomp`/`bcdiv`, jamais une egalite flottante). L'arrondi a la
     * precision de la colonne est fait par `MouvementStockService`, point
     * unique.
     */
    public function stockConsommePour(string $quantiteVendue): string
    {
        $unites = (string) $this->unites_vendables_par_unite_stock;

        if (bccomp($unites, '0', 4) <= 0) {
            // Le schema pose NOT NULL DEFAULT 1 et le service refuse zero :
            // ce cas ne peut venir que d'une ecriture directe en base. Il est
            // nomme plutot que divise par zero.
            throw new \RuntimeException(__('carte.conversion_invalide', [
                'article' => $this->libelle,
            ]));
        }

        return bcdiv($quantiteVendue, $unites, 4);
    }

    /**
     * @return BelongsTo<Article, $this>
     */
    public function article(): BelongsTo
    {
        return $this->belongsTo(Article::class, 'article_id');
    }

    /**
     * L'indisponibilité EN COURS de la boisson — celle que rien n'a levée —,
     * ou aucune.
     *
     * Lecture seule : l'écriture passe exclusivement par
     * `DisponibiliteCarteService`, sous verrou. Déclarée ici pour que l'API
     * la charge en UNE requête sur toute une page de carte (`with()`), là où
     * un appel au service par ligne ferait N+1 — même raison que
     * `DisponibiliteCarteService::indisponibilitesEnCours()` pour la PWA.
     *
     * @return HasOne<IndisponibiliteCarte, $this>
     */
    public function indisponibiliteEnCours(): HasOne
    {
        return $this->hasOne(IndisponibiliteCarte::class, 'boisson_id')
            ->whereNull('date_retour_disponibilite');
    }
}
