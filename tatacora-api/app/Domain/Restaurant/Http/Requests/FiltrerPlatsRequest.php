<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtres du catalogue de plats — EF-M4-01.
 *
 * Les deux contrôles de la barre d'outils du maître
 * (`m4-restauration.html` : « Rechercher un plat... » et « Toutes les
 * catégories »), plus la pagination.
 */
final class FiltrerPlatsRequest extends FormRequest
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
            'recherche' => ['sometimes', 'nullable', 'string', 'max:255'],
            'categorie' => ['sometimes', 'nullable', Rule::in(Menu::TYPES)],
            'menu_id' => ['sometimes', 'nullable', 'uuid', 'exists:menus,id'],
            'par_page' => ['sometimes', 'integer', 'min:1', 'max:' . Plat::PAR_PAGE_MAX],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'categorie.in' => __('restaurant.validation.categorie_inconnue'),
            'menu_id.exists' => __('restaurant.validation.menu_inexistant'),
            'par_page.max' => __('restaurant.validation.page_trop_grande', ['max' => Plat::PAR_PAGE_MAX]),
        ];
    }

    public function parPage(): int
    {
        return (int) $this->input('par_page', Plat::PAR_PAGE_DEFAUT);
    }

    public function filtre(string $nom): ?string
    {
        $valeur = $this->input($nom);

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
