<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Requests;

use App\Domain\Achats\Models\CommandeAchat;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtres du registre des commandes d'achat — EF-M7-02.
 *
 * Le filtre `statut` couvre les CINQ valeurs de l'enum, y compris les trois
 * que l'on ne peut pas saisir : on filtre un état constaté, on ne le pose pas.
 * Confondre les deux registres a été soigneusement évité —
 * `CommandeAchatService::STATUTS_SAISISSABLES` n'est pas la même liste, et ce
 * n'est pas un oubli.
 */
final class FiltrerCommandesRequest extends FormRequest
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
            'statut' => ['sometimes', 'nullable', Rule::in(CommandeAchat::STATUTS)],
            'fournisseur_id' => ['sometimes', 'nullable', 'uuid', 'exists:fournisseurs,id'],
            'par_page' => ['sometimes', 'integer', 'min:1', 'max:' . CommandeAchat::PAR_PAGE_MAX],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'statut.in' => __('achats.validation.statut_inconnu'),
            'fournisseur_id.exists' => __('achats.validation.fournisseur_inexistant'),
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
