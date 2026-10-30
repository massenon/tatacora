<?php

declare(strict_types=1);

use App\Http\Middleware\EnTetesSecurite;
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
        // Jeton CSRF/session expire HORS Livewire (formulaire de repli, bouton
        // de deconnexion d'un onglet perime) : renvoi vers la connexion avec le
        // message « Votre session a expire », jamais la page « Page Expired ».
        // Les requetes Livewire gardent leur 419 : leur script
        // (`pwa.partials.session-expiree`) l'intercepte et recharge la page ;
        // une redirection suivie par `fetch` donnerait une page HTML a la place
        // du JSON attendu. L'API (jetons Sanctum, pas de CSRF) n'est pas touchee.
        // Laravel convertit TokenMismatchException en HttpException(419) AVANT
        // les rendus personnalises : c'est celle-ci qu'il faut attraper.
        $exceptions->render(function (HttpExceptionInterface $e, Request $request) {
            if ($e->getStatusCode() !== 419) {
                return null;
            }
            if ($request->hasHeader('X-Livewire') || $request->is('api/*') || $request->expectsJson()) {
                return null;
            }

            return redirect()->route('pwa.connexion')->with('session_expiree', true);
        });
    })->create();
