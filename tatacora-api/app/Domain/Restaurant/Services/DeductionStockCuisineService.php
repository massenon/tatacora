<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Services;

use App\Domain\Restaurant\Exceptions\RecetteManquanteException;
use App\Domain\Restaurant\Models\CommandeRestaurant;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Sortie de stock déclenchée par une commande restaurant — RG-05.
 *
 * ## Pourquoi ce n'est PAS un Listener, contrairement à la lettre de RG-05
 *
 * RG-05 décrit « un événement `VenteEnregistree` avec listener
 * `DecrementerStock`, déclenché de façon synchrone ». L'intention — décrémenter
 * immédiatement, jamais en file d'attente — est respectée intégralement. Mais
 * la décrémentation doit pouvoir **refuser la vente** quand le stock est
 * insuffisant (RG-06) : un listener qui annule l'action qui l'a déclenché n'est
 * plus un listener, c'est une étape de la transaction.
 *
 * La déduction est donc appelée explicitement par `CommandeRestaurantService`,
 * dans la même transaction que la commande : si un ingrédient manque, la
 * commande entière est annulée. Un événement `CommandeTransmiseCuisine` reste
 * émis **après** succès, pour les consommateurs qui n'ont pas de droit de veto
 * (bon de cuisine, notifications M12).
 *
 * Sans cette distinction, une rupture d'ingrédient laisserait une commande
 * enregistrée que la cuisine ne peut pas produire.
 *
 * ## Moment de la sortie
 *
 * À la **transmission en cuisine**, pas à la clôture : c'est le moment où les
 * denrées sont réellement engagées. Attendre le service ferait apparaître du
 * stock encore disponible alors qu'il est déjà dans la casserole, et deux
 * commandes simultanées se le verraient promettre. Le moment exact n'est pas
 * spécifié dans la documentation — choix signalé au Product Owner.
 */
class DeductionStockCuisineService
{
    /**
     * Type de point de stockage desservant la cuisine.
     *
     * PUBLIQUE parce que `CarteRestaurantService` compte les portions encore
     * servables sur ce meme point : la recopier ailleurs ferait diverger
     * l'ecran de la sortie reelle au premier renommage, et la carte
     * promettrait des assiettes puisees dans un autre magasin que celui ou la
     * cuisine se sert.
     */
    public const TYPE_POINT_CUISINE = 'cuisine';

    public function __construct(
        private readonly MouvementStockService $mouvements,
    ) {
    }

    /**
     * Décrémente tous les ingrédients de toutes les lignes d'une commande.
     *
     * @param  bool  $validationRupture  Rupture assumée par un utilisateur habilité (RG-06)
     * @return list<array{article_id: string, quantite: string, plat: string}>
     *
     * @throws RecetteManquanteException
     * @throws \App\Domain\Stocks\Exceptions\RuptureStockException
     */
    public function deduire(CommandeRestaurant $commande, bool $validationRupture = false): array
    {
        return $this->deduireLignes(
            $commande->lignes()->with('plat.recette')->get()
                ->map(static fn ($ligne): array => ['plat' => $ligne->plat, 'quantite' => (int) $ligne->quantite])
                ->all(),
            $validationRupture,
        );
    }

    /**
     * La même déduction, sur des lignes `plat × quantité` SANS commande de
     * cuisine — extraite le 15/10/2026 pour la synchronisation des ventes
     * (lot S3, décision du Product Owner).
     *
     * Pourquoi : une vente faite hors connexion au restaurant a DÉJÀ été
     * servie. Créer et transmettre une commande au moment de la
     * synchronisation imprimerait un bon de cuisine pour une assiette mangée
     * il y a trois jours (`CommandeTransmiseCuisine` alimente le bon et les
     * notifications). Mais les denrées ont bien quitté la cuisine : RG-05
     * s'applique quand même. Le calcul reste UNIQUE — `deduire()` délègue
     * ici — pour qu'une fiche technique modifiée change les deux chemins à la
     * fois.
     *
     * `$dateMouvement` : la date MÉTIER de la vente (D246) ; `null` = maintenant.
     *
     * @param  iterable<array{plat: \App\Domain\Restaurant\Models\Plat, quantite: int}>  $lignes
     * @return list<array{article_id: string, quantite: string, plat: string}>
     *
     * @throws RecetteManquanteException
     * @throws \App\Domain\Stocks\Exceptions\RuptureStockException
     */
    public function deduireLignes(
        iterable $lignes,
        bool $validationRupture = false,
        ?CarbonInterface $dateMouvement = null,
    ): array {
        $pointCuisine = $this->pointCuisine();
        $sorties = [];

        foreach ($lignes as $ligne) {
            $plat = $ligne['plat'];
            $nombre = (int) $ligne['quantite'];

            // Lien DIRECT au stock : le plat se revend en l'état (bouteille
            // d'eau servie à table). Le maître l'admet nommément
            // (`carte-engine.js` l.22-26). Il prime sur la recette parce qu'il
            // est plus précis : un article unique n'a pas de nomenclature à
            // traverser. Un plat ne peut pas avoir les deux à la fois de façon
            // cohérente — `CartePlatMenuService` exige l'article ET son
            // conditionnement ensemble, ou aucun des deux.
            if ($plat->aUnLienDirectAuStock()) {
                $quantite = $this->mouvements->arrondirQuantite(
                    $plat->stockConsommePour((string) $nombre),
                );

                $this->mouvements->sortie(
                    articleId: (string) $plat->article_id,
                    pointId: $pointCuisine->id,
                    quantite: $quantite,
                    motif: __('restaurant.motif_vente', ['plat' => $plat->libelle, 'quantite' => $nombre]),
                    validationRupture: $validationRupture,
                    dateMouvement: $dateMouvement,
                );

                $sorties[] = [
                    'article_id' => (string) $plat->article_id,
                    'quantite' => $quantite,
                    'plat' => $plat->libelle,
                ];

                continue;
            }

            // `plats.recette_id` étant NOT NULL, un plat sans fiche technique
            // ne peut pas exister — inutile de le vérifier ici. Le trou réel
            // que le schéma NE couvre PAS est une recette dont la nomenclature
            // est vide : elle se vendrait sans rien consommer, et l'écart
            // n'apparaîtrait qu'à l'inventaire, imputé à une perte physique.
            $ingredients = DB::table('ingredients_recette')
                ->where('recette_id', $plat->recette_id)
                ->get(['article_id', 'quantite_unitaire']);

            if ($ingredients->isEmpty()) {
                throw new RecetteManquanteException($plat->libelle);
            }

            /*
             * LES ARTICLES NON SUIVIS SONT ÉCARTÉS — 04/09/2026.
             *
             * `Article::estSuiviEnStock()` porte la règle depuis toujours et
             * son docblock l'écrit en toutes lettres : « un article journalier
             * REFUSE le mouvement de stock ». Elle n'était consultée nulle
             * part sur ce chemin — déclarée, jamais branchée.
             *
             * Conséquence mesurée le 04/09/2026 sur la base de démonstration :
             * la laitue, la tomate, l'oignon, la carotte, le concombre et le
             * piment sont `journalier`, donc sans aucun mouvement et à stock
             * zéro par construction. Toute fiche technique qui les nomme —
             * c'est-à-dire les cinq entrées et les cinq pizzas de la carte
             * réelle — faisait lever `RuptureStockException` **au comptoir**,
             * sur un article que personne ne compte et que personne ne
             * réapprovisionne. Le seul contournement était de mentir sur la
             * fiche en retirant l'ingrédient.
             *
             * La fiche dit donc ce que le plat CONTIENT (c'est la carte du
             * client), et le stock ne bouge que pour ce qui est réellement
             * tenu. Les deux ne sont pas la même question.
             *
             * ⚠ Un plat dont TOUS les ingrédients sont journaliers ne
             * décrémente rien — et ce n'est pas le trou que
             * `RecetteManquanteException` couvre : là, rien n'est suivi, et
             * c'est la vérité. Pour que cela ne se lise pas comme une fiche
             * absente, l'écran « Fiches techniques » en fait un état à part
             * (`Recette::decrementeUnStockSuivi()`).
             */
            $suivis = Article::query()
                ->whereIn('id', $ingredients->pluck('article_id')->all())
                ->get()
                ->filter(static fn (Article $article): bool => $article->estSuiviEnStock())
                ->keyBy('id');

            foreach ($ingredients as $ingredient) {
                if (! $suivis->has((string) $ingredient->article_id)) {
                    continue;
                }

                // Quantité unitaire de la fiche × nombre de plats commandés.
                //
                // ATTENTION — décalage de précision assumé, voir PA-38 :
                // `ingredients_recette.quantite_unitaire` est en DECIMAL(10,3)
                // (les recettes s'expriment en grammes et centilitres) alors que
                // `mouvements_stock.quantite` n'accepte que DECIMAL(10,2).
                // Le calcul est donc mené au millième puis arrondi au centième
                // ICI, explicitement, plutôt que laissé à la troncature
                // silencieuse de MySQL — au moins l'arrondi est visible et
                // testable. Sur une recette à 0,125 kg, cela crée une
                // sur-consommation de 5 g par portion : le schéma doit être
                // revu par l'Architecte, ce service ne peut pas le corriger.
                $quantiteExacte = bcmul(
                    (string) $ingredient->quantite_unitaire,
                    (string) $nombre,
                    3,
                );

                // Arrondi par le service de mouvement, point unique : le
                // recopier ici l'aurait fait diverger de la conversion de
                // carte au premier changement de précision du schéma.
                $quantite = $this->mouvements->arrondirQuantite($quantiteExacte);

                $this->mouvements->sortie(
                    articleId: (string) $ingredient->article_id,
                    pointId: $pointCuisine->id,
                    quantite: $quantite,
                    motif: __('restaurant.motif_vente', ['plat' => $plat->libelle, 'quantite' => $nombre]),
                    validationRupture: $validationRupture,
                    dateMouvement: $dateMouvement,
                );

                $sorties[] = [
                    'article_id' => (string) $ingredient->article_id,
                    'quantite' => $quantite,
                    'plat' => $plat->libelle,
                ];
            }
        }

        return $sorties;
    }

    /**
     * Le point de stockage « cuisine » doit exister : sans lui, on ne saurait
     * pas d'où sortent les denrées. Échec explicite plutôt que sortie imputée
     * à un point arbitraire.
     */
    private function pointCuisine(): PointStockage
    {
        $point = PointStockage::where('type', self::TYPE_POINT_CUISINE)->first();

        if ($point === null) {
            throw new RuntimeException(__('stocks.point_type_absent', ['type' => self::TYPE_POINT_CUISINE]));
        }

        return $point;
    }
}
