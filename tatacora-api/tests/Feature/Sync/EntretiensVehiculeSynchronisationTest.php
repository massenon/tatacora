<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Vehicules\Models\EntretienVehicule;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les entretiens et carburations saisis sur un poste (« Immobiliser »,
 * 21/10/2026) : un fait daté, écrit par le service du parc, sans toucher au
 * statut du véhicule, rejoué sans doublon, descendu vers les autres postes.
 */
final class EntretiensVehiculeSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $gerant;

    private Vehicule $vehicule;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-21 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->gerant = $this->creerUtilisateur('gerant');
        $this->vehicule = Vehicule::create(['immatriculation' => 'BJ-77', 'categorie' => 'voiture', 'annee' => 2020, 'tarif_jour' => '25000', 'statut' => 'disponible']);
    }

    #[Test]
    public function l_entretien_du_poste_est_ecrit_sans_toucher_au_statut_et_son_rejeu_ne_double_rien(): void
    {
        $id = $this->uuid();
        $operation = $this->creation('entretiens_vehicule', $id, [
            'vehicule_id' => $this->vehicule->id, 'type' => 'entretien', 'date' => '2026-10-20', 'cout' => 15000,
        ]);

        $this->pousser([$operation], $this->gerant)->assertJsonPath('resultats.0.statut', 'synchronise');

        $e = EntretienVehicule::findOrFail($id);
        $this->assertSame(['entretien', '2026-10-20', '15000.00'], [$e->type, $e->date->toDateString(), (string) $e->cout]);
        $this->assertSame('disponible', $this->vehicule->refresh()->statut);

        $this->pousser([$operation], $this->gerant)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(1, EntretienVehicule::query()->count());
    }

    #[Test]
    public function les_cas_invalides_sont_refuses_et_le_droit_est_celui_de_m8(): void
    {
        foreach ([
            ['vehicule_id' => $this->vehicule->id, 'type' => 'panne', 'date' => '2026-10-20', 'cout' => 1],
            ['vehicule_id' => $this->vehicule->id, 'type' => 'entretien', 'date' => '20/10/2026', 'cout' => 1],
            ['vehicule_id' => $this->vehicule->id, 'type' => 'entretien', 'date' => '2026-10-20', 'cout' => -5],
            ['vehicule_id' => $this->uuid(), 'type' => 'entretien', 'date' => '2026-10-20', 'cout' => 1],
        ] as $payload) {
            $this->pousser([$this->creation('entretiens_vehicule', $this->uuid(), $payload)], $this->gerant)
                ->assertJsonPath('resultats.0.statut', 'rejete');
        }

        $sansDroit = $this->creerUtilisateur('cuisine');
        $this->pousser([$this->creation('entretiens_vehicule', $this->uuid(), [
            'vehicule_id' => $this->vehicule->id, 'type' => 'entretien', 'date' => '2026-10-20', 'cout' => 1,
        ])], $sansDroit)->assertJsonPath('resultats.0.statut', 'rejete');

        $this->assertSame(0, EntretienVehicule::query()->count());
    }

    #[Test]
    public function une_modification_est_refusee_et_l_entretien_descend_vers_les_autres_postes(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('entretiens_vehicule', $id, [
            'vehicule_id' => $this->vehicule->id, 'type' => 'carburation', 'date' => '2026-10-19', 'cout' => 8000,
        ])], $this->gerant, 'poste-a');

        $this->pousser([$this->operation('entretiens_vehicule', 'modification', $id, ['cout' => 1])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'rejete');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($this->gerant);
        $elements = [];
        $curseur = null;

        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        $ligne = collect($elements)->firstWhere('table', 'entretiens_vehicule');
        $this->assertSame($id, $ligne['id']);
        $this->assertSame(['carburation', '8000.00'], [$ligne['donnees']['type'], $ligne['donnees']['cout']]);
        $this->assertSame($this->vehicule->id, $ligne['donnees']['vehicule_id']);
    }
}
