<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\CommandeRestaurant;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtres du registre des commandes — EF-M4-03.
 *
 * Le filtre `statut` porte un `Rule::in` sur le registre du **schéma**
 * (`en_preparation`, `transmise_cuisine`, …). Un statut mal orthographié
 * silencieusement ignoré rendrait le registre entier sous un intitulé qui
 * promet un sous-ensemble — PA-119, et ici l'erreur se paie en cuisine : un
 * écran « transmises » qui affiche tout ferait préparer des commandes annulées.
 */
final class FiltrerCommandesRestaurantRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'statut' => ['sometimes', 'nullable', Rule::in(CommandeRestaurant::STATUTS)],
            'client_id' => ['sometimes', 'nullable', 'uuid'],
            'table_ou_chambre_id' => ['sometimes', 'nullable', 'uuid'],
            'depuis' => ['sometimes', 'nullable', 'date'],
            'jusqu_a' => ['sometimes', 'nullable', 'date', 'after_or_equal:depuis'],
            'par_page' => ['sometimes', 'integer', 'min:1', 'max:' . CommandeRestaurant::PAR_PAGE_MAX],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'statut.in' => __('restaurant.validation.statut_inconnu'),
            'jusqu_a.after_or_equal' => __('restaurant.validation.periode_inversee'),
            'par_page.max' => __('restaurant.validation.page_trop_grande', [
                'max' => CommandeRestaurant::PAR_PAGE_MAX,
            ]),
        ];
    }

    public function parPage(): int
    {
        return (int) $this->input('par_page', CommandeRestaurant::PAR_PAGE_DEFAUT);
    }

    public function filtre(string $nom): ?string
    {
        $valeur = $this->input($nom);

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
