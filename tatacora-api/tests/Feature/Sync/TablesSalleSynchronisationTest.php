<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\TableSalle;
use App\Domain\Ventes\Services\PanierService;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * L'arbitrage des tables de salle entre postes — lot F6, décision du PO du
 * 18/10/2026 (« il faut le créer »). Le plan se synchronise (clé naturelle
 * espace + numéro) ; l'occupation est un panier ouvert, inscrit sous verrou :
 * deux postes n'ouvrent jamais la même table.
 */
final class TablesSalleSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $admin;

    private User $barman;

    private TableSalle $r1;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->admin = $this->creerUtilisateur('administrateur');
        $this->barman = $this->creerUtilisateur('barman');
        $this->r1 = TableSalle::create(['espace' => 'restaurant', 'numero' => 1, 'libelle' => 'R1', 'places' => 4, 'actif' => true]);
    }

    /**
     * @return array<string, mixed>
     */
    private function ouverture(string $id, string $tableId): array
    {
        return $this->creation('paniers', $id, ['point_vente' => 'Restaurant', 'table_id' => $tableId]);
    }

    #[Test]
    public function une_table_creee_sur_un_poste_est_ecrite_et_un_doublon_fusionne(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->creation('tables_salle', $id, ['espace' => 'jardin', 'numero' => 3, 'places' => 6])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('J3', TableSalle::findOrFail($id)->libelle);

        $this->pousser([$this->creation('tables_salle', $this->uuid(), ['espace' => 'restaurant', 'numero' => 1])], $this->admin)
            ->assertJsonPath('resultats.0.fusionne_avec', $this->r1->id);

        $this->pousser([$this->operation('tables_salle', 'modification', $id, ['numero' => 5, 'places' => 8])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $t = TableSalle::findOrFail($id);
        $this->assertSame(['J5', 8], [$t->libelle, (int) $t->places]);

        // Un barman n'administre pas le plan.
        $this->pousser([$this->creation('tables_salle', $this->uuid(), ['espace' => 'plage', 'numero' => 1])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete');
    }

    #[Test]
    public function deux_postes_n_ouvrent_jamais_la_meme_table(): void
    {
        [$a, $b] = [$this->uuid(), $this->uuid()];

        $this->pousser([$this->ouverture($a, $this->r1->id)], $this->barman, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$this->ouverture($b, $this->r1->id)], $this->barman, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.tables.occupee', ['libelle' => 'R1']));

        // La PWA voit la table occupée.
        $this->assertTrue(app(\App\Domain\Ventes\Services\TableSalleService::class)->estOccupee($this->r1->id));

        // A libère ; B peut alors l'ouvrir. La fermeture d'une ouverture
        // refusée passe sans rien écrire.
        $this->pousser([$this->operation('paniers', 'modification', $a, ['statut' => 'cloture'])], $this->barman, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$this->operation('paniers', 'modification', $b, ['statut' => 'cloture'])], $this->barman, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$this->ouverture($this->uuid(), $this->r1->id)], $this->barman, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(1, Panier::query()->where('statut', 'ouvert')->count());
    }

    #[Test]
    public function une_table_ouverte_a_la_pwa_est_refusee_au_poste(): void
    {
        app(PanierService::class)->ouvrirPourPoste('Restaurant', $this->r1->id);

        $this->pousser([$this->ouverture($this->uuid(), $this->r1->id)], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete');
    }

    #[Test]
    public function le_plan_et_l_occupation_descendent_seulement_les_paniers_de_table(): void
    {
        $a = $this->uuid();
        $this->pousser([$this->ouverture($a, $this->r1->id)], $this->barman, 'poste-a');
        app(PanierService::class)->ouvrirPourPoste('Bar', null);

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($this->barman);
        $elements = [];
        $curseur = null;

        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        $parTable = collect($elements)->groupBy('table');
        $this->assertSame([$this->r1->id], $parTable['tables_salle']->pluck('id')->all());
        $this->assertSame([$a], $parTable['paniers']->pluck('id')->all());
        $this->assertSame('ouvert', $parTable['paniers'][0]['donnees']['statut']);
        $this->assertSame('poste-a', $parTable['paniers'][0]['poste_origine']);
    }
}
