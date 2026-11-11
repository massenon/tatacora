<?php

declare(strict_types=1);

namespace App\Shared\Auth\Services;

use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Auth\Support\GenerateurDeSecret;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Mot de passe perdu — SANS e-mail automatique (décision du PO du 29/10/2026,
 * option A). Trois gestes, un seul service, un seul endroit où se tiennent les
 * règles :
 *
 *  1. **Réinitialisation par un administrateur** : un mot de passe TEMPORAIRE
 *     est généré, rendu UNE fois à l'administrateur, son empreinte est posée,
 *     le compte est marqué « changement obligatoire » et le temporaire expire
 *     après 24 h. Un administrateur ne réinitialise pas son propre compte par
 *     ce chemin (il utilise « Mon profil », avec l'ancien mot de passe).
 *  2. **Changement forcé** : à la connexion suivante, le temporaire n'ouvre que
 *     l'écran « Définissez votre nouveau mot de passe ».
 *  3. **Code de secours** de l'administrateur, à usage unique : seule son
 *     empreinte est stockée ; l'utiliser réinitialise le compte et en pose un
 *     NOUVEAU, rendu une seule fois. Les essais sont limités (5, puis 15 min
 *     de blocage) par compte ET par adresse, et le refus est identique que le
 *     compte existe ou non.
 *
 * ## Ce qui ne figure JAMAIS au journal d'audit ni aux logs
 *
 * Ni le mot de passe temporaire, ni le code de secours, ni leur empreinte :
 * les entrées de `journal_audit` ne portent que « qui », « quel compte »,
 * « quand » et l'adresse. Tenu par `ReinitialisationMotDePasseTest`.
 *
 * @see RG-15 Traçabilité des actions sensibles
 */
final class MotDePassePerduService
{
    /** Validité du mot de passe temporaire. */
    public const VALIDITE_TEMPORAIRE_HEURES = 24;

    /** Essais permis avant blocage du code de secours. */
    public const ESSAIS_MAX = 5;

    /** Durée du blocage après `ESSAIS_MAX` échecs : 15 minutes. */
    public const BLOCAGE_SECONDES = 900;

    /** Règle de force existante (« Mon profil » : min. 8 caractères). */
    public const LONGUEUR_MIN = 8;

    /** Identifiant d'entité des tentatives sur un compte INCONNU (colonne `uuid` non nulle). */
    private const ENTITE_INCONNUE = '00000000-0000-0000-0000-000000000000';

    /**
     * Réinitialise le mot de passe de [$cibleId] par l'administrateur [$auteur].
     *
     * @return array{motDePasse: string, expireLe: \Illuminate\Support\Carbon, login: string}
     *
     * @throws RuntimeException message lisible, en français, à afficher tel quel
     */
    public function reinitialiserParAdministrateur(User $auteur, string $cibleId, ?string $adresse): array
    {
        if (! $auteur->estActif() || ! $auteur->estAdministrateur()) {
            throw new RuntimeException(__('pwa.comptes.refus_droit'));
        }

        if ($auteur->id === $cibleId) {
            throw new RuntimeException(__('pwa.comptes.refus_soi_meme'));
        }

        /** @var User|null $cible */
        $cible = User::query()->with('role')->find($cibleId);

        if ($cible === null) {
            throw new RuntimeException(__('pwa.comptes.refus_introuvable'));
        }

        // Un administrateur ne prend pas la main sur un super_admin : il lirait
        // le temporaire et se connecterait AVANT lui.
        if ($cible->estSuperAdmin() && ! $auteur->estSuperAdmin()) {
            throw new RuntimeException(__('pwa.comptes.refus_super_admin'));
        }

        $temporaire = GenerateurDeSecret::motDePasseTemporaire();
        $expireLe = now()->addHours(self::VALIDITE_TEMPORAIRE_HEURES);

        DB::transaction(function () use ($auteur, $cible, $temporaire, $expireLe, $adresse): void {
            // L'« ancien » à ne pas réutiliser est le dernier mot de passe CHOISI
            // par son titulaire : si un temporaire est déjà en cours, on garde
            // celui qu'il avait mémorisé, pas le temporaire précédent.
            $ancien = $cible->must_change_password && $cible->previous_password_hash !== null
                ? $cible->previous_password_hash
                : $cible->mot_de_passe_hash;

            $cible->forceFill([
                'mot_de_passe_hash' => $temporaire,
                'previous_password_hash' => $ancien,
                'must_change_password' => true,
                'temp_expires_at' => $expireLe,
            ])->save();

            $this->couperLesAcces($cible);

            $this->tracer('reinitialisation_mot_de_passe', $auteur->id, $cible->id, [
                'login' => $cible->login,
                'expire_le' => $expireLe->toIso8601String(),
            ], $adresse);
        });

        return ['motDePasse' => $temporaire, 'expireLe' => $expireLe, 'login' => $cible->login];
    }

    /**
     * Pose le mot de passe CHOISI par le titulaire après une réinitialisation.
     *
     * @throws RuntimeException le temporaire a expiré, ou le nouveau mot de
     *                          passe est celui du temporaire / l'ancien
     */
    public function definirApresChangementObligatoire(User $utilisateur, string $nouveau): void
    {
        if ($utilisateur->motDePasseTemporaireExpire()) {
            throw new RuntimeException(__('pwa.changement_mdp.expire'));
        }

        if (Hash::check($nouveau, $utilisateur->mot_de_passe_hash)) {
            throw new RuntimeException(__('pwa.changement_mdp.identique_temporaire'));
        }

        if ($utilisateur->previous_password_hash !== null
            && Hash::check($nouveau, $utilisateur->previous_password_hash)) {
            throw new RuntimeException(__('pwa.changement_mdp.identique_ancien'));
        }

        DB::transaction(function () use ($utilisateur, $nouveau): void {
            $utilisateur->forceFill([
                'mot_de_passe_hash' => $nouveau,
                'previous_password_hash' => null,
                'must_change_password' => false,
                'temp_expires_at' => null,
            ])->save();

            $this->couperLesAcces($utilisateur);
        });
    }

    /**
     * Pose un NOUVEAU code de secours à l'administrateur [$administrateur] et
     * le rend UNE fois (seule son empreinte est stockée).
     *
     * @throws RuntimeException le compte n'est pas administrateur
     */
    public function poserCodeDeSecours(User $administrateur, ?string $adresse): string
    {
        if (! $administrateur->estActif() || ! $administrateur->estAdministrateur()) {
            throw new RuntimeException(__('pwa.comptes.refus_droit'));
        }

        $code = GenerateurDeSecret::codeDeSecours();

        $administrateur->forceFill([
            'recovery_code_hash' => Hash::make(GenerateurDeSecret::normaliserCode($code)),
            'recovery_code_generated_at' => now(),
        ])->save();

        $this->tracer('code_secours_genere', $administrateur->id, $administrateur->id, [
            'login' => $administrateur->login,
        ], $adresse);

        return $code;
    }

    /**
     * « J'ai perdu mon mot de passe administrateur » : login + code de secours
     * + nouveau mot de passe. Rend le NOUVEAU code de secours (le précédent est
     * consommé).
     *
     * Le refus est UN SEUL message, que le compte existe ou non, soit
     * administrateur ou non, ait un code ou non. Le temps de calcul est
     * comparable (une vérification d'empreinte est toujours faite).
     *
     * @throws RuntimeException message générique, ou blocage (avec la durée)
     */
    public function reinitialiserParCodeDeSecours(string $login, string $code, string $nouveau, ?string $adresse): string
    {
        $cleCompte = 'secours|'.mb_strtolower($login);
        $cleAdresse = 'secours-adresse|'.($adresse ?? 'inconnue');

        if (RateLimiter::tooManyAttempts($cleCompte, self::ESSAIS_MAX)
            || RateLimiter::tooManyAttempts($cleAdresse, self::ESSAIS_MAX)) {
            $secondes = max(RateLimiter::availableIn($cleCompte), RateLimiter::availableIn($cleAdresse));

            $this->tracer('code_secours_bloque', null, null, ['login_tente' => $login], $adresse);

            throw new RuntimeException(__('pwa.code_secours.bloque', ['minutes' => (string) max(1, (int) ceil($secondes / 60))]));
        }

        /** @var User|null $utilisateur */
        $utilisateur = User::query()->with('role')->where('login', $login)->first();

        // Une vérification d'empreinte est TOUJOURS faite : sans cela, le temps
        // de réponse dit si le compte existe et s'il porte un code.
        $empreinte = $utilisateur?->recovery_code_hash ?? '$2y$12$'.str_repeat('0', 53);
        $codeValide = Hash::check(GenerateurDeSecret::normaliserCode($code), $empreinte);

        if (! $codeValide
            || $utilisateur === null
            || $utilisateur->recovery_code_hash === null
            || ! $utilisateur->estActif()
            || ! $utilisateur->estAdministrateur()) {
            RateLimiter::hit($cleCompte, self::BLOCAGE_SECONDES);
            RateLimiter::hit($cleAdresse, self::BLOCAGE_SECONDES);

            $this->tracer('code_secours_refuse', null, $utilisateur?->id, ['login_tente' => $login], $adresse);

            throw new RuntimeException(__('pwa.code_secours.refus'));
        }

        $nouveauCode = GenerateurDeSecret::codeDeSecours();

        DB::transaction(function () use ($utilisateur, $nouveau, $nouveauCode, $adresse): void {
            $utilisateur->forceFill([
                'mot_de_passe_hash' => $nouveau,
                'previous_password_hash' => null,
                'must_change_password' => false,
                'temp_expires_at' => null,
                // Usage unique : l'ancien code est remplacé dans la même écriture.
                'recovery_code_hash' => Hash::make(GenerateurDeSecret::normaliserCode($nouveauCode)),
                'recovery_code_generated_at' => now(),
            ])->save();

            $this->couperLesAcces($utilisateur);

            $this->tracer('code_secours_utilise', $utilisateur->id, $utilisateur->id, [
                'login' => $utilisateur->login,
            ], $adresse);
        });

        RateLimiter::clear($cleCompte);

        return $nouveauCode;
    }

    /**
     * Coupe tout ce que le compte tenait ouvert : jetons d'API, « se souvenir de
     * moi » de Laravel (jeton régénéré) et sessions enregistrées en base. Les
     * sessions d'un autre pilote de stockage sont fermées par
     * `AuthenticateSession` (l'empreinte du mot de passe a changé).
     */
    private function couperLesAcces(User $utilisateur): void
    {
        $utilisateur->tokens()->delete();
        $utilisateur->forceFill(['remember_token' => Str::random(60)])->save();

        if (config('session.driver') === 'database') {
            $table = (string) config('session.table', 'sessions');

            if (Schema::hasTable($table) && Schema::hasColumn($table, 'user_id')) {
                DB::table($table)->where('user_id', $utilisateur->id)->delete();
            }
        }
    }

    /**
     * Une entrée du journal d'audit. [$details] ne reçoit JAMAIS un secret ni
     * une empreinte : des identifiants et des dates seulement.
     *
     * @param  array<string, mixed>  $details
     */
    private function tracer(string $action, ?string $auteurId, ?string $entiteId, array $details, ?string $adresse): void
    {
        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => $auteurId,
            'action' => $action,
            'entite_concernee' => 'utilisateurs',
            'entite_id' => $entiteId ?? self::ENTITE_INCONNUE,
            'valeur_avant' => null,
            'valeur_apres' => $details,
            'adresse_poste' => $adresse,
        ]);
    }
}
