<?php

declare(strict_types=1);

namespace Tests\Feature\ProcessusMetiers;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
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
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Processus métier n°3 — Restauration.
 *
 * « Élaboration menu/recette (M4) → Prise de commande → Vérification
 * disponibilité ingrédients (M6) → Bon de cuisine → Préparation/service →
 * Clôture → Facturation » (05_MODULE_SPECIFICATIONS.md §5).
 *
 * Traverse M4 → M6 → M2. C'est exactement le chemin que
 * `07_TESTING_QA.md` §8 cite : un changement dans M6 casserait ce processus
 * sans qu'aucun test de M6 ne le détecte.
 */
final class RestaurationTest extends TestCase
{
    use RefreshDatabase;

    private PointStockage $cuisine;

    private Article $riz;

    private Article $poulet;

    private Plat $plat;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs($this->utilisateur('cuisine'));

        $this->cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);
        $this->riz = $this->article('Riz', 'kg');
        $this->poulet = $this->article('Poulet', 'kg');
        $this->client = Client::factory()->create();

        // --- Élaboration de la fiche technique (M4)
        $recette = Recette::create(['libelle' => 'Poulet DG', 'cout_matiere_calcule' => '0.00']);
        $recette->ingredients()->attach([
            $this->riz->id => ['quantite_unitaire' => '0.250'],
            $this->poulet->id => ['quantite_unitaire' => '0.400'],
        ]);

        $menu = Menu::create(['libelle' => 'Carte principale', 'type' => 'local']);
        $this->plat = Plat::create([
            'menu_id' => $menu->id, 'recette_id' => $recette->id,
            'libelle' => 'Poulet DG', 'prix_vente' => '4500.00',
        ]);

        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($this->riz->id, $this->cuisine->id, '10.00', 'Réception');
        $mouvements->entree($this->poulet->id, $this->cuisine->id, '4.00', 'Réception');
    }

    #[Test]
    public function le_cycle_va_de_la_commande_a_la_facturation(): void
    {
        $commandes = app(CommandeRestaurantService::class);
        $stock = app(StockTheoriqueService::class);

        // --- 1. Prise de commande (M4) — aucun stock engagé
        $commande = $commandes->creer(
            [['plat_id' => $this->plat->id, 'quantite' => 4]],
            clientId: $this->client->id,
            tableOuChambreId: null,
        );

        $this->assertSame('10.00', $stock->stock($this->riz->id, $this->cuisine->id));

        // --- 2. Transmission cuisine : vérification disponibilité + déduction (M6)
        $commandes->transmettreEnCuisine($commande);

        // 4 portions : riz 10 − 1,00 ; poulet 4 − 1,60
        $this->assertSame('9.00', $stock->stock($this->riz->id, $this->cuisine->id));
        $this->assertSame('2.40', $stock->stock($this->poulet->id, $this->cuisine->id));

        // --- 3. Service
        $servie = $commandes->marquerServie($commande->fresh());
        $this->assertSame('servie', $servie->statut);

        // --- 4. Facturation (M2), rattachée au module d'origine (RG-04)
        $emission = app(EmissionFactureService::class);
        $facture = $emission->emettrePourReservation($this->reservation(), '25000.00');
        $emission->ajouterLigne($facture, 'M4', $commande->id, 'Poulet DG ×4', '4.00', '4500.00');

        $facture->refresh();
        $ligneRestaurant = $facture->lignes()->where('source_module', 'M4')->sole();

        // La ligne pointe vers la commande réelle : sans cette traçabilité, un
        // litige sur une facture consolidée serait invérifiable.
        $this->assertSame($commande->id, $ligneRestaurant->source_id);
        $this->assertSame('18000.00', $ligneRestaurant->montant);
    }

    /**
     * La rupture de chaîne critique : un ingrédient manquant doit remonter
     * jusqu'à la prise de commande, pas se découvrir en cuisine.
     */
    #[Test]
    public function une_rupture_d_ingredient_empeche_la_transmission_et_ne_laisse_aucune_trace(): void
    {
        $commandes = app(CommandeRestaurantService::class);
        $stock = app(StockTheoriqueService::class);

        // 11 portions demandent 4,40 kg de poulet ; il n'y en a que 4.
        $commande = $commandes->creer([['plat_id' => $this->plat->id, 'quantite' => 11]]);

        $this->assertThrows(
            fn () => $commandes->transmettreEnCuisine($commande),
            RuptureStockException::class,
        );

        // Le riz, pourtant suffisant et traité en premier, n'a pas bougé : la
        // transaction a tout annulé. Une déduction partielle laisserait un
        // stock faux que seul l'inventaire révélerait.
        $this->assertSame('10.00', $stock->stock($this->riz->id, $this->cuisine->id));
        $this->assertSame('4.00', $stock->stock($this->poulet->id, $this->cuisine->id));
        $this->assertSame('en_preparation', $commande->fresh()->statut);
    }

    /**
     * Le lien M4 → M6 doit être solidaire : si M6 refuse, M4 n'avance pas.
     * C'est précisément la régression inter-domaines visée par §8.
     */
    #[Test]
    public function une_commande_non_transmise_reste_annulable_sans_effet_sur_le_stock(): void
    {
        $commandes = app(CommandeRestaurantService::class);

        $commande = $commandes->creer([['plat_id' => $this->plat->id, 'quantite' => 2]]);
        $commandes->annuler($commande);

        $this->assertSame('annulee', $commande->fresh()->statut);
        $this->assertSame(
            '10.00',
            app(StockTheoriqueService::class)->stock($this->riz->id, $this->cuisine->id),
        );

        // Après transmission en revanche, les denrées sont engagées :
        // l'annulation devient une perte à constater.
        $seconde = $commandes->creer([['plat_id' => $this->plat->id, 'quantite' => 2]]);
        $commandes->transmettreEnCuisine($seconde);

        $this->expectException(\RuntimeException::class);
        $commandes->annuler($seconde->fresh());
    }

    private function reservation(): \App\Domain\Hebergement\Models\Reservation
    {
        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow', 'capacite_max' => 4, 'tarif_base' => '25000.00',
        ]);
        $unite = UniteHebergement::create([
            'categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre',
        ]);

        return app(ReservationService::class)->creer([
            'client_id' => $this->client->id, 'unite_id' => $unite->id,
            'date_arrivee' => '2026-09-01', 'date_depart' => '2026-09-04',
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);
    }

    private function article(string $libelle, string $unite): Article
    {
        return Article::create([
            'libelle' => $libelle, 'categorie' => 'denree', 'unite_mesure' => $unite,
            'seuil_alerte' => '2.00', 'seuil_reappro' => '5.00', 'cout_moyen_pondere' => '1000.0000',
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
