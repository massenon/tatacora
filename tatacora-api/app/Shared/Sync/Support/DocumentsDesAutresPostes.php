<?php

declare(strict_types=1);

namespace App\Shared\Sync\Support;

use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Qui peut défaire un document saisi AILLEURS — décision Q3 du Product Owner
 * du 17/10/2026 : « l'administration et le comptable » (lot F6).
 *
 * Un document est « d'un autre poste » quand son poste d'origine
 * (`origines_synchronisation`) n'est pas le poste qui envoie le geste — un
 * document saisi au serveur (PWA, aucune origine) compte comme tel. Son
 * annulation par la synchronisation exige un compte d'administration
 * (`User::estAdministrateur`) ou le rôle `comptable` ; sinon elle est
 * refusée avec sa phrase, et reste visible au poste (« À traiter »).
 */
final class DocumentsDesAutresPostes
{
    /** Les rôles admis EN PLUS de l'administration. */
    public const ROLES_ADMIS = ['comptable'];

    /**
     * @throws RuntimeException le compte n'est ni d'administration ni comptable
     */
    public function verifierAnnulation(string $table, string $entiteId, ContexteSynchronisation $contexte): void
    {
        $origine = DB::table('origines_synchronisation')
            ->where('table_concernee', $table)
            ->where('entite_id', $entiteId)
            ->value('poste_id');

        if ($origine === $contexte->posteId) {
            return;
        }

        $utilisateur = $contexte->utilisateur;

        if ($utilisateur->estAdministrateur()
            || in_array((string) $utilisateur->role?->libelle, self::ROLES_ADMIS, true)) {
            return;
        }

        throw new RuntimeException(__('sync.annulation_autre_poste'));
    }
}
