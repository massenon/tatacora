<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Controllers;

use App\Domain\Restaurant\Exceptions\RecetteManquanteException;
use App\Domain\Restaurant\Http\Requests\CreerCommandeRestaurantRequest;
use App\Domain\Restaurant\Http\Requests\FiltrerCommandesRestaurantRequest;
use App\Domain\Restaurant\Http\Requests\TransmettreCommandeRequest;
use App\Domain\Restaurant\Http\Resources\BonCuisineResource;
use App\Domain\Restaurant\Http\Resources\CommandeRestaurantResource;
use App\Domain\Restaurant\Models\CommandeRestaurant;
use App\Domain\Restaurant\Services\CommandeRestaurantService;
use App\Domain\Stocks\Exceptions\RuptureStockException;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Cycle de vie d'une commande restaurant — M4, EF-M4-03 / EF-M4-05.
 *
 * @see EF-M4-03 Prise de commande par table ou par chambre
 * @see EF-M4-04 Déduction automatique des ingrédients à la validation
 * @see EF-M4-05 Transmission à la cuisine (bon de cuisine)
 * @see RG-05 Sortie de stock automatique
 * @see RG-06 Blocage contrôlé sur rupture
 *
 * ## Pourquoi ces routes, alors que le maître ne montre aucun écran de commande
 *
 * PA-23 et `SPEC_ECRAN_M4_RESTAURANT.md` §7 le constatent : le prototype ne
 * montre que la couche catalogue. Mais `CommandeRestaurantService` et
 * `DeductionStockCuisineService` existent, sont testés — et **n'étaient appelés
 * par aucun code de production, seulement par des tests**. C'est la forme
 * exacte de PA-63 : sans point d'entrée HTTP, RG-05 et RG-06 ne peuvent pas
 * s'exécuter une seule fois en production, et la déduction automatique du stock
 * cuisine — la raison d'être du module — reste du code mort. Deux consommateurs
 * réels attendent ce contrat : le point de vente restaurant du client Flutter
 * (PA-98) et le rayon « Restauration » de la fiche de réservation (PA-110).
 *
 * Ce que ce lot NE tranche PAS : la maquette de l'écran de prise de commande,
 * qui reste à la charge de l'Architecte (PA-23).
 *
 * ## Simple orchestrateur (`06_DEVELOPMENT_STANDARDS.md` §2.2)
 *
 * Toutes les écritures passent par `CommandeRestaurantService`, unique point
 * d'entrée. Une insertion directe contournerait la déduction de stock, son
 * verrou pessimiste et le contrôle de rupture — sans lever la moindre erreur.
 *
 * ## Deux refus de nature différente, et l'écart est délibéré
 *
 * Une **rupture de stock** rend 422 avec `necessite_validation_rupture`, que le
 * client affiche comme une demande de confirmation : RG-06 autorise la rupture
 * assumée par un utilisateur habilité. Une **recette vide** rend 422 sans ce
 * drapeau : elle ne se confirme pas, elle se corrige — laisser passer vendrait
 * le plat sans rien consommer, et l'écart n'apparaîtrait qu'à l'inventaire,
 * imputé à tort à une perte physique.
 *
 * ## Aucune suppression, et aucune clôture
 *
 * `DELETE` n'est routé nulle part : une commande s'annule, elle ne disparaît
 * pas. Et `PATCH .../cloture` n'existe pas — EF-M4-07 (transfert vers la
 * facturation) exigerait un prix par ligne que
 * `lignes_commande_restaurant` **ne porte pas**. Router une clôture qui ne
 * facturerait rien serait un bouton qui confirme sans enregistrer (Article 6 de
 * la directive de conformité). La lacune est au rapport.
 */
class CommandeRestaurantController
{
    public function __construct(
        private readonly CommandeRestaurantService $commandes,
    ) {
    }

    /**
     * Registre des commandes — EF-M4-03.
     */
    public function index(FiltrerCommandesRestaurantRequest $request): AnonymousResourceCollection
    {
        $requete = CommandeRestaurant::query()
            ->with(['client:id,nom,prenom', 'lignes:id,commande_id'])
            ->when(
                $request->filtre('statut'),
                fn (Builder $q, string $statut): Builder => $q->where('statut', $statut),
            )
            ->when(
                $request->filtre('client_id'),
                fn (Builder $q, string $id): Builder => $q->where('client_id', $id),
            )
            ->when(
                $request->filtre('table_ou_chambre_id'),
                fn (Builder $q, string $id): Builder => $q->where('table_ou_chambre_id', $id),
            )
            ->when(
                $request->filtre('depuis'),
                fn (Builder $q, string $date): Builder => $q->whereDate('date_commande', '>=', $date),
            )
            ->when(
                $request->filtre('jusqu_a'),
                fn (Builder $q, string $date): Builder => $q->whereDate('date_commande', '<=', $date),
            )
            // La plus récente en tête : c'est la commande en cours qui
            // intéresse la salle, pas la première de l'année.
            ->orderByDesc('date_commande')
            // Départage STABLE : plusieurs commandes peuvent porter le même
            // horodatage à la seconde près lors d'un rush.
            ->orderBy('id');

        return CommandeRestaurantResource::collection($requete->paginate($request->parPage()));
    }

    /**
     * Le BON DE CUISINE — EF-M4-05.
     */
    public function show(CommandeRestaurant $commande): BonCuisineResource
    {
        return $this->bon($commande);
    }

    /**
     * Prise de commande — EF-M4-03.
     *
     * **Aucun stock n'est engagé ici** : un serveur qui compose une commande
     * peut encore la modifier ou l'annuler sans que la cuisine ait rien entamé.
     * RG-05 s'applique à la transmission, pas à la saisie.
     */
    public function store(CreerCommandeRestaurantRequest $request): JsonResponse
    {
        $valide = $request->validated();

        $commande = $this->commandes->creer(
            lignes: $request->lignes(),
            clientId: isset($valide['client_id']) ? (string) $valide['client_id'] : null,
            tableOuChambreId: isset($valide['table_ou_chambre_id'])
                ? (string) $valide['table_ou_chambre_id']
                : null,
        );

        return $this->bon($commande)->response()->setStatusCode(201);
    }

    /**
     * Transmission en cuisine — EF-M4-05, et c'est ICI que RG-05 s'applique.
     *
     * La déduction de stock et le changement de statut sont dans la même
     * transaction : si un ingrédient manque, la commande n'est pas transmise et
     * reste modifiable. Le contraire — une commande transmise dont le stock n'a
     * pas suivi — laisserait la cuisine avec un bon qu'elle ne peut pas
     * honorer.
     */
    public function transmettre(
        TransmettreCommandeRequest $request,
        CommandeRestaurant $commande,
    ): BonCuisineResource|JsonResponse {
        try {
            $commande = $this->commandes->transmettreEnCuisine($commande, $request->validationRupture());
        } catch (RuptureStockException $e) {
            // 422 avec le drapeau attendu par le client, jamais un 500 : le
            // responsable doit pouvoir assumer la rupture en un geste (RG-06).
            return response()->json($e->versReponse(), 422);
        } catch (RecetteManquanteException $e) {
            // Pas de drapeau de confirmation : une fiche technique vide ne
            // s'assume pas, elle se corrige.
            return response()->json([
                'message' => $e->getMessage(),
                'plat' => $e->plat,
            ], 422);
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return $this->bon($commande);
    }

    /**
     * Commande servie — la salle constate, le stock a déjà bougé.
     */
    public function servir(CommandeRestaurant $commande): BonCuisineResource|JsonResponse
    {
        try {
            $commande = $this->commandes->marquerServie($commande);
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return $this->bon($commande);
    }

    /**
     * Annulation — possible uniquement AVANT transmission.
     *
     * Après transmission, les denrées sont engagées : l'annulation devient une
     * perte de stock à constater, pas un changement de statut. Ce refus est le
     * livrable — l'autoriser ferait disparaître de la comptabilité matière des
     * ingrédients réellement sortis.
     */
    public function annuler(CommandeRestaurant $commande): BonCuisineResource|JsonResponse
    {
        try {
            $commande = $this->commandes->annuler($commande);
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return $this->bon($commande);
    }

    /**
     * Compose le bon de cuisine : la commande, ses lignes, et le nombre
     * d'ingrédients de chaque recette — en UNE requête d'agrégation plutôt
     * qu'une par ligne.
     */
    private function bon(CommandeRestaurant $commande): BonCuisineResource
    {
        $commande->load(['client:id,nom,prenom', 'lignes.plat']);

        $recetteIds = $commande->lignes
            ->map(fn ($ligne): ?string => $ligne->plat?->recette_id)
            ->filter()
            ->unique()
            ->values()
            ->all();

        /** @var array<string, int> $ingredients */
        $ingredients = $recetteIds === []
            ? []
            : DB::table('ingredients_recette')
                ->whereIn('recette_id', $recetteIds)
                ->groupBy('recette_id')
                ->pluck(DB::raw('COUNT(*) AS nb'), 'recette_id')
                ->map(fn (mixed $nb): int => (int) $nb)
                ->all();

        return new BonCuisineResource($commande, $ingredients);
    }
}
