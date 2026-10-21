<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Sync\Models\DemandeSynchronisation;
use App\Shared\Sync\Models\EtatPosteSynchronisation;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Laravel\Sanctum\PersonalAccessToken;
use RuntimeException;

/**
 * Le bouton « Synchroniser » du serveur et l'état des postes — décision du
 * Product Owner du 18/10/2026.
 *
 * Le serveur ne pousse rien : il ENREGISTRE une demande, que chaque poste lit
 * (`GET /api/v1/sync/demande`, toutes les 30 s) avant de lancer aussitôt sa
 * synchronisation complète — envoi de sa file, puis descente de tout ce que
 * le serveur a enregistré, tous modules. Une demande répétée dans la même
 * minute n'en crée pas une seconde.
 *
 * ## Révoquer l'appairage d'un poste (19/10/2026, décision du PO :
 * « enregistrer les configurations… appairage… dans le poste et le web »)
 *
 * Un poste s'appaire par `POST /login` : son jeton Sanctum porte le NOM du
 * poste. Révoquer, c'est supprimer les jetons de ce nom — tous comptes
 * confondus — : le poste reçoit 401 au passage suivant, garde sa file
 * INTACTE (rien n'est perdu) et le dit à l'écran jusqu'au réappairage.
 * Réservé aux deux rôles d'administration ; tracé au journal d'audit.
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

    /** Un poste a lancé son contrôle de cohérence (`GET /sync/coherence`). */
    public function noterControle(string $posteId, User $utilisateur): void
    {
        $this->ecrire($posteId, $utilisateur, ['dernier_controle_le' => now()]);
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
     * Supprime les jetons d'appairage du poste [posteId] ; rend leur nombre.
     */
    public function revoquer(string $posteId, User $auteur): int
    {
        if (! $auteur->estAdministrateur()) {
            throw new RuntimeException(__('sync.postes.revocation_reservee'));
        }

        return DB::transaction(function () use ($posteId, $auteur): int {
            $jetons = $this->jetons()->where('name', $posteId);
            $nombre = $jetons->count();

            if ($nombre === 0) {
                throw new RuntimeException(__('sync.postes.poste_non_appaire', ['poste' => $posteId]));
            }

            $jetons->delete();
            JournalAudit::create([
                'id' => (string) Str::uuid(),
                'utilisateur_id' => $auteur->id,
                'action' => 'appairage_revoque',
                'entite_concernee' => 'personal_access_tokens',
                'entite_id' => (string) Str::uuid(),
                'valeur_avant' => null,
                'valeur_apres' => ['poste' => $posteId, 'jetons' => $nombre],
                'adresse_poste' => request()->ip(),
            ]);

            return $nombre;
        });
    }

    /**
     * Chaque poste connu : sa dernière montée (`sessions_synchronisation`), sa
     * dernière descente, sa file déclarée, et s'il a SUIVI la dernière
     * demande — c'est-à-dire reçu le flux depuis (une simple lecture ne
     * suffit pas : le poste peut s'être arrêté entre les deux).
     *
     * Et son APPAIRAGE : vivant tant qu'un jeton de ce nom existe (dernier
     * usage), révoqué sinon. Un poste appairé qui n'a encore rien envoyé est
     * listé aussi.
     *
     * « Postes & Appairage » (21/10/2026) y ajoute `appaire_le` (premier jeton),
     * `expire_le` (le jeton qui dure le plus longtemps ; `null` = sans
     * expiration), `dernier_controle` et `etat` — `actif` (jeton valide, des
     * nouvelles depuis moins de `SILENCE_MAX_HEURES`), `silencieux` (valide,
     * mais plus de nouvelles), `expire` (tous les jetons ont expiré) ou
     * `non_appaire` (aucun jeton : révoqué, ou jamais appairé).
     *
     * @return list<array{poste_id: string, utilisateur: ?string, derniere_montee: ?CarbonImmutable, derniere_descente: ?CarbonImmutable, en_attente: ?int, demande_suivie: bool, appaire: bool, jeton_utilise_le: ?CarbonImmutable, appaire_le: ?CarbonImmutable, expire_le: ?CarbonImmutable, dernier_controle: ?CarbonImmutable, etat: string}>
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
        $jetons = $this->jetons()
            ->select(
                'name',
                DB::raw('MAX(COALESCE(last_used_at, created_at)) AS utilise_le'),
                DB::raw('MIN(created_at) AS appaire_le'),
                DB::raw('MAX(expires_at) AS expire_le'),
                DB::raw('SUM(CASE WHEN expires_at IS NULL OR expires_at > ? THEN 1 ELSE 0 END) AS valides'),
            )
            ->addBinding(now()->toDateTimeString(), 'select')
            ->groupBy('name')
            ->get()
            ->keyBy('name');
        $postes = array_values(array_unique([...array_keys($montees), ...$etats->keys()->all(), ...$jetons->keys()->all()]));
        sort($postes);
        $lignes = [];

        foreach ($postes as $poste) {
            $etat = $etats->get($poste);
            $recu = $etat?->derniere_descente_le;
            $jeton = $jetons->get($poste);
            $utilise = $jeton !== null ? CarbonImmutable::parse($jeton->utilise_le) : null;

            $lignes[] = [
                'poste_id' => (string) $poste,
                'utilisateur' => $etat?->utilisateur_id !== null ? ($comptes[$etat->utilisateur_id] ?? null) : null,
                'derniere_montee' => isset($montees[$poste]) ? CarbonImmutable::parse($montees[$poste]) : null,
                'derniere_descente' => $etat?->derniere_descente_le?->toImmutable(),
                'en_attente' => $etat?->en_attente,
                'demande_suivie' => $demande === null || ($recu !== null && $recu->greaterThanOrEqualTo($demande)),
                'appaire' => isset($jetons[$poste]),
                'jeton_utilise_le' => $utilise,
                'appaire_le' => $jeton?->appaire_le !== null ? CarbonImmutable::parse($jeton->appaire_le) : null,
                'expire_le' => $jeton?->expire_le !== null ? CarbonImmutable::parse($jeton->expire_le) : null,
                'dernier_controle' => $etat?->dernier_controle_le?->toImmutable(),
                'etat' => match (true) {
                    $jeton === null => 'non_appaire',
                    (int) $jeton->valides === 0 => 'expire',
                    $utilise !== null && $utilise->greaterThanOrEqualTo(now()->subHours(self::SILENCE_MAX_HEURES)) => 'actif',
                    default => 'silencieux',
                },
            ];
        }

        return $lignes;
    }

    /** Au-delà, un poste silencieux n'a plus d'état connu (lot « alerte avant clôture »). */
    public const SILENCE_MAX_HEURES = 24;

    /**
     * Les postes APPAIRÉS dont on ne peut pas affirmer qu'ils ont tout envoyé
     * — l'alerte AVANT de démarrer une clôture (20/10/2026) : une fois N en
     * clôture, le serveur refuse les pièces datées de N.
     *
     *  - `en_attente` : le poste a dit avoir N opérations à envoyer ;
     *  - `inconnu` : aucun état reçu, ou plus de nouvelles depuis
     *    `SILENCE_MAX_HEURES` — on ne dit pas « à jour », on dit qu'on ne sait pas.
     *
     * @return list<array{poste_id: string, en_attente: int, inconnu: bool, derniere_descente: ?CarbonImmutable}>
     */
    public function postesNonAJour(): array
    {
        $alertes = [];

        foreach ($this->etats() as $poste) {
            if (! $poste['appaire']) {
                continue;
            }

            $descente = $poste['derniere_descente'];
            $enAttente = (int) ($poste['en_attente'] ?? 0);
            $inconnu = $poste['en_attente'] === null
                || $descente === null
                || $descente->lessThan(now()->subHours(self::SILENCE_MAX_HEURES));

            if ($enAttente > 0 || $inconnu) {
                $alertes[] = [
                    'poste_id' => $poste['poste_id'],
                    'en_attente' => $enAttente,
                    'inconnu' => $inconnu,
                    'derniere_descente' => $descente,
                ];
            }
        }

        return $alertes;
    }

    /**
     * Les jetons des COMPTES (le seul porteur de jetons du dépôt).
     *
     * @return \Illuminate\Database\Eloquent\Builder<PersonalAccessToken>
     */
    private function jetons(): \Illuminate\Database\Eloquent\Builder
    {
        return PersonalAccessToken::query()->where('tokenable_type', (new User())->getMorphClass());
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
