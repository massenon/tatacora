<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Services;

use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Calcul du stock théorique — la seule source de vérité du niveau de stock (M6).
 *
 * **Toujours calculé depuis `mouvements_stock`, jamais stocké.** Une colonne
 * `stock` sur `articles` serait fausse dès le premier mouvement qu'un
 * traitement aurait manqué, et personne ne s'en apercevrait avant un
 * inventaire physique — c'est-à-dire des semaines de décisions d'achat prises
 * sur un chiffre faux.
 *
 * ## Convention de signe
 *
 * `entree` et `inventaire` ajoutent, `sortie` et `perte` retranchent. Les
 * mouvements de type `inventaire` portent **l'écart signé** constaté
 * (cohérent avec `lignes_inventaire.ecart`), pas la quantité recomptée : un
 * inventaire qui remplacerait le solde effacerait l'historique des mouvements
 * qui l'ont produit.
 *
 * ## Précision
 *
 * Les quantités sont des `DECIMAL(10,2)` manipulées en chaîne via `bcmath` —
 * jamais en flottant. Un cumul de centaines de mouvements en virgule flottante
 * dérive, et l'écart d'inventaire résultant serait imputé à tort à une perte
 * physique (A1_MASTER_PROMPT.md §2.5).
 */
class StockTheoriqueService
{
    private const PRECISION = 2;

    /**
     * Types de mouvement qui AJOUTENT au stock. Conservés comme constante
     * documentaire : la convention de signe est reprise telle quelle dans
     * `EXPRESSION_SOLDE`, et toute évolution de l'une doit suivre l'autre.
     *
     * @var list<string>
     */
    public const TYPES_ENTRANTS = ['entree', 'inventaire'];

    /**
     * Expression SQL du solde signé, partagée par toutes les agrégations.
     *
     * `SUM()` sur du `DECIMAL` est exact en MySQL — il ne passe jamais par un
     * flottant. La discipline `bcmath` du projet est donc préservée : on ne
     * troque pas la précision contre la vitesse, on déplace simplement le
     * calcul là où il appartient.
     */
    public const EXPRESSION_SOLDE = "COALESCE(SUM(CASE WHEN type_mouvement IN ('entree','inventaire') THEN quantite ELSE -quantite END), 0)";

    /**
     * Stock théorique d'un article en un point de stockage donné.
     *
     * ## Pourquoi une agrégation SQL et non une boucle PHP
     *
     * La première version chargeait TOUS les mouvements du couple
     * (article, point) en mémoire et cumulait en PHP. Mesuré sur 29 000
     * mouvements — un an de bar à 80 boissons/jour, ordre de grandeur réel du
     * gîte à maturité : **1 484 ms par appel, 108 Mo de pic mémoire**.
     *
     * Or cette méthode est appelée DEUX fois par vente : contrôle de
     * disponibilité (RG-06) puis vérification de seuil (RG-07). Soit près de
     * 3 s de calcul de stock par vente, contre un NFR à « moins de 2 s pour
     * 95 % des opérations » et un écran POS annoncé à « moins de 10 s »
     * (02_SOFTWARE_ARCHITECTURE.md §7bis, SPEC_ECRAN_M5_BAR.md).
     *
     * Le coût était invisible en test — quelques dizaines de mouvements — et
     * se serait manifesté au bar un soir d'affluence, c'est-à-dire au pire
     * moment possible.
     *
     * L'index composite `(article_id, point_id)` existe déjà au schéma : cette
     * requête s'y appuie, aucune modification de base n'est nécessaire.
     */
    public function stock(string $articleId, string $pointId): string
    {
        $solde = DB::table('mouvements_stock')
            ->where('article_id', $articleId)
            ->where('point_id', $pointId)
            ->selectRaw(self::EXPRESSION_SOLDE . ' AS solde')
            ->value('solde');

        return $this->normaliser($solde);
    }

    /**
     * Un `SUM()` vide renvoie `0` et non `0.00` ; les décimales sont
     * réimposées ici pour que toute la couche métier compare des chaînes de
     * format identique avec `bccomp`.
     */
    private function normaliser(mixed $valeur): string
    {
        return bcadd((string) ($valeur ?? '0'), '0', self::PRECISION);
    }

    /**
     * Stock d'un article tous points confondus — utile au réapprovisionnement,
     * jamais à une décision de sortie : on ne sert pas un client au bar avec
     * une bouteille qui se trouve au magasin.
     */
    public function stockTousPoints(string $articleId): string
    {
        $solde = DB::table('mouvements_stock')
            ->where('article_id', $articleId)
            ->selectRaw(self::EXPRESSION_SOLDE . ' AS solde')
            ->value('solde');

        return $this->normaliser($solde);
    }

    /**
     * @return Collection<string, string> point_id => stock
     */
    public function stockParPoint(string $articleId): Collection
    {
        // Query builder et non Eloquent : l'agrégat n'est pas une colonne du
        // modèle, et le faire passer pour un attribut d'entité brouillerait la
        // frontière entre une ligne de mouvement et un cumul calculé.
        $lignes = DB::table('mouvements_stock')
            ->where('article_id', $articleId)
            ->groupBy('point_id')
            ->get(['point_id', DB::raw(self::EXPRESSION_SOLDE . ' AS solde')]);

        /** @var array<string, numeric-string> $stocks */
        $stocks = [];

        foreach ($lignes as $ligne) {
            $stocks[(string) $ligne->point_id] = $this->normaliser($ligne->solde);
        }

        return collect($stocks);
    }

    /**
     * La sortie demandée tient-elle dans le stock disponible ? (RG-06)
     */
    public function sortiePossible(string $articleId, string $pointId, string $quantite): bool
    {
        return bccomp($this->stock($articleId, $pointId), $quantite, self::PRECISION) >= 0;
    }
}
