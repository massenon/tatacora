<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Http\Controllers;

use App\Domain\Tourisme\Http\Requests\ReserverCircuitRequest;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Tourisme\Models\ReservationTour;
use App\Domain\Tourisme\Services\ReservationTourService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use RuntimeException;

/**
 * Circuits, guides et réservations touristiques — M9.
 *
 * @see EF-M9-01 Catalogue de circuits
 * @see EF-M9-02 Référentiel des guides
 * @see EF-M9-03 Réservation avec affectation de guide
 * @see EF-M9-05 Suivi du déroulement
 *
 * Simple orchestrateur (`06_DEVELOPMENT_STANDARDS.md` §2.2).
 */
class TourismeController
{
    public function __construct(
        private readonly ReservationTourService $reservations,
    ) {
    }

    public function circuits(Request $request): JsonResponse
    {
        $circuits = Circuit::query()
            ->when($request->filled('theme'), fn ($q) => $q->where('theme', $request->string('theme')))
            ->when($request->filled('zone'), fn ($q) => $q->where('zone', $request->string('zone')))
            ->orderBy('nom')
            ->paginate(50);

        $date = $request->string('date')->toString();

        return response()->json([
            'data' => $circuits->through(fn (Circuit $c): array => [
                'id' => $c->id,
                'nom' => $c->nom,
                'theme' => $c->theme,
                'zone' => $c->zone,
                // Libellé libre, jamais un nombre de jours exploitable (PA-51).
                'duree' => $c->duree,
                'prix' => $c->prix,
                'capacite_max' => $c->capacite_max,
                // Calculée seulement si une date est demandée : sans date, la
                // question « combien de places reste-t-il » n'a pas de sens.
                'places_restantes' => $date === ''
                    ? null
                    : $this->reservations->placesRestantes($c, $date),
            ])->items(),
            'meta' => ['total' => $circuits->total(), 'page' => $circuits->currentPage()],
        ]);
    }

    /**
     * Référentiel des guides — EF-M9-02.
     *
     * `SPEC_ECRAN_M9_TOURISME.md` §6 : ce référentiel n'a **aucun écran** au
     * prototype, contrairement au reste du module. C'est le premier accès
     * programmatique qui lui est donné.
     */
    public function guides(Request $request): JsonResponse
    {
        $zone = $request->string('zone')->toString();

        $guides = Guide::query()->orderBy('nom')->get();

        return response()->json([
            'data' => $guides->map(fn (Guide $g): array => [
                'id' => $g->id,
                'nom' => $g->nom,
                'certification' => $g->certification,
                'zone_competence' => $g->zone_competence,
                'tarif_jour' => $g->tarif_jour,
                // Indicatif : l'affectation hors zone reste permise, un
                // remplacement en urgence est un cas d'exploitation normal.
                'competent_sur_zone' => $zone === '' ? null : $g->competentSurZone($zone),
                'disponible' => $request->filled('date')
                    ? $this->reservations->affectationsDuGuide($g->id, $request->string('date')->toString())->isEmpty()
                    : null,
            ])->all(),
        ]);
    }

    public function reservations(Request $request): JsonResponse
    {
        $reservations = ReservationTour::query()
            ->with(['circuit:id,nom,zone,prix,capacite_max', 'guide:id,nom'])
            ->when($request->filled('statut'), fn ($q) => $q->where('statut', $request->string('statut')))
            ->when($request->filled('date'), fn ($q) => $q->whereDate('date_circuit', $request->string('date')->toString()))
            ->orderByDesc('date_circuit')
            ->paginate(50);

        return response()->json([
            'data' => $reservations->through(fn (ReservationTour $r): array => [
                'id' => $r->id,
                'circuit' => $r->circuit->nom,
                'date_circuit' => $r->date_circuit->toDateString(),
                'nb_participants' => $r->nb_participants,
                'guide' => $r->guide->nom,
                'statut' => $r->statut,
                // Montant CALCULÉ, jamais soumis.
                'montant' => $r->montant(),
            ])->items(),
            'meta' => ['total' => $reservations->total(), 'page' => $reservations->currentPage()],
        ]);
    }

    public function reserver(ReserverCircuitRequest $request): JsonResponse
    {
        try {
            $reservation = $this->reservations->reserver($request->validated());
        } catch (RuntimeException $e) {
            // 422 : la demande est refusée par une règle de gestion (capacité,
            // guide occupé) que l'utilisateur peut corriger en changeant sa
            // saisie — contrairement au 409 de RG-08, qui signale un conflit
            // d'état concurrent sur une ressource unique.
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'data' => [
                'id' => $reservation->id,
                'circuit_id' => $reservation->circuit_id,
                'date_circuit' => $reservation->date_circuit->toDateString(),
                'nb_participants' => $reservation->nb_participants,
                'statut' => $reservation->statut,
                'montant' => $reservation->montant(),
            ],
        ], 201);
    }

    /**
     * Affectation d'un guide — UC-39.
     */
    public function affecterGuide(Request $request, ReservationTour $reservation): JsonResponse
    {
        $valide = $request->validate([
            'guide_id' => ['required', 'uuid', 'exists:guides,id'],
        ]);

        try {
            $reservation = $this->reservations->affecterGuide($reservation, $valide['guide_id']);
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['data' => ['id' => $reservation->id, 'guide_id' => $reservation->guide_id]]);
    }

    /**
     * Clôture d'une prestation — UC-40.
     */
    public function cloturer(ReservationTour $reservation): JsonResponse
    {
        try {
            $reservation = $this->reservations->cloturer($reservation);
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['data' => ['id' => $reservation->id, 'statut' => $reservation->statut]]);
    }

    /**
     * Annulation — libère la place au départ.
     */
    public function annuler(ReservationTour $reservation): JsonResponse
    {
        try {
            $reservation = $this->reservations->annuler($reservation);
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['data' => ['id' => $reservation->id, 'statut' => $reservation->statut]]);
    }
}
