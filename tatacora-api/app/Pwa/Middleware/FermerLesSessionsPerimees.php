<?php

declare(strict_types=1);

namespace App\Pwa\Middleware;

use App\Pwa\Support\EmpreinteMotDePasseEnSession;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Ferme toute session dont le compte a changé de mot de passe depuis qu'elle l'a
 * vu (réinitialisation par un administrateur, code de secours) — décision du PO
 * du 29/10/2026 : « sessions du compte coupées ».
 *
 * Le compte qui change SON PROPRE mot de passe (« Mon profil ») reste connecté :
 * l'empreinte est reposée à la fin de sa requête, comme le fait
 * `AuthenticateSession` de Laravel.
 *
 * @see EmpreinteMotDePasseEnSession
 */
final class FermerLesSessionsPerimees
{
    public function handle(Request $request, Closure $next): Response
    {
        $utilisateur = $request->user();

        if ($utilisateur === null || ! $request->hasSession()) {
            return $next($request);
        }

        if (EmpreinteMotDePasseEnSession::estPeriee($utilisateur)) {
            Auth::logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();

            return redirect()->route('pwa.connexion');
        }

        $reponse = $next($request);

        // Le titulaire a pu changer son propre mot de passe pendant la requête.
        $apres = Auth::user();

        if ($apres !== null) {
            EmpreinteMotDePasseEnSession::poser($apres);
        }

        return $reponse;
    }
}
