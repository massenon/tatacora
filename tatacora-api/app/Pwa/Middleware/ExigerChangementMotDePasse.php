<?php

declare(strict_types=1);

namespace App\Pwa\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Tant qu'un compte doit définir un nouveau mot de passe (réinitialisé par un
 * administrateur), il n'accède À AUCUN module : toute page authentifiée le
 * renvoie vers « Définissez votre nouveau mot de passe ».
 *
 * Deux sorties seulement, qui ne sont pas des modules : l'écran de changement
 * lui-même et la déconnexion. Un mot de passe temporaire EXPIRÉ (24 h) ferme la
 * session et renvoie à la connexion : il faut en faire générer un nouveau.
 *
 * Posé sur le groupe `auth` de `routes/web.php`, donc avant toute garde de
 * module (`module:M1,L`…).
 *
 * @see App\Shared\Auth\Services\MotDePassePerduService
 */
final class ExigerChangementMotDePasse
{
    /** Les routes qu'un compte « changement obligatoire » peut atteindre. */
    public const ROUTES_PERMISES = ['pwa.changement-mot-de-passe', 'logout'];

    public function handle(Request $request, Closure $next): Response
    {
        $utilisateur = $request->user();

        if ($utilisateur === null || ! $utilisateur->must_change_password) {
            return $next($request);
        }

        if ($utilisateur->motDePasseTemporaireExpire()) {
            Auth::logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();

            return redirect()->route('pwa.connexion')
                ->with('pwa-connexion-info', __('pwa.changement_mdp.expire'));
        }

        if (in_array($request->route()?->getName(), self::ROUTES_PERMISES, true)) {
            return $next($request);
        }

        return redirect()->route('pwa.changement-mot-de-passe');
    }
}
