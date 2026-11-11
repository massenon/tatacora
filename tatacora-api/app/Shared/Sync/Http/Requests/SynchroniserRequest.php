<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Requests;

use App\Shared\Sync\Services\SynchronisationService;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Valide un lot de synchronisation — LARAVEL_SYNC_FLUTTER.md §2.1 et §7.
 *
 * La taille de lot est plafonnee a 50 operations : au-dela, le client decoupe.
 * Ce n'est pas une precaution de confort — un lot trop gros tient la
 * transaction ouverte plus longtemps sur une connexion de mauvaise qualite, et
 * le NFR « moins de 2 s » est exige MEME en conditions degradees.
 */
final class SynchroniserRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Le jeton Sanctum suffit : jamais de synchronisation anonyme, meme
        // temporaire (LARAVEL_SYNC_FLUTTER.md §8).
        return $this->user() !== null;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'poste_id' => ['required', 'string', 'max:255'],
            'operations' => ['required', 'array', 'min:1', 'max:' . SynchronisationService::TAILLE_LOT_MAX],

            // uuid_operation identifie la TENTATIVE, entite_id l'enregistrement
            // metier : les confondre casserait l'idempotence (§2.1).
            'operations.*.uuid_operation' => ['required', 'uuid'],
            'operations.*.table' => ['required', 'string'],
            'operations.*.type' => ['required', Rule::in(['creation', 'modification', 'suppression'])],
            'operations.*.entite_id' => ['required', 'uuid'],
            'operations.*.payload' => ['required', 'array'],

            // ⚠ `payload.date_metier` (D246, 15/10/2026) n'est PAS validee ici :
            // une regle sur une sous-cle fait rendre a `validated()` le payload
            // reduit a ses seules sous-cles validees — le document entier
            // disparaissait (essaye le 15/10/2026). Elle est controlee par
            // operation dans `SynchronisationService::contexte()`, et une date
            // illisible y est un rejet de l'operation, pas du lot.

            // Horodatage de l'APPAREIL au moment de la saisie, jamais celui de
            // reception serveur : c'est lui qui arbitre le last-write-wins.
            'operations.*.horodatage_client' => ['required', 'date'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'operations.max' => __('sync.lot_trop_grand', ['max' => SynchronisationService::TAILLE_LOT_MAX]),
            'operations.*.horodatage_client.required' => __('sync.horodatage_obligatoire'),
        ];
    }
}
