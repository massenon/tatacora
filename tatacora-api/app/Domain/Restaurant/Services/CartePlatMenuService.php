<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Services;

use App\Domain\Carte\MarquesDePrix;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Support\DescriptionPlat;
use App\Domain\Stocks\Models\Article;
use RuntimeException;

/**
 * Écritures de la carte : plats et menus (M4, EF-M4-01 et EF-M4-06).
 *
 * Extrait de `CarteRestaurantController` (PA-159, lot 0b) : `LARAVEL_PWA.md`
 * §3 impose qu'un composant Livewire appelle un Service de domaine — ce
 * service est le point d'entrée commun de l'API et de la PWA.
 *
 * ## Distinct de `CarteRestaurantService`, et c'est voulu
 *
 * `CarteRestaurantService` LIT : il calcule portions vendables et couverture
 * de stock (`carte()`, `ligne()`), sans une seule écriture. Verser l'écriture
 * dedans aurait mêlé deux responsabilités que la garde d'écriture PWA balaye
 * par réflexion sur les Services — un service de lecture qui écrit serait
 * exactement le motif qu'elle existe pour détecter (PA-159).
 *
 * ## Le lien direct au stock est l'EXCEPTION, la recette est la règle
 *
 * Un plat se décrémente normalement par sa fiche technique (EF-M4-02). Le lien
 * direct (`article_id` + `unites_vendables_par_unite_stock`) existe pour ce
 * qui se revend en l'état — une bouteille d'eau servie à table, que le maître
 * cite nommément (`carte-engine.js` l.22-26). Les deux colonnes vont toujours
 * ensemble : un `article_id` sans conditionnement ne dit pas COMBIEN sortir du
 * stock, et un conditionnement sans article ne décrémente rien tout en
 * laissant croire le contraire.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M4-02 Fiches techniques (recettes)
 * @see EF-M4-06 Événements culinaires et menus spéciaux
 * @see RG-05 Sortie de stock automatique
 * @see RG-15 Journalisation (trait Auditable sur Plat et Menu)
 */
class CartePlatMenuService
{
    private const PRECISION = 4;

    /**
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerPlatRequest` ou les règles qui en dérivent
     */
    public function creerPlat(array $donnees): Plat
    {
        $this->verifierCoherenceLien(
            $donnees['article_id'] ?? null,
            $donnees['unites_vendables_par_unite_stock'] ?? null,
            (string) ($donnees['libelle'] ?? ''),
        );

        return Plat::create($this->normaliserDescription($donnees));
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    public function modifierPlat(Plat $plat, array $donnees): Plat
    {
        // La cohérence s'apprécie sur l'état RÉSULTANT, jamais sur les seules
        // clés soumises — même raisonnement que PA-124 sur les paramètres :
        // un contrôle clé par clé refuserait de poser l'article et son
        // conditionnement du même geste.
        $this->verifierCoherenceLien(
            array_key_exists('article_id', $donnees) ? $donnees['article_id'] : $plat->article_id,
            array_key_exists('unites_vendables_par_unite_stock', $donnees)
                ? $donnees['unites_vendables_par_unite_stock']
                : $plat->unites_vendables_par_unite_stock,
            $plat->libelle,
        );

        // PA-161 (b) — « corrigé à la main » est un FAIT, pas une case à
        // cocher : changer au clavier le prix d'un plat qui portait un tarif
        // provisoire EST la correction manuelle. La déduction vit dans
        // `MarquesDePrix`, partagée avec le bar : la recopier ici la ferait
        // diverger de celle des boissons au premier ajustement.
        $donnees = MarquesDePrix::completer($plat, $this->normaliserDescription($donnees));

        $plat->update($donnees);

        return $plat->refresh();
    }

    /**
     * Rattache le plat à un article de stock unique, avec son conditionnement.
     *
     * @param  string  $unitesVendablesParUniteStock  nombre d'unités VENDABLES
     *                                                contenues dans une unité de stock — 24 pour un pack de 24. La
     *                                                décrémentation vaut `quantité vendue / cette valeur`.
     *
     * @throws RuntimeException article inconnu ou conditionnement non positif
     */
    public function lierAuStock(
        Plat $plat,
        string $articleId,
        string $unitesVendablesParUniteStock,
    ): Plat {
        if (! Article::whereKey($articleId)->exists()) {
            throw new RuntimeException(__('carte.article_stock_inconnu', ['article' => $articleId]));
        }

        $this->verifierCoherenceLien($articleId, $unitesVendablesParUniteStock, $plat->libelle);

        $plat->update([
            'article_id' => $articleId,
            'unites_vendables_par_unite_stock' => $unitesVendablesParUniteStock,
        ]);

        return $plat->refresh();
    }

    /**
     * Retire le lien direct : le plat repasse à sa recette.
     *
     * Les deux colonnes partent ENSEMBLE. Laisser le conditionnement derrière
     * l'article afficherait un taux de conversion sur un plat qui ne
     * décrémente plus rien.
     */
    public function delierDuStock(Plat $plat): Plat
    {
        $plat->update([
            'article_id' => null,
            'unites_vendables_par_unite_stock' => null,
        ]);

        return $plat->refresh();
    }

    /**
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerMenuRequest` ou les règles qui en dérivent
     */
    public function creerMenu(array $donnees): Menu
    {
        return Menu::create($donnees);
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    public function modifierMenu(Menu $menu, array $donnees): Menu
    {
        $menu->update($donnees);

        return $menu->refresh();
    }

    /**
     * La description facultative (30/10/2026) : trim, vide = `null`. Absente du
     * lot, elle n'est PAS ajoutée (une modification qui ne la soumet pas la
     * laisse en place).
     *
     * @param  array<string, mixed>  $donnees
     * @return array<string, mixed>
     */
    private function normaliserDescription(array $donnees): array
    {
        if (array_key_exists('description', $donnees)) {
            $donnees['description'] = DescriptionPlat::normaliser($donnees['description']);
        }

        return $donnees;
    }

    /**
     * Les deux colonnes du lien direct vont ensemble, ou aucune des deux.
     */
    private function verifierCoherenceLien(mixed $articleId, mixed $conversion, string $libelle): void
    {
        $aArticle = $articleId !== null && $articleId !== '';
        $aConversion = $conversion !== null && $conversion !== '';

        if ($aArticle && ! $aConversion) {
            throw new RuntimeException(__('carte.conversion_requise_avec_lien', ['article' => $libelle]));
        }

        if (! $aArticle && $aConversion) {
            throw new RuntimeException(__('carte.conversion_sans_lien', ['article' => $libelle]));
        }

        if ($aConversion && bccomp((string) $conversion, '0', self::PRECISION) <= 0) {
            throw new RuntimeException(__('carte.conversion_invalide', ['article' => $libelle]));
        }
    }
}
