<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Bar;

use App\Domain\Bar\Models\CarteBoisson;
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
 * `PUT /api/v1/bar/boissons/{boisson}/lien-stock` — « Lier au stock » par
 * l'API, l'article ET son conditionnement (11/09/2026).
 *
 * ## Ce que ces cas protègent
 *
 * **Que le conditionnement ne soit jamais séparé du lien.** C'est le défaut
 * que la PWA a fermé : la valeur était saisie, prévisualisée, puis jetée, et
 * un casier de 24 décrémentait comme une bouteille. Un lien écrit sans elle,
 * ou avec un 1 inventé, le rouvrirait.
 *
 * **Que le chemin soit celui de la PWA** — `CarteBoissonService::lierAuStock()`
 * — et donc que ses refus reviennent en 422 sur le bon champ, jamais en 500.
 *
 * @see EF-M5-02 Carte des boissons
 * @see RG-05 Sortie de stock automatique
 */
final class LienStockBoissonApiTest extends TestCase
{
    use RefreshDatabase;

    private Article $bouteille;

    private Article $casier;

    private CarteBoisson $biere;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->bouteille = $this->article('Béninoise 66 cl — bouteille', 'bouteille');
        $this->casier = $this->article('Béninoise 66 cl — casier de 24', 'casier');

        $this->biere = CarteBoisson::create([
            'article_id' => $this->bouteille->id,
            'libelle' => 'Béninoise 66 cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
        ]);
    }

    #[Test]
    public function le_lien_et_son_conditionnement_s_ecrivent_ensemble(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->putJson($this->url(), [
            'article_id' => $this->casier->id,
            'unites_vendables_par_unite_stock' => '24',
        ])
            ->assertOk()
            ->assertJsonPath('data.article_id', $this->casier->id)
            ->assertJsonPath('data.unites_vendables_par_unite_stock', '24.0000');

        $this->biere->refresh();
        $this->assertSame($this->casier->id, $this->biere->article_id);
        $this->assertSame('24.0000', (string) $this->biere->unites_vendables_par_unite_stock);
    }

    #[Test]
    public function la_ressource_expose_le_conditionnement_enregistre(): void
    {
        // Sans lui, un client rouvrirait la modale sur 1, et un casier de 24
        // décrémenterait vingt-quatre fois trop (`ouvrirLienAuStock()`).
        $this->biere->update(['unites_vendables_par_unite_stock' => '24']);
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->getJson('/api/v1/bar/boissons/' . $this->biere->id)
            ->assertOk()
            ->assertJsonPath('data.unites_vendables_par_unite_stock', '24.0000');
    }

    #[Test]
    public function un_conditionnement_absent_est_refuse_jamais_remplace_par_un(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->putJson($this->url(), ['article_id' => $this->casier->id])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('unites_vendables_par_unite_stock');

        // Le lien n'a PAS bougé : un lien sans son conditionnement est le défaut.
        $this->assertSame($this->bouteille->id, $this->biere->refresh()->article_id);
    }

    #[Test]
    public function un_conditionnement_nul_est_refuse(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->putJson($this->url(), [
            'article_id' => $this->casier->id,
            'unites_vendables_par_unite_stock' => '0',
        ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('unites_vendables_par_unite_stock');
    }

    #[Test]
    public function un_article_inconnu_est_refuse_sur_son_champ(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->putJson($this->url(), [
            'article_id' => (string) Str::uuid(),
            'unites_vendables_par_unite_stock' => '24',
        ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('article_id');
    }

    #[Test]
    public function rg16_un_role_en_lecture_sur_m5_ne_peut_pas_lier(): void
    {
        // Le réceptionniste est en `L` sur M5 : il lit la carte, il ne la
        // modifie pas.
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->putJson($this->url(), [
            'article_id' => $this->casier->id,
            'unites_vendables_par_unite_stock' => '24',
        ])->assertForbidden();

        $this->assertSame($this->bouteille->id, $this->biere->refresh()->article_id);
    }

    private function url(): string
    {
        return '/api/v1/bar/boissons/' . $this->biere->id . '/lien-stock';
    }

    private function article(string $libelle, string $unite): Article
    {
        return Article::create([
            'libelle' => $libelle,
            'categorie' => 'boisson',
            'unite_mesure' => $unite,
            'seuil_alerte' => '10.00',
            'cout_moyen_pondere' => '450.0000',
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
