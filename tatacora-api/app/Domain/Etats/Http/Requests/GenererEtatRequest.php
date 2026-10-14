<?php

declare(strict_types=1);

namespace App\Domain\Etats\Http\Requests;

use App\Domain\Etats\Services\CatalogueEtatsService;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Demande d'édition d'un état — EF-M14-03, EF-M14-04.
 *
 * L'autorisation n'est **pas** décidée ici : le niveau d'accès dépend du module
 * source de l'état demandé, que `GenerateurEtatService` seul connaît. Une
 * vérification ici dupliquerait la matrice RBAC à un second endroit, où elle
 * finirait par diverger.
 */
class GenererEtatRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            // Liste fermée : un code inconnu est refusé en 422 plutôt que de
            // remonter en exception depuis le catalogue.
            'etat' => ['required', 'string', Rule::in(app(CatalogueEtatsService::class)->codesDisponibles())],
            'format' => ['sometimes', Rule::in(['pdf', 'excel', 'csv'])],

            // Filtres libres, mais bornés : ce sont eux qui sont archivés
            // (EF-M14-06) et imprimés en tête du document.
            'filtres' => ['sometimes', 'array'],
            'filtres.*' => ['nullable', 'string', 'max:255'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'etat.in' => __('rapports.etat_inconnu', ['code' => (string) $this->input('etat')]),
            'format.in' => __('rapports.format_inconnu', ['format' => (string) $this->input('format')]),
        ];
    }
}
