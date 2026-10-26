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
 * Directive du PO du 26/10/2026 : « Tourisme » et « Location » (M9/M8) sont
 * ENLEVES de la selection du POS du comptoir et du POS des clients heberges.
 * Le domaine (`VenteService`, `PanierService`) reste defensif — une vente M8/M9
 * deja faite est acceptee, voir `VenteTourismeLocationTest` — mais aucun ecran
 * ne propose plus ces rayons : ni carte, ni famille, ni pastille.
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
    public function le_catalogue_du_comptoir_ne_propose_ni_circuit_ni_vehicule_ni_leurs_rayons(): void
    {
        Livewire::test(PosComptant::class)
            ->assertSee('Béninoise 65cl')
            ->assertDontSee('Cascades de Kota')
            ->assertDontSee('AB-123-CD')
            ->assertDontSee('Tourisme')
            ->assertDontSee('Location')
            ->assertDontSee('Tourisme & location');
    }

    #[Test]
    public function le_selecteur_de_famille_du_comptoir_ne_garde_que_tout_bar_et_restaurant(): void
    {
        $html = Livewire::test(PosComptant::class)->html();

        $this->assertStringContainsString('value="'.__('pos_pwa.comptant.famille_bar').'"', $html);
        $this->assertStringContainsString('value="'.__('pos_pwa.comptant.famille_restaurant').'"', $html);
        $this->assertStringNotContainsString('value="Tourisme"', $html);
        $this->assertStringNotContainsString('value="Location"', $html);
        $this->assertFalse(\Illuminate\Support\Facades\Lang::has('pos_pwa.comptant.famille_tourisme'));
        $this->assertFalse(\Illuminate\Support\Facades\Lang::has('pos_pwa.comptant.famille_location'));
    }

    #[Test]
    public function une_action_forgee_sur_un_circuit_ou_un_vehicule_n_ajoute_rien_au_panier(): void
    {
        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M9', $this->circuit->id)
            ->assertSet('toastType', 'error')
            ->call('ajouterAuPanier', 'M8', $this->vehicule->id)
            ->assertSet('toastType', 'error');

        $this->assertSame(0, \App\Domain\Ventes\Models\LigneVente::count());
        $this->assertSame(0, \App\Domain\Ventes\Models\Panier::count());
    }

    #[Test]
    public function un_barman_ne_vend_pas_non_plus_de_circuit_par_une_action_forgee(): void
    {
        $this->actingAs($this->utilisateur('barman'));

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M9', $this->circuit->id);

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
