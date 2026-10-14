<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Requests;

use App\Domain\Achats\Models\Fournisseur;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtres du référentiel fournisseurs — EF-M7-01.
 *
 * Le filtre `evaluation` porte un `Rule::in` sur le registre du **schéma**
 * (`excellent`, `bon`, `moyen`, `a_revoir`), pas sur les libellés du prototype
 * (« Excellent », « À revoir »). Un filtre mal orthographié qui serait
 * silencieusement ignoré rendrait le référentiel entier sous un intitulé qui
 * promet « À revoir » — et un acheteur passerait commande sur cette base
 * (même famille que PA-119).
 */
final class FiltrerFournisseursRequest extends FormRequest
{
    /**
     * Le contrôle d'accès en lecture est porté par le middleware `module:M7,L`
     * de la route. Le redoubler ici renverrait 403 sur un chemin déjà fermé.
     */
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
            'evaluation' => ['sometimes', 'nullable', Rule::in(Fournisseur::EVALUATIONS)],
            'categorie' => ['sometimes', 'nullable', 'string', 'max:255'],
            'par_page' => ['sometimes', 'integer', 'min:1', 'max:' . Fournisseur::PAR_PAGE_MAX],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'evaluation.in' => __('achats.validation.evaluation_inconnue'),
            'par_page.max' => __('achats.validation.page_trop_grande', ['max' => Fournisseur::PAR_PAGE_MAX]),
        ];
    }

    public function parPage(): int
    {
        return (int) $this->input('par_page', Fournisseur::PAR_PAGE_DEFAUT);
    }

    public function filtre(string $nom): ?string
    {
        $valeur = $this->input($nom);

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
