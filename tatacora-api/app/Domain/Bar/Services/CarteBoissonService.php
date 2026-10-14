<?php

declare(strict_types=1);

namespace App\Domain\Bar\Services;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\MarquesDePrix;
use App\Domain\Stocks\Models\Article;
use RuntimeException;

/**
 * Carte des boissons — création, modification et lien au stock (M5, EF-M5-02).
 *
 * Extrait de `BoissonController` (PA-159, lot 0b) : `LARAVEL_PWA.md` §3
 * impose qu'un composant Livewire appelle un Service de domaine — ce service
 * est le point d'entrée commun de l'API et de la PWA.
 *
 * ## Le lien au stock est OBLIGATOIRE au bar, et il porte un conditionnement
 *
 * `cartes_boisson.article_id` est NOT NULL : une boisson vendue au bar est
 * toujours un article du référentiel Stocks. La note antérieure de ce fichier
 * le disait nullable — elle était fausse, vérifié contre le schéma le
 * 31/08/2026 (`create_stocks.php` l.80, `foreignUuid(...)->constrained(...)`
 * sans `nullable()`).
 *
 * Conséquence pratique pour l'écran : **le bouton « Délier » de la maquette ne
 * peut pas exister au bar**, et aucune méthode ne l'offre ici. Le proposer
 * ferait échouer l'écriture en base sur une contrainte NOT NULL, message SQL
 * à l'appui. Le lien se REMPLACE (`lierAuStock` sur un autre article), il ne
 * se retire pas.
 *
 * Le conditionnement (`unites_vendables_par_unite_stock`) est la réponse à la
 * question que la modale posait déjà en champ obligatoire et dont elle jetait
 * la valeur. Sans lui, un casier de 24 et une bouteille à l'unité produisent
 * la même décrémentation.
 *
 * @see EF-M5-02 Carte des boissons
 * @see RG-05 Sortie de stock automatique — la conversion est consommée par
 *      `VenteBarService` et `VenteService`
 * @see RG-15 Journalisation (trait Auditable sur CarteBoisson)
 */
class CarteBoissonService
{
    private const PRECISION = 4;

    /**
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerBoissonRequest` ou les règles qui en dérivent
     */
    public function creer(array $donnees): CarteBoisson
    {
        // Clé absente = conditionnement laissé au défaut du schéma (1), c'est
        // à dire au comportement 1 pour 1 en vigueur jusqu'ici. Le rendre
        // obligatoire ici casserait tous les appelants existants sans rien
        // gagner : c'est la modale « Lier au stock » qui pose la question, et
        // c'est `lierAuStock()` qui l'exige.
        if (array_key_exists('unites_vendables_par_unite_stock', $donnees)) {
            $this->verifierConversion(
                $donnees['unites_vendables_par_unite_stock'],
                (string) ($donnees['libelle'] ?? ''),
            );
        }

        return CarteBoisson::create($donnees);
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    public function modifier(CarteBoisson $boisson, array $donnees): CarteBoisson
    {
        if (array_key_exists('unites_vendables_par_unite_stock', $donnees)) {
            $this->verifierConversion(
                $donnees['unites_vendables_par_unite_stock'],
                $boisson->libelle,
            );
        }

        // PA-161 (b) — « corrigé à la main » est un FAIT, pas une case à
        // cocher : changer au clavier le prix d'une boisson qui portait un
        // tarif provisoire EST la correction manuelle. La déduction vit dans
        // `MarquesDePrix`, partagée avec le restaurant : la recopier ici la
        // ferait diverger de celle des plats au premier ajustement.
        $donnees = MarquesDePrix::completer($boisson, $donnees);

        $boisson->update($donnees);

        return $boisson->refresh();
    }

    /**
     * Rattache la boisson à un article de stock, avec son conditionnement.
     *
     * @param  string  $unitesVendablesParUniteStock  nombre d'unités VENDABLES
     *                                                contenues dans une unité de stock — 24 pour un casier de 24. La
     *                                                décrémentation vaut `quantité vendue / cette valeur`.
     *
     * @throws RuntimeException article inconnu ou conditionnement non positif
     */
    public function lierAuStock(
        CarteBoisson $boisson,
        string $articleId,
        string $unitesVendablesParUniteStock,
    ): CarteBoisson {
        if (! Article::whereKey($articleId)->exists()) {
            // Échec explicite plutôt qu'une violation de clé étrangère, dont
            // le message SQL n'aiderait personne au comptoir.
            throw new RuntimeException(__('carte.article_stock_inconnu', ['article' => $articleId]));
        }

        $this->verifierConversion($unitesVendablesParUniteStock, $boisson->libelle);

        $boisson->update([
            'article_id' => $articleId,
            'unites_vendables_par_unite_stock' => $unitesVendablesParUniteStock,
        ]);

        return $boisson->refresh();
    }

    /**
     * Un conditionnement nul ou négatif rendrait la division impossible ; une
     * absence est refusée ici plutôt que remplacée par 1, qui serait un
     * conditionnement inventé sur une donnée de stock.
     */
    private function verifierConversion(mixed $valeur, string $libelle): void
    {
        if ($valeur === null || $valeur === '') {
            throw new RuntimeException(__('carte.conversion_requise_avec_lien', ['article' => $libelle]));
        }

        if (bccomp((string) $valeur, '0', self::PRECISION) <= 0) {
            throw new RuntimeException(__('carte.conversion_invalide', ['article' => $libelle]));
        }
    }
}
