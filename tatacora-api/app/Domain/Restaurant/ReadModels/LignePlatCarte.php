<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\ReadModels;

use App\Domain\Restaurant\Models\Plat;
use App\Domain\Stocks\Models\Article;

/**
 * Un plat de la carte ET sa couverture de stock — projection de LECTURE.
 *
 * Alimente `prototype_v2/pages/m4-restaurant-carte.html` (onglets « Carte du
 * jour » et « Couverture du stock »).
 *
 * ## Rien de tout cela n'est une colonne de `plats`, et il ne faut pas en faire
 *
 * Les portions vendables se déduisent du stock des ingrédients, lui-même
 * calculé depuis `mouvements_stock`. Une colonne « stock disponible » sur
 * `plats` serait fausse dès la première vente — c'est l'anti-pattern nommé en
 * tête d'`Article` et le premier des trois défauts que `carte-module.js`
 * corrige lui-même dans le prototype.
 *
 * ## Trois motifs distincts d'absence de chiffre
 *
 * Un tiret ne dit rien s'il ne dit pas pourquoi (Article 7 de la directive de
 * conformité) :
 *
 * - `MOTIF_RECETTE_VIDE` — la fiche technique n'a aucun ingrédient. Le plat se
 *   vend sans rien décrémenter (décision du PO du 30/10/2026 : il était
 *   auparavant refusé au comptoir) : l'écran le dit, pour que personne ne lise
 *   un tiret comme un stock suivi.
 * - `MOTIF_POINT_CUISINE_ABSENT` — aucun point de stockage de type `cuisine`
 *   n'existe. On ne sait pas d'où sortiraient les denrées, donc on ne sait pas
 *   combien il en reste.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M4-02 Fiches techniques
 * @see RG-05 Sortie de stock automatique
 */
final readonly class LignePlatCarte
{
    public const MOTIF_RECETTE_VIDE = 'recette_sans_ingredient';

    public const MOTIF_POINT_CUISINE_ABSENT = 'point_cuisine_absent';

    /**
     * @param  string  $categorie  type du menu porteur (`local`, `europeen`, `special`)
     * @param  int|null  $portionsVendables  null si non calculable — voir MOTIF_*
     * @param  Article|null  $ingredientLimitant  l'ingrédient qui borne le nombre de portions
     */
    public function __construct(
        public Plat $plat,
        public string $categorie,
        public int $nbIngredients,
        public bool $lieAuStock,
        public ?string $motifSansStock,
        public ?int $portionsVendables,
        public ?Article $ingredientLimitant,
        public bool $rupture,
        public bool $sousSeuil,
        public CoutMatiere $coutMatiere,
    ) {
    }

    /**
     * Marge brute unitaire, ou `null` si le coût matière est inconnu.
     */
    public function marge(): ?string
    {
        return $this->coutMatiere->marge((string) $this->plat->prix_vente);
    }
}
