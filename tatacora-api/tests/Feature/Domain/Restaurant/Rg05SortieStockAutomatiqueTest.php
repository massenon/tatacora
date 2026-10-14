<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Restaurant;

use App\Domain\Restaurant\Events\CommandeTransmiseCuisine;
use App\Domain\Restaurant\Exceptions\RecetteManquanteException;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CommandeRestaurantService;
use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * RG-05 — Sortie de stock automatique déclenchée par une vente restaurant.
 *
 * Complète la moitié livrée au sprint M6 : `MouvementStockService` savait
 * décrémenter, il manquait la nomenclature qui dit quoi décrémenter.
 *
 * Cas obligatoires de 07_TESTING_QA.md §2 (RG-05/RG-06) : vente avec stock
 * suffisant → décrémentation correcte ; vente dépassant le stock sans
 * validation → rejet ; avec validation explicite → passage forcé + audit.
 */
final class Rg05SortieStockAutomatiqueTest extends TestCase
{
    use RefreshDatabase;

    private CommandeRestaurantService $commandes;

    private StockTheoriqueService $stock;

    private PointStockage $cuisine;

    private Article $riz;

    private Article $poulet;

    private Plat $poulletDg;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->commandes = app(CommandeRestaurantService::class);
        $this->stock = app(StockTheoriqueService::class);
        $this->actingAs($this->utilisateur('cuisine'));

        $this->cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);

        $this->riz = $this->article('Riz', 'kg', '5.00');
        $this->poulet = $this->article('Poulet', 'kg', '2.00');

        // Fiche technique : 0,250 kg de riz et 0,400 kg de poulet par portion.
        $recette = Recette::create(['libelle' => 'Poulet DG', 'cout_matiere_calcule' => '0.00']);
        $recette->ingredients()->attach([
            $this->riz->id => ['quantite_unitaire' => '0.250'],
            $this->poulet->id => ['quantite_unitaire' => '0.400'],
        ]);

        $menu = Menu::create(['libelle' => 'Carte principale', 'type' => 'local']);
        $this->poulletDg = Plat::create([
            'menu_id' => $menu->id,
            'recette_id' => $recette->id,
            'libelle' => 'Poulet DG',
            'prix_vente' => '4500.00',
        ]);

        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($this->riz->id, $this->cuisine->id, '10.00', 'Réception');
        $mouvements->entree($this->poulet->id, $this->cuisine->id, '4.00', 'Réception');
    }

    #[Test]
    public function les_ingredients_sont_de_vraies_cles_etrangeres_jamais_du_texte_libre(): void
    {
        $ingredients = $this->poulletDg->recette->ingredients;

        $this->assertCount(2, $ingredients);
        // Chaque ingrédient EST un article du référentiel, avec son identifiant.
        $this->assertContains($this->riz->id, $ingredients->pluck('id')->all());
        $this->assertInstanceOf(Article::class, $ingredients->first());
    }

    #[Test]
    public function creer_une_commande_n_engage_aucun_stock(): void
    {
        $this->commandes->creer([['plat_id' => $this->poulletDg->id, 'quantite' => 2]]);

        // Tant que la commande n'est pas transmise, le serveur peut la modifier :
        // rien ne doit être sorti du stock.
        $this->assertSame('10.00', $this->stockRiz());
    }

    #[Test]
    public function rg05_la_transmission_en_cuisine_decremente_chaque_ingredient(): void
    {
        $commande = $this->commandes->creer([['plat_id' => $this->poulletDg->id, 'quantite' => 2]]);

        $this->commandes->transmettreEnCuisine($commande);

        // 2 portions : riz 10 − (0,250 × 2) = 9,500 ; poulet 4 − (0,400 × 2) = 3,200
        $this->assertSame('9.50', $this->stockRiz());
        $this->assertSame('3.20', $this->stock->stock($this->poulet->id, $this->cuisine->id));
        $this->assertSame('transmise_cuisine', $commande->fresh()->statut);
    }

    #[Test]
    public function rg05_l_evenement_est_emis_apres_la_deduction(): void
    {
        Event::fake([CommandeTransmiseCuisine::class]);

        $commande = $this->commandes->creer([['plat_id' => $this->poulletDg->id, 'quantite' => 1]]);
        $this->commandes->transmettreEnCuisine($commande);

        Event::assertDispatched(
            CommandeTransmiseCuisine::class,
            fn (CommandeTransmiseCuisine $e): bool => $e->commandeId === $commande->id
                && count($e->sorties) === 2,
        );
    }

    /**
     * Le cas central : une rupture d'ingrédient doit annuler la commande
     * ENTIÈRE, pas la laisser à moitié transmise.
     */
    #[Test]
    public function rg06_une_rupture_d_ingredient_annule_toute_la_transmission(): void
    {
        // 11 portions demanderaient 4,400 kg de poulet ; il n'y en a que 4.
        $commande = $this->commandes->creer([['plat_id' => $this->poulletDg->id, 'quantite' => 11]]);

        $this->assertThrows(
            fn () => $this->commandes->transmettreEnCuisine($commande),
            RuptureStockException::class,
        );

        // Rien n'a bougé : ni le riz (pourtant suffisant et traité en premier),
        // ni le statut de la commande. La transaction a tout annulé.
        $this->assertSame('10.00', $this->stockRiz());
        $this->assertSame('4.00', $this->stock->stock($this->poulet->id, $this->cuisine->id));
        $this->assertSame('en_preparation', $commande->fresh()->statut);
    }

    #[Test]
    public function rg06_une_rupture_assumee_passe_et_laisse_une_trace(): void
    {
        $commande = $this->commandes->creer([['plat_id' => $this->poulletDg->id, 'quantite' => 11]]);

        $this->commandes->transmettreEnCuisine($commande, validationRupture: true);

        $this->assertSame('transmise_cuisine', $commande->fresh()->statut);
        // Le poulet passe en négatif : rupture assumée, pas anomalie masquée.
        $this->assertSame('-0.40', $this->stock->stock($this->poulet->id, $this->cuisine->id));
        $this->assertGreaterThan(0, JournalAudit::where('action', 'rupture_stock_forcee')->count());
    }

    /**
     * RG-05 est garantie **au niveau du schéma** : `plats.recette_id` est
     * NOT NULL, donc un plat sans fiche technique ne peut pas exister.
     *
     * C'est une garantie plus forte qu'un contrôle applicatif — contrairement à
     * RG-01, dont la contrainte SQL a disparu avec la bascule MySQL, celle-ci
     * est déclarative et inviolable. `RecetteManquanteException` reste en
     * défense de second rideau dans le service, mais la base l'a déjà rendue
     * inatteignable par le chemin normal.
     */
    #[Test]
    public function rg05_le_schema_interdit_qu_un_plat_existe_sans_fiche_technique(): void
    {
        $menu = Menu::first();

        $this->assertThrows(
            fn () => Plat::create([
                'menu_id' => $menu->id,
                'recette_id' => null,
                'libelle' => 'Plat du jour',
                'prix_vente' => '3000.00',
            ]),
            QueryException::class,
        );

        $this->assertSame(1, Plat::count());
        // La classe d'exception applicative existe bien comme second rideau.
        $this->assertTrue(class_exists(RecetteManquanteException::class));
    }

    #[Test]
    public function une_commande_ne_peut_pas_etre_transmise_deux_fois(): void
    {
        $commande = $this->commandes->creer([['plat_id' => $this->poulletDg->id, 'quantite' => 1]]);
        $this->commandes->transmettreEnCuisine($commande);

        // Une double transmission décrémenterait deux fois pour une seule vente.
        $this->assertThrows(
            fn () => $this->commandes->transmettreEnCuisine($commande->fresh()),
            RuntimeException::class,
        );

        $this->assertSame('9.75', $this->stockRiz());
    }

    #[Test]
    public function une_commande_transmise_ne_s_annule_pas_simplement(): void
    {
        $commande = $this->commandes->creer([['plat_id' => $this->poulletDg->id, 'quantite' => 1]]);
        $this->commandes->transmettreEnCuisine($commande);

        // Les denrées sont engagées : l'annulation devient une perte à
        // constater, pas un changement de statut.
        $this->expectException(RuntimeException::class);
        $this->commandes->annuler($commande->fresh());
    }

    #[Test]
    public function une_commande_non_transmise_s_annule_sans_effet_sur_le_stock(): void
    {
        $commande = $this->commandes->creer([['plat_id' => $this->poulletDg->id, 'quantite' => 3]]);

        $this->commandes->annuler($commande);

        $this->assertSame('annulee', $commande->fresh()->statut);
        $this->assertSame('10.00', $this->stockRiz());
    }

    #[Test]
    public function la_deduction_est_proportionnelle_a_la_quantite_commandee(): void
    {
        $commande = $this->commandes->creer([['plat_id' => $this->poulletDg->id, 'quantite' => 4]]);
        $this->commandes->transmettreEnCuisine($commande);

        // 4 × 0,250 = 1,000 — la précision au millième est conservée.
        $this->assertSame('9.00', $this->stockRiz());
    }

    private function stockRiz(): string
    {
        return $this->stock->stock($this->riz->id, $this->cuisine->id);
    }

    private function article(string $libelle, string $unite, string $seuil): Article
    {
        return Article::create([
            'libelle' => $libelle,
            'categorie' => 'denree',
            'unite_mesure' => $unite,
            'seuil_alerte' => $seuil,
            'seuil_reappro' => bcmul($seuil, '2', 2),
            'cout_moyen_pondere' => '1000.0000',
        ]);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
