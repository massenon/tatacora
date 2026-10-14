<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Models;

use App\Domain\Stocks\Models\Article;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Fiche technique de fabrication d'un plat (M4).
 *
 * C'est elle qui rend RG-05 possible : sans nomenclature reliant un plat aux
 * articles qu'il consomme, une vente ne peut pas decrementer quoi que ce soit.
 *
 * @property string $id
 * @property string $libelle
 * @property string $cout_matiere_calcule
 * @property bool $composition_provisoire
 */
class Recette extends Model
{
    use Auditable;
    use HasUuids;

    /**
     * La marque « composition provisoire » — 04/09/2026.
     *
     * Les grammages viennent du referentiel de demonstration, ils sont
     * PLAUSIBLES et NON RELEVES : la fiche decremente donc un stock reel sur
     * une quantite que personne n'a pesee. Nommee ici plutot qu'ecrite en
     * litteral aux quatre endroits qui la lisent (service, seeder, ecran,
     * point de vente) — un litteral recopie est ce que ce depot appelle un
     * second auteur.
     *
     * ⚠ C'est un FAIT, pas une case a cocher : la marque tombe des que la
     * composition est enregistree (`CompositionRecetteService`). Meme
     * raisonnement que `MarquesDePrix::CORRIGE_MAIN`.
     */
    public const PROVISOIRE = 'composition_provisoire';

    public const PAR_PAGE_DEFAUT = 50;

    public const PAR_PAGE_MAX = 200;

    protected $table = 'recettes';

    protected $fillable = ['id', 'libelle', 'cout_matiere_calcule', self::PROVISOIRE];

    protected function casts(): array
    {
        return [
            'cout_matiere_calcule' => 'decimal:2',
            self::PROVISOIRE => 'boolean',
        ];
    }

    /**
     * Ingredients : de VRAIES cles etrangeres vers `articles`, jamais un champ
     * texte libre. Le prototype affichait « Ingredients principaux » en texte
     * saisi — porte tel quel, aucune decrementation de stock n'aurait ete
     * possible, et la fiche technique n'aurait servi a rien
     * (SPEC_ECRAN_M4_RESTAURANT.md, PA-23).
     *
     * @return BelongsToMany<Article, $this>
     */
    public function ingredients(): BelongsToMany
    {
        return $this->belongsToMany(Article::class, 'ingredients_recette', 'recette_id', 'article_id')
            ->withPivot('quantite_unitaire');
    }

    /**
     * Cette fiche fait-elle REELLEMENT bouger un stock ? — 04/09/2026.
     *
     * Trois etats, pas deux : une fiche peut etre VIDE (aucune ligne, la vente
     * est refusee), COMPOSEE ET SUIVIE (au moins un ingredient dont le stock
     * est tenu), ou COMPOSEE SANS SUIVI — toutes ses lignes portent des
     * articles `journalier`, achetes et consommes le jour meme, qui n'entrent
     * ni dans les mouvements ni dans l'inventaire (`Article::estSuiviEnStock`).
     *
     * Le troisieme cas est la verite d'une salade verte : laitue, tomate,
     * oignon, concombre — la carte les nomme, aucun n'est inventorie. La vente
     * passe et rien ne bouge, ce qui est correct. Mais rendu comme
     * « Composee » sans plus, cela se lirait comme une fiche qui decremente,
     * alors qu'elle ne decremente rien : l'ecran doit le dire, sans quoi ce
     * serait un indicateur qui affirme un etat qu'il n'a pas verifie
     * (PA-59/60/61).
     *
     * ⚠ Suppose `ingredients` charge (`with('ingredients')`) : appele par
     * ligne sur une liste paginee, il ferait sinon N+1.
     */
    public function decrementeUnStockSuivi(): bool
    {
        return $this->ingredients->contains(
            static fn (Article $article): bool => $article->estSuiviEnStock(),
        );
    }

    /**
     * Les plats qui se decrementent par cette fiche — 04/09/2026.
     *
     * L'ecran « Fiches techniques » nomme le plat concerne sur chaque ligne, et
     * c'est ce qui rend une fiche vide actionnable : « Recette a ecrire » ne
     * dit rien, « Recette a ecrire — Salade nue » dit quelle vente est
     * bloquee. `plats.recette_id` est NOT NULL, mais la relation reste un
     * `hasMany` : rien n'interdit a deux plats de partager une fiche, et c'est
     * le cas dans le jeu de demonstration.
     *
     * @return HasMany<Plat, $this>
     */
    public function plats(): HasMany
    {
        return $this->hasMany(Plat::class, 'recette_id');
    }
}
