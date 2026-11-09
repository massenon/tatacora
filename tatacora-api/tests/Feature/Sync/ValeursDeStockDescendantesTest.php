<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * « Valeur d'achat », CMP et « Valeur stock » vus d'un SECOND poste (bug du PO du
 * 09/11/2026). Le barman (poste A) renseigne les prix d'articles importés SANS
 * prix ; le gérant (poste B) descend le catalogue : il voyait les mêmes stocks
 * et les mêmes seuils mais « — » partout où il fallait un prix, parce que le
 * COÛT de l'entrée ne descendait pas (le poste RECALCULE le CMP en rejouant les
 * mouvements : sans leur coût, il n'a rien à rejouer — piège 11, seconde moitié).
 *
 * Le coût est désormais une colonne du mouvement (`mouvements_stock.cout_unitaire`,
 * écrite par `MouvementStockService::entree`, le seul point d'écriture), et
 * descend avec lui.
 */
final class ValeursDeStockDescendantesTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $barman;

    private User $gerant;

    private PointStockage $bar;

    private Article $cafe;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-11-09 08:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->barman = $this->creerUtilisateur('barman');
        $this->gerant = $this->creerUtilisateur('gerant');
        $this->bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        // Article IMPORTÉ sans prix ni quantité (modèle Excel).
        $this->cafe = app(ReferentielArticleService::class)->creer([
            'libelle' => 'Café double', 'categorie' => 'boisson', 'unite_mesure' => 'tasse',
            'seuil_alerte' => '5.00', 'point_stockage_id' => $this->bar->id,
        ]);
        $this->travelTo('2026-11-09 12:00:00');
    }

    /** @return list<array<string, mixed>> */
    private function mouvementsDescendus(string $poste): array
    {
        Sanctum::actingAs($this->gerant);
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        $elements = [];
        $curseur = null;

        do {
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(
                ['poste_id' => $poste, 'depuis' => $curseur, 'limite' => 500],
                static fn ($v): bool => $v !== null,
            )))->assertOk();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        return array_values(array_filter($elements, static fn (array $e): bool => $e['table'] === 'mouvements_stock'));
    }

    #[Test]
    public function le_cout_de_l_entree_saisie_au_poste_a_descend_au_poste_b(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('mouvements_stock', $id, [
            'article_id' => $this->cafe->id, 'point_id' => $this->bar->id, 'type_mouvement' => 'entree',
            'quantite' => 1500, 'motif' => 'Stock initial', 'date_mouvement' => '2026-11-09 09:00:00',
            'cout_unitaire' => 5000000,
        ])], $this->barman)->assertJsonPath('resultats.0.statut', 'synchronise');

        // Le serveur (et donc le web) a bien les trois valeurs.
        $article = $this->cafe->fresh();
        $this->assertSame('500.00', (string) $article->prix_achat);
        $this->assertSame('500.0000', (string) $article->cout_moyen_pondere);

        $mouvements = $this->mouvementsDescendus('poste-b');
        $this->assertCount(1, $mouvements);
        $this->assertSame('500.0000', $mouvements[0]['donnees']['cout_unitaire'] ?? null, 'le coût de l\'entrée doit descendre avec le mouvement');
    }

    #[Test]
    public function une_sortie_ou_une_entree_non_valorisee_descend_sans_cout(): void
    {
        $this->pousser([$this->creation('mouvements_stock', $this->uuid(), [
            'article_id' => $this->cafe->id, 'point_id' => $this->bar->id, 'type_mouvement' => 'entree',
            'quantite' => 1000, 'motif' => 'Transfert reçu', 'date_mouvement' => '2026-11-09 09:00:00',
        ])], $this->barman)->assertJsonPath('resultats.0.statut', 'synchronise');

        $m = $this->mouvementsDescendus('poste-b');
        $this->assertCount(1, $m);
        $this->assertArrayHasKey('cout_unitaire', $m[0]['donnees']);
        $this->assertNull($m[0]['donnees']['cout_unitaire']);
        $this->assertNull(MouvementStock::query()->firstOrFail()->cout_unitaire);
    }

    #[Test]
    public function la_migration_rattrape_le_cout_des_entrees_deja_acceptees_d_un_poste(): void
    {
        // Une entrée valorisée acceptée AVANT la colonne : le journal de
        // réception porte son coût, le mouvement non.
        $id = $this->uuid();
        $this->pousser([$this->creation('mouvements_stock', $id, [
            'article_id' => $this->cafe->id, 'point_id' => $this->bar->id, 'type_mouvement' => 'entree',
            'quantite' => 1500, 'motif' => 'Stock initial', 'date_mouvement' => '2026-11-09 09:00:00',
            'cout_unitaire' => 5000000,
        ])], $this->barman);
        DB::table('mouvements_stock')->where('id', $id)->update(['cout_unitaire' => null]);

        $migration = require database_path('migrations/2026_11_09_200000_ajouter_cout_unitaire_mouvements_stock.php');
        $migration->up();

        $this->assertSame('500.0000', (string) MouvementStock::findOrFail($id)->cout_unitaire);
    }
}
