<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Http\Controllers;

use App\Domain\Vehicules\Http\Requests\CreerContratLocationRequest;
use App\Domain\Vehicules\Http\Requests\EnregistrerEntretienRequest;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ContratLocationService;
use App\Domain\Vehicules\Services\ParcVehiculeService;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use RuntimeException;

/**
 * Parc de véhicules et contrats de location — M8.
 *
 * @see EF-M8-01 Référentiel véhicules
 * @see EF-M8-02 Disponibilité et planning
 * @see EF-M8-03 Contrat de location
 *
 * Simple orchestrateur (`06_DEVELOPMENT_STANDARDS.md` §2.2) : RG-08 et RG-09
 * vivent dans le service et le `FormRequest`, jamais ici.
 */
class VehiculeController
{
    public function __construct(
        private readonly ContratLocationService $locations,
        private readonly ParcVehiculeService $parc,
    ) {
    }

    /**
     * Parc filtrable — double filtre catégorie + statut
     * (`SPEC_ECRAN_M8_VEHICULES.md` §3).
     */
    public function index(Request $request): JsonResponse
    {
        $vehicules = Vehicule::query()
            ->when($request->filled('categorie'), fn ($q) => $q->where('categorie', $request->string('categorie')))
            ->when($request->filled('statut'), fn ($q) => $q->where('statut', $request->string('statut')))
            ->orderBy('immatriculation')
            ->paginate(50);

        return response()->json([
            'data' => $vehicules->through(fn (Vehicule $v): array => [
                'id' => $v->id,
                'immatriculation' => $v->immatriculation,
                'categorie' => $v->categorie,
                'annee' => $v->annee,
                'transmission' => $v->transmission,
                'capacite' => $v->capacite,
                'tarif_jour' => $v->tarif_jour,
                'statut' => $v->statut,
                // Exposé pour que l'écran Flutter conditionne son formulaire
                // sans réimplémenter RG-09 de son côté.
                'exige_permis' => $v->exigePermis(),
            ])->items(),
            'meta' => ['total' => $vehicules->total(), 'page' => $vehicules->currentPage()],
        ]);
    }

    /**
     * Disponibilité calculée d'un véhicule sur une période — EF-M8-02, RG-08.
     *
     * Lecture sans verrou : c'est un confort d'affichage de planning, jamais
     * une garantie. Entre cette réponse et la création du contrat, un
     * concurrent peut insérer — seul `creer()` protège réellement.
     */
    public function disponibilite(Request $request): JsonResponse
    {
        $valide = $request->validate([
            'vehicule_id' => ['required', 'uuid', 'exists:vehicules,id'],
            'date_debut' => ['required', 'date'],
            'date_fin' => ['required', 'date', 'after:date_debut'],
        ]);

        $vehicule = Vehicule::findOrFail($valide['vehicule_id']);

        return response()->json([
            'data' => [
                'vehicule_id' => $vehicule->id,
                'calendrier_libre' => $this->locations->estDisponible(
                    $vehicule->id,
                    $valide['date_debut'],
                    $valide['date_fin'],
                ),
                // Deux notions distinctes : un véhicule au calendrier libre
                // mais en entretien n'est pas louable pour autant.
                'statut_louable' => $vehicule->estLouable(),
                'statut' => $vehicule->statut,
                'exige_permis' => $vehicule->exigePermis(),
            ],
        ]);
    }

    public function contrats(Request $request): JsonResponse
    {
        $contrats = ContratLocation::query()
            ->with(['vehicule:id,immatriculation,categorie,tarif_jour', 'client:id,nom,prenom'])
            ->when($request->filled('vehicule_id'), fn ($q) => $q->where('vehicule_id', $request->string('vehicule_id')))
            ->orderByDesc('date_debut')
            ->paginate(50);

        return response()->json([
            'data' => $contrats->through(fn (ContratLocation $c): array => [
                'id' => $c->id,
                'vehicule' => $c->vehicule->immatriculation,
                'client_id' => $c->client_id,
                'date_debut' => $c->date_debut->toDateString(),
                'date_fin' => $c->date_fin->toDateString(),
                'nombre_jours' => $c->nombreJours(),
                // Montant CALCULÉ, jamais un champ de formulaire soumis.
                'montant' => $c->montant(),
                'package_avec_guide' => $c->estPackageAvecGuide(),
            ])->items(),
            'meta' => ['total' => $contrats->total(), 'page' => $contrats->currentPage()],
        ]);
    }

    /**
     * Création d'un contrat — RG-08 (verrou) + RG-09 (pièces).
     */
    public function creerContrat(CreerContratLocationRequest $request): JsonResponse
    {
        try {
            $contrat = $this->locations->creer($request->validated());
        } catch (ChevauchementDetecteException $e) {
            // 409 : la demande est valide, c'est l'état concurrent du système
            // qui la refuse. Un 422 laisserait croire à une saisie fautive.
            return response()->json([
                'message' => $e->getMessage(),
                'contrats_en_conflit' => $e->identifiantsEnConflit,
            ], 409);
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'data' => [
                'id' => $contrat->id,
                'vehicule_id' => $contrat->vehicule_id,
                'date_debut' => $contrat->date_debut->toDateString(),
                'date_fin' => $contrat->date_fin->toDateString(),
                'nombre_jours' => $contrat->nombreJours(),
                'montant' => $contrat->montant(),
            ],
        ], 201);
    }

    /**
     * Entretien ou carburation — EF-M8-05.
     *
     * Les règles vivaient EN LIGNE ici : extraites vers
     * `EnregistrerEntretienRequest` (PA-159, lot 0b) pour que la PWA ait une
     * source de règles à réutiliser via `ReglesDeLApi`.
     */
    public function enregistrerEntretien(EnregistrerEntretienRequest $request): JsonResponse
    {
        $entretien = $this->parc->enregistrerEntretien($request->validated());

        return response()->json(['data' => ['id' => $entretien->id]], 201);
    }
}
