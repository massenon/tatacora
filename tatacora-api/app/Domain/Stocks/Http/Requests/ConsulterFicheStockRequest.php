<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Période et portée d'une fiche de stock — EF-M6-04.
 *
 * Les deux dates sont **obligatoires**. Une fiche de stock est un flux sur une
 * plage : lui donner une période par défaut muette produirait un document dont
 * personne ne saurait dire ce qu'il couvre, alors que son objet est justement
 * de justifier un solde.
 */
final class ConsulterFicheStockRequest extends FormRequest
{
    /** Le middleware `module:M6,L` de la route porte le contrôle d'accès. */
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
            'debut' => ['required', 'date_format:Y-m-d'],
            'fin' => ['required', 'date_format:Y-m-d', 'after_or_equal:debut'],
            'point_id' => ['sometimes', 'nullable', 'uuid', 'exists:points_stockage,id'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'debut.required' => __('stocks.validation.periode_obligatoire'),
            'fin.required' => __('stocks.validation.periode_obligatoire'),
            'fin.after_or_equal' => __('stocks.validation.periode_inversee'),
            'point_id.exists' => __('stocks.validation.point_inexistant'),
        ];
    }

    public function pointId(): ?string
    {
        $valeur = $this->input('point_id');

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
