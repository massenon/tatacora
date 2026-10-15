<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Valide la création d'une catégorie d'hébergement — EF-M1-01.
 *
 * ## Les règles de la modale « Unité » de la PWA, sorties du composant (15/10/2026)
 *
 * Elles étaient écrites dans `Hebergement::enregistrerUnite()`, seul endroit
 * qui créait une catégorie. Le lot S2 de synchronisation (décision du Product
 * Owner du 15/10/2026 : un poste peut créer une catégorie hors connexion, le
 * serveur la fusionne sur son libellé) en fait un second lecteur : deux
 * listes auraient divergé au premier durcissement. Elles vivent donc ici, et
 * la PWA comme la synchronisation les lisent par `ReglesDeLApi`.
 *
 * Aucune route d'API ne l'emploie encore : le parc se modifie à l'écran PWA.
 *
 * La catégorie naît AVEC son tarif réel et sa capacité — jamais un zéro
 * d'attente qui se lirait comme une nuit gratuite.
 */
final class EnregistrerCategorieHebergementRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->niveauSurModule('M1') === 'C';
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            // Hors la catégorie elle-même quand elle est MODIFIÉE (paramètre
            // de route `categorie`, posé par la synchronisation depuis la
            // décision PO du 15/10/2026) : garder son propre libellé n'est pas
            // un doublon.
            'libelle' => ['required', 'string', 'max:100', Rule::unique('categories_hebergement', 'libelle')
                ->ignore($this->route('categorie'))],
            'tarif_base' => ['required', 'numeric', 'gt:0'],
            'capacite_max' => ['required', 'integer', 'min:1', 'max:20'],
            'id' => ['sometimes', 'uuid', Rule::unique('categories_hebergement', 'id')],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'libelle.required' => __('hebergement.validation.categorie_libelle_obligatoire'),
            'tarif_base.gt' => __('hebergement.validation.categorie_tarif_positif'),
        ];
    }
}
