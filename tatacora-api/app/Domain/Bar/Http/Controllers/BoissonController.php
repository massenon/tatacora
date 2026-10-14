<?php

declare(strict_types=1);

namespace App\Domain\Bar\Http\Controllers;

use App\Domain\Bar\Http\Requests\ConsulterVentesBarRequest;
use App\Domain\Bar\Http\Requests\EnregistrerBoissonRequest;
use App\Domain\Bar\Http\Requests\LierBoissonAuStockRequest;
use App\Domain\Bar\Http\Requests\RemettreBoissonALaCarteRequest;
use App\Domain\Bar\Http\Requests\RetirerBoissonDeLaCarteRequest;
use App\Domain\Bar\Http\Resources\BoissonResource;
use App\Domain\Bar\Http\Resources\HistoriquePrixResource;
use App\Domain\Bar\Http\Resources\LigneVenteRayonResource;
use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Bar\Services\VenteBarService;
use App\Domain\Carte\Models\HistoriquePrixCarte;
use App\Domain\Carte\Services\DisponibiliteCarteService;
use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Domain\Ventes\Services\LignesVenteDuRayonService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use RuntimeException;

/**
 * CRUD de la carte des boissons et enregistrement des ventes (M5).
 *
 * Simple orchestrateur (06_DEVELOPMENT_STANDARDS.md §2.2).
 */
class BoissonController
{
    public function __construct(
        private readonly VenteBarService $ventes,
        private readonly CarteBoissonService $carte,
        private readonly DisponibiliteCarteService $disponibilite,
    ) {
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        $boissons = CarteBoisson::query()
            // UNE requête pour l'état de toute la page, pas une par ligne —
            // l'article de stock aussi, que la ressource lit pour le stock.
            ->with(['indisponibiliteEnCours', 'article'])
            ->when($request->filled('categorie'), fn ($q) => $q->where('categorie', $request->string('categorie')))
            ->orderBy('libelle')
            ->paginate(50);

        return BoissonResource::collection($boissons);
    }

    public function store(EnregistrerBoissonRequest $request): JsonResponse
    {
        $boisson = $this->carte->creer($request->validated());

        return (new BoissonResource($boisson))->response()->setStatusCode(201);
    }

    public function show(CarteBoisson $boisson): BoissonResource
    {
        return new BoissonResource($boisson);
    }

    public function update(EnregistrerBoissonRequest $request, CarteBoisson $boisson): BoissonResource
    {
        return new BoissonResource(
            $this->carte->modifier($boisson, $request->validated()),
        );
    }

    /**
     * « Lier au stock » — l'article ET son conditionnement (EF-M5-02, RG-05).
     *
     * Le refus du domaine (article introuvable, conditionnement invalide)
     * revient en 422 SUR LE CHAMP DU CONDITIONNEMENT, comme la PWA l'affiche
     * (`EcranDeCarte::enregistrerLienAuStock()`) : il nomme la donnée en
     * cause, et un 500 ne dirait rien au comptoir.
     */
    public function lierAuStock(LierBoissonAuStockRequest $request, CarteBoisson $boisson): JsonResponse
    {
        $valide = $request->validated();

        try {
            $boisson = $this->carte->lierAuStock(
                $boisson,
                (string) $valide['article_id'],
                (string) $valide['unites_vendables_par_unite_stock'],
            );
        } catch (RuntimeException $refus) {
            return response()->json([
                'message' => $refus->getMessage(),
                'errors' => ['unites_vendables_par_unite_stock' => [$refus->getMessage()]],
            ], 422);
        }

        return (new BoissonResource($boisson))->response();
    }

    /**
     * « Retirer de la carte du jour » — une indisponibilité motivée, écrite
     * par `DisponibiliteCarteService` sous verrou, imputée à l'utilisateur du
     * jeton (RG-15). Le chemin de la PWA (`enregistrerRetraitDeLaCarte()`).
     *
     * Le refus du domaine — article déjà retiré, décision non imputable —
     * revient en 422 sur `motif`, là où la PWA l'affiche : un 500 ne dirait
     * rien au comptoir.
     */
    public function retirer(RetirerBoissonDeLaCarteRequest $request, CarteBoisson $boisson): JsonResponse
    {
        $valide = $request->validated();

        try {
            $this->disponibilite->rendreIndisponible(
                $boisson,
                (string) $valide['motif'],
                isset($valide['commentaire']) ? (string) $valide['commentaire'] : null,
            );
        } catch (RuntimeException $refus) {
            return $this->refus('motif', $refus);
        }

        return (new BoissonResource($boisson->refresh()->load('indisponibiliteEnCours')))->response();
    }

    /**
     * « Remettre » — l'indisponibilité en cours est LEVÉE, jamais effacée :
     * l'historique des ruptures est ce sur quoi se décide un
     * réapprovisionnement. Remettre ce qui n'était pas retiré est refusé, pas
     * ignoré (`carte.pas_indisponible`) : un succès silencieux laisserait
     * croire qu'une action a eu lieu.
     */
    public function remettre(RemettreBoissonALaCarteRequest $request, CarteBoisson $boisson): JsonResponse
    {
        try {
            $this->disponibilite->rendreDisponible($boisson);
        } catch (RuntimeException $refus) {
            return $this->refus('etat', $refus);
        }

        return (new BoissonResource($boisson->refresh()->load('indisponibiliteEnCours')))->response();
    }

    /**
     * « Historique des prix » d'une boisson, du plus récent au plus ancien —
     * la même requête qu'`EcranDeCarte::historiquePrixDe()` (PWA).
     *
     * LECTURE : `module:M5,L` suffit, comme dans la PWA, où
     * `ouvrirHistoriquePrix()` n'exige aucun droit d'écriture — un `barman`
     * en lecture doit pouvoir vérifier depuis quand un tarif a changé. Les
     * traces sont écrites par `CarteBoissonObserver` seul ; cette route ne
     * fait que les rendre.
     */
    public function historiquePrix(CarteBoisson $boisson): AnonymousResourceCollection
    {
        return HistoriquePrixResource::collection(
            HistoriquePrixCarte::query()
                ->where('source', HistoriquePrixCarte::SOURCE_BOISSON)
                ->where('source_id', $boisson->getKey())
                ->with('utilisateurCreation')
                ->orderByDesc('created_at')
                ->get(),
        );
    }

    /**
     * « Ventes du Bar » — les LIGNES de vente du rayon M5, filtrées et
     * paginées, avec les compteurs du jeu filtré ENTIER.
     *
     * Même requête et même total que l'onglet de la PWA : l'une et l'autre
     * appellent `LignesVenteDuRayonService`, l'auteur unique (PA-197). Le
     * total n'additionne que les lignes validées (RG-02) et porte sur le jeu
     * filtré, jamais sur la page — un total qui changerait en tournant les
     * pages dirait deux vérités sur le même filtre.
     */
    public function ventes(ConsulterVentesBarRequest $request, LignesVenteDuRayonService $lignes): AnonymousResourceCollection
    {
        $valide = $request->validated();
        $requete = $lignes->requete(
            LignesVenteDuRayonService::RAYON_BAR,
            (string) ($valide['recherche'] ?? ''),
            (string) ($valide['statut'] ?? ''),
            (string) ($valide['du'] ?? ''),
            (string) ($valide['au'] ?? ''),
        );
        $totaux = $lignes->totaux($requete);

        return LigneVenteRayonResource::collection(
            (clone $requete)
                ->with(['vente', 'vente.utilisateur'])
                ->paginate(LignesVenteDuRayonService::PAR_PAGE),
        )->additional([
            'totaux' => [
                'lignes' => $totaux['lignes'],
                'annulees' => $totaux['annulees'],
                'total_valide' => $totaux['total'],
            ],
        ]);
    }

    /** Un refus du domaine, en 422 sur le champ qui le porte. */
    private function refus(string $champ, RuntimeException $refus): JsonResponse
    {
        return response()->json([
            'message' => $refus->getMessage(),
            'errors' => [$champ => [$refus->getMessage()]],
        ], 422);
    }

    /**
     * Vente au comptoir — EF-M5-01 (POS).
     */
    public function vendre(Request $request): JsonResponse
    {
        $valide = $request->validate([
            'session_id' => ['required', 'uuid', 'exists:sessions_caisse,id'],
            'client_id' => ['sometimes', 'nullable', 'uuid', 'exists:clients,id'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.boisson_id' => ['required', 'uuid', 'exists:cartes_boisson,id'],
            'lignes.*.quantite' => ['required', 'integer', 'min:1'],
            // RG-06 : le forçage de rupture est une décision explicite, jamais
            // un défaut. Le client Flutter ne l'envoie qu'après confirmation.
            'validation_rupture' => ['sometimes', 'boolean'],
        ]);

        try {
            $vente = $this->ventes->enregistrer(
                sessionCaisseId: $valide['session_id'],
                lignes: $valide['lignes'],
                clientId: $valide['client_id'] ?? null,
                validationRupture: (bool) ($valide['validation_rupture'] ?? false),
            );
        } catch (RuptureStockException $e) {
            // 422 avec le drapeau attendu par le client, jamais un 500 :
            // le barman doit pouvoir confirmer la rupture en un geste.
            return response()->json($e->versReponse(), 422);
        }

        return response()->json([
            'data' => [
                'id' => $vente->id,
                'montant' => $vente->montant,
                'date_vente' => $vente->date_vente->toIso8601String(),
                'nb_lignes' => $vente->lignes()->count(),
            ],
        ], 201);
    }
}
