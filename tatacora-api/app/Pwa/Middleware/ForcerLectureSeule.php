<?php

declare(strict_types=1);

namespace App\Pwa\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Sécurise le périmètre des routes HTTP du canal web /pwa.
 * Les soumissions transactionnelles de formulaires transitent exclusivement via Livewire.
 */
class ForcerLectureSeule
{
    /** Méthodes HTTP autorisées pour la consultation directe d'URL. */
    private const METHODES_LECTURE = ['GET', 'HEAD', 'OPTIONS'];

    public function handle(Request $request, Closure $next): Response
    {
        if (! in_array($request->method(), self::METHODES_LECTURE, true)) {
            abort(405, __('pwa.ecriture_refusee'));
        }

        return $next($request);
    }
}
