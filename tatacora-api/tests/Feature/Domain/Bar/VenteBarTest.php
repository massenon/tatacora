<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Bar;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Models\VenteBar;
use App\Domain\Bar\Services\VenteBarService;
use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * M5 Bar — CRUD des boissons et vente au comptoir.
 *
 * Deux enjeux : RG-05 en 1 pour 1 (une bière vendue sort une bière du stock)
 * et l'anti-pattern PA-24 (« Stock disponible » éditable du prototype), qui ne
 * doit jamais réapparaître.
 */
final class VenteBarTest extends TestCase
{
    use RefreshDatabase;

    private VenteBarService $ventes;

    private StockTheoriqueService $stock;

    private PointStockage $bar;

    private Article $article;

    private CarteBoisson $biere;

    private string $sessionId;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->ventes = app(VenteBarService::class);
        $this->stock = app(StockTheoriqueService::class);

        $utilisateur = $this->utilisateur('barman');
        $this->actingAs($utilisateur);

        $this->bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);

        $this->article = Article::create([
            'libelle' => 'Bière La Béninoise 65cl',
            'categorie' => 'boisson',
            'unite_mesure' => 'bouteille',
            'seuil_alerte' => '10.00',
            'seuil_reappro' => '24.00',
            'cout_moyen_pondere' => '450.0000',
        ]);

        $this->biere = CarteBoisson::create([
            'article_id' => $this->article->id,
            'libelle' => 'Béninoise 65cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
        ]);

        app(MouvementStockService::class)->entree($this->article->id, $this->bar->id, '48.00', 'Réception');

        $this->sessionId = (string) Str::uuid();
        DB::table('sessions_caisse')->insert([
            'id' => $this->sessionId,
            'point_vente' => 'bar',
            'utilisateur_ouverture_id' => $utilisateur->id,
            'date_ouverture' => now(),
            'montant_fond' => '10000.00',
        ]);
    }

    // ------------------------------------------------------------- Anti-pattern

    /**
     * PA-24 — le champ « Stock disponible » éditable du prototype ne doit
     * jamais réapparaître.
     */
    #[Test]
    public function pa24_la_table_des_boissons_ne_porte_aucune_colonne_de_stock(): void
    {
        $colonnes = array_keys($this->biere->getAttributes());

        foreach (['stock', 'stock_disponible', 'quantite_stock'] as $interdite) {
            $this->assertNotContains($interdite, $colonnes);
        }
    }

    #[Test]
    public function pa24_le_stock_soumis_dans_le_formulaire_est_ignore(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        // Un client mal intentionné — ou un formulaire hérité du prototype —
        // tente de fixer le stock à la création.
        $this->postJson('/api/v1/bar/boissons', [
            'libelle' => 'Sucrerie 33cl',
            'article_id' => $this->article->id,
            'categorie' => 'locale',
            'prix_vente' => '500.00',
            'stock_disponible' => '9999',
        ])->assertCreated();

        // La valeur soumise n'a aucun effet : le stock reste celui des mouvements.
        $this->assertSame('48.00', $this->stockBar());
    }

    #[Test]
    public function pa24_le_stock_est_expose_en_lecture_seule_et_calcule(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->getJson("/api/v1/bar/boissons/{$this->biere->id}")
            ->assertOk()
            ->assertJsonPath('data.stock_disponible', '48.00')
            ->assertJsonPath('data.stock_lecture_seule', true);
    }

    // --------------------------------------------------------------- RG-05

    #[Test]
    public function rg05_une_vente_decremente_le_stock_en_un_pour_un(): void
    {
        $vente = $this->ventes->enregistrer($this->sessionId, [
            ['boisson_id' => $this->biere->id, 'quantite' => 3],
        ]);

        $this->assertSame('45.00', $this->stockBar());
        // Montant CALCULÉ depuis les lignes, jamais saisi par le barman.
        $this->assertSame('3000.00', $vente->montant);
    }

    #[Test]
    public function le_prix_est_fige_a_la_vente(): void
    {
        $vente = $this->ventes->enregistrer($this->sessionId, [
            ['boisson_id' => $this->biere->id, 'quantite' => 2],
        ]);

        // Le tarif de la carte augmente après la vente.
        $this->biere->update(['prix_vente' => '1500.00']);

        // La vente d'hier ne change pas de montant.
        $this->assertSame('1000.00', $vente->lignes()->sole()->prix_unitaire);
        $this->assertSame('2000.00', $vente->fresh()->montant);
    }

    #[Test]
    public function rg06_une_vente_au_dela_du_stock_est_refusee_et_rien_n_est_enregistre(): void
    {
        $this->assertThrows(
            fn () => $this->ventes->enregistrer($this->sessionId, [
                ['boisson_id' => $this->biere->id, 'quantite' => 60],
            ]),
            RuptureStockException::class,
        );

        // La transaction a tout annulé : ni vente, ni ligne, ni mouvement.
        $this->assertSame(0, VenteBar::count());
        $this->assertSame('48.00', $this->stockBar());
    }

    #[Test]
    public function rg06_une_rupture_assumee_passe_avec_validation_explicite(): void
    {
        $vente = $this->ventes->enregistrer(
            $this->sessionId,
            [['boisson_id' => $this->biere->id, 'quantite' => 50]],
            validationRupture: true,
        );

        $this->assertSame('-2.00', $this->stockBar());
        $this->assertSame('50000.00', $vente->montant);
    }

    #[Test]
    public function une_vente_multi_lignes_decremente_chaque_article(): void
    {
        $autreArticle = Article::create([
            'libelle' => 'Sucrerie 33cl', 'categorie' => 'boisson', 'unite_mesure' => 'bouteille',
            'seuil_alerte' => '5.00', 'seuil_reappro' => '12.00', 'cout_moyen_pondere' => '250.0000',
        ]);
        $sucrerie = CarteBoisson::create([
            'article_id' => $autreArticle->id, 'libelle' => 'Sucrerie 33cl',
            'categorie' => 'locale', 'prix_vente' => '500.00',
        ]);
        app(MouvementStockService::class)->entree($autreArticle->id, $this->bar->id, '24.00', 'Réception');

        $vente = $this->ventes->enregistrer($this->sessionId, [
            ['boisson_id' => $this->biere->id, 'quantite' => 2],
            ['boisson_id' => $sucrerie->id, 'quantite' => 4],
        ]);

        $this->assertSame('46.00', $this->stockBar());
        $this->assertSame('20.00', $this->stock->stock($autreArticle->id, $this->bar->id));
        // 2 × 1000 + 4 × 500
        $this->assertSame('4000.00', $vente->montant);
    }

    /**
     * Une rupture sur la SECONDE ligne doit annuler la première aussi.
     */
    #[Test]
    public function rg06_une_rupture_sur_une_ligne_annule_toute_la_vente(): void
    {
        $autreArticle = Article::create([
            'libelle' => 'Vin importé', 'categorie' => 'boisson', 'unite_mesure' => 'bouteille',
            'seuil_alerte' => '2.00', 'seuil_reappro' => '6.00', 'cout_moyen_pondere' => '5000.0000',
        ]);
        $vin = CarteBoisson::create([
            'article_id' => $autreArticle->id, 'libelle' => 'Vin rouge',
            'categorie' => 'importee', 'prix_vente' => '12000.00',
        ]);
        // Aucun stock de vin.

        $this->assertThrows(
            fn () => $this->ventes->enregistrer($this->sessionId, [
                ['boisson_id' => $this->biere->id, 'quantite' => 2],
                ['boisson_id' => $vin->id, 'quantite' => 1],
            ]),
            RuptureStockException::class,
        );

        // La bière, pourtant disponible et traitée en premier, n'a pas bougé.
        $this->assertSame('48.00', $this->stockBar());
        $this->assertSame(0, VenteBar::count());
    }

    // ----------------------------------------------------------------- API

    #[Test]
    public function l_api_de_vente_renvoie_422_avec_le_drapeau_de_rupture(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->postJson('/api/v1/bar/ventes', [
            'session_id' => $this->sessionId,
            'lignes' => [['boisson_id' => $this->biere->id, 'quantite' => 60]],
        ])
            ->assertStatus(422)
            ->assertJsonPath('necessite_validation_rupture', true)
            ->assertJsonPath('stock_disponible', '48.00');
    }

    #[Test]
    public function une_boisson_doit_etre_liee_a_un_article_du_stock(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->postJson('/api/v1/bar/boissons', [
            'libelle' => 'Boisson orpheline',
            'categorie' => 'locale',
            'prix_vente' => '500.00',
        ])->assertStatus(422)->assertJsonValidationErrors('article_id');
    }

    #[Test]
    public function rg16_un_role_sans_acces_a_m5_ne_peut_pas_vendre(): void
    {
        // Le réceptionniste est en lecture seule sur M5.
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->postJson('/api/v1/bar/ventes', [
            'session_id' => $this->sessionId,
            'lignes' => [['boisson_id' => $this->biere->id, 'quantite' => 1]],
        ])->assertForbidden();

        $this->getJson('/api/v1/bar/boissons')->assertOk();
    }

    private function stockBar(): string
    {
        return $this->stock->stock($this->article->id, $this->bar->id);
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
