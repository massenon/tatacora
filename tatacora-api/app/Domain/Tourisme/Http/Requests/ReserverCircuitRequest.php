<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Http\Requests;

use App\Domain\Tourisme\Models\ReservationTour;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Validation d'une réservation de circuit — EF-M9-03, EF-M9-04.
 *
 * La capacité (EF-M9-04) n'est **pas** vérifiée ici : elle dépend des
 * réservations déjà prises sur le même départ, donc d'un état concurrent. La
 * contrôler sans verrou laisserait passer deux réservations sur le dernier
 * siège. Le contrôle vit dans `ReservationTourService`, sous verrou.
 */
class ReserverCircuitRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('create', ReservationTour::class) ?? false;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            // Vraies clés étrangères, jamais du texte libre (règle projet).
            'circuit_id' => ['required', 'uuid', 'exists:circuits,id'],
            'client_id' => ['required', 'uuid', 'exists:clients,id'],
            // NOT NULL au schema : une prestation ne peut pas exister sans
            // guide. UC-39 est donc une REaffectation (PA-51).
            'guide_id' => ['required', 'uuid', 'exists:guides,id'],

            'date_circuit' => ['required', 'date'],
            // Borne haute volontairement absente : la capacité réelle dépend
            // du circuit ET des réservations déjà prises, elle se contrôle
            // sous verrou. Une borne ici donnerait une fausse assurance.
            'nb_participants' => ['required', 'integer', 'min:1'],

            'id' => ['sometimes', 'uuid'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'circuit_id.exists' => __('tourisme.validation.circuit_inexistant'),
            'client_id.exists' => __('tourisme.validation.client_inexistant'),
            'guide_id.exists' => __('tourisme.validation.guide_inexistant'),
            'nb_participants.min' => __('tourisme.participants_minimum'),
        ];
    }
}
