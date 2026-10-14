<?php

declare(strict_types=1);

namespace App\Domain\Bar\Http\Requests;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Ventes\Models\Vente;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * « Ventes du Bar » — la LECTURE des lignes de vente du rayon M5, filtres de
 * l'onglet de la PWA (recherche, statut, plage de dates incluse, page).
 *
 * Le 2e niveau RBAC est la `Policy` en LECTURE (`viewAny`, `C` ou `L` sur
 * M5) : un barman en lecture consulte ce qu'il a vendu, comme dans la PWA.
 *
 * Une date illisible est REFUSÉE ici (422), là où l'écran PWA l'ignore : une
 * URL saisie à la main n'existe pas côté API, et un client qui envoie
 * « hier » a un défaut à corriger, pas un filtre à deviner.
 *
 * @see EF-M5 — carte du bar, onglet des ventes (PA-197)
 */
final class ConsulterVentesBarRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('viewAny', CarteBoisson::class) ?? false;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'recherche' => ['sometimes', 'nullable', 'string', 'max:100'],
            'statut' => ['sometimes', 'nullable', Rule::in(Vente::STATUTS)],
            'du' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'au' => ['sometimes', 'nullable', 'date_format:Y-m-d', 'after_or_equal:du'],
            'page' => ['sometimes', 'integer', 'min:1'],
        ];
    }
}
