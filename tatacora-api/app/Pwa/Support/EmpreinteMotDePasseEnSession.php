<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Models\User;

/**
 * L'empreinte du mot de passe d'un compte, rangée dans SA session : c'est ce qui
 * permet de fermer les sessions d'un compte dont le mot de passe a été
 * réinitialisé par un administrateur, QUEL QUE SOIT le pilote de session
 * (fichier, base, cache) — un pilote « fichier » ne se parcourt pas par
 * utilisateur.
 *
 * Même idée que `AuthenticateSession` de Laravel, mais l'empreinte est rangée
 * PAR COMPTE : une session ne change jamais de titulaire en production, mais un
 * test qui enchaîne deux `actingAs()` le fait, et l'implémentation du cadre
 * y voit un mot de passe changé. Ici, un second compte n'a simplement pas encore
 * d'empreinte.
 *
 * On range un HMAC de l'empreinte (clé de l'application), jamais l'empreinte
 * elle-même : la session ne doit pas porter de quoi attaquer le mot de passe.
 * La clé de session est un état de SÉCURITÉ de la session, pas une donnée
 * métier (voir `SessionSansDonneeMetierTest`).
 */
final class EmpreinteMotDePasseEnSession
{
    /** Pose l'empreinte COURANTE de [$utilisateur] dans la session. */
    public static function poser(User $utilisateur): void
    {
        $empreintes = (array) session('empreintes_mots_de_passe', []);
        $empreintes[(string) $utilisateur->getAuthIdentifier()] = self::calculer($utilisateur);
        session()->put('empreintes_mots_de_passe', $empreintes);
    }

    /**
     * Le mot de passe de [$utilisateur] a-t-il changé depuis que cette session
     * l'a vu ? Sans empreinte rangée (session d'avant ce lot), on la pose : la
     * session est alors acceptée UNE fois — la seule fenêtre de ce déploiement.
     */
    public static function estPeriee(User $utilisateur): bool
    {
        $attendue = ((array) session('empreintes_mots_de_passe', []))[(string) $utilisateur->getAuthIdentifier()] ?? null;

        if (! is_string($attendue)) {
            self::poser($utilisateur);

            return false;
        }

        return ! hash_equals($attendue, self::calculer($utilisateur));
    }

    private static function calculer(User $utilisateur): string
    {
        return hash_hmac('sha256', (string) $utilisateur->getAuthPassword(), (string) config('app.key'));
    }
}
