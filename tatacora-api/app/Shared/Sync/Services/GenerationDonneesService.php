<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Models\User;
use App\Shared\Sync\Models\GenerationDonnees;

/**
 * La GÉNÉRATION des données du serveur (décision du Product Owner du
 * 19/10/2026 : essais en production, puis réinitialisation sur le web ET
 * sur les postes).
 *
 * Le serveur la donne à chaque réponse de synchronisation (en-tête
 * `X-Tatacora-Generation`) ; le poste la retient, puis la rappelle à chaque
 * envoi (`generation`). Une génération rappelée qui n'est plus la courante
 * — le serveur a été réinitialisé depuis — est REFUSÉE (409) : le poste
 * s'arrête et demande sa propre réinitialisation. Un poste qui n'en rappelle
 * aucune (neuf, ou réinitialisé) adopte la courante.
 */
class GenerationDonneesService
{
    public const MOTIF_INSTALLATION = 'installation';

    public const MOTIF_REINITIALISATION = 'reinitialisation';

    public function courante(): GenerationDonnees
    {
        return GenerationDonnees::query()->orderByDesc('rang')->first()
            // Défensif : une base migrée sans la ligne de départ en reçoit une.
            ?? GenerationDonnees::create(['motif' => self::MOTIF_INSTALLATION]);
    }

    /** Ouvre une génération nouvelle — appelée par la réinitialisation. */
    public function ouvrir(?User $auteur, string $motif = self::MOTIF_REINITIALISATION): GenerationDonnees
    {
        return GenerationDonnees::create(['utilisateur_id' => $auteur?->id, 'motif' => $motif]);
    }

    /** Vrai si [rappelee] est absente (poste neuf) ou la courante. */
    public function concorde(?string $rappelee): bool
    {
        return $rappelee === null || $rappelee === '' || $rappelee === $this->courante()->generation;
    }
}
