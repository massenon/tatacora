<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\Menu;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtres du référentiel des menus — EF-M4-01, EF-M4-06.
 */
final class FiltrerMenusRequest extends FormRequest
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
            'type' => ['sometimes', 'nullable', Rule::in(Menu::TYPES)],
            'par_page' => ['sometimes', 'integer', 'min:1', 'max:' . Menu::PAR_PAGE_MAX],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'type.in' => __('restaurant.validation.categorie_inconnue'),
            'par_page.max' => __('restaurant.validation.page_trop_grande', ['max' => Menu::PAR_PAGE_MAX]),
        ];
    }

    public function parPage(): int
    {
        return (int) $this->input('par_page', Menu::PAR_PAGE_DEFAUT);
    }

    public function filtre(string $nom): ?string
    {
        $valeur = $this->input($nom);

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
