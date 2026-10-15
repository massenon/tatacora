<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Valide la création d'une unité d'hébergement — EF-M1-01.
 *
 * Sortie de `Hebergement::enregistrerUnite()` le 15/10/2026, pour la même
 * raison que `EnregistrerCategorieHebergementRequest` : la synchronisation
 * (lot S2) devient le second lecteur de ces règles, et il n'en faut qu'une
 * liste.
 *
 * ⚠ `statut` n'est PAS une règle, donc jamais une donnée validée : le cycle
 * opérationnel appartient à `SejourService`, et une unité créée entre au parc
 * `libre` (`ParcHebergementService::creerUnite()`). Le laisser choisir ferait
 * dire à l'écran qu'une chambre est occupée sans que personne y dorme.
 */
final class EnregistrerUniteHebergementRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->niveauSurModule('M1') === 'C';
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'numero' => ['required', 'string', 'max:50'],
            'categorie_id' => ['required', 'uuid', 'exists:categories_hebergement,id'],
            'id' => ['sometimes', 'uuid', Rule::unique('unites_hebergement', 'id')],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'numero.required' => __('hebergement.validation.unite_numero_obligatoire'),
            'categorie_id.required' => __('hebergement.validation.unite_categorie_obligatoire'),
            'categorie_id.exists' => __('hebergement.validation.unite_categorie_inexistante'),
        ];
    }
}
