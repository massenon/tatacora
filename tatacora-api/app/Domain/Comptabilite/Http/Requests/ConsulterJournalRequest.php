<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Requests;

/**
 * Filtres du Journal General — `m10-journal.html`.
 *
 * Le maitre n'offre qu'UN controle : la barre de boutons de journaux (l.32,
 * l.76-79), « Tous les journaux » par defaut. Aucun autre filtre n'est ajoute
 * ici : l'Article 1 de `DIRECTIVE_CONFORMITE_100.md` interdit d'ajouter un
 * controle non maquette, et un parametre que l'ecran ne sait pas produire est
 * un parametre que personne n'appellera (PA-63).
 *
 * `statut` fait exception et vient du socle : ce n'est pas un controle
 * d'ecran, c'est la portee de l'etat — voir `RequeteExerciceRequest`.
 */
final class ConsulterJournalRequest extends RequeteExerciceRequest
{
    /**
     * @return array<string, array<int, mixed>>
     */
    protected function reglesSupplementaires(): array
    {
        return [
            'journal_id' => ['sometimes', 'nullable', 'uuid', 'exists:journaux_comptables,id'],
        ];
    }

    /**
     * @return array<string, string>
     */
    protected function messagesSupplementaires(): array
    {
        return [
            'journal_id.exists' => __('comptabilite.validation.journal_inexistant'),
        ];
    }

    public function journalId(): ?string
    {
        $valeur = $this->input('journal_id');

        return is_string($valeur) && $valeur !== '' ? $valeur : null;
    }
}
