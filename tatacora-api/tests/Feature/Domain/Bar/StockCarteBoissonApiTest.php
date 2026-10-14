<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Bar;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Le stock d'une boisson PAR L'API est celui de la carte PWA (PA-199).
 *
 * ## Le défaut que ces cas ferment
 *
 * `BoissonResource` écrivait son propre calcul : solde en CASIERS là où la
 * carte rend des BOUTEILLES, point de bar pris au hasard, levée sur une
 * lecture impossible. Invisible à `VenteBarTest`, dont le conditionnement vaut
 * 1 — les deux unités s'y confondent. Ici, un casier de 24.
 *
 * Les mouvements passent par `MouvementStockService`, comme en production.
 */
final class StockCarteBoissonApiTest extends TestCase
{
    use RefreshDatabase;

    private Article $casier;

    private CarteBoisson $biere;

    private PointStockage $magasin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs($this->utilisateur('gerant'));

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $this->casier = Article::create([
            'libelle' => 'Béninoise 66 cl — casier de 24',
            'categorie' => 'boisson',
            'unite_mesure' => 'casier',
            'seuil_alerte' => '3.00',
            'cout_moyen_pondere' => '10800.0000',
        ]);

        $this->biere = CarteBoisson::create([
            'article_id' => $this->casier->id,
            'libelle' => 'Béninoise 66 cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
        ]);
        $this->biere->forceFill(['unites_vendables_par_unite_stock' => '24.0000'])->save();
    }

    #[Test]
    public function le_stock_vendable_est_en_bouteilles_comme_sur_la_carte(): void
    {
        $bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($this->casier->id, $bar->id, '2.00', 'Réception');
        $mouvements->entree($this->casier->id, $this->magasin->id, '3.00', 'Réception');
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->getJson("/api/v1/bar/boissons/{$this->biere->id}")
            ->assertOk()
            // Le sens historique est gardé : deux CASIERS au point de vente.
            ->assertJsonPath('data.stock_disponible', '2.00')
            // Le chiffre de la carte : 2 × 24 = 48 BOUTEILLES.
            ->assertJsonPath('data.stock_vendable', '48')
            // La réserve, hors point de vente : 3 casiers au magasin = 72.
            ->assertJsonPath('data.reserve', '72')
            // 2 casiers ≤ seuil de 3 : sous le seuil, pas en rupture.
            ->assertJsonPath('data.sous_seuil', true)
            ->assertJsonPath('data.rupture', false)
            ->assertJsonPath('data.stock_non_consulte', false)
            ->assertJsonPath('data.point_de_vente_absent', false);
    }

    #[Test]
    public function deux_points_de_bar_se_lisent_par_libelle_jamais_au_hasard(): void
    {
        // Identifiants FIXÉS à l'inverse de l'ordre des libellés : sans
        // `ORDER BY libelle`, MySQL rendrait le premier par clé primaire —
        // la terrasse —, et le cas le verrait.
        $terrasse = PointStockage::create(['id' => '00000000-0000-4000-8000-000000000001', 'libelle' => 'Bar terrasse', 'type' => 'bar']);
        $principal = PointStockage::create(['id' => 'ffffffff-ffff-4fff-8fff-ffffffffffff', 'libelle' => 'Bar principal', 'type' => 'bar']);
        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($this->casier->id, $principal->id, '1.00', 'Réception');
        $mouvements->entree($this->casier->id, $terrasse->id, '5.00', 'Réception');
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->getJson("/api/v1/bar/boissons/{$this->biere->id}")
            ->assertOk()
            ->assertJsonPath('data.stock_disponible', '1.00')
            ->assertJsonPath('data.stock_vendable', '24');
    }

    #[Test]
    public function sans_point_de_bar_aucun_chiffre_et_la_raison_est_dite(): void
    {
        app(MouvementStockService::class)->entree($this->casier->id, $this->magasin->id, '3.00', 'Réception');
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->getJson("/api/v1/bar/boissons/{$this->biere->id}")
            ->assertOk()
            // Jamais « 0 » : ce qui dort au magasin n'est pas vendable au
            // comptoir, et un zéro se lirait comme une rupture.
            ->assertJsonPath('data.stock_disponible', null)
            ->assertJsonPath('data.stock_vendable', null)
            ->assertJsonPath('data.reserve', null)
            ->assertJsonPath('data.point_de_vente_absent', true)
            ->assertJsonPath('data.stock_non_consulte', true);
    }

    #[Test]
    public function une_lecture_impossible_rend_non_consulte_jamais_une_erreur(): void
    {
        PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $this->mock(StockTheoriqueService::class, function ($mock): void {
            $mock->shouldReceive('stock')->andThrow(new RuntimeException('base indisponible'));
        });
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->getJson("/api/v1/bar/boissons/{$this->biere->id}")
            ->assertOk()
            ->assertJsonPath('data.stock_vendable', null)
            ->assertJsonPath('data.stock_non_consulte', true)
            ->assertJsonPath('data.point_de_vente_absent', false);
    }

    #[Test]
    public function la_marque_prix_provisoire_est_rendue(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));
        $this->getJson("/api/v1/bar/boissons/{$this->biere->id}")
            ->assertOk()
            ->assertJsonPath('data.prix_provisoire', false);

        $this->biere->forceFill(['prix_provisoire' => true])->save();

        $this->getJson("/api/v1/bar/boissons/{$this->biere->id}")
            ->assertOk()
            ->assertJsonPath('data.prix_provisoire', true);
    }

    #[Test]
    public function le_lien_de_stock_se_dit_comme_la_carte_pwa(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        // La phrase de la colonne « Article de stock » — celle que la PWA
        // rend, par le même auteur (`StockDeCarteService::conversionLisible`).
        $this->getJson("/api/v1/bar/boissons/{$this->biere->id}")
            ->assertOk()
            ->assertJsonPath('data.lien_stock.libelle', 'Béninoise 66 cl — casier de 24')
            ->assertJsonPath('data.lien_stock.detail', '24 par casier')
            ->assertJsonPath('data.prix_corrige_main', false);

        $this->biere->forceFill(['prix_corrige_main' => true])->save();

        $this->getJson("/api/v1/bar/boissons/{$this->biere->id}")
            ->assertOk()
            ->assertJsonPath('data.prix_corrige_main', true);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.stockcarte.'.Str::random(4),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
