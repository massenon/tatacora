<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Models\User;
use App\Shared\Sync\Models\DemandeSynchronisation;
use App\Shared\Sync\Models\EtatPosteSynchronisation;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/**
 * Le bouton « Synchroniser » du serveur et l'état des postes — décision du
 * Product Owner du 18/10/2026.
 *
 * Le serveur ne pousse rien : il ENREGISTRE une demande, que chaque poste lit
 * (`GET /api/v1/sync/demande`, toutes les 30 s) avant de lancer aussitôt sa
 * synchronisation complète — envoi de sa file, puis descente de tout ce que
 * le serveur a enregistré, tous modules. Une demande répétée dans la même
 * minute n'en crée pas une seconde.
 */
class SuiviPostesService
{
    /** L'intervalle sous lequel une nouvelle demande reprend la précédente. */
    public const ANTI_REBOND_SECONDES = 60;

    public function demander(User $utilisateur): DemandeSynchronisation
    {
        $derniere = DemandeSynchronisation::query()->latest('demandee_le')->first();

        if ($derniere !== null && $derniere->demandee_le->greaterThan(now()->subSeconds(self::ANTI_REBOND_SECONDES))) {
            return $derniere;
        }

        return DemandeSynchronisation::create(['utilisateur_id' => $utilisateur->id, 'demandee_le' => now()]);
    }

    public function derniereDemande(): ?DemandeSynchronisation
    {
        return DemandeSynchronisation::query()->latest('demandee_le')->first();
    }

    /** Un poste a lu la demande (sans rien télécharger encore). */
    public function noterLecture(string $posteId, User $utilisateur): void
    {
        $this->ecrire($posteId, $utilisateur, ['demande_lue_le' => now()]);
    }

    /** Un poste a téléchargé une page du flux ; il déclare sa file. */
    public function noterDescente(string $posteId, User $utilisateur, ?int $enAttente): void
    {
        $this->ecrire($posteId, $utilisateur, [
            'derniere_descente_le' => now(),
            ...($enAttente !== null ? ['en_attente' => $enAttente] : []),
        ]);
    }

    /**
     * Chaque poste connu : sa dernière montée (`sessions_synchronisation`), sa
     * dernière descente, sa file déclarée, et s'il a SUIVI la dernière
     * demande — c'est-à-dire reçu le flux depuis (une simple lecture ne
     * suffit pas : le poste peut s'être arrêté entre les deux).
     *
     * @return list<array{poste_id: string, utilisateur: ?string, derniere_montee: ?CarbonImmutable, derniere_descente: ?CarbonImmutable, en_attente: ?int, demande_suivie: bool}>
     */
    public function etats(): array
    {
        $demande = $this->derniereDemande()?->demandee_le;
        $montees = DB::table('sessions_synchronisation')
            ->select('poste_id', DB::raw('MAX(date_sync) AS derniere'))
            ->groupBy('poste_id')
            ->pluck('derniere', 'poste_id')
            ->all();
        $etats = EtatPosteSynchronisation::query()->get()->keyBy('poste_id');
        $comptes = DB::table('utilisateurs')->pluck('login', 'id')->all();
        $postes = array_values(array_unique([...array_keys($montees), ...$etats->keys()->all()]));
        sort($postes);
        $lignes = [];

        foreach ($postes as $poste) {
            $etat = $etats->get($poste);
            $recu = $etat?->derniere_descente_le;

            $lignes[] = [
                'poste_id' => (string) $poste,
                'utilisateur' => $etat?->utilisateur_id !== null ? ($comptes[$etat->utilisateur_id] ?? null) : null,
                'derniere_montee' => isset($montees[$poste]) ? CarbonImmutable::parse($montees[$poste]) : null,
                'derniere_descente' => $etat?->derniere_descente_le?->toImmutable(),
                'en_attente' => $etat?->en_attente,
                'demande_suivie' => $demande === null || ($recu !== null && $recu->greaterThanOrEqualTo($demande)),
            ];
        }

        return $lignes;
    }

    /** @param array<string, mixed> $valeurs */
    private function ecrire(string $posteId, User $utilisateur, array $valeurs): void
    {
        EtatPosteSynchronisation::query()->updateOrCreate(
            ['poste_id' => $posteId],
            ['utilisateur_id' => $utilisateur->id, ...$valeurs],
        );
    }
}
