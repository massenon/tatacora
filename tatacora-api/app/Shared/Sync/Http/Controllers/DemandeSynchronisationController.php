<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Controllers;

use App\Shared\Sync\Services\SuiviPostesService;
use App\Shared\Sync\Support\PosteDuJeton;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * `GET /api/v1/sync/demande?poste_id=…` — le passage court du poste (toutes
 * les 30 s) : la dernière demande « Synchroniser » faite au serveur. Plus
 * récente que celle qu'il a déjà suivie, le poste lance aussitôt sa
 * synchronisation complète. Rien n'est téléchargé ici.
 */
class DemandeSynchronisationController
{
    public function __construct(private readonly SuiviPostesService $suivi)
    {
    }

    public function __invoke(Request $request): JsonResponse
    {
        $valide = $request->validate(['poste_id' => ['required', 'string', 'max:255']]);

        if (! PosteDuJeton::concorde($request, $valide['poste_id'])) {
            return response()->json(['message' => __('sync.poste_non_reconnu')], 403);
        }

        $this->suivi->noterLecture($valide['poste_id'], $request->user());

        return response()->json([
            'data' => ['demandee_le' => $this->suivi->derniereDemande()?->demandee_le?->toIso8601String()],
        ]);
    }
}
