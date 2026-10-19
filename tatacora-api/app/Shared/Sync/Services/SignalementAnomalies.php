<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Support\ContexteSynchronisation;

/**
 * Seul auteur de `anomalies_synchronisation` — lot S3, décisions du Product
 * Owner du 15/10/2026.
 *
 * Un document synchronisé décrit un fait accompli : le serveur l'enregistre
 * tel quel et SIGNALE ce qui s'écarte de ce qu'il aurait calculé (prix du
 * catalogue, stock, théorique de caisse, verdict RG-10). Ce service écrit le
 * signalement DANS la transaction du document : un document annulé n'a pas
 * d'anomalie orpheline, un document écrit a toujours la sienne.
 *
 * Idempotent par l'unicité `(table, entité, type, référence)` : un rejeu du
 * même document (même UUID, après purge de la mémoire d'idempotence) ne
 * double pas le signalement.
 */
class SignalementAnomalies
{
    /**
     * @param  array<string, mixed>  $details
     */
    public function signaler(
        ContexteSynchronisation $contexte,
        string $table,
        string $entiteId,
        string $type,
        string $reference = '',
        ?string $valeurPoste = null,
        ?string $valeurServeur = null,
        array $details = [],
    ): AnomalieSynchronisation {
        return AnomalieSynchronisation::query()->firstOrCreate(
            [
                'table_concernee' => $table,
                'entite_id' => $entiteId,
                'type' => $type,
                'reference' => $reference,
            ],
            [
                'poste_id' => $contexte->posteId,
                'utilisateur_id' => $contexte->utilisateur->id,
                'valeur_poste' => $valeurPoste,
                'valeur_serveur' => $valeurServeur,
                'details' => $details === [] ? null : $details,
                'statut' => 'a_examiner',
            ],
        );
    }

    /**
     * Les anomalies d'un document, dans la forme rendue au poste.
     *
     * @return list<array<string, mixed>>
     */
    public function duDocument(string $table, string $entiteId, ?string $type = null): array
    {
        return AnomalieSynchronisation::query()
            ->where('table_concernee', $table)
            ->where('entite_id', $entiteId)
            ->when($type !== null, static fn ($q) => $q->where('type', $type))
            ->orderBy('type')
            ->orderBy('reference')
            ->get()
            ->map(static fn (AnomalieSynchronisation $a): array => [
                'type' => $a->type,
                'reference' => $a->reference,
                'valeur_poste' => $a->valeur_poste,
                'valeur_serveur' => $a->valeur_serveur,
                ...($a->details ?? []),
            ])
            ->all();
    }
}
