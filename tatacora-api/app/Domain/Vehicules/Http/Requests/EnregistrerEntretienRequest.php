<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Validation d'un entretien ou d'une carburation — EF-M8-05.
 *
 * Créée au lot 0b (PA-159) : ces règles vivaient EN LIGNE dans
 * `VehiculeController::enregistrerEntretien`, donc la PWA n'aurait eu aucune
 * source de règles à réutiliser via `ReglesDeLApi`. Elles sont reprises À
 * L'IDENTIQUE — le contrat HTTP ne change pas.
 *
 * ## `authorize()` rend `true`, et ce n'est pas un trou
 *
 * Le RBAC est tenu par le middleware de la route (`module:M8,C`), comme il
 * l'était avant l'extraction. Aucune `EntretienVehiculePolicy` n'existe — en
 * inventer une ici ajouterait un second refus là où la validation en ligne
 * n'en portait aucun, c'est-à-dire changerait le contrat. La question d'une
 * policy dédiée appartient à l'Architecte (même famille que les 20 policies
 * héritées de `BasePolicy`).
 */
class EnregistrerEntretienRequest extends FormRequest
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
            // Vraie clé étrangère avec vérification d'existence, jamais du
            // texte libre (règle projet).
            'vehicule_id' => ['required', 'uuid', 'exists:vehicules,id'],
            // Registre fermé : les deux natures de dépense du suivi de parc.
            'type' => ['required', Rule::in(['entretien', 'carburation'])],
            'date' => ['required', 'date'],
            'cout' => ['required', 'numeric', 'min:0'],
            'chauffeur_id' => ['sometimes', 'nullable', 'uuid', 'exists:employes,id'],
        ];
    }
}
