<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Services;

use App\Domain\Stocks\Models\Article;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Référentiel des articles — création, modification, ARCHIVAGE (M6, EF-M6-01).
 *
 * Extrait de `StockController` (PA-159, lot 0b) : `LARAVEL_PWA.md` §3 impose
 * qu'un composant Livewire appelle un Service de domaine — ce service est le
 * point d'entrée commun de l'API et de la PWA.
 *
 * ## Aucune écriture de stock ici, jamais
 *
 * L'article naît sans stock : la seule façon d'en poser est un mouvement
 * `entree` via `MouvementStockService`, unique point d'entrée sur
 * `mouvements_stock`. Ni le stock ni le coût moyen pondéré ne sont des champs
 * — ce sont des calculs (`StockTheoriqueService`, `ValorisationStockService`),
 * et `EnregistrerArticleRequest` refuse déjà de les recevoir.
 *
 * @see EF-M6-01 Référentiel articles multi-catégories
 * @see EF-M6-03 Valorisation au coût moyen pondéré
 * @see RG-15 Journalisation (trait Auditable sur Article)
 */
class ReferentielArticleService
{
    /**
     * Les VERROUS de l'article — les raisons, lisibles, de refuser l'archivage
     * (demande du Product Owner du 03/09/2026, « supprimer = archiver »).
     *
     * Quatre engagements, et chacun décrit une conséquence réelle :
     *
     * 1. **Du stock reste au magasin.** Retirer du référentiel un article qui
     *    a des unités en rayon les rendrait invisibles à l'inventaire, sans
     *    qu'aucune ligne ne soit corrigée — un écart que personne ne verrait.
     * 2. **Une commande d'achat en cours le porte.** La réception à venir a
     *    besoin de l'article au sélecteur.
     * 3. **Il est vendu à la carte** (`cartes_boisson.article_id` au bar,
     *    `plats.article_id` au restaurant). Le comptoir continuerait de le
     *    vendre et de décrémenter son stock pendant qu'il est « archivé » :
     *    l'écran de carte porte son propre geste de retrait, qui vient avant.
     * 4. **Il entre dans une recette** (`ingredients_recette`). La déduction
     *    de stock cuisine le cherche par cette table.
     *
     * ## Pourquoi `DB::table()` sur trois de ces quatre lectures
     *
     * `cartes_boisson`, `plats` et `ingredients_recette` appartiennent à M5 et
     * M4. Importer leurs modèles ici créerait une dépendance Stocks → Bar et
     * Stocks → Restaurant que l'architecture par domaine interdit hors
     * relation documentée. Ce sont des LECTURES : le refus que `DB::table()`
     * condamne ailleurs est l'ÉCRITURE directe, qui contourne un verrou
     * pessimiste — il n'y en a aucun ici.
     *
     * @return list<string> les motifs, un par engagement — vide : archivable
     */
    public function verrous(Article $article): array
    {
        $motifs = [];

        $stock = app(StockTheoriqueService::class)->stockTousPoints($article->id);

        if (bccomp($stock, '0', 2) > 0) {
            $motifs[] = __('stocks_pwa.archivage.verrou_stock', ['quantite' => $stock]);
        }

        $commandes = DB::table('lignes_commande_achat')
            ->join('commandes_achat', 'commandes_achat.id', '=', 'lignes_commande_achat.commande_id')
            ->where('lignes_commande_achat.article_id', $article->id)
            ->whereNotIn('commandes_achat.statut', ['receptionnee', 'cloturee'])
            ->count();

        if ($commandes > 0) {
            $motifs[] = __('stocks_pwa.archivage.verrou_commande', ['nombre' => $commandes]);
        }

        $carte = DB::table('cartes_boisson')->where('article_id', $article->id)->count()
            + DB::table('plats')->where('article_id', $article->id)->count();

        if ($carte > 0) {
            $motifs[] = __('stocks_pwa.archivage.verrou_carte', ['nombre' => $carte]);
        }

        $recettes = DB::table('ingredients_recette')->where('article_id', $article->id)->count();

        if ($recettes > 0) {
            $motifs[] = __('stocks_pwa.archivage.verrou_recette', ['nombre' => $recettes]);
        }

        return $motifs;
    }

    /**
     * Archive l'article — `actif = false`, jamais un `delete()` : chaque
     * mouvement de stock le cite (`mouvements_stock.article_id` est
     * `restrictOnDelete`), et effacer l'article rendrait le journal illisible.
     *
     * @throws RuntimeException l'article est engagé (voir `verrous()`)
     */
    public function archiver(Article $article): void
    {
        // Recontrôlé au moment d'AGIR : entre l'ouverture de la modale et le
        // clic, une entrée de stock ou une commande a pu naître.
        // Preuve par mutation (03/09/2026) : ce bloc retiré, le cas
        // `un_article_avec_du_stock_est_refuse_et_reste_intact` d'`ArchivageReferentielsPwaTest` passe
        // au ROUGE — la garde mord.
        $motifs = $this->verrous($article);

        if ($motifs !== []) {
            throw new RuntimeException(implode(' ', $motifs));
        }

        // `forceFill` et non `update` : `actif` est délibérément HORS de
        // `$fillable` — ce service est le seul chemin d'archivage.
        $article->forceFill(['actif' => false])->save();
    }

    /**
     * Le pendant de l'archivage — sans lui, « reste restaurable » serait une
     * promesse que rien ne tient (PA-59/60/61).
     */
    public function restaurer(Article $article): void
    {
        if ((bool) $article->actif) {
            return;
        }

        $article->forceFill(['actif' => true])->save();
    }

    /**
     * @param  array<string, mixed>  $donnees données validées par
     *                                        `EnregistrerArticleRequest` ou les règles qui en dérivent
     */
    public function creer(array $donnees): Article
    {
        // `refresh()` et non le modèle tel qu'il sort de `create()` : le coût
        // moyen pondéré est posé par un DEFAUT de la base (0), que l'instance
        // en mémoire ignore. Sans cette relecture, la réponse rendrait une
        // chaîne VIDE là où le client attend un montant — un champ vide se lit
        // « inconnu », pas « zéro ».
        return Article::create($donnees)->refresh();
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    public function modifier(Article $article, array $donnees): Article
    {
        $article->update($donnees);

        return $article->refresh();
    }
}
