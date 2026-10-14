<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Requests;

use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtres du registre des bons de réception — EF-M7-03.
 *
 * L'onglet « Réceptions » du prototype filtre sur « Conformes » / « Avec
 * écart ». Le second regroupe `partielle` et `non_conforme` ; le filtre exposé
 * ici porte donc sur les trois valeurs réelles de l'enum, et le regroupement
 * reste l'affaire de l'écran — l'API ne doit pas perdre l'information que
 * `non_conforme` n'est pas `partielle`.
 */
final class FiltrerReceptionsRequest extends FormRequest
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
            'commande_id' => ['sometimes', 'nullable', 'uuid', 'exists:commandes_achat,id'],
            'conformite' => ['sometimes', 'nullable', Rule::in(BonReception::CONFORMITES)],
            'par_page' => ['sometimes', 'integer', 'min:1', 'max:' . CommandeAchat::PAR_PAGE_MAX],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'conformite.in' => __('achats.validation.conformite_inconnue'),
            'par_page.max' => __('achats.validation.page_trop_grande', ['max' => CommandeAchat::PAR_PAGE_MAX]),
        ];
    }

    public function parPage(): int
    {
        return (int) $this->input('par_page', CommandeAchat::PAR_PAGE_DEFAUT);
    }

    public function filtre(string $nom): ?string
    {
        $valeur = $this->input($nom);

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
