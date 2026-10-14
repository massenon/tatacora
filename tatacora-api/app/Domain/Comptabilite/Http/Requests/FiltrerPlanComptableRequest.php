<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Requests;

use App\Domain\Comptabilite\Models\CompteComptable;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Filtre du plan comptable — `m10-plan-comptable.html`.
 *
 * Le maitre n'offre qu'un controle : les huit boutons de classe, « Toutes les
 * classes » puis les sept classes (l.32, l.71-74). Pas de barre de recherche,
 * donc pas de parametre de recherche : ajouter un filtre que l'ecran n'a pas
 * violerait l'Article 1, et personne ne l'appellerait.
 *
 * ## Le registre validé est celui du SCHEMA, pas celui de l'ecran
 *
 * `Rule::in(CLASSES_SYSCOHADA)` admet 1 a 9. L'ecran n'expose que 1 a 7, mais
 * refuser `8` ici rendrait les comptes HAO inaccessibles par tout chemin, alors
 * que le decompte de la reponse annonce justement leur existence. Refuser une
 * valeur dont on vient de signaler qu'elle existe serait une impasse.
 */
final class FiltrerPlanComptableRequest extends FormRequest
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
            'classe' => ['sometimes', 'nullable', Rule::in(CompteComptable::CLASSES_SYSCOHADA)],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'classe.in' => __('comptabilite.validation.classe_inconnue', [
                'valeurs' => implode(', ', CompteComptable::CLASSES_SYSCOHADA),
            ]),
        ];
    }

    public function classe(): ?string
    {
        $valeur = $this->input('classe');

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
