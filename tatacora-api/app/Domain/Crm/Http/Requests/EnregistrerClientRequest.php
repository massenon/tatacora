<?php

declare(strict_types=1);

namespace App\Domain\Crm\Http\Requests;

use App\Domain\Crm\Models\Client;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Valide la création et la modification d'une fiche client.
 *
 * **Ne bloque JAMAIS sur un doublon.** RG-18 impose un avertissement, pas un
 * refus : la détection est faite par `DetectionDoublonService` et remontée dans
 * la réponse (`meta.avertissement_doublon`), jamais transformée en erreur de
 * validation. Un FormRequest qui rejetterait un homonyme forcerait le
 * réceptionniste à déformer l'orthographe pour passer — recréant précisément le
 * doublon que la règle cherche à éviter.
 *
 * @see EF-M3-01 Fiche client unique
 * @see EF-M3-03 Segmentation de la clientèle
 * @see RG-18
 */
final class EnregistrerClientRequest extends FormRequest
{
    public function authorize(): bool
    {
        $client = $this->route('client');

        return $client instanceof Client
            ? ($this->user()?->can('update', $client) ?? false)
            : ($this->user()?->can('create', Client::class) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'nom' => ['required', 'string', 'max:255'],
            'prenom' => ['nullable', 'string', 'max:255'],
            'telephone' => ['required', 'string', 'max:255'],
            'email' => ['nullable', 'email', 'max:255'],
            'piece_identite' => ['nullable', 'string', 'max:255'],
            // EF-M3-03 — segmentation : liste fermée, jamais du texte libre.
            'type_client' => ['required', Rule::in(['particulier', 'groupe', 'agence', 'structure'])],
            // EF-M3-04 — solde. Voir la note du contrôleur : cette valeur devra
            // vraisemblablement devenir calculée une fois M2 livré.
            'solde' => ['sometimes', 'numeric'],
            'id' => ['sometimes', 'uuid'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'nom.required' => __('crm.validation.nom_requis'),
            'telephone.required' => __('crm.validation.telephone_requis'),
            'type_client.required' => __('crm.validation.type_requis'),
            'type_client.in' => __('crm.validation.type_invalide'),
        ];
    }
}
