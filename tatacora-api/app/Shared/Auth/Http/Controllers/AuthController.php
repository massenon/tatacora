<?php

declare(strict_types=1);

namespace App\Shared\Auth\Http\Controllers;

use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Auth\Http\Requests\ConnexionRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * Authentification du client Flutter par jetons Sanctum.
 *
 * ## Pourquoi ce contrôleur existe
 *
 * Les 32 routes de `routes/api.php` sont toutes derrière `auth:sanctum`, mais
 * **aucun jeton n'était jamais émis** : `createToken()` n'apparaissait nulle
 * part au dépôt. L'API entière était donc inaccessible au client Flutter.
 *
 * Constat fait à la Definition of Ready du Sprint 1 (`SDLC_FLUTTER.md` §6.1),
 * qui impose de vérifier l'existence réelle des routes plutôt que de la
 * supposer — précisément pour éviter de découvrir le mur au troisième jour.
 *
 * ## Le contrat de réponse
 *
 * Le client reçoit ses **droits** dès la connexion, sous forme de matrice
 * `{module: niveau}`. Sans cela, il devrait interroger le serveur module par
 * module pour construire son menu — impossible pour un guide en circuit, qui
 * doit voir son interface correctement masquée sans réseau.
 *
 * Ce n'est pas une délégation de sécurité : le masquage reste le niveau 1 sur
 * 3, et chaque appel est de toute façon revérifié ici par le middleware
 * `module:`.
 *
 * @see RG-15 (traçabilité), RG-16 (RBAC à trois niveaux)
 */
final class AuthController extends Controller
{
    /**
     * Modules de la matrice RBAC.
     *
     * Liste **fermée**, jamais dérivée des permissions attachées : un module
     * absent doit apparaître explicitement à `'-'` dans la réponse. L'omettre
     * laisserait le client décider quoi faire d'une clé manquante, et un droit
     * ne s'obtient jamais par omission.
     */
    private const MODULES = [
        'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7',
        'M8', 'M9', 'M10', 'M11', 'M12', 'M13', 'M14',
        'ROLES', 'PARAM',
    ];

    /**
     * Fenêtre de blocage après cinq échecs, en secondes.
     *
     * ⚠ **Publique depuis le 27/08/2026, et pour une raison précise** : la
     * PWA appliquait 60 s là où ce contrôleur en applique 300. Deux politiques
     * différentes sur la même porte reviennent à n'avoir que la plus faible.
     * `App\Pwa\Livewire\Connexion` lit désormais cette constante — une seule
     * valeur, un seul endroit où la changer.
     */
    public const BLOCAGE_SECONDES = 300;

    /**
     * Émet un jeton Sanctum.
     */
    public function connexion(ConnexionRequest $requete): JsonResponse
    {
        $identifiant = (string) $requete->string('identifiant');
        $cle = 'connexion:'.mb_strtolower($identifiant).'|'.$requete->ip();

        // Limitation de débit sur (login + IP) plutôt que sur l'IP seule : au
        // Gîte, tous les postes sortent derrière la même adresse publique.
        // Limiter par IP y bloquerait la réception entière dès qu'un employé
        // se trompe cinq fois de mot de passe.
        if (RateLimiter::tooManyAttempts($cle, maxAttempts: 5)) {
            throw ValidationException::withMessages([
                'identifiant' => __('auth.trop_de_tentatives', [
                    'secondes' => (string) RateLimiter::availableIn($cle),
                ]),
            ])->status(429);
        }

        $utilisateur = User::query()
            ->with(['role.permissions', 'employe'])
            ->where('login', $identifiant)
            ->first();

        // `Hash::check` est appelé même si l'utilisateur est introuvable, contre
        // un haché factice : sans cela, le temps de réponse révèle quels logins
        // existent.
        $hache = $utilisateur?->getAuthPassword() ?? '$2y$12$'.str_repeat('0', 53);
        $motDePasseValide = Hash::check((string) $requete->string('mot_de_passe'), $hache);

        if (! $motDePasseValide || $utilisateur === null) {
            RateLimiter::hit($cle, self::BLOCAGE_SECONDES);

            // Message unique, volontairement : distinguer « login inconnu » de
            // « mot de passe incorrect » indiquerait à un attaquant quels
            // comptes existent.
            throw ValidationException::withMessages([
                'identifiant' => __('auth.failed'),
            ])->status(401);
        }

        // Un compte suspendu est refusé APRÈS validation du mot de passe : le
        // refuser avant révélerait son existence à qui ignore le mot de passe.
        if (! $utilisateur->estActif()) {
            RateLimiter::hit($cle, self::BLOCAGE_SECONDES);

            throw ValidationException::withMessages([
                'identifiant' => __('auth.compte_desactive'),
            ])->status(403);
        }

        // Mot de passe TEMPORAIRE posé par un administrateur (29/10/2026) : aucun
        // jeton d'API tant que le titulaire n'a pas défini le sien (écran web).
        // Refus prononcé APRÈS validation du mot de passe, comme le précédent.
        if ($utilisateur->must_change_password) {
            RateLimiter::hit($cle, self::BLOCAGE_SECONDES);

            throw ValidationException::withMessages([
                'identifiant' => __('auth.changement_requis'),
            ])->status(403);
        }

        RateLimiter::clear($cle);

        // Le jeton antérieur de ce poste est révoqué : un appareil perdu ne
        // doit pas conserver un accès parce que son propriétaire s'est
        // reconnecté depuis le même poste. Les autres postes sont préservés.
        $poste = (string) $requete->string('poste', 'inconnu');
        $utilisateur->tokens()->where('name', $poste)->delete();

        $jeton = $utilisateur->createToken($poste)->plainTextToken;

        $utilisateur->forceFill(['derniere_connexion' => now()])->save();
        $this->tracer('connexion', $utilisateur, $poste, $requete);

        return response()->json([
            'token' => $jeton,
            'utilisateur' => $this->profil($utilisateur),
        ]);
    }

    /**
     * Révoque le jeton courant — et lui seul.
     *
     * Révoquer tous les jetons déconnecterait le même utilisateur de ses autres
     * postes, ce qu'il n'a pas demandé.
     */
    public function deconnexion(Request $requete): JsonResponse
    {
        $utilisateur = $requete->user();

        // `instanceof PersonalAccessToken` plutot qu'un simple appel : sous
        // authentification par session, Sanctum renvoie ici un
        // `TransientToken`, qui ne porte ni nom de poste ni `delete()`.
        // L'appeler directement provoquerait une erreur fatale.
        $jeton = $utilisateur instanceof User ? $utilisateur->currentAccessToken() : null;

        if ($utilisateur instanceof User && $jeton instanceof PersonalAccessToken) {
            $poste = $jeton->name;
            $jeton->delete();

            $this->tracer('deconnexion', $utilisateur, $poste, $requete);
        }

        return response()->json(['message' => __('auth.deconnecte')]);
    }

    /**
     * Profil de la session courante — sert au client à revalider son jeton et à
     * rafraîchir ses droits au démarrage.
     */
    public function utilisateur(Request $requete): JsonResponse
    {
        $utilisateur = $requete->user();

        if (! $utilisateur instanceof User) {
            return response()->json(['message' => __('auth.requise')], 401);
        }

        $utilisateur->loadMissing(['role.permissions', 'employe']);

        return response()->json($this->profil($utilisateur));
    }

    /**
     * @return array<string, mixed>
     */
    private function profil(User $utilisateur): array
    {
        $employe = $utilisateur->employe;

        return [
            'id' => $utilisateur->id,
            'login' => $utilisateur->login,
            // Un compte technique n'a pas de fiche employé : on affiche alors
            // son login plutôt qu'un nom fabriqué (cf. docblock de `employe()`).
            'nom' => $employe !== null
                ? trim($employe->nom.' '.($employe->prenom ?? ''))
                : $utilisateur->login,
            // `role_id` est NOT NULL sous contrainte de cle etrangere : le
            // role existe toujours, un defaut vide serait du code mort.
            'role' => $utilisateur->role->libelle,
            'droits' => $this->droits($utilisateur),
        ];
    }

    /**
     * Matrice des droits, module par module.
     *
     * @return array<string, string>
     */
    private function droits(User $utilisateur): array
    {
        $droits = [];

        foreach (self::MODULES as $module) {
            $droits[$module] = $utilisateur->niveauSurModule($module);
        }

        return $droits;
    }

    private function tracer(string $action, User $utilisateur, string $poste, Request $requete): void
    {
        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => $utilisateur->id,
            'action' => $action,
            'entite_concernee' => 'utilisateurs',
            'entite_id' => $utilisateur->id,
            'valeur_avant' => null,
            // Ni le jeton ni le mot de passe ne sont tracés : le journal
            // d'audit est consultable, et y déposer un secret le diffuserait.
            'valeur_apres' => ['poste' => $poste],
            'adresse_poste' => $requete->ip(),
        ]);
    }
}
