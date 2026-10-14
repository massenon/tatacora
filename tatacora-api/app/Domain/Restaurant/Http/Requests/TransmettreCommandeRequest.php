<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\CommandeRestaurant;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Transmission en cuisine — EF-M4-05, et c'est ICI que RG-05 s'applique.
 *
 * ## `validation_rupture` est une décision, jamais un défaut
 *
 * RG-06 autorise une sortie en rupture **assumée par un utilisateur habilité**,
 * jamais subie en silence. Le drapeau arrive donc du client après confirmation
 * explicite, et vaut `false` en l'absence de champ. L'inverser par commodité
 * ferait passer chaque rupture inaperçue, et le stock deviendrait négatif sans
 * que personne n'ait rien décidé.
 */
final class TransmettreCommandeRequest extends FormRequest
{
    public function authorize(): bool
    {
        $commande = $this->route('commande');

        return $commande instanceof CommandeRestaurant
            && ($this->user()?->can('update', $commande) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'validation_rupture' => ['sometimes', 'boolean'],

            // Le statut résulte de la transmission, il ne l'accompagne pas.
            'statut' => ['prohibited'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'statut.prohibited' => __('restaurant.validation.statut_non_saisissable'),
        ];
    }

    public function validationRupture(): bool
    {
        return (bool) $this->input('validation_rupture', false);
    }
}
