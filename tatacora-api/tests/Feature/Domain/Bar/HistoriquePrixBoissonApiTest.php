<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Bar;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * `GET /api/v1/bar/boissons/{boisson}/historique-prix` — l'historique des
 * prix d'une boisson par l'API (11/09/2026).
 *
 * ## Ce que ces cas protègent
 *
 * **Que la trace rendue soit celle que l'Observer a écrite** : le prix est
 * changé par le SERVICE, comme en production, et jamais inséré à la main dans
 * `historique_prix_carte` — une trace fabriquée par le test prouverait
 * seulement que la route sait lire ce que le test a écrit.
 *
 * **Que la lecture reste une lecture** : `L` sur M5 suffit, comme dans la PWA.
 *
 * @see EF-M5-02 Carte des boissons
 */
final class HistoriquePrixBoissonApiTest extends TestCase
{
    use RefreshDatabase;

    private CarteBoisson $biere;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $article = Article::create([
            'libelle' => 'Béninoise 66 cl — bouteille',
            'categorie' => 'boisson',
            'unite_mesure' => 'bouteille',
            'seuil_alerte' => '10.00',
            'cout_moyen_pondere' => '450.0000',
        ]);

        $this->biere = CarteBoisson::create([
            'article_id' => $article->id,
            'libelle' => 'Béninoise 66 cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
        ]);
    }

    #[Test]
    public function les_changements_de_prix_reviennent_du_plus_recent_au_plus_ancien(): void
    {
        $barman = $this->utilisateur('barman');
        $this->actingAs($barman);
        app(CarteBoissonService::class)->modifier($this->biere, ['prix_vente' => '1200.00']);
        $this->travel(1)->minutes();
        app(CarteBoissonService::class)->modifier($this->biere->refresh(), ['prix_vente' => '1500.00']);

        Sanctum::actingAs($barman);
        $donnees = $this->getJson($this->url())->assertOk()->json('data');
        $this->assertIsArray($donnees);
        $traces = collect($donnees)->where('champ', 'prix_vente')->values();

        $this->assertCount(2, $traces);
        // Le plus récent d'abord : c'est la question qu'on pose au comptoir.
        $this->assertSame('1200.00', $traces[0]['ancien_prix']);
        $this->assertSame('1500.00', $traces[0]['nouveau_prix']);
        $this->assertSame('1000.00', $traces[1]['ancien_prix']);
        $this->assertSame('1200.00', $traces[1]['nouveau_prix']);
        // La colonne « Par » : l'auteur du changement, pas le lecteur.
        $this->assertSame($barman->login, $traces[0]['par']);
    }

    #[Test]
    public function une_boisson_jamais_modifiee_rend_une_liste_vide(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->getJson($this->url())->assertOk()->assertJsonCount(0, 'data');
    }

    #[Test]
    public function un_role_en_lecture_sur_m5_peut_consulter(): void
    {
        // Comme `ouvrirHistoriquePrix()` : consulter une trace n'écrit rien.
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->getJson($this->url())->assertOk();
    }

    #[Test]
    public function rg16_un_role_sans_acces_a_m5_ne_consulte_pas(): void
    {
        // La cuisine n'a aucun droit sur M5.
        Sanctum::actingAs($this->utilisateur('cuisine'));

        $this->getJson($this->url())->assertForbidden();
    }

    private function url(): string
    {
        return '/api/v1/bar/boissons/' . $this->biere->id . '/historique-prix';
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
