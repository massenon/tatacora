<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\ReadModels;

/**
 * L'écran « Carte du restaurant » entier — ses lignes, sa bande d'indicateurs
 * et sa couverture par catégorie, produits par UN seul parcours.
 *
 * ## Pourquoi les trois ensemble, et pas trois routes
 *
 * Les indicateurs, le tableau et la couverture décrivent la même carte. Servis
 * par trois calculs séparés, ils finiraient par se contredire à l'écran — un
 * total qui ne fait pas la somme des lignes affichées juste en dessous. C'est
 * le raisonnement de PA-121 sur les séries du tableau de bord, appliqué ici :
 * **une seule source, plusieurs vues.**
 *
 * ## Les indicateurs portent sur la carte ENTIÈRE, les lignes sur le filtre
 *
 * Ce n'est pas une incohérence, c'est ce que fait le maître :
 * `carte-module.js` appelle `C.kpis(MODULE)` et `C.articles({module})` sans
 * filtre pour la bande et l'onglet Couverture, et `C.articles(filtres())` pour
 * le tableau. Filtrer les compteurs ferait tomber « ne décrémentent rien » à
 * zéro dès qu'on filtre sur « liés au stock » — c'est-à-dire précisément quand
 * on cherche à mesurer le trou.
 *
 * `filtresAppliques` est remonté pour que tout export DISE son filtre
 * (PA-119) : un document qui ne le dit pas passe pour un état complet.
 */
final readonly class CarteRestaurant
{
    /**
     * @param  list<LignePlatCarte>  $lignes  filtrées, dans l'ordre d'affichage
     * @param  array{plats: int, lies: int, sans_lien: int, taux_couverture: string|null, en_rupture: int, sous_seuil: int, cout_matiere_inconnu: int, prix_provisoires: int}  $indicateurs
     * @param  list<array{categorie: string, plats: int, lies: int, sans_lien: int, taux: string|null}>  $couverture
     * @param  array<string, string>  $filtresAppliques
     */
    public function __construct(
        public array $lignes,
        public array $indicateurs,
        public array $couverture,
        public array $filtresAppliques,
        public ?string $pointCuisineId,
        public string $arreteAu,
    ) {
    }
}
