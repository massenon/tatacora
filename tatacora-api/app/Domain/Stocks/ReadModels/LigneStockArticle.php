<?php

declare(strict_types=1);

namespace App\Domain\Stocks\ReadModels;

use App\Domain\Stocks\Models\Article;

/**
 * Un article ET son stock calculé, sur une portée donnée — projection de
 * LECTURE, jamais une entité.
 *
 * ## Pourquoi une classe séparée et non un attribut sur `Article`
 *
 * `StockTheoriqueService` le dit en toutes lettres : « faire passer l'agrégat
 * pour un attribut d'entité brouillerait la frontière entre une ligne de
 * mouvement et un cumul calculé ». Un `Article` qui porterait `->stock`
 * deviendrait indiscernable d'un modèle à colonne `stock` — c'est-à-dire
 * exactement l'anti-pattern que le schéma refuse depuis le premier jour
 * (aucune colonne de stock n'existe sur `articles`, et il ne faut jamais en
 * ajouter).
 *
 * La projection porte donc sa **portée** avec elle : un chiffre de stock sans
 * son point de stockage ne veut rien dire. « 10 au bar et 0 au magasin » n'est
 * pas « 0 au bar et 10 au magasin », même total.
 *
 * @see EF-M6-01 Référentiel articles
 * @see RG-07 Seuil d'alerte
 */
final readonly class LigneStockArticle
{
    /** Stock consolidé sur TOUS les points de stockage. */
    public const PORTEE_TOUS_POINTS = 'tous_points';

    /** Stock du seul point de stockage demandé. */
    public const PORTEE_POINT = 'point';

    /**
     * @param  string  $stock  quantité, `numeric-string` à 2 décimales
     * @param  string  $valeur  valorisation au CMP, `numeric-string` à 2 décimales
     * @param  string  $portee  self::PORTEE_*
     * @param  string|null  $pointId  renseigné si et seulement si la portée est un point
     */
    public function __construct(
        public Article $article,
        public string $stock,
        public string $valeur,
        public string $portee,
        public ?string $pointId,
        public bool $sousSeuil,
        public bool $rupture,
    ) {
    }
}
