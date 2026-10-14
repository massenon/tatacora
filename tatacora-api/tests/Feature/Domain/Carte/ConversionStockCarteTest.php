<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Carte;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Bar\Services\VenteBarService;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\CommandeRestaurantService;
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
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Conversion « carte -> stock » — PA-159 lot 0b, T2.
 *
 * La modale « Lier au stock » demandait le conditionnement en champ
 * obligatoire, avec un aperçu en direct (« Soit, en unités vendables »,
 * « Chaque vente décrémentera »), et **jetait la réponse** : le composant
 * n'écrivait que `article_id`. Un casier de 24 et une bouteille vendue à
 * l'unité produisaient le même enregistrement, donc la même décrémentation —
 * fausse d'un facteur 24 pour l'un des deux. L'écart n'apparaissait qu'à
 * l'inventaire, imputé à une perte physique.
 *
 * @see RG-05 Sortie de stock automatique
 * @see EF-M4-02 Fiches techniques
 * @see EF-M5-02 Carte des boissons
 */
final class ConversionStockCarteTest extends TestCase
{
    use RefreshDatabase;

    private StockTheoriqueService $stock;

    private PointStockage $bar;

    private PointStockage $cuisine;

    private Article $casier;

    private string $sessionId;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->stock = app(StockTheoriqueService::class);

        $utilisateur = $this->utilisateur('barman');
        $this->actingAs($utilisateur);

        $this->bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $this->cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);

        // L'article est suivi au CASIER : c'est l'unité d'achat et la seule
        // que l'inventaire compte.
        $this->casier = Article::create([
            'libelle' => 'Béninoise 65cl — casier de 24',
            'categorie' => 'boisson',
            'unite_mesure' => 'casier',
            'seuil_alerte' => '2.00',
            'seuil_reappro' => '5.00',
            'cout_moyen_pondere' => '12000.0000',
        ]);

        app(MouvementStockService::class)->entree($this->casier->id, $this->bar->id, '10.00', 'Réception');

        $this->sessionId = (string) Str::uuid();
        DB::table('sessions_caisse')->insert([
            'id' => $this->sessionId,
            'point_vente' => 'bar',
            'utilisateur_ouverture_id' => $utilisateur->id,
            'date_ouverture' => now(),
            'montant_fond' => '10000.00',
        ]);
    }

    // ------------------------------------------------------------ Le défaut

    #[Test]
    public function rg05_un_conditionnement_de_24_deduit_un_vingt_quatrieme_par_bouteille(): void
    {
        $boisson = $this->boissonAuCasier('24.0000');

        app(VenteBarService::class)->enregistrer($this->sessionId, [
            ['boisson_id' => $boisson->id, 'quantite' => 24],
        ]);

        // Vingt-quatre bouteilles vendues = un casier exactement.
        $this->assertSame('9.00', $this->stock->stock($this->casier->id, $this->bar->id));
    }

    #[Test]
    public function une_seule_bouteille_ne_retire_pas_un_casier_entier(): void
    {
        $boisson = $this->boissonAuCasier('24.0000');

        app(VenteBarService::class)->enregistrer($this->sessionId, [
            ['boisson_id' => $boisson->id, 'quantite' => 1],
        ]);

        // 1/24 = 0,0417, arrondi au centième que la colonne sait garder.
        // C'est le comportement que le code d'origine remplaçait par « 1,00 ».
        $this->assertSame('9.96', $this->stock->stock($this->casier->id, $this->bar->id));
    }

    #[Test]
    public function un_conditionnement_a_l_unite_reste_du_un_pour_un(): void
    {
        $boisson = $this->boissonAuCasier('1.0000');

        app(VenteBarService::class)->enregistrer($this->sessionId, [
            ['boisson_id' => $boisson->id, 'quantite' => 3],
        ]);

        $this->assertSame('7.00', $this->stock->stock($this->casier->id, $this->bar->id));
    }

    #[Test]
    public function le_conditionnement_est_reellement_persiste_par_le_service(): void
    {
        $boisson = $this->boissonAuCasier('1.0000');

        app(CarteBoissonService::class)->lierAuStock($boisson, $this->casier->id, '12.0000');

        $this->assertDatabaseHas('cartes_boisson', [
            'id' => $boisson->id,
            'unites_vendables_par_unite_stock' => '12.0000',
        ]);
    }

    // ------------------------------------------------------------ Les refus

    #[Test]
    public function un_conditionnement_nul_est_refuse_et_nomme(): void
    {
        $boisson = $this->boissonAuCasier('24.0000');

        $this->expectException(RuntimeException::class);

        app(CarteBoissonService::class)->lierAuStock($boisson, $this->casier->id, '0');
    }

    #[Test]
    public function un_article_de_stock_inconnu_est_refuse_avant_la_contrainte(): void
    {
        $boisson = $this->boissonAuCasier('24.0000');

        $this->expectException(RuntimeException::class);

        app(CarteBoissonService::class)->lierAuStock($boisson, (string) Str::uuid(), '24.0000');
    }

    // ------------------------------------------------------------- Côté M4

    #[Test]
    public function un_plat_lie_a_un_article_deduit_selon_son_conditionnement(): void
    {
        $plat = $this->platEau();

        app(CartePlatMenuService::class)->lierAuStock($plat, $this->casier->id, '24.0000');

        $commandes = app(CommandeRestaurantService::class);
        $commande = $commandes->creer([['plat_id' => $plat->id, 'quantite' => 12]]);

        app(MouvementStockService::class)->entree($this->casier->id, $this->cuisine->id, '5.00', 'Dotation');
        $commandes->transmettreEnCuisine($commande);

        // Douze bouteilles = un demi-pack.
        $this->assertSame('4.50', $this->stock->stock($this->casier->id, $this->cuisine->id));
    }

    #[Test]
    public function un_plat_sans_conditionnement_ne_deduit_rien_par_ce_chemin_et_le_dit(): void
    {
        $plat = $this->platEau();

        // Poser l'article SANS son conditionnement est refusé : c'est le seul
        // moyen d'empêcher un lien qui ne dirait pas combien sortir.
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/unités vendables par unité de stock/u');

        app(CartePlatMenuService::class)->modifierPlat($plat, ['article_id' => $this->casier->id]);
    }

    #[Test]
    public function un_conditionnement_sans_article_est_refuse(): void
    {
        $plat = $this->platEau();

        $this->expectException(RuntimeException::class);

        app(CartePlatMenuService::class)->modifierPlat($plat, [
            'unites_vendables_par_unite_stock' => '24.0000',
        ]);
    }

    #[Test]
    public function delier_un_plat_retire_les_DEUX_colonnes_ensemble(): void
    {
        $plat = $this->platEau();
        $service = app(CartePlatMenuService::class);

        $service->lierAuStock($plat, $this->casier->id, '24.0000');
        $delie = $service->delierDuStock($plat);

        $this->assertNull($delie->article_id);
        $this->assertNull($delie->unites_vendables_par_unite_stock);
        $this->assertFalse($delie->aUnLienDirectAuStock());
    }

    // ------------------------------------------------------------- Fixtures

    private function boissonAuCasier(string $unitesParStock): CarteBoisson
    {
        return CarteBoisson::create([
            'article_id' => $this->casier->id,
            'libelle' => 'Béninoise 65cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
            'unites_vendables_par_unite_stock' => $unitesParStock,
        ]);
    }

    private function platEau(): Plat
    {
        $recette = Recette::create(['libelle' => 'Eau en bouteille', 'cout_matiere_calcule' => '0.00']);
        $menu = Menu::create(['libelle' => 'Carte principale', 'type' => 'local']);

        return Plat::create([
            'menu_id' => $menu->id,
            'recette_id' => $recette->id,
            'libelle' => 'Eau minérale 50 cl',
            'prix_vente' => '500.00',
        ]);
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
