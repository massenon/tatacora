<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Filtres de l'état des stocks consolidé — EF-M14-02, EF-M14-03.
 *
 * **Exactement les deux filtres de `EtatStocks`**, le générateur PDF/CSV du
 * même état (RG-19) : `point_id` et `sous_seuil`. En ajouter un ici — une
 * recherche par libellé, par exemple — ferait diverger l'écran du document
 * remis au Gérant, et les deux porteraient le même titre.
 */
final class ConsulterEtatStockRequest extends FormRequest
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
            'point_id' => ['sometimes', 'nullable', 'uuid', 'exists:points_stockage,id'],
            'sous_seuil' => ['sometimes', 'boolean'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'point_id.exists' => __('stocks.validation.point_inexistant'),
        ];
    }

    public function pointId(): ?string
    {
        $valeur = $this->input('point_id');

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
