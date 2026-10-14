<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Resources;

use App\Domain\Carte\MarquesDePrix;
use App\Domain\Restaurant\ReadModels\LignePlatCarte;
use App\Domain\Stocks\Models\Article;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un plat à la carte, avec sa couverture de stock — l'onglet « Carte du jour »
 * de `m4-restaurant-carte.html`.
 *
 * ## `portions_vendables` peut valoir `null`, et ce n'est pas `0`
 *
 * `null` veut dire « pas de chiffre » — soit la recette n'a aucun ingrédient,
 * soit aucun point de stockage de cuisine n'existe. `0` veut dire « il n'en
 * reste plus ». Les confondre ferait retirer de la carte un plat que personne
 * n'a compté, ou l'inverse : afficher « 0 » sous un plat dont on ignore le
 * stock est une bonne nouvelle inventée (Article 7 de la directive de
 * conformité, PA-129 pour le même arbitrage sur la carte du bar).
 *
 * `motif_sans_stock` accompagne toujours le `null` : un tiret qui ne dit pas
 * pourquoi renvoie chercher un bug là où il n'y en a pas.
 *
 * ## `cout_matiere` et `marge` peuvent valoir `null` ensemble
 *
 * Le coût matière est inconnu dès qu'un ingrédient n'a jamais été réceptionné :
 * son coût moyen pondéré vaut zéro, ce qui n'est pas un prix. La marge
 * disparaît avec lui — prix de vente moins coût inconnu n'est pas une marge,
 * c'est le prix de vente.
 *
 * ## Pas de `disponible` — mais les deux MARQUES DE PRIX sont rendues
 *
 * `disponible` n'a toujours aucune colonne : le rendre à `true` par défaut
 * annoncerait qu'un plat est à la carte du jour sans que personne l'ait
 * décidé — PA-61 dans sa forme la plus directe. Le refus est documenté dans
 * `EnregistrerPlatRequest`.
 *
 * `prix_provisoire` et `prix_corrige_main`, eux, sont de vraies colonnes
 * depuis la migration `2026_09_02_200000` (PA-161 (b)). Les taire obligerait
 * le client à deviner pourquoi un plat ressort du filtre « Prix provisoire »,
 * et surtout : un tarif provisoire imprimé sans sa marque devient un tarif
 * ferme sur un papier remis au client — la version papier de PA-61.
 *
 * @property-read LignePlatCarte $resource
 */
class LignePlatCarteResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $ligne = $this->resource;
        $limitant = $ligne->ingredientLimitant;

        return [
            'id' => $ligne->plat->id,
            'libelle' => $ligne->plat->libelle,
            // La catégorie vient du menu porteur — `menus.type`, seule source.
            'categorie' => $ligne->categorie,
            'menu_id' => $ligne->plat->menu_id,
            'recette_id' => $ligne->plat->recette_id,
            'prix_vente' => (string) $ligne->plat->prix_vente,
            // Les deux marques de `MarquesDePrix` : « posé faute de relevé »
            // et « corrigé à la main » sont deux faits distincts, et c'est la
            // raison qui dit quoi faire — aller lire l'ardoise, ou faire
            // retirer l'étiquette collée.
            MarquesDePrix::PROVISOIRE => $ligne->plat->prix_provisoire,
            MarquesDePrix::CORRIGE_MAIN => $ligne->plat->prix_corrige_main,

            'lie_au_stock' => $ligne->lieAuStock,
            'nb_ingredients' => $ligne->nbIngredients,
            'motif_sans_stock' => $ligne->motifSansStock,

            'portions_vendables' => $ligne->portionsVendables,
            'rupture' => $ligne->rupture,
            'sous_seuil' => $ligne->sousSeuil,

            // Ce qui BORNE le nombre de portions : « 4 portions » sans dire ce
            // qui manque n'indique pas quoi racheter.
            'ingredient_limitant' => $limitant instanceof Article ? [
                'id' => $limitant->id,
                'libelle' => $limitant->libelle,
                'unite_mesure' => $limitant->unite_mesure,
            ] : null,

            'cout_matiere' => $ligne->coutMatiere->montant,
            'cout_matiere_incomplet' => $ligne->coutMatiere->incomplet,
            'articles_sans_cout' => $ligne->coutMatiere->articlesSansCout,
            'marge' => $ligne->marge(),
        ];
    }
}
