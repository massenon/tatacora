<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Http\Requests;

use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

/**
 * Validation d'un contrat de location — EF-M8-03, RG-09.
 *
 * ## RG-09 est une règle CONDITIONNELLE, pas un NOT NULL
 *
 * `01_BUSINESS_ANALYSIS_SPEC.md` §RG-09 : « règle conditionnelle, **pas une
 * contrainte NOT NULL générique sur la table** ». Les colonnes
 * `piece_identite` et `permis_conduire` sont donc nullable en base, et
 * l'exigence se décide à la validation, d'après la catégorie du véhicule
 * réellement loué.
 *
 * La condition n'est pas réécrite ici : elle vit dans
 * `Vehicule::exigePermis()`, appelée aussi par le service et exposable à
 * l'écran Flutter. Trois copies finiraient par diverger.
 */
class CreerContratLocationRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('create', ContratLocation::class) ?? false;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            // Vraie clé étrangère avec vérification d'existence, jamais du
            // texte libre (règle projet).
            'vehicule_id' => ['required', 'uuid', 'exists:vehicules,id'],
            'client_id' => ['required', 'uuid', 'exists:clients,id'],

            // EF-M8-04 — package véhicule + guide, optionnel.
            'guide_id' => ['sometimes', 'nullable', 'uuid', 'exists:guides,id'],

            'date_debut' => ['required', 'date'],
            // Contrainte CHECK en base (date_fin > date_debut) : doublée ici
            // pour rendre un 422 lisible plutôt qu'une erreur SQL brute.
            'date_fin' => ['required', 'date', 'after:date_debut'],

            // RG-09 — toujours exigée, quelle que soit la catégorie.
            'piece_identite' => ['required', 'string', 'max:255'],
            // Conditionnalité traitée en `withValidator()` : elle dépend d'une
            // ligne en base, pas d'un champ du formulaire.
            'permis_conduire' => ['nullable', 'string', 'max:255'],

            // UUID client pour l'idempotence hors connexion.
            'id' => ['sometimes', 'uuid'],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            $vehicule = Vehicule::find($this->input('vehicule_id'));

            if ($vehicule === null) {
                // La règle `exists` a déjà signalé le problème.
                return;
            }

            if ($vehicule->exigePermis() && blank($this->input('permis_conduire'))) {
                $validator->errors()->add(
                    'permis_conduire',
                    __('vehicules.permis_requis', ['categorie' => $vehicule->categorie]),
                );
            }

            if (! $vehicule->estLouable()) {
                $validator->errors()->add(
                    'vehicule_id',
                    __('vehicules.non_louable', ['statut' => $vehicule->statut]),
                );
            }
        });
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'vehicule_id.exists' => __('vehicules.validation.vehicule_inexistant'),
            'client_id.exists' => __('vehicules.validation.client_inexistant'),
            'guide_id.exists' => __('vehicules.validation.guide_inexistant'),
            'date_fin.after' => __('vehicules.validation.fin_apres_debut'),
            'piece_identite.required' => __('vehicules.piece_identite_requise'),
        ];
    }
}
