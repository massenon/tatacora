<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\Recette;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Création d'une fiche technique — EF-M4-02.
 *
 * ## `cout_matiere_calcule` est REFUSÉ à la saisie
 *
 * C'est une valeur calculée : somme des quantités de la composition
 * multipliées par le coût moyen pondéré de chaque article (M6). L'accepter en
 * saisie la ferait diverger de sa composition dès le premier ingrédient
 * ajouté, et personne ne le verrait — c'est le premier des anti-patterns du
 * prototype (« Net à payer » saisi, « Stock disponible » éditable) et la
 * deuxième des six règles sans exception du projet.
 *
 * Le seul chemin qui l'écrit est `CompositionRecetteService::recalculer()`,
 * appelé par `PUT /restaurant/recettes/{recette}/composition`.
 */
final class EnregistrerRecetteRequest extends FormRequest
{
    /**
     * @var list<string>
     */
    public const CHAMPS_CALCULES = [
        'cout_matiere_calcule',
        'cout_matiere',
        'marge',
    ];

    public function authorize(): bool
    {
        $recette = $this->route('recette');

        return $recette instanceof Recette
            ? ($this->user()?->can('update', $recette) ?? false)
            : ($this->user()?->can('create', Recette::class) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        $modification = $this->route('recette') instanceof Recette;

        $regles = [
            'libelle' => ['required', 'string', 'max:255'],
            'id' => $modification
                ? ['prohibited']
                : ['sometimes', 'uuid', Rule::unique('recettes', 'id')],
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
            $regles[$champ] = ['prohibited'];
        }

        return $regles;
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        $messages = [
            'libelle.required' => __('restaurant.validation.libelle_obligatoire'),
            'id.prohibited' => __('restaurant.validation.identifiant_non_modifiable'),
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
            $messages[$champ . '.prohibited'] = __('restaurant.validation.cout_matiere_calcule');
        }

        return $messages;
    }
}
