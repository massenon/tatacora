<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\Menu;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Création et modification d'un menu — EF-M4-01 (mise à jour saisonnière) et
 * EF-M4-06 (événements culinaires, menus spéciaux).
 *
 * ## Pourquoi un écran de menus alors que le maître n'en montre pas
 *
 * `SPEC_ECRAN_M4_RESTAURANT.md` §7 et PA-23 le disent : le prototype ne montre
 * que la couche catalogue, jamais les workflows. Mais `plats.menu_id` est NOT
 * NULL — **aucun plat ne peut être créé sans menu existant**. Sans ces deux
 * routes, `POST /restaurant/plats` serait inutilisable sur une base neuve, et
 * l'écran de carte n'aurait jamais rien à afficher. C'est la même racine que
 * PA-128 : une donnée absente de l'API est une donnée absente du client.
 *
 * ## Les dates encadrent la saison, elles ne la déclarent pas
 *
 * `date_debut` et `date_fin` sont nullable au schéma : un menu permanent n'en
 * a pas. `date_fin` antérieure à `date_debut` est refusée — une saison qui
 * finit avant de commencer ne rendrait jamais aucun plat, et l'écran
 * afficherait une carte vide sans dire pourquoi.
 */
final class EnregistrerMenuRequest extends FormRequest
{
    public function authorize(): bool
    {
        $menu = $this->route('menu');

        return $menu instanceof Menu
            ? ($this->user()?->can('update', $menu) ?? false)
            : ($this->user()?->can('create', Menu::class) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        $modification = $this->route('menu') instanceof Menu;

        return [
            'libelle' => ['required', 'string', 'max:255'],

            // Registre FERMÉ : la colonne est un `enum` MySQL, et une valeur
            // hors liste serait rejetée par la base avec un message SQL
            // illisible plutôt que par une erreur de validation lisible.
            'type' => ['required', Rule::in(Menu::TYPES)],

            'date_debut' => ['sometimes', 'nullable', 'date'],
            'date_fin' => ['sometimes', 'nullable', 'date', 'after_or_equal:date_debut'],

            'id' => $modification
                ? ['prohibited']
                : ['sometimes', 'uuid', Rule::unique('menus', 'id')],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'libelle.required' => __('restaurant.validation.libelle_obligatoire'),
            'type.required' => __('restaurant.validation.categorie_obligatoire'),
            'type.in' => __('restaurant.validation.categorie_inconnue'),
            'date_fin.after_or_equal' => __('restaurant.validation.saison_inversee'),
            'id.prohibited' => __('restaurant.validation.identifiant_non_modifiable'),
        ];
    }
}
