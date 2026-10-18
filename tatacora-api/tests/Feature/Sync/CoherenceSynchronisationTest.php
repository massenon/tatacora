<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le contrôle de cohérence (P1-1) : par table et par jour MÉTIER, le nombre
 * de documents actifs et leur total en centimes ; seules les tables que le
 * compte lit ; une fenêtre bornée.
 */
final class CoherenceSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-18 10:00:00');
        $this->seed(RolePermissionSeeder::class);
    }

    private function vente(string $jour, string $montant, string $statut = 'validee'): void
    {
        DB::table('ventes')->insert([
            'id' => (string) Str::uuid(), 'numero' => 'V-'.Str::random(6), 'point_vente' => 'Bar',
            'montant_total' => $montant, 'mode_paiement' => 'especes', 'statut' => $statut,
            'created_at' => $jour.' 09:00:00', 'updated_at' => now(), 'date_creation' => now(),
        ]);
    }

    #[Test]
    public function les_comptes_par_jour_metier_et_par_table_lisible(): void
    {
        $this->vente('2026-10-17', '3000.00');
        $this->vente('2026-10-17', '1500.50');
        $this->vente('2026-10-17', '9999.00', 'annulee');
        $this->vente('2026-10-18', '2000.00');

        Sanctum::actingAs($this->creerUtilisateur('barman'));
        $r = $this->getJson('/api/v1/sync/coherence?du=2026-10-16&au=2026-10-18')->assertOk();

        $r->assertJsonPath('data.tables.ventes.2026-10-17', ['nombre' => 2, 'total' => 450050])
            ->assertJsonPath('data.tables.ventes.2026-10-18', ['nombre' => 1, 'total' => 200000]);
        $this->assertArrayNotHasKey('depenses', $r->json('data.tables'), 'le barman ne lit pas M10');
        $this->assertArrayNotHasKey('2026-10-16', $r->json('data.tables.ventes'));
    }

    #[Test]
    public function la_fenetre_est_bornee(): void
    {
        Sanctum::actingAs($this->creerUtilisateur('administrateur'));
        $this->getJson('/api/v1/sync/coherence?du=2026-08-01&au=2026-10-18')->assertUnprocessable();
        $this->getJson('/api/v1/sync/coherence?du=2026-10-18&au=2026-10-01')->assertUnprocessable();
    }
}
