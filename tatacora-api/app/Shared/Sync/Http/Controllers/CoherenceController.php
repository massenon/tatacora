<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Controllers;

use App\Shared\Sync\Services\CoherenceService;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * `GET /api/v1/sync/coherence?du=AAAA-MM-JJ&au=AAAA-MM-JJ` — les comptes du
 * serveur pour le contrôle de cohérence du poste (P1-1).
 */
class CoherenceController
{
    public function __construct(private readonly CoherenceService $coherence)
    {
    }

    public function __invoke(Request $request): JsonResponse
    {
        $valide = $request->validate([
            'du' => ['required', 'date_format:Y-m-d'],
            'au' => ['required', 'date_format:Y-m-d', 'after_or_equal:du'],
        ]);
        $du = CarbonImmutable::parse($valide['du']);
        $au = CarbonImmutable::parse($valide['au']);

        if ($du->diffInDays($au) >= CoherenceService::JOURS_MAX) {
            return response()->json([
                'message' => __('sync.coherence.fenetre', ['jours' => CoherenceService::JOURS_MAX]),
                'errors' => ['au' => [__('sync.coherence.fenetre', ['jours' => CoherenceService::JOURS_MAX])]],
            ], 422);
        }

        return response()->json(['data' => [
            'du' => $valide['du'],
            'au' => $valide['au'],
            'genere_le' => now()->toIso8601String(),
            'tables' => $this->coherence->comptes($request->user(), $valide['du'], $valide['au']),
        ]]);
    }
}
