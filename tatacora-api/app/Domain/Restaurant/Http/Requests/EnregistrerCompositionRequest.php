<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\Recette;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Composition d'une fiche technique — EF-M4-02, le sous-formulaire réclamé par
 * PA-23 en remplacement du textarea « Ingrédients principaux ».
 *
 * ## Un article ne peut pas figurer deux fois
 *
 * `ingredients_recette` a une clé primaire composite `(recette_id,
 * article_id)` : la seconde ligne lèverait une violation de contrainte MySQL,
 * illisible pour l'utilisateur. Mais surtout, le doublon a un sens métier faux
 * — deux lignes « huile 0,05 L » et « huile 0,10 L » veulent dire 0,15 L, pas
 * 0,10 L. Refuser, en nommant l'article, force à additionner les quantités
 * plutôt qu'à en perdre une en silence (même raisonnement que
 * `achats.validation.article_en_double`).
 *
 * ## Une composition VIDE est acceptée, et ce n'est pas un oubli
 *
 * Elle est le seul moyen de vider une fiche technique erronée. Sa conséquence
 * est réelle et visible : le plat apparaît « ne décrémente rien » sur la carte,
 * et `RecetteManquanteException` refuse sa transmission en cuisine. Interdire
 * le vide obligerait à laisser en place une composition fausse — bien pire,
 * puisqu'elle décrémenterait les mauvais articles sans que rien ne le signale.
 */
final class EnregistrerCompositionRequest extends FormRequest
{
    public function authorize(): bool
    {
        $recette = $this->route('recette');

        return $recette instanceof Recette
            && ($this->user()?->can('update', $recette) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            // `present` et non `required` : `required` rejette le tableau vide,
            // qui est ici un geste légitime (vider une fiche erronée).
            'lignes' => ['present', 'array'],

            // De VRAIES clés étrangères vers `articles` — jamais du texte
            // libre. C'est toute la différence entre une fiche technique et le
            // textarea du prototype (PA-23).
            'lignes.*.article_id' => ['required', 'uuid', 'exists:articles,id'],

            // DECIMAL(10,3) : les recettes s'expriment en grammes et
            // centilitres. `gt:0` — un ingrédient à zéro n'est pas un
            // ingrédient, c'est une ligne à retirer, et il fausserait le coût
            // matière en donnant l'impression qu'il a été compté.
            'lignes.*.quantite_unitaire' => ['required', 'numeric', 'gt:0', 'max:9999999'],

            // Le coût matière ne se soumet jamais : il se recalcule.
            'cout_matiere_calcule' => ['prohibited'],
            'cout_matiere' => ['prohibited'],
        ];
    }

    public function withValidator(\Illuminate\Validation\Validator $validator): void
    {
        $validator->after(function (\Illuminate\Validation\Validator $validator): void {
            $lignes = $this->input('lignes');

            if (! is_array($lignes)) {
                return;
            }

            $vus = [];

            foreach ($lignes as $index => $ligne) {
                $articleId = is_array($ligne) ? ($ligne['article_id'] ?? null) : null;

                if (! is_string($articleId)) {
                    continue;
                }

                if (isset($vus[$articleId])) {
                    $validator->errors()->add(
                        "lignes.{$index}.article_id",
                        __('restaurant.validation.ingredient_en_double'),
                    );
                }

                $vus[$articleId] = true;
            }
        });
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'lignes.present' => __('restaurant.validation.composition_absente'),
            'lignes.*.article_id.required' => __('restaurant.validation.article_obligatoire'),
            'lignes.*.article_id.exists' => __('restaurant.validation.article_inexistant'),
            'lignes.*.quantite_unitaire.required' => __('restaurant.validation.quantite_recette_obligatoire'),
            'lignes.*.quantite_unitaire.gt' => __('restaurant.validation.quantite_recette_positive'),
            'cout_matiere_calcule.prohibited' => __('restaurant.validation.cout_matiere_calcule'),
            'cout_matiere.prohibited' => __('restaurant.validation.cout_matiere_calcule'),
        ];
    }

    /**
     * Lignes normalisées pour le service — les quantités en chaîne, jamais en
     * flottant : `bcmath` est la convention du projet sur toute valeur qui
     * finit dans un montant.
     *
     * @return list<array{article_id: string, quantite_unitaire: string}>
     */
    public function lignes(): array
    {
        $lignes = [];

        /** @var array<int, array{article_id: string, quantite_unitaire: mixed}> $brutes */
        $brutes = $this->validated()['lignes'] ?? [];

        foreach ($brutes as $brute) {
            $lignes[] = [
                'article_id' => (string) $brute['article_id'],
                'quantite_unitaire' => (string) $brute['quantite_unitaire'],
            ];
        }

        return $lignes;
    }
}
