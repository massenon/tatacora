<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtres du journal des mouvements — EF-M6-04, EF-M6-06.
 *
 * Le type accepte les QUATRE valeurs du schéma, `inventaire` compris : on
 * consulte les régularisations d'inventaire, même si on ne les saisit pas
 * (voir `EnregistrerMouvementRequest`). Lire et écrire n'ont pas le même
 * registre, et les confondre masquerait la moitié de l'historique.
 */
final class FiltrerMouvementsRequest extends FormRequest
{
    /** Registre du schéma — `enum('entree','sortie','perte','inventaire')`. */
    public const TYPES_CONSULTABLES = ['entree', 'sortie', 'perte', 'inventaire'];

    public const PAR_PAGE_DEFAUT = 50;

    public const PAR_PAGE_MAX = 200;

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
            'article_id' => ['sometimes', 'nullable', 'uuid', 'exists:articles,id'],
            'point_id' => ['sometimes', 'nullable', 'uuid', 'exists:points_stockage,id'],
            'type_mouvement' => ['sometimes', 'nullable', Rule::in(self::TYPES_CONSULTABLES)],
            'date_debut' => ['sometimes', 'nullable', 'date'],
            // `after_or_equal` et non `after` : une consultation sur une seule
            // journée est le cas le plus courant au comptoir.
            'date_fin' => ['sometimes', 'nullable', 'date', 'after_or_equal:date_debut'],
            'par_page' => ['sometimes', 'integer', 'min:1', 'max:' . self::PAR_PAGE_MAX],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'type_mouvement.in' => __('stocks.validation.type_inconnu'),
            'article_id.exists' => __('stocks.validation.article_inexistant'),
            'point_id.exists' => __('stocks.validation.point_inexistant'),
            'date_fin.after_or_equal' => __('stocks.validation.periode_inversee'),
            'par_page.max' => __('stocks.validation.page_trop_grande', ['max' => self::PAR_PAGE_MAX]),
        ];
    }

    public function parPage(): int
    {
        return (int) $this->input('par_page', self::PAR_PAGE_DEFAUT);
    }

    public function filtre(string $nom): ?string
    {
        $valeur = $this->input($nom);

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
