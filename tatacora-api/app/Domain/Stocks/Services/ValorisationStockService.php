<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Services;

use App\Domain\Stocks\Models\Article;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Valorisation du stock au coût moyen pondéré — SYSCOHADA.
 *
 * @see EF-M6-01 Référentiel articles
 * @see RG-05 Sortie de stock automatique
 *
 * ## Le défaut que ce service corrige
 *
 * `articles.cout_moyen_pondere` existait au schéma mais **n'était jamais
 * recalculé** : la valeur était saisie à la création de l'article et n'évoluait
 * plus, alors que `ReceptionService` enregistre des entrées à des prix
 * différents à chaque livraison.
 *
 * Conséquence comptable, et elle est lourde : dès la deuxième réception à un
 * prix différent, **toute valorisation devient fausse**. Or elle alimente
 * directement :
 *
 * - le poste de stocks à l'actif du bilan (classe 3 SYSCOHADA) ;
 * - la **variation de stock** (comptes 603x), qui entre dans le résultat —
 *   un stock surévalué gonfle le bénéfice, et l'impôt qui va avec ;
 * - la valorisation des écarts d'inventaire (601x/603x) ;
 * - le KPI « valeur du stock » de M11 et l'état des stocks de M14.
 *
 * Un stock faux ne se voit pas : il se lit exactement comme un stock juste.
 *
 * ## Méthode retenue : CMP après chaque entrée
 *
 * SYSCOHADA admet le coût moyen pondéré et le PEPS/FIFO. Le CMP **après chaque
 * entrée** est retenu — c'est la variante que la colonne existante suppose
 * (une seule valeur par article, pas un empilement de lots), et la seule
 * calculable sans table de lots.
 *
 *     CMP = (valeur du stock avant + valeur de l'entrée) / (quantité avant + quantité entrée)
 *
 * Les **sorties ne modifient pas le CMP** : elles sont valorisées à son
 * niveau du moment. C'est le principe même de la méthode.
 *
 * ## Précision
 *
 * Le CMP est un `DECIMAL(15,4)`, à quatre décimales et non deux : sur un
 * article à faible valeur unitaire acheté par sacs de 50 kg, arrondir le coût
 * unitaire au franc introduirait une dérive de plusieurs pourcents sur la
 * valorisation totale.
 */
class ValorisationStockService
{
    /** Précision du coût unitaire — `DECIMAL(15,4)` au schéma. */
    public const PRECISION_COUT = 4;

    /** Précision d'un montant valorisé. */
    public const PRECISION_MONTANT = 2;

    public function __construct(
        private readonly StockTheoriqueService $stock,
    ) {
    }

    /**
     * Recalcule et persiste le CMP après une entrée valorisée.
     *
     * @param  string  $quantiteEntree  quantité reçue
     * @param  string  $coutUnitaire  prix d'achat unitaire de CETTE entrée
     * @return string le nouveau CMP
     *
     * @throws RuntimeException sur une quantité ou un coût négatif
     */
    public function integrerEntree(Article $article, string $quantiteEntree, string $coutUnitaire): string
    {
        $this->refuserValeurNegative($quantiteEntree, $coutUnitaire);

        if (bccomp($quantiteEntree, '0', self::PRECISION_COUT) === 0) {
            // Une entrée nulle ne change ni la quantité ni la valeur : la
            // traiter provoquerait une division par le stock inchangé pour
            // rien, et pourrait faire dériver le CMP par arrondi.
            return $this->cmp($article);
        }

        return DB::transaction(function () use ($article, $quantiteEntree, $coutUnitaire): string {
            // Verrou sur l'article : deux réceptions concurrentes calculeraient
            // toutes deux leur CMP sur le même stock de départ, et la seconde
            // écraserait la première. L'erreur ne se verrait qu'à l'inventaire.
            $verrouille = Article::whereKey($article->id)->lockForUpdate()->firstOrFail();

            // Stock AVANT l'entrée : le mouvement n'est pas encore écrit quand
            // ce service est appelé depuis MouvementStockService::entree().
            $quantiteAvant = $this->stock->stockTousPoints($verrouille->id);
            $cmpAvant = $this->cmp($verrouille);

            $nouveauCmp = $this->moyennePonderee($quantiteAvant, $cmpAvant, $quantiteEntree, $coutUnitaire);

            $verrouille->forceFill(['cout_moyen_pondere' => $nouveauCmp])->save();
            $article->setAttribute('cout_moyen_pondere', $nouveauCmp);

            return $nouveauCmp;
        });
    }

    /**
     * Moyenne pondérée pure — exposée pour être testable sans base.
     *
     * Un stock de départ **négatif ou nul** (rupture forcée par RG-06, ou
     * premier achat) fait retomber le CMP sur le seul coût de l'entrée : il
     * n'y a rien à pondérer, et pondérer par une quantité négative inverserait
     * le résultat.
     */
    public function moyennePonderee(
        string $quantiteAvant,
        string $cmpAvant,
        string $quantiteEntree,
        string $coutEntree,
    ): string {
        if (bccomp($quantiteAvant, '0', self::PRECISION_COUT) <= 0) {
            return bcadd($coutEntree, '0', self::PRECISION_COUT);
        }

        $valeurAvant = bcmul($quantiteAvant, $cmpAvant, self::PRECISION_COUT + 2);
        $valeurEntree = bcmul($quantiteEntree, $coutEntree, self::PRECISION_COUT + 2);
        $quantiteTotale = bcadd($quantiteAvant, $quantiteEntree, self::PRECISION_COUT);

        if (bccomp($quantiteTotale, '0', self::PRECISION_COUT) === 0) {
            return bcadd($cmpAvant, '0', self::PRECISION_COUT);
        }

        return bcdiv(
            bcadd($valeurAvant, $valeurEntree, self::PRECISION_COUT + 2),
            $quantiteTotale,
            self::PRECISION_COUT,
        );
    }

    /**
     * Valeur d'un stock au CMP courant — `quantité × CMP`.
     */
    public function valoriser(Article $article, string $quantite): string
    {
        return bcmul($quantite, $this->cmp($article), self::PRECISION_MONTANT);
    }

    /**
     * Valeur totale du stock d'un article, tous points confondus.
     */
    public function valeurArticle(Article $article): string
    {
        return $this->valoriser($article, $this->stock->stockTousPoints($article->id));
    }

    public function cmp(Article $article): string
    {
        return bcadd((string) ($article->cout_moyen_pondere ?? '0'), '0', self::PRECISION_COUT);
    }

    private function refuserValeurNegative(string $quantite, string $cout): void
    {
        if (bccomp($quantite, '0', self::PRECISION_COUT) < 0) {
            throw new RuntimeException(__('stocks.quantite_negative'));
        }

        if (bccomp($cout, '0', self::PRECISION_COUT) < 0) {
            // Un coût d'achat négatif n'existe pas ; le laisser passer
            // ferait baisser le CMP et sous-évaluerait le stock au bilan.
            throw new RuntimeException(__('stocks.cout_negatif'));
        }
    }
}
