<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Services;

use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\ReadModels\CoutMatiere;
use App\Domain\Stocks\Models\Article;
use Illuminate\Support\Facades\DB;

/**
 * Fiche technique d'un plat : composition et coût matière — EF-M4-02.
 *
 * ## `recettes.cout_matiere_calcule` N'ÉTAIT ÉCRIT PAR PERSONNE
 *
 * La migration annonce en commentaire « recalculé à chaque modification
 * d'ingredients_recette ». Aucun code du dépôt ne le recalculait : la colonne
 * valait `0.00` pour toutes les recettes, seuls deux tests l'initialisant à la
 * main. Exposer cette colonne telle quelle aurait affiché « coût matière :
 * 0 F » — donc « marge : prix de vente entier » — sur l'écran même où l'on fixe
 * un prix. Même famille que PA-126 (`clients_local.solde`), et même correctif :
 * **le coût se CALCULE depuis les lignes, il ne se lit pas dans une colonne.**
 *
 * `recalculer()` est le seul endroit qui écrit cette colonne, et il n'est
 * appelé que par le chemin qui modifie la composition. Le reste de l'API passe
 * toujours par `coutMatiere()`, qui recalcule : une seule formule pour la fiche
 * détail, la carte et l'écran de prix, comme PA-121 l'impose pour les séries
 * du tableau de bord.
 *
 * ## Le coût matière peut être INCONNU, et ce n'est pas zéro
 *
 * Le coût unitaire d'un ingrédient est son coût moyen pondéré (M6), alimenté
 * par les réceptions d'achat. Un article jamais réceptionné porte un CMP à
 * zéro : il n'est pas gratuit, il est **non valorisé**. Une recette qui en
 * contient un rend donc `null` et nomme les articles fautifs, plutôt qu'un
 * total sous-évalué dont rien ne signalerait le trou.
 *
 * ## Une composition peut être PROVISOIRE, et ce n'est pas une composition
 *
 * Depuis le 04/09/2026, `recettes.composition_provisoire` distingue une fiche
 * pesée par le cuisinier d'une fiche SEMÉE pour débloquer le service. Les deux
 * décrémentent un stock réel ; seule la première décrémente une quantité que
 * quelqu'un a mesurée. Sans la marque, l'écart n'apparaîtrait qu'à
 * l'inventaire, imputé à une perte physique qui n'a jamais eu lieu.
 *
 * @see EF-M4-02 Gestion des fiches techniques de recette
 * @see EF-M6-03 Valorisation au coût moyen pondéré
 */
class CompositionRecetteService
{
    /** Précision des montants — DECIMAL(15,2), comme partout dans le projet. */
    private const PRECISION_MONTANT = 2;

    /** Précision des quantités de recette — `ingredients_recette` est en DECIMAL(10,3). */
    private const PRECISION_QUANTITE = 3;

    /**
     * Coût matière d'une recette, recalculé depuis ses lignes.
     *
     * `bcmul`/`bcadd` et jamais l'arithmétique flottante : un cumul de
     * quantités au millième dérive, et l'écart se retrouverait dans un prix de
     * vente (règle projet, `A1_MASTER_PROMPT.md` §2.5).
     */
    public function coutMatiere(Recette $recette): CoutMatiere
    {
        $lignes = $this->lignes($recette);

        if ($lignes === []) {
            return CoutMatiere::compositionVide();
        }

        $articles = Article::query()
            ->whereIn('id', array_column($lignes, 'article_id'))
            ->get()
            ->keyBy('id');

        $total = '0.00';
        $sansCout = [];

        foreach ($lignes as $ligne) {
            $article = $articles->get($ligne['article_id']);

            if (! $article instanceof Article) {
                // La clé étrangère l'interdit ; si cela arrive, c'est une
                // anomalie d'intégrité et non un coût nul.
                $sansCout[] = $ligne['article_id'];

                continue;
            }

            $cmp = (string) $article->cout_moyen_pondere;

            if (bccomp($cmp, '0', 4) <= 0) {
                $sansCout[] = (string) $article->libelle;

                continue;
            }

            $total = bcadd(
                $total,
                bcmul($ligne['quantite_unitaire'], $cmp, self::PRECISION_MONTANT),
                self::PRECISION_MONTANT,
            );
        }

        // Le trou l'emporte sur le sous-total : un coût partiel présenté comme
        // complet est plus dangereux qu'un coût absent, parce qu'il se compare.
        return $sansCout === []
            ? CoutMatiere::connu($total)
            : CoutMatiere::incomplet(array_values(array_unique($sansCout)));
    }

    /**
     * Remplace intégralement la composition d'une recette — le sous-formulaire
     * réclamé par PA-23, à la place du textarea « Ingrédients principaux » du
     * prototype.
     *
     * ## Remplacement et non fusion
     *
     * `ingredients_recette` a une clé primaire composite `(recette_id,
     * article_id)` et aucune colonne d'identité propre : il n'existe donc aucun
     * moyen de désigner « la ligne à supprimer » autrement que par son article.
     * Un enregistrement ligne à ligne laisserait sur place tout ingrédient
     * retiré du formulaire — le plat continuerait de décrémenter un stock que
     * la fiche ne mentionne plus, et l'écart n'apparaîtrait qu'à l'inventaire.
     *
     * ## La marque « provisoire » TOMBE ici, et nulle part ailleurs
     *
     * `recettes.composition_provisoire` dit que les grammages ont été SEMÉS,
     * plausibles et non relevés (04/09/2026). Remplacer la composition est
     * précisément le geste qui cesse de la rendre vraie : la marque retombe
     * donc à `false` d'elle-même, sans que personne ait à la décocher — le
     * raisonnement de `MarquesDePrix` sur `prix_corrige_main`, à l'envers.
     * Demander en plus de déclarer « ce n'est plus provisoire » reviendrait à
     * faire déclarer ce qu'on vient de faire, et on l'oublierait.
     *
     * ⚠ Le paramètre `$provisoire` existe pour un seul appelant, le
     * référentiel de démonstration, qui POSE la marque en même temps que les
     * quantités. Une décision explicite l'emporte toujours sur la déduction
     * (même règle que `MarquesDePrix::completer()`) ; laisser le seeder écrire
     * la colonne de son côté en ferait un second auteur.
     *
     * @param  list<array{article_id: string, quantite_unitaire: string}>  $lignes
     * @param  bool|null  $provisoire  `null` : la marque tombe, la composition
     *                                 vient d'un geste humain. `true`/`false` : décision de l'appelant.
     */
    public function remplacerComposition(Recette $recette, array $lignes, ?bool $provisoire = null): Recette
    {
        return DB::transaction(function () use ($recette, $lignes, $provisoire): Recette {
            DB::table('ingredients_recette')->where('recette_id', $recette->id)->delete();

            foreach ($lignes as $ligne) {
                DB::table('ingredients_recette')->insert([
                    'recette_id' => $recette->id,
                    'article_id' => $ligne['article_id'],
                    'quantite_unitaire' => bcadd($ligne['quantite_unitaire'], '0', self::PRECISION_QUANTITE),
                ]);
            }

            $recette->update([Recette::PROVISOIRE => $provisoire ?? false]);

            return $this->recalculer($recette);
        });
    }

    /**
     * Persiste le coût matière dans `recettes.cout_matiere_calcule` — SEUL
     * endroit du dépôt qui écrit cette colonne.
     *
     * ## Question ouverte, laissée telle quelle plutôt que masquée
     *
     * La colonne est `DECIMAL(15,2) NOT NULL DEFAULT 0` : elle ne sait pas dire
     * « inconnu ». Une recette dont un ingrédient n'a pas de CMP y retombe donc
     * à `0.00`, indiscernable d'une recette réellement gratuite. **C'est
     * pourquoi aucune ressource d'API ne lit cette colonne** — toutes passent
     * par `coutMatiere()`, qui rend les trois états. La rendre `nullable`
     * relève de l'Architecte (modification d'une colonne existante) ; la
     * question est posée, pas tranchée ici.
     */
    public function recalculer(Recette $recette): Recette
    {
        $cout = $this->coutMatiere($recette);

        $recette->update(['cout_matiere_calcule' => $cout->montant ?? '0.00']);

        return $recette->refresh();
    }

    /**
     * Lignes brutes de la composition, triées par article pour que deux appels
     * successifs rendent le même ordre.
     *
     * @return list<array{article_id: string, quantite_unitaire: string}>
     */
    public function lignes(Recette $recette): array
    {
        $lignes = [];

        $brutes = DB::table('ingredients_recette')
            ->where('recette_id', $recette->id)
            ->orderBy('article_id')
            ->get(['article_id', 'quantite_unitaire']);

        foreach ($brutes as $brute) {
            $lignes[] = [
                'article_id' => (string) $brute->article_id,
                'quantite_unitaire' => bcadd((string) $brute->quantite_unitaire, '0', self::PRECISION_QUANTITE),
            ];
        }

        return $lignes;
    }
}
