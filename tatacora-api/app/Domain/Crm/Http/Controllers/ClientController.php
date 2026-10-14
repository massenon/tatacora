<?php

declare(strict_types=1);

namespace App\Domain\Crm\Http\Controllers;

use App\Domain\Crm\Http\Requests\EnregistrerClientRequest;
use App\Domain\Crm\Http\Resources\ClientResource;
use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\ClientHistoriqueService;
use App\Domain\Crm\Services\DetectionDoublonService;
use App\Domain\Crm\Services\EnregistrementClientService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * API du référentiel client (M3).
 *
 * Simple orchestrateur (06_DEVELOPMENT_STANDARDS.md §2.2) : aucune règle de
 * gestion n'est implémentée ici, tout passe par les Services du domaine.
 */
class ClientController
{
    public function __construct(
        private readonly DetectionDoublonService $doublons,
        private readonly ClientHistoriqueService $historique,
        private readonly EnregistrementClientService $enregistrement,
    ) {
    }

    /**
     * EF-M3-03 — segmentation : filtre par type de client.
     */
    public function index(Request $request): AnonymousResourceCollection
    {
        $clients = Client::query()
            ->when($request->filled('type_client'), fn ($q) => $q->where('type_client', $request->string('type_client')))
            ->when($request->filled('recherche'), function ($q) use ($request) {
                $terme = '%' . $request->string('recherche') . '%';

                return $q->where(fn ($sq) => $sq->where('nom', 'like', $terme)
                    ->orWhere('prenom', 'like', $terme)
                    ->orWhere('telephone', 'like', $terme));
            })
            ->orderBy('nom')
            ->paginate(50);

        return ClientResource::collection($clients);
    }

    /**
     * Pré-vérification de doublon — RG-18.
     *
     * Endpoint distinct de la création : il permet au client Flutter d'avertir
     * PENDANT la saisie, au moment où le réceptionniste peut encore consulter
     * la fiche existante plutôt qu'en créer une seconde. Avertir seulement
     * après l'enregistrement serait trop tard : le doublon existerait déjà.
     */
    public function verifierDoublons(Request $request): JsonResponse
    {
        $valide = $request->validate([
            'nom' => ['required', 'string'],
            'telephone' => ['required', 'string'],
            'exclure_id' => ['sometimes', 'uuid'],
        ]);

        $doublons = $this->doublons->rechercherDoublons(
            $valide['nom'],
            $valide['telephone'],
            $valide['exclure_id'] ?? null,
        );

        return response()->json([
            'doublons_potentiels' => $doublons->map(fn (array $d): array => [
                'id' => $d['client']->id,
                'nom_complet' => $d['client']->nomComplet(),
                'telephone' => $d['client']->telephone,
                'motif' => $d['motif'],
            ])->all(),
            'avertissement' => $this->doublons->messageAvertissement($doublons),
            // Jamais un blocage : l'utilisateur reste libre de créer la fiche.
            'bloquant' => false,
        ]);
    }

    public function store(EnregistrerClientRequest $request): JsonResponse
    {
        // RG-18 (recherche de doublons AVANT création, avertissement rendu avec
        // la fiche) vit dans le service — commun à l'API et à la PWA (PA-159).
        $resultat = $this->enregistrement->creer($request->validated());

        // L'avertissement accompagne une création RÉUSSIE (201) : RG-18 est
        // avertissante, jamais bloquante. Le client Flutter l'affiche comme une
        // invitation à vérifier, pas comme une erreur.
        return (new ClientResource($resultat['client']))
            ->additional(['meta' => [
                'avertissement_doublon' => $resultat['avertissement_doublon'],
            ]])
            ->response()
            ->setStatusCode(201);
    }

    /**
     * EF-M3-02 — fiche + historique consolidé.
     */
    public function show(Client $client): JsonResponse
    {
        $historique = $this->historique->pourClient($client->id);

        return (new ClientResource($client))
            ->additional([
                'historique' => [
                    'sejours' => $historique['sejours']->map(fn ($sejour): array => [
                        'id' => $sejour->id,
                        'unite' => $sejour->unite?->numero,
                        'date_arrivee' => $sejour->date_arrivee->toDateString(),
                        'date_depart' => $sejour->date_depart->toDateString(),
                        'nb_nuitees' => $sejour->nombreNuitees(),
                        'statut' => $sejour->statut,
                    ])->all(),
                    'statistiques' => $this->historique->statistiques($client->id),
                    // Indispensable : sans ces deux clés, une interface
                    // afficherait un historique partiel comme s'il était complet.
                    'sources' => $historique['sources'],
                    'complet' => $historique['complet'],
                ],
            ])
            ->response();
    }

    public function update(EnregistrerClientRequest $request, Client $client): ClientResource
    {
        return new ClientResource(
            $this->enregistrement->modifier($client, $request->validated()),
        );
    }
}
