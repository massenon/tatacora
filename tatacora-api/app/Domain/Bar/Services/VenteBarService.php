<?php

declare(strict_types=1);

namespace App\Domain\Bar\Services;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Models\LigneVenteBar;
use App\Domain\Bar\Models\VenteBar;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Vente au comptoir du bar — RG-05 en 1 pour 1 (M5).
 *
 * ## Plus simple que le restaurant, et c'est voulu
 *
 * M4 doit traverser une fiche technique : un plat consomme N ingrédients en
 * quantités fractionnaires. Au bar, une bière vendue sort une bière du stock.
 * Le lien `cartes_boisson.article_id` suffit, aucune nomenclature n'est
 * nécessaire — et surtout, aucune ne doit être inventée : ajouter une fiche
 * technique à une boisson revendue en l'état serait de la complexité pure.
 *
 * Les cocktails « maison » (catégorie `maison`) sont le seul cas qui
 * consommerait plusieurs articles. Le schéma ne le permet pas aujourd'hui — un
 * cocktail est lié à un article unique. **Signalé au Product Owner** : soit le
 * cocktail est géré comme un article stocké préparé à l'avance, soit il faudra
 * lui associer une recette comme en M4.
 *
 * ## Contrainte de temps
 *
 * L'écran POS a une contrainte affichée de « moins de 10 s » par opération
 * (SPEC_ECRAN_M5_BAR.md). Toute la vente tient donc en une transaction courte :
 * pas de recalcul global de stock, seulement les articles réellement vendus.
 *
 * @see RG-05 Sortie de stock automatique
 * @see RG-06 Blocage au-delà du disponible
 */
class VenteBarService
{
    private const TYPE_POINT_BAR = 'bar';

    private const PRECISION = 2;

    public function __construct(
        private readonly MouvementStockService $mouvements,
    ) {
    }

    /**
     * Enregistre une vente et décrémente le stock, en une seule transaction.
     *
     * @param  list<array{boisson_id: string, quantite: int}>  $lignes
     *
     * @throws \App\Domain\Stocks\Exceptions\RuptureStockException
     */
    public function enregistrer(
        string $sessionCaisseId,
        array $lignes,
        ?string $clientId = null,
        bool $validationRupture = false,
    ): VenteBar {
        if ($lignes === []) {
            throw new RuntimeException(__('bar.vente_vide'));
        }

        $pointBar = $this->pointBar();

        return DB::transaction(function () use ($sessionCaisseId, $lignes, $clientId, $validationRupture, $pointBar) {
            $vente = VenteBar::create([
                'session_id' => $sessionCaisseId,
                'client_id' => $clientId,
                'date_vente' => now(),
                // Montant provisoire : il est CALCULÉ depuis les lignes juste
                // après, jamais saisi par le barman.
                'montant' => '0.00',
            ]);

            $montant = '0.00';

            foreach ($lignes as $ligne) {
                $boisson = CarteBoisson::findOrFail($ligne['boisson_id']);
                $quantite = (int) $ligne['quantite'];

                if ($quantite < 1) {
                    throw new RuntimeException(__('bar.quantite_minimale'));
                }

                // Prix figé à la vente : une hausse de tarif demain ne doit pas
                // changer le montant d'une vente d'aujourd'hui.
                $prixUnitaire = (string) $boisson->prix_vente;

                LigneVenteBar::create([
                    'vente_id' => $vente->id,
                    'boisson_id' => $boisson->id,
                    'quantite' => $quantite,
                    'prix_unitaire' => $prixUnitaire,
                ]);

                $montant = bcadd(
                    $montant,
                    bcmul($prixUnitaire, (string) $quantite, self::PRECISION),
                    self::PRECISION,
                );

                // RG-05 — la conversion carte -> stock est APPLIQUÉE, elle
                // n'est plus supposée à 1 pour 1.
                //
                // Jusqu'au 31/08/2026 ce service sortait une unité de stock
                // par unité vendue. C'est juste pour une bouteille achetée à
                // l'unité, et faux d'un facteur 24 pour une bouteille tirée
                // d'un casier — la modale « Lier au stock » demandait déjà le
                // conditionnement et jetait la réponse. L'écart n'apparaissait
                // qu'à l'inventaire, imputé à une perte physique.
                //
                // Division au dix-millième puis arrondi au centième par le
                // service de mouvement : la colonne ne garde que deux
                // décimales (PA-38), et l'arrondi doit rester visible.
                $quantiteStock = $this->mouvements->arrondirQuantite(
                    $boisson->stockConsommePour((string) $quantite),
                );

                // Si le stock manque, RG-06 fait échouer la transaction
                // entière — la vente n'est pas enregistrée à moitié.
                $this->mouvements->sortie(
                    articleId: $boisson->article_id,
                    pointId: $pointBar->id,
                    quantite: $quantiteStock,
                    motif: __('bar.motif_vente', ['boisson' => $boisson->libelle, 'quantite' => $quantite]),
                    validationRupture: $validationRupture,
                );
            }

            $vente->update(['montant' => $montant]);

            return $vente->refresh();
        });
    }

    private function pointBar(): PointStockage
    {
        $point = PointStockage::where('type', self::TYPE_POINT_BAR)->first();

        if ($point === null) {
            throw new RuntimeException(__('stocks.point_type_absent', ['type' => self::TYPE_POINT_BAR]));
        }

        return $point;
    }
}
