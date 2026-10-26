<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Services;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\Inventaire;
use App\Domain\Stocks\Models\LigneInventaire;
use App\Domain\Stocks\Models\PointStockage;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Inventaire physique et régularisation — EF-M6-05.
 *
 * @see EF-M6-05 Inventaire physique avec écarts
 *
 * ## Théorique contre constaté : la seule mesure de fiabilité du stock
 *
 * Le stock théorique est le cumul des mouvements ; le constaté est ce qu'on
 * trouve en rayon. L'écart entre les deux est **la** mesure de qualité du
 * processus : casse non déclarée, vol, erreur de saisie, sortie oubliée.
 *
 * Comptablement l'écart n'est pas neutre — il alimente un compte de charge
 * (manquant) ou de produit (excédent) et modifie la valeur du stock à l'actif.
 * Le valoriser au CMP est donc indispensable : un écart exprimé en unités ne
 * se comptabilise pas.
 *
 * ## La régularisation passe par un mouvement, jamais par un UPDATE
 *
 * Corriger le stock en écrivant directement une quantité effacerait la raison
 * de la correction. Chaque écart génère un mouvement `inventaire` (excédent)
 * ou `perte` (manquant), qui reste dans la fiche de stock et rend l'inventaire
 * suivant vérifiable.
 *
 * ## Une ligne n'existe QUE si l'article a été compté — contrainte de schéma
 *
 * `lignes_inventaire.quantite_constatee` et `ecart` sont **NOT NULL** : il est
 * donc impossible d'y représenter « article non encore compté ». Créer les
 * lignes à l'ouverture obligerait à y placer une valeur d'attente, et un
 * article oublié serait alors indiscernable d'un article compté conforme —
 * exactement le défaut qu'un inventaire doit révéler.
 *
 * La ligne est donc créée **au moment du comptage**, et la complétude se
 * vérifie en comparant le nombre de lignes au nombre d'articles du point.
 * Le stock théorique est figé au comptage de chaque article, ce qui est aussi
 * la bonne sémantique d'un comptage qui s'étale sur une matinée. Limitation
 * tracée en PA-54.
 */
class InventaireService
{
    private const PRECISION = 2;

    public function __construct(
        private readonly StockTheoriqueService $stock,
        private readonly MouvementStockService $mouvements,
        private readonly ValorisationStockService $valorisation,
    ) {
    }

    /**
     * Ouvre un inventaire — aucune ligne n'est créée à ce stade.
     */
    public function ouvrir(PointStockage $point, ?string $date = null): Inventaire
    {
        return Inventaire::create([
            'point_id' => $point->id,
            'date_inventaire' => $date ?? now()->toDateString(),
            'utilisateur_id' => auth()->id(),
        ])->refresh();
    }

    /**
     * Enregistre un inventaire CLÔTURÉ sur un poste (synchronisation,
     * 21/10/2026) : l'en-tête et ses lignes, tels que le poste les a figés —
     * théorique du MOMENT de son comptage, constaté, écart. Rien n'est
     * recalculé : le théorique du serveur, à l'instant de l'envoi, n'est pas
     * celui que le poste avait sous les yeux, et l'écart régularisé (les
     * mouvements `inventaire` et `perte` que le poste envoie à part) est
     * celui-ci.
     *
     * Aucun mouvement n'est écrit ici : la régularisation arrive comme les
     * autres mouvements saisis (`GestionnaireMouvementsStock`), sous leur UUID.
     *
     * @param  list<array{id?: string|null, article_id: string, quantite_theorique: string, quantite_constatee: string, ecart: string}>  $lignes
     */
    public function enregistrerCloture(string $id, PointStockage $point, string $date, string $utilisateurId, array $lignes): Inventaire
    {
        return DB::transaction(function () use ($id, $point, $date, $utilisateurId, $lignes): Inventaire {
            $inventaire = Inventaire::create([
                'id' => $id,
                'point_id' => $point->id,
                'date_inventaire' => $date,
                'utilisateur_id' => $utilisateurId,
            ]);

            foreach ($lignes as $ligne) {
                LigneInventaire::create([
                    ...(isset($ligne['id']) && $ligne['id'] !== '' ? ['id' => $ligne['id']] : []),
                    'inventaire_id' => $inventaire->id,
                    'article_id' => $ligne['article_id'],
                    'quantite_theorique' => $ligne['quantite_theorique'],
                    'quantite_constatee' => $ligne['quantite_constatee'],
                    'ecart' => $ligne['ecart'],
                ]);
            }

            return $inventaire->refresh();
        });
    }

    /**
     * Enregistre le comptage d'un article — fige son théorique et calcule
     * l'écart.
     *
     * Un second comptage du même article **écrase** le premier : c'est le
     * comportement attendu d'une correction de saisie pendant le comptage.
     */
    public function compter(Inventaire $inventaire, Article $article, string $quantiteConstatee): LigneInventaire
    {
        if (bccomp($quantiteConstatee, '0', self::PRECISION) < 0) {
            throw new RuntimeException(__('stocks.quantite_negative'));
        }

        return DB::transaction(function () use ($inventaire, $article, $quantiteConstatee): LigneInventaire {
            $theorique = $this->stock->stock($article->id, $inventaire->point_id);

            $ligne = LigneInventaire::updateOrCreate(
                ['inventaire_id' => $inventaire->id, 'article_id' => $article->id],
                [
                    'quantite_theorique' => $theorique,
                    'quantite_constatee' => $quantiteConstatee,
                    // Négatif = manquant, positif = excédent.
                    'ecart' => bcsub($quantiteConstatee, $theorique, self::PRECISION),
                ],
            );

            return $ligne->refresh();
        });
    }

    /**
     * Articles du point restant à compter — EF-M6-05.
     *
     * @return \Illuminate\Database\Eloquent\Collection<int, Article>
     */
    public function articlesNonComptes(Inventaire $inventaire): \Illuminate\Database\Eloquent\Collection
    {
        $comptes = $inventaire->lignes()->pluck('article_id');

        return Article::query()
            ->whereNotIn('id', $comptes)
            ->orderBy('libelle')
            ->get();
    }

    /**
     * Clôture : génère les mouvements de régularisation.
     *
     * @param  bool  $partielAutorise  inventaire tournant, ne portant que sur une sélection
     * @return array{lignes_regularisees: int, manquants: string, excedents: string, ecart_valorise: string}
     *
     * @throws RuntimeException si des articles n'ont pas été comptés
     */
    public function cloturer(Inventaire $inventaire, bool $partielAutorise = false): array
    {
        if (! $partielAutorise) {
            $manquantes = $this->articlesNonComptes($inventaire);

            if ($manquantes->isNotEmpty()) {
                // Clôturer un inventaire incomplet régulariserait une partie
                // du stock et laisserait le reste inchangé, sans que rien ne
                // le signale. Un inventaire tournant reste possible, mais il
                // doit être demandé explicitement.
                throw new RuntimeException(__('stocks.inventaire_incomplet', [
                    'nombre' => $manquantes->count(),
                ]));
            }
        }

        return DB::transaction(function () use ($inventaire): array {
            $regularisees = 0;
            $manquants = '0.00';
            $excedents = '0.00';

            foreach ($inventaire->lignes()->with('article')->get() as $ligne) {
                $ecart = bcadd((string) $ligne->ecart, '0', self::PRECISION);
                $comparaison = bccomp($ecart, '0.00', self::PRECISION);

                if ($comparaison === 0) {
                    continue;
                }

                $valeur = $this->valorisation->valoriser($ligne->article, $ecart);
                $motif = __('stocks.motif_regularisation', [
                    'inventaire' => $inventaire->id,
                    'ecart' => $ecart,
                ]);

                if ($comparaison > 0) {
                    // Excédent : entrée NON valorisée — aucun achat n'a eu
                    // lieu, recalculer le CMP créerait de la valeur ex nihilo.
                    $this->mouvements->ecartInventaire(
                        $ligne->article_id,
                        $inventaire->point_id,
                        $ecart,
                        $motif,
                    );
                    $excedents = bcadd($excedents, $valeur, self::PRECISION);
                } else {
                    // Manquant : constaté en PERTE, pas en sortie — une sortie
                    // suppose une consommation identifiée, ce qui n'est
                    // justement pas le cas ici.
                    $this->mouvements->perte(
                        $ligne->article_id,
                        $inventaire->point_id,
                        bcmul($ecart, '-1', self::PRECISION),
                        $motif,
                    );
                    $manquants = bcadd($manquants, $valeur, self::PRECISION);
                }

                $regularisees++;
            }

            return [
                'lignes_regularisees' => $regularisees,
                // Exposés séparément : ils ne s'imputent pas au même compte.
                // Le manquant est négatif, l'excédent positif.
                'manquants' => $manquants,
                'excedents' => $excedents,
                'ecart_valorise' => bcadd($manquants, $excedents, self::PRECISION),
            ];
        });
    }

    /**
     * Synthèse valorisée — base de l'écriture comptable de régularisation.
     *
     * @return array{
     *     inventaire_id: string, date: string, point: string,
     *     nb_comptes: int, nb_non_comptes: int, nb_ecarts: int,
     *     valeur_theorique: string, valeur_constatee: string, ecart_valorise: string,
     *     lignes: list<array{article: string, theorique: string, constatee: string, ecart: string, ecart_valorise: string}>
     * }
     */
    public function synthese(Inventaire $inventaire): array
    {
        $lignes = $inventaire->lignes()->with('article')->get();

        $valeurTheorique = '0.00';
        $valeurConstatee = '0.00';
        $detail = [];
        $nbEcarts = 0;

        foreach ($lignes as $ligne) {
            $theorique = bcadd((string) $ligne->quantite_theorique, '0', self::PRECISION);
            $constatee = bcadd((string) $ligne->quantite_constatee, '0', self::PRECISION);
            $ecart = bcadd((string) $ligne->ecart, '0', self::PRECISION);

            $valeurTheorique = bcadd(
                $valeurTheorique,
                $this->valorisation->valoriser($ligne->article, $theorique),
                self::PRECISION,
            );
            $valeurConstatee = bcadd(
                $valeurConstatee,
                $this->valorisation->valoriser($ligne->article, $constatee),
                self::PRECISION,
            );

            if (bccomp($ecart, '0.00', self::PRECISION) !== 0) {
                $nbEcarts++;
            }

            $detail[] = [
                'article' => $ligne->article->libelle,
                'theorique' => $theorique,
                'constatee' => $constatee,
                'ecart' => $ecart,
                'ecart_valorise' => $this->valorisation->valoriser($ligne->article, $ecart),
            ];
        }

        return [
            'inventaire_id' => $inventaire->id,
            'date' => $inventaire->date_inventaire->toDateString(),
            'point' => $inventaire->point->libelle,
            'nb_comptes' => $lignes->count(),
            'nb_non_comptes' => $this->articlesNonComptes($inventaire)->count(),
            'nb_ecarts' => $nbEcarts,
            'valeur_theorique' => $valeurTheorique,
            'valeur_constatee' => $valeurConstatee,
            'ecart_valorise' => bcsub($valeurConstatee, $valeurTheorique, self::PRECISION),
            'lignes' => $detail,
        ];
    }
}
