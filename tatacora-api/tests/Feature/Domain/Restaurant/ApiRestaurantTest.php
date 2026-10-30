<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Restaurant;

use App\Domain\Restaurant\Models\CommandeRestaurant;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Policies\CommandeRestaurantPolicy;
use App\Domain\Restaurant\Policies\MenuPolicy;
use App\Domain\Restaurant\Policies\PlatPolicy;
use App\Domain\Restaurant\Policies\RecettePolicy;
use App\Domain\Restaurant\ReadModels\LignePlatCarte;
use App\Domain\Restaurant\Services\CarteRestaurantService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Route as RouteFacade;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * API M4 — Restaurant & Cuisine. Routes consommées par
 * `m4-restaurant-carte.html` (l'entrée « Restaurant » du menu) et
 * `m4-restauration.html` (le catalogue de plats).
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M4-02 Fiches techniques de recette
 * @see EF-M4-03 Prise de commande par table ou par chambre
 * @see EF-M4-05 Transmission à la cuisine (bon de cuisine)
 * @see RG-05 Sortie de stock automatique
 * @see RG-06 Blocage contrôlé sur rupture
 * @see RG-16 RBAC de 2e niveau
 *
 * ## Ce que cette suite existe pour empêcher
 *
 * 1. **Que le textarea « Ingrédients principaux » revienne** (PA-23). Le
 *    prototype porte la composition d'un plat en texte libre ; l'accepter
 *    ferait un plat qui ne décrémente aucun stock, et l'écart n'apparaîtrait
 *    qu'à l'inventaire, imputé à tort à une perte physique.
 * 2. **Qu'un stock calculé redevienne un champ saisi.** Les portions vendables
 *    et le coût matière se calculent ; les soumettre est refusé, jamais ignoré.
 * 3. **Qu'un chiffre inconnu se rende en `0`.** Un coût matière dont un
 *    ingrédient n'a jamais été réceptionné, ou des portions qu'aucun point de
 *    cuisine ne permet de compter, rendent `null` avec leur motif — jamais un
 *    zéro plausible (PA-126, Article 7 de la directive de conformité).
 * 4. **Qu'une route d'écriture perde sa garde RBAC** (PA-65). Les rôles sont
 *    dérivés de `RolePermissionSeeder::MATRICE`, jamais écrits en dur.
 * 5. **Qu'un filtre que le schéma ne sait pas calculer soit silencieusement
 *    ignoré** (PA-119) : la carte entière s'afficherait alors sous un intitulé
 *    qui promet le contraire.
 */
final class ApiRestaurantTest extends TestCase
{
    use RefreshDatabase;

    private PointStockage $cuisine;

    private Article $riz;

    private Article $poulet;

    /** Jamais réceptionné : son coût moyen pondéré vaut zéro, ce qui n'est pas un prix. */
    private Article $plantain;

    private Menu $carte;

    private Recette $recettePouletDg;

    private Plat $pouletDg;

    /** Plat dont la fiche technique est VIDE : il ne décrémente rien. */
    private Plat $saladeSansRecette;

    private StockTheoriqueService $stocks;

    /** Mémoïsé : les fixtures en ont besoin avant que le test ne s'authentifie. */
    private ?User $cuisinier = null;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->stocks = app(StockTheoriqueService::class);
        $this->actingAs($this->cuisinier());

        $this->cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);

        $this->riz = $this->article('Riz parfumé', 'kg', '5.00', '1200.0000');
        $this->poulet = $this->article('Poulet fermier', 'kg', '2.00', '2500.0000');
        $this->plantain = $this->article('Plantain mûr', 'régime', '3.00', '0.0000');

        $this->carte = Menu::create(['libelle' => 'Carte principale', 'type' => 'local']);

        // 0,250 kg de riz + 0,400 kg de poulet par portion.
        $this->recettePouletDg = Recette::create(['libelle' => 'Poulet DG', 'cout_matiere_calcule' => '0.00']);
        $this->recettePouletDg->ingredients()->attach([
            $this->riz->id => ['quantite_unitaire' => '0.250'],
            $this->poulet->id => ['quantite_unitaire' => '0.400'],
        ]);

        $this->pouletDg = Plat::create([
            'menu_id' => $this->carte->id,
            'recette_id' => $this->recettePouletDg->id,
            'libelle' => 'Poulet DG',
            'prix_vente' => '4500.00',
        ]);

        $this->saladeSansRecette = Plat::create([
            'menu_id' => Menu::create(['libelle' => 'Carte européenne', 'type' => 'europeen'])->id,
            'recette_id' => Recette::create(['libelle' => 'Salade César', 'cout_matiere_calcule' => '0.00'])->id,
            'libelle' => 'Salade César',
            'prix_vente' => '4000.00',
        ]);

        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($this->riz->id, $this->cuisine->id, '10.00', 'Réception');
        $mouvements->entree($this->poulet->id, $this->cuisine->id, '4.00', 'Réception');
    }

    // ------------------------------------------------------- Authentification

    /**
     * Aucune des dix-huit routes n'est publique. La liste est explicite : une
     * route ajoutée au groupe sans jeton passerait sinon inaperçue.
     */
    #[Test]
    public function aucune_route_de_restaurant_n_est_accessible_sans_jeton(): void
    {
        $commande = $this->commande();
        $plat = $this->pouletDg->id;
        $recette = $this->recettePouletDg->id;

        // Les fixtures ont eu besoin d'un utilisateur authentifie — un
        // mouvement de stock porte obligatoirement son auteur. Sans cette
        // ligne, ce test partirait AUTHENTIFIE et verifierait donc l'inverse
        // exact de ce qu'il annonce : il resterait vert quel que soit l'etat
        // des gardes. Constate a la premiere execution.
        $this->app['auth']->forgetGuards();

        $this->getJson('/api/v1/restaurant/carte')->assertUnauthorized();
        $this->getJson('/api/v1/restaurant/plats')->assertUnauthorized();
        $this->postJson('/api/v1/restaurant/plats', [])->assertUnauthorized();
        $this->getJson("/api/v1/restaurant/plats/{$plat}")->assertUnauthorized();
        $this->putJson("/api/v1/restaurant/plats/{$plat}", [])->assertUnauthorized();
        $this->getJson('/api/v1/restaurant/menus')->assertUnauthorized();
        $this->postJson('/api/v1/restaurant/menus', [])->assertUnauthorized();
        $this->putJson("/api/v1/restaurant/menus/{$this->carte->id}", [])->assertUnauthorized();
        $this->getJson('/api/v1/restaurant/recettes')->assertUnauthorized();
        $this->postJson('/api/v1/restaurant/recettes', [])->assertUnauthorized();
        $this->getJson("/api/v1/restaurant/recettes/{$recette}")->assertUnauthorized();
        $this->putJson("/api/v1/restaurant/recettes/{$recette}/composition", [])->assertUnauthorized();
        $this->getJson('/api/v1/restaurant/commandes')->assertUnauthorized();
        $this->postJson('/api/v1/restaurant/commandes', [])->assertUnauthorized();
        $this->getJson("/api/v1/restaurant/commandes/{$commande->id}")->assertUnauthorized();
        $this->patchJson("/api/v1/restaurant/commandes/{$commande->id}/transmission")->assertUnauthorized();
        $this->patchJson("/api/v1/restaurant/commandes/{$commande->id}/service")->assertUnauthorized();
        $this->patchJson("/api/v1/restaurant/commandes/{$commande->id}/annulation")->assertUnauthorized();
    }

    // ------------------------------------------------------------------ RBAC

    /**
     * RG-16 — un rôle sans aucun accès à M4 est refusé, en lecture comme en
     * écriture. Le rôle est DÉRIVÉ de la matrice : l'écrire en dur ferait
     * passer la suite au vert le jour où la matrice changerait.
     */
    #[Test]
    public function rg16_un_role_sans_acces_a_m4_est_refuse_partout(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM4('-')));

        $this->getJson('/api/v1/restaurant/carte')->assertForbidden();
        $this->getJson('/api/v1/restaurant/plats')->assertForbidden();
        $this->getJson('/api/v1/restaurant/menus')->assertForbidden();
        $this->getJson('/api/v1/restaurant/recettes')->assertForbidden();
        $this->getJson('/api/v1/restaurant/commandes')->assertForbidden();
        $this->postJson('/api/v1/restaurant/plats', $this->platValide())->assertForbidden();
        $this->postJson('/api/v1/restaurant/menus', $this->menuValide())->assertForbidden();
        $this->postJson('/api/v1/restaurant/recettes', ['libelle' => 'Sauce arachide'])->assertForbidden();
        $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide())->assertForbidden();
        $this->patchJson("/api/v1/restaurant/commandes/{$commande->id}/transmission")->assertForbidden();

        $this->assertSame(2, Plat::count());
        $this->assertSame(1, CommandeRestaurant::count());
        // Le refus a bien empêché la déduction : le stock n'a pas bougé.
        $this->assertSame('10.00', $this->stockRiz());
    }

    /**
     * RG-16 — un rôle en LECTURE seule consulte tout et n'écrit rien.
     */
    #[Test]
    public function rg16_un_role_en_lecture_seule_consulte_mais_n_ecrit_pas(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM4('L')));

        $this->getJson('/api/v1/restaurant/carte')->assertOk();
        $this->getJson('/api/v1/restaurant/plats')->assertOk();
        $this->getJson("/api/v1/restaurant/plats/{$this->pouletDg->id}")->assertOk();
        $this->getJson('/api/v1/restaurant/menus')->assertOk();
        $this->getJson('/api/v1/restaurant/recettes')->assertOk();
        $this->getJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}")->assertOk();
        $this->getJson('/api/v1/restaurant/commandes')->assertOk();
        $this->getJson("/api/v1/restaurant/commandes/{$commande->id}")->assertOk();

        $this->postJson('/api/v1/restaurant/plats', $this->platValide())->assertForbidden();
        $this->putJson("/api/v1/restaurant/plats/{$this->pouletDg->id}", $this->platValide())->assertForbidden();
        $this->postJson('/api/v1/restaurant/menus', $this->menuValide())->assertForbidden();
        $this->putJson("/api/v1/restaurant/menus/{$this->carte->id}", $this->menuValide())->assertForbidden();
        $this->postJson('/api/v1/restaurant/recettes', ['libelle' => 'Sauce'])->assertForbidden();
        $this->putJson(
            "/api/v1/restaurant/recettes/{$this->recettePouletDg->id}/composition",
            ['lignes' => []],
        )->assertForbidden();
        $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide())->assertForbidden();
        $this->patchJson("/api/v1/restaurant/commandes/{$commande->id}/transmission")->assertForbidden();
        $this->patchJson("/api/v1/restaurant/commandes/{$commande->id}/annulation")->assertForbidden();

        $this->assertSame(2, Plat::count());
        $this->assertSame('en_preparation', $commande->refresh()->statut);
        // La composition n'a pas été vidée par le refus.
        $this->assertSame(2, DB::table('ingredients_recette')
            ->where('recette_id', $this->recettePouletDg->id)->count());
    }

    /**
     * Le refus RBAC est traduit, jamais écrit en dur dans le middleware.
     */
    #[Test]
    public function rg16_le_refus_est_un_message_traduit(): void
    {
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM4('-')));

        $this->getJson('/api/v1/restaurant/carte')
            ->assertForbidden()
            ->assertJsonPath('message', __('auth.module_refuse'));
    }

    /**
     * Garde STRUCTURELLE à liste fermée — chaque route du groupe `restaurant`
     * déclare le niveau RBAC qu'elle exige, et la suite échoue tant qu'une
     * route nouvelle n'y est pas inscrite.
     *
     * ## Pourquoi un test de structure en plus des tests de comportement
     *
     * Retirer `module:M4,C` de `POST /restaurant/plats` ne fait rougir aucun
     * test de comportement : le `FormRequest` refuse aussi, en 3ᵉ niveau, et le
     * 403 reste un 403. La garde disparue serait donc invisible — jusqu'au jour
     * où quelqu'un ajouterait une route d'écriture sans `FormRequest`, et où
     * plus rien ne la tiendrait. C'est exactement la forme de PA-65, et les
     * trois routes PATCH de ce groupe n'ont justement PAS toutes de
     * `FormRequest`.
     */
    #[Test]
    public function rg16_chaque_route_du_groupe_restaurant_porte_sa_garde_rbac(): void
    {
        $attendu = [
            'GET|HEAD api/v1/restaurant/carte' => 'M4,L',
            'GET|HEAD api/v1/restaurant/plats' => 'M4,L',
            'POST api/v1/restaurant/plats' => 'M4,C',
            'GET|HEAD api/v1/restaurant/plats/{plat}' => 'M4,L',
            'PUT api/v1/restaurant/plats/{plat}' => 'M4,C',
            'GET|HEAD api/v1/restaurant/menus' => 'M4,L',
            'POST api/v1/restaurant/menus' => 'M4,C',
            'PUT api/v1/restaurant/menus/{menu}' => 'M4,C',
            'GET|HEAD api/v1/restaurant/recettes' => 'M4,L',
            'POST api/v1/restaurant/recettes' => 'M4,C',
            'GET|HEAD api/v1/restaurant/recettes/{recette}' => 'M4,L',
            'PUT api/v1/restaurant/recettes/{recette}/composition' => 'M4,C',
            'GET|HEAD api/v1/restaurant/commandes' => 'M4,L',
            'POST api/v1/restaurant/commandes' => 'M4,C',
            'GET|HEAD api/v1/restaurant/commandes/{commande}' => 'M4,L',
            'PATCH api/v1/restaurant/commandes/{commande}/transmission' => 'M4,C',
            'PATCH api/v1/restaurant/commandes/{commande}/service' => 'M4,C',
            'PATCH api/v1/restaurant/commandes/{commande}/annulation' => 'M4,C',
        ];

        $constate = [];

        foreach (RouteFacade::getRoutes()->getRoutes() as $route) {
            if (! str_starts_with($route->uri(), 'api/v1/restaurant/')) {
                continue;
            }

            $middlewares = $route->gatherMiddleware();

            $gardes = array_values(array_filter(
                $middlewares,
                fn (mixed $m): bool => is_string($m) && str_starts_with($m, 'module:'),
            ));

            $cle = implode('|', array_diff($route->methods(), ['HEAD'])) . ' ' . $route->uri();
            $cle = str_contains($cle, 'GET ') ? str_replace('GET ', 'GET|HEAD ', $cle) : $cle;

            $constate[$cle] = $gardes === []
                ? 'AUCUNE GARDE'
                : str_replace('module:', '', $gardes[0]);

            $this->assertContains(
                'auth:sanctum',
                $middlewares,
                "La route {$cle} est accessible sans authentification.",
            );
        }

        ksort($attendu);
        ksort($constate);

        $this->assertSame(
            $attendu,
            $constate,
            'Une route du groupe `restaurant` a perdu sa garde RBAC, ou une route nouvelle n\'est pas inscrite ici.',
        );
    }

    /**
     * Aucune suppression n'est exposée. Le verbe non routé (405) est la seule
     * preuve solide qu'elle n'existe pas ; les Policy la refusent en second
     * niveau.
     */
    #[Test]
    public function aucune_suppression_n_est_exposee(): void
    {
        $commande = $this->commande();
        $administrateur = $this->utilisateur($this->roleAvecNiveauM4('C'));
        Sanctum::actingAs($administrateur);

        $this->deleteJson("/api/v1/restaurant/plats/{$this->pouletDg->id}")->assertMethodNotAllowed();
        $this->deleteJson("/api/v1/restaurant/menus/{$this->carte->id}")->assertMethodNotAllowed();
        $this->deleteJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}")->assertMethodNotAllowed();
        $this->deleteJson("/api/v1/restaurant/commandes/{$commande->id}")->assertMethodNotAllowed();

        $this->assertFalse((new PlatPolicy())->delete($administrateur));
        $this->assertFalse((new MenuPolicy())->delete($administrateur));
        $this->assertFalse((new RecettePolicy())->delete($administrateur));
        $this->assertFalse((new CommandeRestaurantPolicy())->delete($administrateur));
    }

    // ------------------------------------------------- EF-M4-01 Carte et plats

    /**
     * La catégorie affichée par le maître vient de `menus.type` : le schéma la
     * porte sur le menu, jamais sur le plat.
     */
    #[Test]
    public function ef_m4_01_la_categorie_d_un_plat_vient_de_son_menu(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $ligne = $this->lignePouletDg();

        $this->assertSame('local', $ligne['categorie']);
        $this->assertSame('Poulet DG', $ligne['libelle']);
        $this->assertSame('4500.00', $ligne['prix_vente']);
    }

    /**
     * Le stock vendable est CALCULÉ, jamais saisi — la mention que le maître
     * porte lui-même en sous-titre de sa page. Le minimum sur les ingrédients
     * commande, et l'ingrédient limitant est nommé : « 10 portions » sans dire
     * ce qui manque n'indique pas quoi racheter.
     */
    #[Test]
    public function ef_m4_02_les_portions_vendables_sont_bornees_par_l_ingredient_limitant(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $ligne = $this->lignePouletDg();

        // Riz : 10 / 0,250 = 40 portions. Poulet : 4 / 0,400 = 10 portions.
        $this->assertSame(10, $ligne['portions_vendables']);
        $this->assertSame($this->poulet->id, $ligne['ingredient_limitant']['id']);
        $this->assertSame('Poulet fermier', $ligne['ingredient_limitant']['libelle']);
        $this->assertFalse($ligne['rupture']);
        $this->assertTrue($ligne['lie_au_stock']);
        $this->assertSame(2, $ligne['nb_ingredients']);
    }

    /**
     * Le stock est lu AU POINT CUISINE, jamais tous points confondus : compter
     * sur le stock consolidé annoncerait des assiettes que la cuisine ne peut
     * pas produire, la marchandise étant au magasin.
     */
    #[Test]
    public function ef_m4_02_le_stock_d_un_autre_point_ne_compte_pas_dans_les_portions(): void
    {
        $magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        app(MouvementStockService::class)->entree($this->poulet->id, $magasin->id, '100.00', 'Réception');

        Sanctum::actingAs($this->cuisinier());

        // 100 kg de poulet sont arrivés — au magasin. La cuisine en a toujours 4.
        $this->assertSame(10, $this->lignePouletDg()['portions_vendables']);
    }

    /**
     * Une fiche technique vide ne rend pas « 0 portion » : elle rend `null`
     * avec son motif. `0` se lirait comme « il n'en reste plus », alors que
     * personne n'a rien compté (Article 7 de la directive de conformité).
     */
    #[Test]
    public function ef_m4_02_un_plat_sans_ingredient_ne_rend_aucun_chiffre_et_dit_pourquoi(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $ligne = $this->ligneCarte($this->saladeSansRecette->id);

        $this->assertNull($ligne['portions_vendables']);
        $this->assertFalse($ligne['lie_au_stock']);
        $this->assertFalse($ligne['rupture']);
        $this->assertSame(LignePlatCarte::MOTIF_RECETTE_VIDE, $ligne['motif_sans_stock']);
    }

    /**
     * Sans point de stockage de cuisine, on ne sait pas d'où sortiraient les
     * denrées : aucun chiffre, et le motif le dit. `point_cuisine_id` à `null`
     * permet au client de l'annoncer plutôt que d'afficher une carte qui
     * passerait pour une carte en rupture.
     */
    #[Test]
    public function ef_m4_02_sans_point_de_cuisine_aucune_portion_n_est_annoncee(): void
    {
        MouvementStock::query()->delete();
        $this->cuisine->delete();

        Sanctum::actingAs($this->cuisinier());

        $reponse = $this->getJson('/api/v1/restaurant/carte')->assertOk();

        $this->assertNull($reponse->json('data.point_cuisine_id'));
        $ligne = $this->ligneDe($reponse->json('data.lignes'), $this->pouletDg->id);
        $this->assertNull($ligne['portions_vendables']);
        $this->assertSame(LignePlatCarte::MOTIF_POINT_CUISINE_ABSENT, $ligne['motif_sans_stock']);
        // La recette est bien renseignée : le motif ne doit pas se confondre
        // avec celui d'une fiche vide.
        $this->assertTrue($ligne['lie_au_stock']);
    }

    /**
     * Un stock épuisé rend bien `0`, et `rupture` à vrai. C'est le pendant du
     * test précédent : « — » et « 0 » ne disent pas la même chose, et il faut
     * que les DEUX soient produits au bon moment.
     */
    #[Test]
    public function ef_m4_02_un_ingredient_epuise_rend_zero_portion_et_non_un_tiret(): void
    {
        app(MouvementStockService::class)->sortie(
            $this->poulet->id,
            $this->cuisine->id,
            '4.00',
            'Consommation interne',
        );

        Sanctum::actingAs($this->cuisinier());

        $ligne = $this->lignePouletDg();

        $this->assertSame(0, $ligne['portions_vendables']);
        $this->assertTrue($ligne['rupture']);
        $this->assertNull($ligne['motif_sans_stock']);
    }

    /**
     * Les indicateurs portent sur la carte ENTIÈRE, les lignes sur le filtre.
     * Filtrer les compteurs ferait tomber « ne décrémentent rien » à zéro dès
     * qu'on filtre sur « liés au stock » — c'est-à-dire précisément quand on
     * cherche à mesurer le trou.
     */
    #[Test]
    public function ef_m4_01_les_indicateurs_ne_suivent_pas_le_filtre_des_lignes(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $reponse = $this->getJson('/api/v1/restaurant/carte?etat=lie')->assertOk();

        // Une seule ligne affichée…
        $this->assertCount(1, $reponse->json('data.lignes'));
        // …mais les compteurs continuent de décrire les deux plats.
        $reponse->assertJsonPath('data.indicateurs.plats', 2);
        $reponse->assertJsonPath('data.indicateurs.lies', 1);
        $reponse->assertJsonPath('data.indicateurs.sans_lien', 1);
        $reponse->assertJsonPath('data.indicateurs.taux_couverture', '50.0');
        // Et l'état DIT son filtre (PA-119).
        $reponse->assertJsonPath('data.filtres_appliques.etat', 'lie');
    }

    /**
     * Le filtre du maître qu'aucune colonne ne sait calculer est REFUSÉ avec sa
     * raison, jamais ignoré. L'ignorer rendrait la carte entière sous un
     * intitulé qui promet le contraire (PA-119), et le serveur retirerait de la
     * vente un plat qui n'a jamais été retiré.
     *
     * ## Pourquoi `provisoire` a quitté ce cas — la CAUSE, écrite
     *
     * Il y figurait au même motif : « aucune colonne au schéma ». Ce motif est
     * FAUX depuis la migration `2026_09_02_200000` (PA-161 (b)), qui pose
     * `plats.prix_provisoire`. Le test épinglait donc un refus dont la raison
     * avait cessé d'exister, et il l'aurait maintenu indéfiniment — c'est la
     * forme la plus discrète de PA-144 : un test vert qui garde un oubli.
     * L'attente n'a pas été « corrigée » pour redevenir verte, elle a été
     * DÉPLACÉE vers le cas qui prouve le filtre réel
     * ({@see self::ef_m4_01_le_filtre_prix_provisoire_porte_sur_la_vraie_colonne()}).
     */
    #[Test]
    public function ef_m4_01_un_filtre_sans_colonne_est_refuse_avec_sa_raison(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->getJson('/api/v1/restaurant/carte?etat=indisponible')
            ->assertStatus(422)
            ->assertJsonPath('errors.etat.0', __('restaurant.validation.etat_sans_schema'));

        // Un état simplement inconnu reçoit l'autre message : envoyer chercher
        // une faute de frappe là où la cause est l'absence de colonne, ou
        // l'inverse, fait perdre le vrai motif.
        $this->getJson('/api/v1/restaurant/carte?etat=nimportequoi')
            ->assertStatus(422)
            ->assertJsonPath('errors.etat.0', __('restaurant.validation.etat_inconnu'));
    }

    /**
     * Les indicateurs que l'API ne produit pas sont NOMMÉS avec leur raison,
     * jamais rendus à zéro. « Aucun plat retiré, aucun prix provisoire » sous
     * un écran qui n'a rien consulté est l'indicateur qui affirme un état qu'il
     * n'a pas vérifié (PA-59/60/61).
     */
    #[Test]
    public function ef_m4_01_les_indicateurs_non_calculables_sont_nommes_et_non_rendus_a_zero(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $reponse = $this->getJson('/api/v1/restaurant/carte')->assertOk();

        $indicateurs = $reponse->json('data.indicateurs');
        $this->assertArrayNotHasKey('indisponibles', $indicateurs);

        $reponse->assertJsonPath('data.indicateurs_absents.indisponibles', __('restaurant.absent.disponibilite'));

        // `prix_provisoires` n'est plus dans la liste des absents : il est
        // COMPTE. Le laisser des deux cotes ferait un ecran qui affiche a la
        // fois un chiffre et la raison pour laquelle il n'y en a pas.
        $this->assertArrayNotHasKey('prix_provisoires', $reponse->json('data.indicateurs_absents'));
        $this->assertArrayHasKey('prix_provisoires', $indicateurs);
    }

    /**
     * Le filtre « Prix provisoire » porte sur la VRAIE colonne, et l'indicateur
     * la compte.
     *
     * MUTATION PROUVEE (02/09/2026) : remettre `'provisoire'` dans
     * `CarteRestaurantService::ETATS_SANS_SCHEMA` fait rougir ce cas sur le
     * premier `assertOk()` (422). Remplacer le predicat du filtre par `true`
     * le fait rougir sur le nombre de lignes rendues (2 au lieu d'une). Les
     * deux moities mordent.
     */
    #[Test]
    public function ef_m4_01_le_filtre_prix_provisoire_porte_sur_la_vraie_colonne(): void
    {
        Sanctum::actingAs($this->cuisinier());

        // Un seul des deux plats du decor porte la marque.
        $this->saladeSansRecette->forceFill(['prix_provisoire' => true])->save();

        $reponse = $this->getJson('/api/v1/restaurant/carte?etat=provisoire')->assertOk();

        $lignes = $reponse->json('data.lignes');
        $this->assertCount(1, $lignes);
        $this->assertSame($this->saladeSansRecette->id, $lignes[0]['id']);
        $this->assertTrue($lignes[0]['prix_provisoire']);
        $this->assertFalse($lignes[0]['prix_corrige_main']);

        // L'indicateur porte sur la carte ENTIERE, pas sur le filtre : meme
        // convention que les autres compteurs de cette bande.
        $reponse->assertJsonPath('data.indicateurs.prix_provisoires', 1);
        // Et l'etat DIT son filtre (PA-119).
        $reponse->assertJsonPath('data.filtres_appliques.etat', 'provisoire');
    }

    /**
     * Les deux registres d'etat ne se recouvrent JAMAIS — et ce cas existe
     * parce qu'une mutation a failli ne pas mordre.
     *
     * En eprouvant le filtre ci-dessus, remettre `'provisoire'` dans
     * `ETATS_SANS_SCHEMA` a laisse la suite VERTE : `Rule::in(ETATS)` valide
     * seul, et `ETATS_SANS_SCHEMA` ne sert qu'a choisir le MESSAGE du refus.
     * Un etat present dans les deux serait donc accepte tout en portant, s'il
     * venait a etre refuse un jour, la raison « aucune colonne au schema » —
     * exactement le motif perime que ce lot corrige (PA-144).
     *
     * La mutation ne mordait pas : ce cas est la mesure qui manquait.
     */
    #[Test]
    public function les_deux_registres_d_etat_ne_se_recouvrent_pas(): void
    {
        $this->assertSame(
            [],
            array_values(array_intersect(
                CarteRestaurantService::ETATS,
                CarteRestaurantService::ETATS_SANS_SCHEMA,
            )),
            "Un etat ne peut pas etre a la fois calculable et sans colonne : "
            .'accepte par la validation, il porterait un motif de refus faux.',
        );

        // Et le balayage n'est pas vide : sans ce plancher, vider l'un des
        // deux registres rendrait ce cas vert pour toujours.
        $this->assertNotEmpty(CarteRestaurantService::ETATS);
        $this->assertNotEmpty(CarteRestaurantService::ETATS_SANS_SCHEMA);
    }

    /**
     * La couverture par catégorie de l'onglet « Couverture du stock » se
     * calcule sur le même parcours que les lignes : un total qui ne fait pas la
     * somme des lignes affichées juste en dessous est ce que cette route existe
     * pour rendre impossible (PA-121).
     */
    #[Test]
    public function ef_m4_01_la_couverture_par_categorie_somme_les_memes_lignes(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $couverture = $this->getJson('/api/v1/restaurant/carte')->assertOk()->json('data.couverture');

        $parCategorie = $this->indexerPar($couverture, 'categorie');

        $this->assertSame(1, $parCategorie['local']['plats']);
        $this->assertSame(1, $parCategorie['local']['lies']);
        $this->assertSame('100.0', $parCategorie['local']['taux']);
        $this->assertSame(1, $parCategorie['europeen']['plats']);
        $this->assertSame(0, $parCategorie['europeen']['lies']);
        $this->assertSame('0.0', $parCategorie['europeen']['taux']);
    }

    /**
     * Sur une carte VIDE, le taux de couverture rend « — » et non « 0 % ».
     *
     * ## Ce test existe parce que la branche n'était exécutée par personne
     *
     * `taux()` rend `null` quand le total est nul ; aucun des quarante-deux
     * tests précédents n'atteignait ce cas, tous partant d'une carte peuplée.
     * Une branche jamais exécutée est exactement ce que PA-59/60/61 décrivent :
     * du code qui affirme un comportement que rien n'a vérifié. Et l'écart
     * compte — « 0 % de couverture » sur une carte sans plat se lit comme un
     * défaut à corriger, alors qu'il n'y a rien à rattacher.
     */
    #[Test]
    public function ef_m4_01_une_carte_vide_rend_un_taux_inconnu_et_non_zero(): void
    {
        Plat::query()->delete();

        Sanctum::actingAs($this->cuisinier());

        $reponse = $this->getJson('/api/v1/restaurant/carte')->assertOk();

        $reponse->assertJsonPath('data.indicateurs.plats', 0);
        $reponse->assertJsonPath('data.indicateurs.taux_couverture', null);
        $this->assertSame([], $reponse->json('data.lignes'));
        $this->assertSame([], $reponse->json('data.couverture'));
    }

    /**
     * Le catalogue de plats est paginé et filtrable — la barre d'outils de
     * `m4-restauration.html`. C'est aussi la source du sélecteur de plats du
     * point de vente et du rayon « Restauration » de la fiche de réservation,
     * rendu vide faute de cette route (PA-110).
     */
    #[Test]
    public function ef_m4_01_le_catalogue_de_plats_est_filtrable_par_categorie(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->getJson('/api/v1/restaurant/plats')->assertOk()->assertJsonCount(2, 'data');

        $this->getJson('/api/v1/restaurant/plats?categorie=local')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.libelle', 'Poulet DG')
            ->assertJsonPath('data.0.categorie', 'local');

        $this->getJson('/api/v1/restaurant/plats?recherche=Salade')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.libelle', 'Salade César');
    }

    /**
     * `plats.menu_id` et `plats.recette_id` sont NOT NULL : un plat sans menu
     * n'aurait aucune catégorie, un plat sans fiche technique ne décrémenterait
     * rien. Les deux sont de VRAIES clés étrangères, jamais du texte libre.
     */
    #[Test]
    public function ef_m4_01_un_plat_exige_un_menu_et_une_recette_existants(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->postJson('/api/v1/restaurant/plats', ['libelle' => 'Amiwo', 'prix_vente' => '2000'])
            ->assertStatus(422)
            ->assertJsonPath('errors.menu_id.0', __('restaurant.validation.menu_obligatoire'))
            ->assertJsonPath('errors.recette_id.0', __('restaurant.validation.recette_obligatoire'));

        $this->postJson('/api/v1/restaurant/plats', [
            'libelle' => 'Amiwo',
            'prix_vente' => '2000',
            'menu_id' => (string) Str::uuid(),
            'recette_id' => $this->recettePouletDg->id,
        ])
            ->assertStatus(422)
            ->assertJsonPath('errors.menu_id.0', __('restaurant.validation.menu_inexistant'));

        $this->assertSame(2, Plat::count());
    }

    #[Test]
    public function ef_m4_01_un_plat_se_cree_et_se_modifie(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->postJson('/api/v1/restaurant/plats', $this->platValide())
            ->assertCreated()
            ->assertJsonPath('data.libelle', 'Amiwo sauce tomate')
            ->assertJsonPath('data.categorie', 'local');

        $plat = Plat::where('libelle', 'Amiwo sauce tomate')->firstOrFail();

        $this->putJson("/api/v1/restaurant/plats/{$plat->id}", [
            'libelle' => 'Amiwo sauce tomate',
            'menu_id' => $this->carte->id,
            'recette_id' => $this->recettePouletDg->id,
            'prix_vente' => '2200',
        ])->assertOk()->assertJsonPath('data.prix_vente', '2200.00');
    }

    /**
     * EF-M4-01 (mise à jour saisonnière) : une saison qui finit avant de
     * commencer ne rendrait jamais aucun plat, et la carte s'afficherait vide
     * sans dire pourquoi.
     */
    #[Test]
    public function ef_m4_01_une_saison_de_menu_ne_peut_pas_finir_avant_de_commencer(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->postJson('/api/v1/restaurant/menus', [
            'libelle' => 'Fête de l\'Igname',
            'type' => 'special',
            'date_debut' => '2026-09-15',
            'date_fin' => '2026-09-01',
        ])
            ->assertStatus(422)
            ->assertJsonPath('errors.date_fin.0', __('restaurant.validation.saison_inversee'));

        $this->postJson('/api/v1/restaurant/menus', [
            'libelle' => 'Fête de l\'Igname',
            'type' => 'special',
            'date_debut' => '2026-09-01',
            'date_fin' => '2026-09-15',
        ])->assertCreated()->assertJsonPath('data.type', 'special');
    }

    // ------------------------------------- Anti-patterns du prototype refusés

    /**
     * PA-23 — le textarea « Ingrédients principaux » du prototype n'entre
     * jamais dans l'API. Il est REFUSÉ et non ignoré : un champ ignoré laisse
     * le client croire qu'il a été enregistré, et le serveur découvrirait
     * l'absence de recette au comptoir, à la transmission en cuisine.
     */
    #[Test]
    public function pa23_les_ingredients_en_texte_libre_sont_refuses(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->postJson('/api/v1/restaurant/plats', $this->platValide() + [
            'ingredients_principaux' => 'Poulet, plantain mûr, poivron, tomate, oignon',
        ])
            ->assertStatus(422)
            ->assertJsonPath('errors.ingredients_principaux.0', __('restaurant.validation.ingredients_texte_libre'));

        $this->assertSame(2, Plat::count());
    }

    /**
     * Les trois autres champs du formulaire du maître que le schéma ne porte
     * pas ou qui se déduisent d'ailleurs.
     */
    #[Test]
    public function les_champs_sans_colonne_ou_calcules_sont_refuses_un_par_un(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->postJson('/api/v1/restaurant/plats', $this->platValide() + ['disponible' => 'Non'])
            ->assertStatus(422)
            ->assertJsonPath('errors.disponible.0', __('restaurant.validation.disponibilite_sans_schema'));

        $this->postJson('/api/v1/restaurant/plats', $this->platValide() + ['categorie' => 'Local'])
            ->assertStatus(422)
            ->assertJsonPath('errors.categorie.0', __('restaurant.validation.categorie_du_menu'));

        $this->postJson('/api/v1/restaurant/plats', $this->platValide() + ['portions_vendables' => 12])
            ->assertStatus(422)
            ->assertJsonPath('errors.portions_vendables.0', __('restaurant.validation.valeur_calculee'));

        $this->assertSame(2, Plat::count());
    }

    // ------------------------------------------- EF-M4-02 Fiches techniques

    /**
     * Le coût matière est CALCULÉ : quantité × coût moyen pondéré, ingrédient
     * par ingrédient. Il n'est jamais lu dans `recettes.cout_matiere_calcule`,
     * colonne que rien n'écrivait avant ce lot.
     */
    #[Test]
    public function ef_m4_02_le_cout_matiere_est_calcule_depuis_la_composition(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $reponse = $this->getJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}")->assertOk();

        // 0,250 × 1 200 = 300 ; 0,400 × 2 500 = 1 000 → 1 300,00
        $reponse->assertJsonPath('data.cout_matiere', '1300.00');
        $reponse->assertJsonPath('data.cout_matiere_incomplet', false);
        $reponse->assertJsonPath('data.composition_vide', false);
        $reponse->assertJsonPath('data.composition.0.cout_ligne', '300.00');

        // Et la marge suit, sur la carte.
        $this->assertSame('3200.00', $this->lignePouletDg()['marge']);
    }

    /**
     * Un ingrédient jamais réceptionné porte un coût moyen pondéré à zéro : il
     * n'est pas gratuit, il est NON VALORISÉ. Le coût matière rend donc `null`
     * et NOMME l'article fautif — un total sous-évalué se comparerait, et le
     * prix de vente serait fixé dessus (PA-126).
     */
    #[Test]
    public function ef_m4_02_un_ingredient_sans_cout_rend_le_cout_matiere_inconnu_et_non_zero(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->putJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}/composition", [
            'lignes' => [
                ['article_id' => $this->riz->id, 'quantite_unitaire' => '0.250'],
                ['article_id' => $this->plantain->id, 'quantite_unitaire' => '0.500'],
            ],
        ])
            ->assertOk()
            ->assertJsonPath('data.cout_matiere', null)
            ->assertJsonPath('data.cout_matiere_incomplet', true)
            ->assertJsonPath('data.articles_sans_cout', ['Plantain mûr'])
            // La ligne non valorisée le dit aussi, plutôt que d'afficher 0.
            ->assertJsonPath('data.composition.1.cout_unitaire', null);

        // Et la marge disparaît avec le coût : prix de vente moins coût inconnu
        // n'est pas une marge, c'est le prix de vente.
        $ligne = $this->lignePouletDg();
        $this->assertNull($ligne['cout_matiere']);
        $this->assertNull($ligne['marge']);
        $this->assertTrue($ligne['cout_matiere_incomplet']);
    }

    /**
     * PA-23 — le sous-formulaire de composition : de vraies clés étrangères
     * vers `articles`, avec leurs quantités. Le remplacement est INTÉGRAL :
     * un ingrédient retiré du formulaire disparaît réellement, sans quoi le
     * plat continuerait de décrémenter un article que sa fiche ne mentionne
     * plus.
     */
    #[Test]
    public function ef_m4_02_la_composition_est_remplacee_en_entier_jamais_fusionnee(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->putJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}/composition", [
            'lignes' => [['article_id' => $this->riz->id, 'quantite_unitaire' => '0.300']],
        ])->assertOk()->assertJsonCount(1, 'data.composition');

        $lignes = DB::table('ingredients_recette')
            ->where('recette_id', $this->recettePouletDg->id)
            ->pluck('quantite_unitaire', 'article_id');

        $this->assertCount(1, $lignes);
        $this->assertSame('0.300', $lignes[$this->riz->id]);
        // Le poulet a bien disparu : il ne sera plus décrémenté.
        $this->assertArrayNotHasKey($this->poulet->id, $lignes->all());
    }

    /**
     * `recettes.cout_matiere_calcule` est RECALCULÉ et persisté par ce chemin —
     * seul endroit du dépôt qui écrit cette colonne. Avant ce lot, rien ne
     * l'écrivait : elle valait `0.00` pour toutes les recettes.
     */
    #[Test]
    public function ef_m4_02_la_colonne_de_cout_matiere_est_reellement_ecrite(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->assertSame('0.00', (string) $this->recettePouletDg->cout_matiere_calcule);

        $this->putJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}/composition", [
            'lignes' => [['article_id' => $this->riz->id, 'quantite_unitaire' => '0.250']],
        ])->assertOk();

        $this->assertSame('300.00', (string) $this->recettePouletDg->refresh()->cout_matiere_calcule);
    }

    /**
     * Le coût matière ne se saisit jamais : il divergerait de sa composition
     * dès le premier ingrédient ajouté.
     */
    #[Test]
    public function ef_m4_02_le_cout_matiere_ne_se_saisit_pas(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->postJson('/api/v1/restaurant/recettes', [
            'libelle' => 'Sauce arachide',
            'cout_matiere_calcule' => '999.00',
        ])
            ->assertStatus(422)
            ->assertJsonPath('errors.cout_matiere_calcule.0', __('restaurant.validation.cout_matiere_calcule'));

        $this->putJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}/composition", [
            'lignes' => [['article_id' => $this->riz->id, 'quantite_unitaire' => '0.250']],
            'cout_matiere_calcule' => '999.00',
        ])->assertStatus(422);
    }

    /**
     * Un article en double additionnerait mal : deux lignes « huile 0,05 » et
     * « huile 0,10 » veulent dire 0,15, pas 0,10. La clé primaire composite le
     * refuserait par une erreur SQL illisible ; la validation le refuse en
     * nommant l'article.
     */
    #[Test]
    public function ef_m4_02_un_ingredient_en_double_est_refuse(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $reponse = $this->putJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}/composition", [
            'lignes' => [
                ['article_id' => $this->riz->id, 'quantite_unitaire' => '0.250'],
                ['article_id' => $this->riz->id, 'quantite_unitaire' => '0.100'],
            ],
        ])
            ->assertStatus(422);

        $this->assertErreur($reponse, 'lignes.1.article_id', __('restaurant.validation.ingredient_en_double'));

        // Le refus n'a rien détruit : la composition d'origine tient toujours.
        $this->assertSame(2, DB::table('ingredients_recette')
            ->where('recette_id', $this->recettePouletDg->id)->count());
    }

    /**
     * Une quantité à zéro n'est pas un ingrédient : c'est une ligne à retirer,
     * et elle fausserait le coût matière en donnant l'impression d'avoir été
     * comptée.
     */
    #[Test]
    public function ef_m4_02_une_quantite_d_ingredient_a_zero_est_refusee(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $reponse = $this->putJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}/composition", [
            'lignes' => [['article_id' => $this->riz->id, 'quantite_unitaire' => '0']],
        ])
            ->assertStatus(422);

        $this->assertErreur($reponse, 'lignes.0.quantite_unitaire', __('restaurant.validation.quantite_recette_positive'));
    }

    /**
     * Vider une composition erronée est un geste légitime, et sa conséquence
     * est VISIBLE : le plat apparaît « ne décrémente rien » sur la carte, et sa
     * transmission en cuisine sera refusée.
     */
    #[Test]
    public function ef_m4_02_vider_une_composition_est_possible_et_se_voit_sur_la_carte(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->putJson("/api/v1/restaurant/recettes/{$this->recettePouletDg->id}/composition", ['lignes' => []])
            ->assertOk()
            ->assertJsonPath('data.composition_vide', true)
            ->assertJsonPath('data.cout_matiere', null);

        $ligne = $this->lignePouletDg();
        $this->assertFalse($ligne['lie_au_stock']);
        $this->assertSame(LignePlatCarte::MOTIF_RECETTE_VIDE, $ligne['motif_sans_stock']);
    }

    // ---------------------------------- EF-M4-03 / EF-M4-05 Cycle de commande

    #[Test]
    public function ef_m4_03_une_commande_se_cree_sans_engager_de_stock(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide())
            ->assertCreated()
            ->assertJsonPath('data.statut', 'en_preparation')
            ->assertJsonPath('data.lignes.0.plat_libelle', 'Poulet DG')
            ->assertJsonPath('data.lignes.0.quantite', 2)
            ->assertJsonPath('data.transmise', false);

        // RG-05 ne s'applique qu'à la transmission : le serveur peut encore
        // modifier ou annuler sans que la cuisine ait rien entamé.
        $this->assertSame('10.00', $this->stockRiz());
    }

    /**
     * RG-05 — la transmission en cuisine décrémente chaque ingrédient, dans la
     * même transaction que le changement de statut.
     */
    #[Test]
    public function rg05_la_transmission_decremente_le_stock_par_l_api(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $id = $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide())
            ->assertCreated()->json('data.id');

        $this->patchJson("/api/v1/restaurant/commandes/{$id}/transmission")
            ->assertOk()
            ->assertJsonPath('data.statut', 'transmise_cuisine')
            ->assertJsonPath('data.transmise', true);

        // 2 portions : riz 10 − (0,250 × 2) = 9,50 ; poulet 4 − (0,400 × 2) = 3,20
        $this->assertSame('9.50', $this->stockRiz());
        $this->assertSame('3.20', $this->stockDe($this->poulet));
    }

    /**
     * RG-06 — une rupture est refusée en 422 AVEC le drapeau de confirmation :
     * elle s'assume, elle ne se subit pas. Rien n'est écrit tant qu'elle n'est
     * pas assumée.
     */
    #[Test]
    public function rg06_une_rupture_est_refusee_avec_son_drapeau_de_confirmation(): void
    {
        Sanctum::actingAs($this->cuisinier());

        // 20 portions demandent 8 kg de poulet ; il n'en reste que 4.
        $id = $this->postJson('/api/v1/restaurant/commandes', [
            'lignes' => [['plat_id' => $this->pouletDg->id, 'quantite' => 20]],
        ])->assertCreated()->json('data.id');

        $this->patchJson("/api/v1/restaurant/commandes/{$id}/transmission")
            ->assertStatus(422)
            ->assertJsonPath('necessite_validation_rupture', true);

        $this->assertSame('en_preparation', CommandeRestaurant::findOrFail($id)->statut);
        // La transaction a tout annulé : même le riz, pourtant suffisant, n'a
        // pas bougé. Une commande transmise à moitié laisserait la cuisine avec
        // un bon qu'elle ne peut pas honorer.
        $this->assertSame('10.00', $this->stockRiz());

        // Assumée par un utilisateur habilité, elle passe.
        $this->patchJson("/api/v1/restaurant/commandes/{$id}/transmission", ['validation_rupture' => true])
            ->assertOk()
            ->assertJsonPath('data.statut', 'transmise_cuisine');

        $this->assertSame('-4.00', $this->stockDe($this->poulet));
    }

    /**
     * Décision du PO du 30/10/2026 (« le stock s'ajoute après ») : une fiche
     * technique vide ne refuse plus la transmission. Le plat part en cuisine
     * SANS aucun mouvement de stock (il était refusé, 422, avec `plat`). Un plat
     * qui a une fiche garnie, dans la même commande, décrémente toujours.
     */
    #[Test]
    public function rg05_un_plat_sans_fiche_technique_se_transmet_sans_mouvement_de_stock(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $id = $this->postJson('/api/v1/restaurant/commandes', [
            'lignes' => [['plat_id' => $this->saladeSansRecette->id, 'quantite' => 1]],
        ])->assertCreated()->json('data.id');

        $this->patchJson("/api/v1/restaurant/commandes/{$id}/transmission")
            ->assertOk()
            ->assertJsonPath('data.statut', 'transmise_cuisine');

        $this->assertSame('10.00', $this->stockRiz(), 'Aucun mouvement de stock pour un plat sans fiche.');
        $this->assertSame('transmise_cuisine', CommandeRestaurant::findOrFail($id)->statut);
    }

    /**
     * Une seconde transmission décrémenterait le stock deux fois pour une seule
     * commande — l'erreur ne se verrait qu'à l'inventaire.
     */
    #[Test]
    public function rg05_une_commande_ne_se_transmet_pas_deux_fois(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $id = $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide())
            ->assertCreated()->json('data.id');

        $this->patchJson("/api/v1/restaurant/commandes/{$id}/transmission")->assertOk();

        $this->patchJson("/api/v1/restaurant/commandes/{$id}/transmission")
            ->assertStatus(422)
            ->assertJsonPath('message', __('restaurant.deja_transmise'));

        // Le stock n'a été touché qu'une fois.
        $this->assertSame('9.50', $this->stockRiz());
    }

    /**
     * Après transmission, les denrées sont engagées : l'annulation devient une
     * perte de stock à constater, pas un changement de statut. Ce refus est le
     * livrable.
     */
    #[Test]
    public function ef_m4_03_une_commande_transmise_ne_s_annule_pas(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $id = $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide())
            ->assertCreated()->json('data.id');

        // Avant transmission, l'annulation passe.
        $autre = $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide())
            ->assertCreated()->json('data.id');
        $this->patchJson("/api/v1/restaurant/commandes/{$autre}/annulation")
            ->assertOk()
            ->assertJsonPath('data.statut', 'annulee');

        $this->patchJson("/api/v1/restaurant/commandes/{$id}/transmission")->assertOk();

        $this->patchJson("/api/v1/restaurant/commandes/{$id}/annulation")
            ->assertStatus(422)
            ->assertJsonPath('message', __('restaurant.annulation_apres_transmission'));

        $this->assertSame('transmise_cuisine', CommandeRestaurant::findOrFail($id)->statut);
    }

    #[Test]
    public function ef_m4_03_une_commande_non_transmise_ne_peut_pas_etre_servie(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $id = $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide())
            ->assertCreated()->json('data.id');

        $this->patchJson("/api/v1/restaurant/commandes/{$id}/service")
            ->assertStatus(422)
            ->assertJsonPath('message', __('restaurant.service_avant_transmission'));

        $this->patchJson("/api/v1/restaurant/commandes/{$id}/transmission")->assertOk();
        $this->patchJson("/api/v1/restaurant/commandes/{$id}/service")
            ->assertOk()
            ->assertJsonPath('data.statut', 'servie');
    }

    /**
     * EF-M4-05 — le bon de cuisine signale le plat dont la fiche est vide :
     * corriger la fiche AVANT que le serveur ne se heurte au refus devant le
     * client.
     */
    #[Test]
    public function ef_m4_05_le_bon_de_cuisine_signale_les_recettes_incompletes(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $id = $this->postJson('/api/v1/restaurant/commandes', [
            'lignes' => [
                ['plat_id' => $this->pouletDg->id, 'quantite' => 1],
                ['plat_id' => $this->saladeSansRecette->id, 'quantite' => 1],
            ],
        ])->assertCreated()->json('data.id');

        $lignes = $this->indexerPar(
            $this->getJson("/api/v1/restaurant/commandes/{$id}")->assertOk()->json('data.lignes'),
            'plat_libelle',
        );

        $this->assertFalse($lignes['Poulet DG']['recette_incomplete']);
        $this->assertSame(2, $lignes['Poulet DG']['nb_ingredients']);
        $this->assertTrue($lignes['Salade César']['recette_incomplete']);
        $this->assertSame(0, $lignes['Salade César']['nb_ingredients']);
    }

    /**
     * Une quantité saisie à zéro deviendrait une portion transmise en cuisine
     * et décrémentée du stock (`QuantiteSaisie`, PA-98).
     */
    #[Test]
    public function ef_m4_03_une_quantite_a_zero_n_est_pas_une_ligne_de_commande(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $reponse = $this->postJson('/api/v1/restaurant/commandes', [
            'lignes' => [['plat_id' => $this->pouletDg->id, 'quantite' => 0]],
        ])
            ->assertStatus(422);

        $this->assertErreur($reponse, 'lignes.0.quantite', __('restaurant.validation.quantite_positive'));

        $this->assertSame(0, CommandeRestaurant::count());
    }

    /**
     * Une commande restaurant ne transporte AUCUN montant : ses lignes ne
     * figent aucun prix unitaire au schéma, et un total recalculé au tarif du
     * jour serait faux pour toute commande antérieure à un changement de carte.
     */
    #[Test]
    public function ef_m4_03_aucun_montant_n_est_accepte_ni_rendu(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide() + ['montant' => '9000'])
            ->assertStatus(422)
            ->assertJsonPath('errors.montant.0', __('restaurant.validation.montant_sans_schema'));

        $donnees = $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide())
            ->assertCreated()->json('data');

        $this->assertArrayNotHasKey('montant', $donnees);
        $this->assertArrayNotHasKey('total', $donnees);
        $this->assertArrayNotHasKey('prix_unitaire', $donnees['lignes'][0]);
    }

    /**
     * `commandes_restaurant` n'est pas au registre `TABLES_SYNCHRONISABLES` :
     * accepter un identifiant fourni par le client laisserait croire à une
     * idempotence qui n'a pas lieu.
     */
    #[Test]
    public function ef_m4_03_aucun_identifiant_client_n_est_accepte(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->postJson('/api/v1/restaurant/commandes', $this->commandeValide() + ['id' => (string) Str::uuid()])
            ->assertStatus(422)
            ->assertJsonPath('errors.id.0', __('restaurant.validation.identifiant_non_accepte'));

        $this->assertSame(0, CommandeRestaurant::count());
    }

    /**
     * Un filtre de statut incompris rendrait le registre entier sous un
     * intitulé qui promet un sous-ensemble : un écran « transmises » qui
     * montre tout ferait préparer des commandes annulées.
     */
    #[Test]
    public function ef_m4_03_un_statut_de_filtre_inconnu_est_refuse(): void
    {
        Sanctum::actingAs($this->cuisinier());

        $this->getJson('/api/v1/restaurant/commandes?statut=en_attente')
            ->assertStatus(422)
            ->assertJsonPath('errors.statut.0', __('restaurant.validation.statut_inconnu'));

        $this->getJson('/api/v1/restaurant/commandes?statut=annulee')->assertOk();
    }

    // --------------------------------------------------------------- Fixtures

    /**
     * Assertion sur une cle de validation POINTEE (`lignes.0.quantite`).
     *
     * `assertJsonPath` lit son chemin avec `data_get`, qui coupe sur les
     * points : il chercherait `errors > lignes > 0 > quantite` la ou la cle EST
     * la chaine « lignes.0.quantite ». Il rendait `null` en silence — ce qui a
     * fait echouer l'assertion ici, mais l'aurait fait PASSER si on avait
     * compare a `null`.
     */
    /**
     * @param  TestResponse<\Illuminate\Http\JsonResponse>  $reponse
     */
    private function assertErreur(TestResponse $reponse, string $cle, string $message): void
    {
        $erreurs = $reponse->json('errors');

        $this->assertIsArray($erreurs);
        $this->assertArrayHasKey($cle, $erreurs, "Aucune erreur de validation sur `{$cle}`.");
        $this->assertSame($message, $erreurs[$cle][0]);
    }

    private function commande(): CommandeRestaurant
    {
        $commande = CommandeRestaurant::create([
            'date_commande' => now(),
            'statut' => 'en_preparation',
        ]);

        $commande->lignes()->create(['plat_id' => $this->pouletDg->id, 'quantite' => 1]);

        return $commande;
    }

    /**
     * @return array<string, mixed>
     */
    private function platValide(): array
    {
        return [
            'libelle' => 'Amiwo sauce tomate',
            'menu_id' => $this->carte->id,
            'recette_id' => $this->recettePouletDg->id,
            'prix_vente' => '2000',
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function menuValide(): array
    {
        return ['libelle' => 'Carte de saison sèche', 'type' => 'local'];
    }

    /**
     * @return array<string, mixed>
     */
    private function commandeValide(): array
    {
        return ['lignes' => [['plat_id' => $this->pouletDg->id, 'quantite' => 2]]];
    }

    /**
     * @return array<string, mixed>
     */
    private function lignePouletDg(): array
    {
        return $this->ligneCarte($this->pouletDg->id);
    }

    /**
     * @return array<string, mixed>
     */
    private function ligneCarte(string $platId): array
    {
        $lignes = $this->getJson('/api/v1/restaurant/carte')->assertOk()->json('data.lignes');

        return $this->ligneDe($lignes, $platId);
    }

    /**
     * @param  array<int, array<string, mixed>>  $lignes
     * @return array<string, mixed>
     */
    private function ligneDe(array $lignes, string $platId): array
    {
        foreach ($lignes as $ligne) {
            if ($ligne['id'] === $platId) {
                return $ligne;
            }
        }

        $this->fail("Le plat {$platId} n'apparaît pas sur la carte.");
    }

    /**
     * Indexe une liste de lignes JSON par la valeur d'une de leurs colonnes.
     *
     * @param  mixed  $lignes
     * @return array<string, array<string, mixed>>
     */
    private function indexerPar(mixed $lignes, string $colonne): array
    {
        $this->assertIsArray($lignes);

        $index = [];

        foreach ($lignes as $ligne) {
            $this->assertIsArray($ligne);
            $index[(string) $ligne[$colonne]] = $ligne;
        }

        return $index;
    }

    private function stockRiz(): string
    {
        return $this->stockDe($this->riz);
    }

    private function stockDe(Article $article): string
    {
        return $this->stocks->stock($article->id, $this->cuisine->id);
    }

    private function article(string $libelle, string $unite, string $seuil, string $cmp): Article
    {
        return Article::create([
            'libelle' => $libelle,
            'categorie' => 'denree',
            'unite_mesure' => $unite,
            'seuil_alerte' => $seuil,
            'seuil_reappro' => '20.00',
            'cout_moyen_pondere' => $cmp,
        ]);
    }

    /**
     * Le rôle est DÉRIVÉ de la matrice, jamais écrit en dur : le jour où elle
     * change, la suite suit — ou échoue en le disant.
     */
    private function roleAvecNiveauM4(string $niveau): string
    {
        foreach (RolePermissionSeeder::MATRICE as $role => $droits) {
            if ($droits['M4'] === $niveau) {
                return $role;
            }
        }

        $this->fail("Aucun rôle de la matrice ne porte M4 = '{$niveau}'.");
    }

    private function cuisinier(): User
    {
        return $this->cuisinier ??= $this->utilisateur($this->roleAvecNiveauM4('C'));
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(8),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
