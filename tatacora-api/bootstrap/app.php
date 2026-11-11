<?php

declare(strict_types=1);

use App\Http\Middleware\EnTetesSecurite;
use App\Http\Support\PageErreur;
use App\Shared\Rbac\Middleware\VerifierAccesModule;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        apiPrefix: 'api',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // 2e niveau RBAC — 00_MASTER_INSTRUCTIONS.md §3.2.
        // Usage : ->middleware('module:M1,C') pour une ecriture,
        //         ->middleware('module:M1,L') pour une consultation.
        $middleware->alias([
            'module' => VerifierAccesModule::class,
        ]);

        // Un invite arrivant sur une page protegee de la PWA est renvoye vers
        // le formulaire de connexion, jamais vers la route `login` par defaut
        // de Laravel, qui n'existe pas ici.
        $middleware->redirectGuestsTo(fn () => route('pwa.connexion'));

        // Les en-tetes de securite HTTP. Audit du 27/08/2026 : AUCUN n'etait
        // pose, par aucun canal — ni middleware, ni `.htaccess`, ni balise
        // meta. Applique globalement, donc a la PWA comme a l'API : une
        // reponse d'API rendue dans un navigateur profite des memes
        // protections, et n'avoir qu'un seul endroit ou elles sont posees
        // evite qu'un canal ajoute demain les oublie.
        $middleware->append(EnTetesSecurite::class);

        // Derriere le proxy de l'hebergeur, la requete arrive en HTTP simple :
        // sans proxys de confiance, Laravel ne voit pas `https`, le cookie de
        // session `Secure` n'est pas reconnu et les jetons CSRF se desynchronisent
        // (« Page Expired »). `TRUSTED_PROXIES` restreint la liste si besoin.
        $middleware->trustProxies(
            at: env('TRUSTED_PROXIES', '*'),
            headers: Request::HEADER_X_FORWARDED_FOR
                | Request::HEADER_X_FORWARDED_HOST
                | Request::HEADER_X_FORWARDED_PORT
                | Request::HEADER_X_FORWARDED_PROTO,
        );
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Pages d'erreur (`resources/views/errors/`, gabarit `errors/layout`).
        // Laravel convertit DEJA les exceptions courantes en HttpException et
        // choisit la vue `errors/<code>` (repli `4xx`/`5xx`) pour une requete
        // HTML : TokenMismatchException -> 419, ThrottleRequestsException ->
        // 429 (avec `Retry-After`), AuthorizationException -> 403,
        // ModelNotFoundException -> 404, tout le reste -> 500. Les vues ne
        // lisent jamais le message de l'exception : aucune fuite. Les requetes
        // JSON (API `/api/v1`, `Accept: application/json`) gardent le rendu
        // JSON de Laravel, et APP_DEBUG=true garde sa page de debogage native.
        //
        // L'identifiant d'incident affiche a l'ecran (`PageErreur::incident`)
        // est verse au contexte du journal : le support retrouve l'entree
        // sans que rien de technique ne soit montre.
        $exceptions->context(fn (\Throwable $e): array => ['incident' => PageErreur::incident($e)]);

        // Jeton CSRF/session expire HORS Livewire (formulaire HTML ordinaire,
        // bouton de deconnexion d'un onglet perime) : la page 419 « premium »
        // (decision du PO, 09/11/2026) — statut 419, « Recharger la page » et
        // « Retour a la connexion » — au lieu de l'ancienne redirection
        // silencieuse vers la connexion. Si le formulaire venait de la
        // connexion elle-meme, « Retour a la connexion » devient le bouton
        // principal (la page de connexion est rechargee avec un jeton neuf).
        // Aucun message d'exception n'est lu par la vue.
        // Les requetes Livewire gardent leur 419 (page 419 servie par Laravel) :
        // leur script (`pwa.partials.session-expiree`) l'intercepte, recharge
        // la page et la connexion affiche alors le bandeau « Votre session a
        // expire » (drapeau `sessionStorage`, seul usage restant du bandeau :
        // le middleware `auth` ne le pose pas). L'API (jetons Sanctum, pas de
        // CSRF) et tout `Accept: application/json` gardent le rendu JSON.
        // Laravel convertit TokenMismatchException en HttpException(419) AVANT
        // les rendus personnalises : c'est celle-ci qu'il faut attraper.
        $exceptions->render(function (HttpExceptionInterface $e, Request $request) {
            if ($e->getStatusCode() !== 419) {
                return null;
            }
            if ($request->hasHeader('X-Livewire') || $request->is('api/*') || $request->expectsJson()) {
                return null;
            }

            return response()->view('errors.419', [
                'exception' => $e,
                'versConnexion' => PageErreur::venaitDeLaConnexion($request),
            ], 419);
        });
    })->create();
