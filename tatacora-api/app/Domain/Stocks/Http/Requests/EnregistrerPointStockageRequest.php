<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Requests;

use App\Domain\Stocks\Models\PointStockage;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Valide la création d'un point de stockage — EF-M6-01.
 *
 * ## Une requête sans route, et pourquoi elle existe quand même (15/10/2026)
 *
 * Le serveur n'a jamais créé de point : les quatre points du Gîte sont semés
 * (`StocksSeeder`) et ni l'API ni la PWA n'offrent de formulaire. Le poste
 * Flutter, lui, en crée (`StocksDao.creerPoint`, modales « Mouvement » et
 * « Nouvel article »), et la décision du Product Owner du 15/10/2026 les fait
 * remonter : sans création côté serveur, un mouvement ou une réception
 * imputés à ce point seraient rejetés en S3 pour une raison que
 * l'utilisateur ne comprendrait pas (« point inconnu », alors qu'il l'a créé).
 *
 * Les règles vivent ici, à la place où vivent celles de tous les autres
 * référentiels : la synchronisation les lit par `ReglesDeLApi`, et la route
 * d'API qui viendrait un jour lirait les mêmes — jamais une seconde liste.
 *
 * Mêmes contraintes que le poste : libellé obligatoire, type dans le registre
 * fermé `PointStockage::TYPES` ou absent. Aucune contrainte d'unicité ici : à
 * l'écran elle serait la bienvenue, mais la synchronisation FUSIONNE un
 * libellé déjà pris au lieu de le refuser (`GestionnairePointsStockage`).
 */
final class EnregistrerPointStockageRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->niveauSurModule('M6') === 'C';
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'libelle' => ['required', 'string', 'max:255'],
            'type' => ['sometimes', 'nullable', Rule::in(PointStockage::TYPES)],
            'id' => ['sometimes', 'uuid', Rule::unique('points_stockage', 'id')],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'libelle.required' => __('stocks.validation.point_libelle_obligatoire'),
            'type.in' => __('stocks.validation.point_type_inconnu'),
            'id.unique' => __('stocks.validation.point_identifiant_deja_pris'),
        ];
    }
}
