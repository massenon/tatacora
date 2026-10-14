<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Controllers;

use App\Domain\Restaurant\Http\Requests\EnregistrerMenuRequest;
use App\Domain\Restaurant\Http\Requests\EnregistrerPlatRequest;
use App\Domain\Restaurant\Http\Requests\FiltrerCarteRequest;
use App\Domain\Restaurant\Http\Requests\FiltrerMenusRequest;
use App\Domain\Restaurant\Http\Requests\FiltrerPlatsRequest;
use App\Domain\Restaurant\Http\Resources\CarteRestaurantResource;
use App\Domain\Restaurant\Http\Resources\LignePlatCarteResource;
use App\Domain\Restaurant\Http\Resources\MenuResource;
use App\Domain\Restaurant\Http\Resources\PlatResource;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\CarteRestaurantService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * API de la carte du restaurant — M4, EF-M4-01 et EF-M4-06.
 *
 * Sert `prototype_v2/pages/m4-restaurant-carte.html` (l'entrée « Restaurant »
 * de la barre latérale, `shell.js` l.68) et le catalogue de plats de
 * `m4-restauration.html`.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M4-06 Événements culinaires et menus spéciaux
 *
 * ## `m4-restaurant.html` n'est PAS porté, et le maître le dit lui-même
 *
 * Cette page porte en tête son propre bandeau : « **Écran remplacé.** Cette
 * page reste consultable comme maquette validée par le client, mais elle n'est
 * plus au menu : la version fonctionnelle est Carte du restaurant »
 * (`m4-restaurant.html` l.20-25). Même cas que `m3-crm.html`, écarté pour la
 * même raison en PA-126. Sa configuration est d'ailleurs identique, à la ligne
 * près, à celle de `m4-restauration.html`.
 *
 * ## Simple orchestrateur (`06_DEVELOPMENT_STANDARDS.md` §2.2)
 *
 * Aucune règle de gestion ici. Le calcul des portions vendables et de la
 * couverture vit dans `CarteRestaurantService` ; le coût matière dans
 * `CompositionRecetteService`.
 *
 * ## Aucune suppression n'est exposée
 *
 * `DELETE` n'est routé nulle part : un plat est référencé par des lignes de
 * commande et sa clé étrangère est en `restrictOnDelete()`. Le supprimer
 * rendrait illisible l'historique des ventes juste au moment où l'on en aurait
 * besoin. `PlatPolicy::delete()` et `MenuPolicy::delete()` le refusent en
 * second niveau.
 *
 * **Conséquence assumée et signalée** : aucune colonne ne porte la
 * disponibilité du jour. Un plat momentanément indisponible ne peut donc être
 * ni retiré de la carte ni supprimé — il y restera. L'arbitrage (ajouter la
 * colonne, qui manque symétriquement sur `cartes_boisson` en M5) appartient à
 * l'Architecte ; le contourner par une suppression physique casserait
 * l'historique.
 */
class CarteRestaurantController
{
    public function __construct(
        private readonly CarteRestaurantService $carte,
        private readonly CartePlatMenuService $ecritures,
    ) {
    }

    /**
     * L'écran « Carte du restaurant » entier — indicateurs, lignes, couverture.
     *
     * Ce que le client en fait : il remplit la bande de six cartes, les deux
     * onglets (« Carte du jour » et « Couverture du stock ») et les trois
     * filtres, sans recalculer quoi que ce soit. Le stock arrive **déjà
     * calculé** et ne se soumet jamais — c'est le premier des trois défauts que
     * `carte-module.js` corrige lui-même dans le prototype.
     */
    public function carte(FiltrerCarteRequest $request): CarteRestaurantResource
    {
        return new CarteRestaurantResource(
            $this->carte->carte(
                recherche: $request->filtre('recherche'),
                categorie: $request->filtre('categorie'),
                etat: $request->filtre('etat'),
            ),
        );
    }

    /**
     * Catalogue des plats — le tableau de `m4-restauration.html`, et la source
     * du sélecteur de plats du point de vente et du rayon « Restauration » de
     * la fiche de réservation (`reservations-services.js` l.50).
     *
     * Paginé, contrairement à `/carte` : c'est une liste qu'on parcourt et
     * qu'on recherche, et **aucun total n'est rendu au-dessus d'une page**.
     */
    public function plats(FiltrerPlatsRequest $request): AnonymousResourceCollection
    {
        $requete = Plat::query()
            ->with(['menu', 'recette'])
            ->when(
                $request->filtre('recherche'),
                fn (Builder $q, string $terme): Builder => $q->where('plats.libelle', 'like', '%' . $terme . '%'),
            )
            ->when(
                $request->filtre('categorie'),
                fn (Builder $q, string $type): Builder => $q->whereHas(
                    'menu',
                    fn (Builder $m): Builder => $m->where('type', $type),
                ),
            )
            ->when(
                $request->filtre('menu_id'),
                fn (Builder $q, string $menuId): Builder => $q->where('plats.menu_id', $menuId),
            )
            ->orderBy('plats.libelle')
            // Départage STABLE : deux plats homonymes se partageraient sinon un
            // rang indéterminé, et MySQL serait libre de rendre le même en
            // page 1 et en page 2 — ou aucun des deux.
            ->orderBy('plats.id');

        return PlatResource::collection($requete->paginate($request->parPage()));
    }

    /**
     * Fiche détail d'un plat — sa couverture de stock et son coût matière
     * compris, calculés par le même service que la carte.
     */
    public function plat(Plat $plat): LignePlatCarteResource
    {
        return new LignePlatCarteResource($this->carte->ligne($plat));
    }

    public function creerPlat(EnregistrerPlatRequest $request): JsonResponse
    {
        $plat = $this->ecritures->creerPlat($request->validated());

        return (new PlatResource($plat->load(['menu', 'recette'])))
            ->response()
            ->setStatusCode(201);
    }

    public function modifierPlat(EnregistrerPlatRequest $request, Plat $plat): PlatResource
    {
        return new PlatResource(
            $this->ecritures->modifierPlat($plat, $request->validated())->load(['menu', 'recette']),
        );
    }

    /**
     * Référentiel des menus — EF-M4-01, EF-M4-06.
     *
     * C'est la source du sélecteur « Menu » du formulaire de plat.
     * `plats.menu_id` étant NOT NULL, sans cette liste aucun plat ne pourrait
     * être créé : la même racine que PA-128, une donnée absente de l'API est
     * une donnée absente du client.
     */
    public function menus(FiltrerMenusRequest $request): AnonymousResourceCollection
    {
        $requete = Menu::query()
            ->when(
                $request->filtre('type'),
                fn (Builder $q, string $type): Builder => $q->where('type', $type),
            )
            ->when(
                $request->filtre('recherche'),
                fn (Builder $q, string $terme): Builder => $q->where('libelle', 'like', '%' . $terme . '%'),
            )
            ->orderBy('libelle')
            ->orderBy('id');

        return MenuResource::collection($requete->paginate($request->parPage()));
    }

    public function creerMenu(EnregistrerMenuRequest $request): JsonResponse
    {
        $menu = $this->ecritures->creerMenu($request->validated());

        return (new MenuResource($menu))->response()->setStatusCode(201);
    }

    public function modifierMenu(EnregistrerMenuRequest $request, Menu $menu): MenuResource
    {
        return new MenuResource(
            $this->ecritures->modifierMenu($menu, $request->validated()),
        );
    }
}
