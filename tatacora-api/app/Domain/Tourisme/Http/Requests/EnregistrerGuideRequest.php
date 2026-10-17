<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Les règles d'un GUIDE — lot F4 (17/10/2026), pour la synchronisation des
 * guides créés sur un poste. Le tarif journalier est facultatif : le poste
 * ne le saisit pas (`guides_local` n'a pas la colonne) ; le gestionnaire
 * range 0 et SIGNALE l'absence (`guide_sans_tarif`), jamais un tarif deviné.
 */
final class EnregistrerGuideRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            'nom' => ['required', 'string', 'max:255'],
            'certification' => ['nullable', 'string', 'max:255'],
            'zone_competence' => ['nullable', 'string', 'max:255'],
            'tarif_jour' => ['nullable', 'numeric', 'min:0'],
        ];
    }
}
