<?php

declare(strict_types=1);

use App\Http\Middleware\EnTetesSecurite;
use App\Shared\Rbac\Middleware\VerifierAccesModule;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

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
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
