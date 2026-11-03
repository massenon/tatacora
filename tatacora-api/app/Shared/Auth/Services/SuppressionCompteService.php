<?php

declare(strict_types=1);

namespace App\Shared\Auth\Services;

use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Sync\Services\EpoqueSynchronisation;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * SUPPRIMER UN COMPTE UTILISATEUR — décision du Product Owner du 03/11/2026,
 * qui lève pour la seule suppression la règle « un compte ne se supprime jamais,
 * il se désactive » (RG-15).
 *
 * ## Ce que « supprimer » veut dire
 *
 * Une suppression LOGIQUE (`utilisateurs.supprime_le`), jamais un DELETE : les
 * ventes, dépenses, écritures et le journal d'audit gardent leur auteur, affiché
 * « <login> (compte supprimé) ». Le compte ne se connecte plus, disparaît des
 * listes, ses jetons d'API et ses sessions web sont coupés. Son identifiant
 * n'est PAS réutilisable (la ligne garde son `login` sous l'index unique).
 *
 * ## Qui peut quoi (la règle d'autorité, écrite une fois)
 *
 * - l'AUTEUR : un super administrateur actif avec l'écriture sur ROLES
 *   ({@see User::peutSupprimerDesComptes()}) ;
 * - la CIBLE : un compte dont le rôle n'administre pas ({@see User::estSupprimable()}) ;
 * - jamais soi-même. Le « dernier administrateur » ne peut pas être visé : un
 *   administrateur ou un super administrateur ne se supprime pas (il se
 *   désactive).
 *
 * ## Synchronisation (sans jamais un mot de passe ni un hash)
 *
 * La suppression est publiée vers les postes par le catalogue descendant
 * (`utilisateurs`, colonnes `login` et `supprime_le` seulement). Une suppression
 * demandée par un poste (`supprimerPourUnPoste`) passe par la MÊME règle, avec
 * pour auteur le compte serveur du jeton d'appairage.
 *
 * @see RG-15 Traçabilité des actions sensibles
 * @see RG-16 Contrôle d'accès basé sur les rôles
 */
class SuppressionCompteService
{
    /**
     * Supprime le compte [$cibleId] (écran web).
     *
     * @throws RuntimeException message lisible, en français, à afficher tel quel
     */
    public function supprimer(User $auteur, string $cibleId, ?string $adresse): User
    {
        $cible = User::query()->with('role')->find($cibleId);

        if ($cible === null) {
            throw new RuntimeException(__('pwa.comptes.refus_introuvable'));
        }

        $this->exiger($auteur, $cible);
        $this->appliquer($auteur, $cible, $adresse, null, null);

        return $cible;
    }

    /**
     * Rejoue la suppression demandée par un POSTE (opération `suppression` de
     * la table `utilisateurs`). Idempotente : un compte inconnu du serveur ou
     * déjà supprimé est un no-op journalisé, jamais une erreur — le compte a pu
     * naître seulement sur ce poste.
     *
     * @return User|null le compte supprimé, `null` si rien n'a été fait
     *
     * @throws RuntimeException refus d'autorité ou de cible (phrase lisible)
     */
    public function supprimerPourUnPoste(User $auteur, string $login, string $poste, ?string $auteurLocal): ?User
    {
        $login = trim($login);
        $cible = User::query()->with('role')->where('login', $login)->first();

        if (! $auteur->peutSupprimerDesComptes()) {
            throw new RuntimeException(__('sync.comptes.suppression_reservee'));
        }

        if ($cible === null) {
            $this->tracer('compte_supprime_inconnu', $auteur->id, null, [
                'login' => $login,
                'poste' => $poste,
                'par_login_local' => $auteurLocal,
                'effet' => 'aucun',
            ], null);

            return null;
        }

        $this->exiger($auteur, $cible);
        $this->appliquer($auteur, $cible, null, $poste, $auteurLocal);

        return $cible;
    }

    /**
     * Les refus, dans cet ordre : droit de l'auteur, soi-même, cible
     * administratrice. Les phrases sont celles de `lang/fr` (reprises à
     * l'identique par le poste).
     */
    private function exiger(User $auteur, User $cible): void
    {
        if (! $auteur->peutSupprimerDesComptes()) {
            throw new RuntimeException(__('pwa.comptes.refus_suppression_droit'));
        }

        if ($auteur->id === $cible->id) {
            throw new RuntimeException(__('pwa.comptes.refus_suppression_soi_meme'));
        }

        if (! $cible->estSupprimable()) {
            throw new RuntimeException(__('pwa.comptes.refus_suppression_administrateur'));
        }
    }

    private function appliquer(User $auteur, User $cible, ?string $adresse, ?string $poste, ?string $auteurLocal): void
    {
        DB::transaction(function () use ($auteur, $cible, $adresse, $poste, $auteurLocal): void {
            $login = $cible->login;
            $role = (string) $cible->role?->libelle;

            // Les accès d'abord : jetons d'API (donc les postes appairés avec ce
            // compte), « se souvenir de moi », sessions enregistrées en base.
            $cible->tokens()->delete();
            $cible->forceFill(['remember_token' => Str::random(60)])->save();

            if (config('session.driver') === 'database') {
                $table = (string) config('session.table', 'sessions');

                if (Schema::hasTable($table) && Schema::hasColumn($table, 'user_id')) {
                    DB::table($table)->where('user_id', $cible->id)->delete();
                }
            }

            // `delete()` pose `supprime_le` ET fait avancer `updated_at` : c'est ce
            // qui fait REPASSER le compte dans le flux descendant des postes.
            $cible->delete();

            // Jamais un secret ni une empreinte : un login, un rôle, un poste.
            $this->tracer('compte_supprime', $auteur->id, $cible->id, [
                'login' => $login,
                'role' => $role,
                'poste' => $poste,
                'par_login_local' => $auteurLocal,
            ], $adresse);
        });

        // Les AUTRES postes l'apprennent au prochain battement de 30 s.
        app(EpoqueSynchronisation::class)->incrementer();
    }

    /**
     * @param  array<string, mixed>  $details
     */
    private function tracer(string $action, ?string $auteurId, ?string $entiteId, array $details, ?string $adresse): void
    {
        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => $auteurId,
            'action' => $action,
            'entite_concernee' => 'utilisateurs',
            'entite_id' => $entiteId ?? '00000000-0000-0000-0000-000000000000',
            'valeur_avant' => null,
            'valeur_apres' => $details,
            'adresse_poste' => $adresse ?? request()->ip(),
        ]);
    }
}
