<?php

declare(strict_types=1);

namespace App\Shared\Rbac\Middleware;

use App\Shared\Rbac\Models\JournalSecurite;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * 2ᵉ niveau du RBAC à trois niveaux (00_MASTER_INSTRUCTIONS.md §3.2) :
 * le 1ᵉʳ est le masquage d'interface côté Flutter, le 3ᵉ le filtrage en base.
 *
 * Vérifie le niveau d'accès (C/L/-) AVANT d'atteindre le contrôleur.
 * Le masquage d'interface côté client ne protège rien : un appel direct à
 * l'API doit être refusé ici, pas seulement caché là-bas.
 *
 * Usage : ->middleware('module:M1,C') pour une action d'écriture,
 *         ->middleware('module:M1,L') pour une simple consultation.
 *
 * @see RG-16
 */
class VerifierAccesModule
{
    public function handle(Request $request, Closure $next, string $module, string $niveauRequis = 'L'): Response
    {
        $utilisateur = $request->user();

        if ($utilisateur === null || ! $utilisateur->estActif()) {
            $this->tracer($request, null, $module);

            return response()->json(['message' => __('auth.requise')], 401);
        }

        $niveauObtenu = $utilisateur->niveauSurModule($module);

        // '-' n'accède à rien ; 'L' n'accède qu'à ce qui exige 'L'.
        $suffisant = match ($niveauRequis) {
            'C' => $niveauObtenu === 'C',
            'L' => in_array($niveauObtenu, ['C', 'L'], true),
            default => false,
        };

        if (! $suffisant) {
            // SECURITY_STRICT.md §10 — toute tentative d'accès refusée est tracée
            // dans journal_securite, distinct du journal_audit métier.
            $this->tracer($request, $utilisateur->id, $module);

            return response()->json(['message' => __('auth.module_refuse')], 403);
        }

        return $next($request);
    }

    private function tracer(Request $request, ?string $utilisateurId, string $module): void
    {
        JournalSecurite::create([
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $utilisateurId,
            'adresse_ip' => $request->ip(),
            'module_concerne' => $module,
        ]);
    }
}
