<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Requests;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Services\ConsultationStockService;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtres de la liste des articles — EF-M6-01, EF-M14-03.
 *
 * ## Pourquoi valider une lecture
 *
 * Un filtre mal orthographié qui serait simplement ignoré rendrait le
 * référentiel ENTIER sous une interface qui affiche « En rupture ». L'écran
 * dirait donc le contraire de ce qu'il montre, et le magasinier commanderait
 * sur cette base. C'est la même famille de défaut que PA-119 : un état doit
 * dire son filtre, et un filtre incompris doit se refuser — pas se taire.
 *
 * `point_id` porte un `exists` pour la même raison : un identifiant obsolète
 * (point supprimé, faute de frappe) rendrait un stock de zéro partout, ce qui
 * se lit « rupture générale » alors que la réalité est « je ne sais pas de
 * quel point vous parlez ».
 */
final class FiltrerArticlesRequest extends FormRequest
{
    /**
     * Le contrôle d'accès en lecture est porté par le middleware `module:M6,L`
     * de la route. Le redoubler ici renverrait 403 sur un chemin déjà fermé,
     * sans rien ajouter.
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
            'categorie' => ['sometimes', 'nullable', 'string', 'max:255'],
            'point_id' => ['sometimes', 'nullable', 'uuid', 'exists:points_stockage,id'],
            'etat' => ['sometimes', 'nullable', Rule::in(ConsultationStockService::ETATS)],
            // Registre FERMÉ, pour la même raison que `etat` : un « permanant »
            // mal orthographié rendrait le référentiel entier sous un
            // intitulé qui promet le contraire.
            'suivi' => ['sometimes', 'nullable', Rule::in(Article::SUIVIS)],
            'par_page' => [
                'sometimes',
                'integer',
                'min:1',
                'max:' . ConsultationStockService::PAR_PAGE_MAX,
            ],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'etat.in' => __('stocks.validation.etat_inconnu'),
            'suivi.in' => __('stocks.validation.suivi_inconnu'),
            'point_id.exists' => __('stocks.validation.point_inexistant'),
            'par_page.max' => __('stocks.validation.page_trop_grande', [
                'max' => ConsultationStockService::PAR_PAGE_MAX,
            ]),
        ];
    }

    public function parPage(): int
    {
        return (int) $this->input('par_page', ConsultationStockService::PAR_PAGE_DEFAUT);
    }

    public function filtre(string $nom): ?string
    {
        $valeur = $this->input($nom);

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
