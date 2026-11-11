<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Shared\Audit\Models\JournalAudit;
use Illuminate\Support\Str;

/**
 * L'entrée « Réglage de la facturation normalisée modifié » du journal d'audit.
 *
 * Jamais un secret : ne reçoit que des NOMS de clés et des valeurs non
 * secrètes (mode, adresse). Le jeton est tracé par son GESTE (« jeton
 * enregistré » / « jeton effacé »), sans valeur.
 */
final class TraceReglageFacturation
{
    public const ACTION = 'reglage_facturation_normalisee_modifie';

    /** @param array<string, mixed> $details */
    public static function tracer(?string $utilisateurId, array $details): void
    {
        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => $utilisateurId,
            'action' => self::ACTION,
            'entite_concernee' => 'parametres_systeme',
            'entite_id' => (string) Str::uuid(),
            'valeur_avant' => null,
            'valeur_apres' => $details,
            'adresse_poste' => request()->ip(),
        ]);
    }
}
