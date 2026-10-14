<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Http\Controllers;

use App\Domain\Hebergement\Http\Requests\CreerReservationRequest;
use App\Domain\Hebergement\Http\Resources\ReservationResource;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Services\DisponibiliteService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * API des réservations d'hébergement (M1).
 *
 * Simple orchestrateur, conformément à 06_DEVELOPMENT_STANDARDS.md §2.2 :
 * récupérer la requête validée → appeler le Service → retourner la Resource.
 * Aucune règle de gestion n'est implémentée ici.
 */
class ReservationController
{
    public function __construct(
        private readonly ReservationService $reservations,
        private readonly DisponibiliteService $disponibilite,
    ) {
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        $reservations = Reservation::query()
            ->with('client')
            ->when($request->filled('unite_id'), fn ($q) => $q->where('unite_id', $request->string('unite_id')))
            ->when($request->filled('statut'), fn ($q) => $q->where('statut', $request->string('statut')))
            ->orderBy('date_arrivee')
            ->paginate(50);

        return ReservationResource::collection($reservations);
    }

    public function store(CreerReservationRequest $request): JsonResponse
    {
        try {
            $reservation = $this->reservations->creer($request->validated());
        } catch (ChevauchementDetecteException $e) {
            // 409 Conflict, pas 500 : le client Flutter qui rejoue une
            // réservation créée hors connexion doit pouvoir distinguer un
            // refus métier d'une panne serveur (LARAVEL_SYNC_FLUTTER.md §4).
            return response()->json([
                'message' => $e->getMessage(),
                'reservations_en_conflit' => $e->identifiantsEnConflit,
            ], 409);
        }

        return (new ReservationResource($reservation->load('client')))
            ->response()
            ->setStatusCode(201);
    }

    public function show(Reservation $reservation): ReservationResource
    {
        return new ReservationResource($reservation->load('client'));
    }

    /**
     * Annulation — jamais de suppression (RG-02, et 03_DATABASE_ENGINEERING.md §15).
     */
    public function annuler(Reservation $reservation): ReservationResource
    {
        return new ReservationResource($this->reservations->annuler($reservation));
    }

    public function disponibilites(Request $request): JsonResponse
    {
        $valide = $request->validate([
            'date_arrivee' => ['required', 'date'],
            'date_depart' => ['required', 'date', 'after:date_arrivee'],
            'categorie_id' => ['sometimes', 'uuid'],
        ]);

        $unites = $this->disponibilite->unitesDisponibles(
            $valide['date_arrivee'],
            $valide['date_depart'],
            $valide['categorie_id'] ?? null,
        );

        return response()->json([
            'data' => $unites->map(fn ($unite): array => [
                'id' => $unite->id,
                'numero' => $unite->numero,
                'categorie_id' => $unite->categorie_id,
            ])->all(),
        ]);
    }
}
