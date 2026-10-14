<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Les en-têtes de sécurité HTTP — SECURITY_STRICT.md.
 *
 * ## Ils étaient ABSENTS, tous les cinq
 *
 * Audit du 27/08/2026 : aucun en-tête de sécurité n'était posé par aucun
 * canal — ni middleware, ni `public/.htaccess` (26 lignes de réécriture
 * seulement), ni balise `meta` dans les gabarits. Le cas d'usage nommé par
 * `LARAVEL_PWA.md` §1 est pourtant la consultation **depuis un cybercafé de
 * Natitingou**, c'est-à-dire un navigateur et un réseau qu'on ne maîtrise pas.
 *
 * ## `Content-Security-Policy` est posée en REPORT-ONLY, délibérément
 *
 * Une CSP trop stricte ne dégrade pas : elle **casse**, en silence, et
 * l'interface cesse de répondre sans message. Alpine.js — embarqué par
 * Livewire — évalue ses expressions par `new Function()`, ce qui exige
 * `'unsafe-eval'` hors de sa variante CSP. Poser une politique bloquante sans
 * l'avoir éprouvée écran par écran reviendrait à livrer une panne.
 *
 * `Report-Only` applique donc la vraie politique visée et **rapporte** ce
 * qu'elle bloquerait, sans rien casser. Le passage en mode bloquant est un
 * geste séparé, à faire quand les rapports sont vides — et il consiste à
 * changer une constante, pas à réécrire ce fichier.
 *
 * ⚠ Ne pas lire `Report-Only` comme une protection : elle n'en est pas une.
 * C'est une MESURE. La confondre avec une défense serait exactement
 * l'indicateur qui affirme un état qu'il n'a pas vérifié (PA-59/60/61).
 *
 * ## `Strict-Transport-Security` n'est posé QUE sur HTTPS
 *
 * Le poser sur une réponse HTTP est sans effet — la spécification impose au
 * navigateur de l'ignorer — mais surtout, le poser en développement local
 * épinglerait `localhost` en HTTPS dans le navigateur du développeur, pour
 * des mois, sans qu'il comprenne pourquoi son serveur ne répond plus.
 */
class EnTetesSecurite
{
    /**
     * La politique visée. Elle est **rapportée**, pas appliquée — voir le bloc
     * ci-dessus.
     *
     * `'self'` partout : la PWA est vendorisée (Tailwind, polices et scripts
     * sont servis localement), précisément pour rester utilisable sans
     * Internet. Aucune origine tierce n'a donc à être autorisée.
     *
     * `frame-ancestors 'none'` double `X-Frame-Options` : le premier est la
     * norme actuelle, le second reste compris des navigateurs anciens, et le
     * parc du Gîte n'est pas maîtrisé.
     */
    private const POLITIQUE_CONTENU = "default-src 'self'; "
        ."script-src 'self' 'unsafe-eval'; "
        ."style-src 'self' 'unsafe-inline'; "
        ."img-src 'self' data:; "
        ."font-src 'self'; "
        ."connect-src 'self'; "
        ."form-action 'self'; "
        ."frame-ancestors 'none'; "
        ."base-uri 'self'; "
        .'object-src \'none\'';

    public function handle(Request $request, Closure $next): Response
    {
        $reponse = $next($request);

        // Le clickjacking : une page de la PWA chargée dans une `iframe`
        // invisible, sur laquelle on fait cliquer l'utilisateur à son insu.
        $reponse->headers->set('X-Frame-Options', 'DENY');

        // Le MIME-sniffing : un fichier servi en `text/plain` que le
        // navigateur décide d'exécuter comme du script parce que son contenu
        // y ressemble.
        $reponse->headers->set('X-Content-Type-Options', 'nosniff');

        // Le référent complet fuite l'URL — donc les identifiants de
        // ressources qu'elle porte — vers tout domaine tiers atteint depuis la
        // page. `same-origin` la garde à la maison.
        $reponse->headers->set('Referrer-Policy', 'same-origin');

        // Aucun de ces trois capteurs n'est employé par la PWA. Les fermer
        // explicitement évite qu'un script injecté puisse les demander.
        $reponse->headers->set(
            'Permissions-Policy',
            'camera=(), microphone=(), geolocation=()',
        );

        $reponse->headers->set(
            'Content-Security-Policy-Report-Only',
            self::POLITIQUE_CONTENU,
        );

        if ($request->secure()) {
            $reponse->headers->set(
                'Strict-Transport-Security',
                'max-age=31536000; includeSubDomains',
            );
        }

        return $reponse;
    }
}
