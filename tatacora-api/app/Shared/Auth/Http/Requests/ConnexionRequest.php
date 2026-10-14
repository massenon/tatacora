<?php

declare(strict_types=1);

namespace App\Shared\Auth\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Validation de la demande de connexion.
 *
 * Le vocabulaire est celui du schéma — `login`, `mot_de_passe` — et non le
 * `email`/`password` par défaut de Laravel : le Gîte n'authentifie pas par
 * adresse e-mail, plusieurs comptes n'en ont aucune.
 *
 * @see EF-M0-01
 */
final class ConnexionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            'identifiant' => ['required', 'string', 'max:100'],
            'mot_de_passe' => ['required', 'string'],
            // Nom du poste, tracé au journal d'audit et utilisé par la
            // résolution de conflits pour distinguer deux écritures
            // concurrentes venant de postes différents (RG-15,
            // LARAVEL_SYNC_FLUTTER.md §4.1).
            'poste' => ['sometimes', 'string', 'max:100'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function attributes(): array
    {
        return [
            'identifiant' => __('auth.identifiant'),
            'mot_de_passe' => __('auth.mot_de_passe'),
        ];
    }
}
