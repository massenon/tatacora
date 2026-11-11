<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Les règles d'un CIRCUIT (prestation touristique) — celles du formulaire
 * PWA (`Departs::enregistrerPrestation`), réunies ici au lot F4 (17/10/2026)
 * pour que la synchronisation d'un poste les applique à l'identique.
 *
 * Un écart, nommé : la DURÉE est facultative. Le poste peut créer un circuit
 * sans durée (texte libre, PA-51) ; le serveur la range vide, ce que
 * `ReservationTourService::dureeIndeterminee()` lit déjà « indéterminée ».
 */
final class EnregistrerCircuitRequest extends FormRequest
{
    /** Les thèmes de l'énumération `circuits.theme`. */
    public const THEMES = ['aventure', 'culture', 'faune', 'nature', 'autre'];

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
            'nom' => ['required', 'string', 'max:255'],
            'theme' => ['required', 'string', 'in:' . implode(',', self::THEMES)],
            'zone' => ['required', 'string', 'max:255'],
            'duree' => ['nullable', 'string', 'max:255'],
            'prix' => ['required', 'numeric', 'min:0'],
            'capacite_max' => ['required', 'integer', 'min:1', 'max:999'],
        ];
    }
}
