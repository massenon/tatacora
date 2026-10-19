<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Requests;

use App\Shared\Sync\Services\CatalogueDescendantService;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Valide une demande de page du catalogue — `GET /api/v1/referentiels`
 * (décision du Product Owner du 15/10/2026).
 *
 * `poste_id` est OBLIGATOIRE, comme à la montée : il choisit les
 * correspondances renvoyées, et il est confronté au jeton (`PosteDuJeton`).
 * `depuis` est le curseur OPAQUE rendu par la page précédente ; absent, le
 * téléchargement part du début. `limite` est plafonnée : une page trop
 * grosse tiendrait la connexion d'un site isolé ouverte trop longtemps.
 */
final class TelechargerReferentielsRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Le jeton Sanctum suffit ici : le droit se vérifie TABLE PAR TABLE
        // dans le service (une table non lue est simplement absente du flux).
        return $this->user() !== null;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'poste_id' => ['required', 'string', 'max:255'],
            'depuis' => ['sometimes', 'nullable', 'string', 'max:8192'],
            'limite' => ['sometimes', 'integer', 'min:1', 'max:' . CatalogueDescendantService::TAILLE_PAGE_MAX],
            // Bouton « Synchroniser » (18/10/2026) : la file que le poste
            // déclare en attente, affichée par la PWA.
            'en_attente' => ['sometimes', 'integer', 'min:0'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'limite.max' => __('sync.referentiels.limite_trop_grande', ['max' => CatalogueDescendantService::TAILLE_PAGE_MAX]),
        ];
    }
}
