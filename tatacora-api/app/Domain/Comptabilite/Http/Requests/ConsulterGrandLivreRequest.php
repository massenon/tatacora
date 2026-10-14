<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Requests;

/**
 * Selection du Grand Livre — `m10-grand-livre.html`.
 *
 * `compte_id` est OBLIGATOIRE : le maitre n'a pas d'etat « aucun compte
 * choisi », il preselectionne le premier compte mouvemente (l.83). Un Grand
 * Livre sans compte n'existe pas — c'est le Journal General.
 *
 * Le compte demande peut n'avoir AUCUN mouvement : la reponse est alors une
 * liste vide, jamais un 404. Le compte existe, c'est son activite qui est
 * nulle, et le maitre a un message pour exactement ce cas (l.29).
 */
final class ConsulterGrandLivreRequest extends RequeteExerciceRequest
{
    /**
     * @return array<string, array<int, mixed>>
     */
    protected function reglesSupplementaires(): array
    {
        return [
            'compte_id' => ['required', 'uuid', 'exists:plan_comptable,id'],
        ];
    }

    /**
     * @return array<string, string>
     */
    protected function messagesSupplementaires(): array
    {
        return [
            'compte_id.required' => __('comptabilite.validation.compte_requis'),
            'compte_id.exists' => __('comptabilite.validation.compte_inexistant'),
        ];
    }

    public function compteId(): string
    {
        return (string) $this->input('compte_id');
    }
}
