<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Controllers;

use App\Shared\Sync\Services\SuiviPostesService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use RuntimeException;

/**
 * L'écran « Synchroniser les postes » du POSTE (décision PO du 18/10/2026) :
 * le même que celui de la PWA, servi par l'API — depuis n'importe quel poste,
 * l'état de tous les postes, et la demande qui les fait passer tout de suite.
 * Ouvert à tout compte, comme la page web : la demande n'écrit aucune donnée
 * métier. La RÉVOCATION d'un appairage (19/10/2026) est réservée aux
 * Administrateurs, et un poste ne révoque pas le sien (il se « Dissocie »).
 */
class SuiviPostesController
{
    public function __construct(private readonly SuiviPostesService $suivi)
    {
    }

    /** `GET /api/v1/sync/postes` */
    public function etats(): JsonResponse
    {
        return response()->json(['data' => [
            'demandee_le' => $this->suivi->derniereDemande()?->demandee_le?->toIso8601String(),
            'postes' => array_map(static fn (array $p): array => [
                'poste_id' => $p['poste_id'],
                'utilisateur' => $p['utilisateur'],
                'derniere_montee' => $p['derniere_montee']?->toIso8601String(),
                'derniere_descente' => $p['derniere_descente']?->toIso8601String(),
                'en_attente' => $p['en_attente'],
                'demande_suivie' => $p['demande_suivie'],
                'appaire' => $p['appaire'],
                'jeton_utilise_le' => $p['jeton_utilise_le']?->toIso8601String(),
                'appaire_le' => $p['appaire_le']?->toIso8601String(),
                'expire_le' => $p['expire_le']?->toIso8601String(),
                'dernier_controle' => $p['dernier_controle']?->toIso8601String(),
                'etat' => $p['etat'],
            ], $this->suivi->etats()),
        ]]);
    }

    /** `POST /api/v1/sync/demande` */
    public function demander(Request $request): JsonResponse
    {
        $demande = $this->suivi->demander($request->user());

        return response()->json(['data' => ['demandee_le' => $demande->demandee_le->toIso8601String()]], 201);
    }

    /** `POST /api/v1/sync/postes/{poste}/revocation` */
    public function revoquer(Request $request, string $poste): JsonResponse
    {
        if ($request->user()?->currentAccessToken()?->name === $poste) {
            return response()->json(['message' => __('sync.postes.revocation_soi_meme')], 422);
        }

        try {
            $nombre = $this->suivi->revoquer($poste, $request->user());
        } catch (RuntimeException $refus) {
            return response()->json(['message' => $refus->getMessage()], $request->user()->estAdministrateur() ? 422 : 403);
        }

        return response()->json(['data' => ['poste_id' => $poste, 'jetons_revoques' => $nombre]]);
    }
}
