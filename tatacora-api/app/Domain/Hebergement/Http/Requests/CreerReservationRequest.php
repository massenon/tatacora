<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Http\Requests;

use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Services\DisponibiliteService;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Valide la création d'une réservation d'hébergement.
 *
 * Reproduit le gabarit de référence de 06_DEVELOPMENT_STANDARDS.md §2.3.
 *
 * @see EF-M1-02 Création, modification et annulation de réservation
 * @see EF-M1-03 Prévention des doubles réservations (RG-01)
 */
final class CreerReservationRequest extends FormRequest
{
    public function authorize(): bool
    {
        // 2e niveau RBAC (le 1er est le masquage UI Flutter,
        // cf. 00_MASTER_INSTRUCTIONS.md §3.2)
        return $this->user()?->can('create', Reservation::class) ?? false;
    }

    /**
     * @return array<string, array<int, string>>
     */
    public function rules(): array
    {
        return [
            // Vraies clés étrangères : jamais un nom de client saisi en texte
            // libre (RG-18, A1_MASTER_PROMPT.md §2.3).
            'client_id' => ['required', 'uuid', 'exists:clients,id'],
            'unite_id' => ['required', 'uuid', 'exists:unites_hebergement,id'],
            'date_arrivee' => ['required', 'date'],
            'date_depart' => ['required', 'date', 'after:date_arrivee'],
            'acompte' => ['sometimes', 'numeric', 'min:0'],
            // UUID fourni par le client Flutter lors d'une création hors
            // connexion (02_SOFTWARE_ARCHITECTURE.md §5) — le serveur ne le
            // réattribue jamais, il sert aussi de clé de déduplication.
            'id' => ['sometimes', 'uuid'],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            if ($validator->errors()->isNotEmpty()) {
                return;
            }

            // RG-01 : la garantie ultime reste VerificationChevauchementService
            // (verrou pessimiste en transaction, appelé par ReservationService).
            // Cette vérification-ci ne fait que produire un message d'erreur
            // exploitable AVANT l'écriture — elle ne la remplace pas, et ne peut
            // pas : entre cette lecture et l'insertion, un concurrent peut
            // insérer.
            $disponibilite = app(DisponibiliteService::class);

            $libre = $disponibilite->uniteEstDisponible(
                (string) $this->input('unite_id'),
                (string) $this->input('date_arrivee'),
                (string) $this->input('date_depart'),
            );

            if (! $libre) {
                $validator->errors()->add(
                    'unite_id',
                    'Cette unité est déjà réservée sur cette période (RG-01).',
                );
            }
        });
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        // Contenu visible utilisateur : en français (00_MASTER_INSTRUCTIONS.md §7)
        // et externalisé dans lang/fr/, jamais écrit en dur ici (06 §4.4).
        return [
            'client_id.exists' => __('hebergement.validation.client_inexistant'),
            'unite_id.exists' => __('hebergement.validation.unite_inexistante'),
            'date_depart.after' => __('hebergement.validation.depart_apres_arrivee'),
        ];
    }
}
