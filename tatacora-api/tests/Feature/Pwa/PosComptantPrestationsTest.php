<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Ventes\Models\Vente;
use App\Models\User;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\TablesSalleSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le tourisme (circuits, M9) et la location (véhicules, M8) s'encaissent au
 * POS du COMPTOIR (directive du PO du 22/10/2026) : rayons du catalogue,
 * panier mixte avec le bar, encaissement par `VenteService`, aucune sortie de
 * stock. Le POS des clients hébergés, lui, ne les porte pas sur une note de
 * chambre.
 */
final class PosComptantPrestationsTest extends TestCase
{
    use RefreshDatabase;

    private User $gerant;

    private Circuit $circuit;

    private Vehicule $vehicule;

    private CarteBoisson $biere;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->seed(TablesSalleSeeder::class);

        $this->gerant = $this->utilisateur('gerant');
        $this->actingAs($this->gerant);

        $bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $article = Article::create([
            'libelle' => 'Bière 65cl',
            'categorie' => 'test',
            'unite_mesure' => 'bouteille',
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '500.0000',
        ]);
        $this->biere = CarteBoisson::create([
            'article_id' => $article->id,
            'libelle' => 'Béninoise 65cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
            'unites_vendables_par_unite_stock' => '1.0000',
        ]);
        app(MouvementStockService::class)->entree($article->id, $bar->id, '48.00', 'Réception');

        $this->circuit = Circuit::create([
            'nom' => 'Cascades de Kota', 'theme' => 'nature', 'zone' => 'Atacora',
            'duree' => '1 jour', 'prix' => '15000.00', 'capacite_max' => 12,
        ]);
        $this->vehicule = Vehicule::create([
            'categorie' => '4x4', 'immatriculation' => 'AB-123-CD', 'annee' => 2022,
            'transmission' => 'automatique', 'capacite' => 5, 'tarif_jour' => '65000.00',
            'statut' => 'disponible',
        ]);

        SessionCaisse::create([
            'point_vente' => 'bar',
            'utilisateur_ouverture_id' => $this->gerant->id,
            'date_ouverture' => now(),
            'montant_fond' => '10000',
        ]);
    }

    #[Test]
    public function le_catalogue_du_comptoir_propose_les_circuits_et_les_vehicules(): void
    {
        Livewire::test(PosComptant::class)
            ->assertSee('Cascades de Kota')
            ->assertSee('AB-123-CD')
            ->assertSee(__('pos_pwa.comptant.famille_tourisme'))
            ->assertSee(__('pos_pwa.comptant.famille_location'));
    }

    #[Test]
    public function un_panier_mixte_bar_tourisme_location_s_encaisse_sans_toucher_au_stock_des_prestations(): void
    {
        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M9', $this->circuit->id)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M9', $this->circuit->id)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M8', $this->vehicule->id)
            ->call('encaisser')
            ->assertSet('toastType', 'success');

        $vente = Vente::with('lignes')->firstOrFail();

        $this->assertEqualsCanonicalizing(['M5', 'M8', 'M9'], $vente->lignes->pluck('module')->all());
        // 1 000 + 2 x 15 000 + 65 000.
        $this->assertSame('96000.00', (string) $vente->montant_total);
        // Seule la boisson sort du stock.
        $this->assertSame(1, \App\Domain\Stocks\Models\MouvementStock::where('type_mouvement', 'sortie')->count());
    }

    #[Test]
    public function un_barman_ne_vend_ni_circuit_ni_vehicule_que_ces_modules_lui_refusent(): void
    {
        $barman = $this->utilisateur('barman');   // M5 = 'C', M8 = M9 = '-'
        $this->actingAs($barman);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M9', $this->circuit->id)
            ->call('encaisser')
            ->assertForbidden();

        $this->assertSame(0, Vente::count());
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
