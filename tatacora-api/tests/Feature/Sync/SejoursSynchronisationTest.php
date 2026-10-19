<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\Sejour;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * L'arrivée et le départ réels saisis sur un poste — lot F5, décision du
 * Product Owner du 17/10/2026. Par `SejourService` : la réservation et
 * l'unité suivent, l'heure est celle du POSTE, deux postes ne pointent pas
 * deux fois la même arrivée ; et le séjour descend vers les autres postes.
 */
final class SejoursSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $receptionniste;

    private Reservation $reservation;

    private UniteHebergement $unite;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-17 12:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->receptionniste = $this->creerUtilisateur('receptionniste');
        $categorie = CategorieHebergement::create(['libelle' => 'Bungalow', 'capacite_max' => 2, 'tarif_base' => '25000.00']);
        $this->unite = UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre']);
        $client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'groupe']);
        $this->reservation = app(ReservationService::class)->creer([
            'client_id' => $client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-10-17', 'date_depart' => '2026-10-19',
        ]);
    }

    #[Test]
    public function l_arrivee_puis_le_depart_du_poste_passent_par_le_service_a_l_heure_du_poste(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->creation('sejours', $id, [
            'reservation_id' => $this->reservation->id, 'date_checkin_reel' => '2026-10-17 10:15:00', 'occupants' => [],
        ])], $this->receptionniste, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');

        $sejour = Sejour::findOrFail($id);
        $this->assertSame('2026-10-17 10:15:00', $sejour->date_checkin_reel->format('Y-m-d H:i:s'));
        $this->assertSame('en_cours', $this->reservation->refresh()->statut);
        $this->assertSame('occupee', $this->unite->refresh()->statut);

        $this->pousser([$this->operation('sejours', 'modification', $id, ['date_checkout_reel' => '2026-10-19 09:40:00'])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame('2026-10-19 09:40:00', $sejour->refresh()->date_checkout_reel->format('Y-m-d H:i:s'));
        $this->assertSame('terminee', $this->reservation->refresh()->statut);
        $this->assertSame('nettoyage', $this->unite->refresh()->statut);
    }

    #[Test]
    public function deux_postes_ne_pointent_pas_deux_fois_la_meme_arrivee(): void
    {
        $arrivee = fn (): array => $this->creation('sejours', $this->uuid(), [
            'reservation_id' => $this->reservation->id, 'date_checkin_reel' => '2026-10-17 10:15:00',
        ]);

        $this->pousser([$arrivee()], $this->receptionniste, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$arrivee()], $this->receptionniste, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete');

        $this->assertSame(1, Sejour::count());
    }

    #[Test]
    public function le_sejour_descend_vers_les_autres_postes(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('sejours', $id, [
            'reservation_id' => $this->reservation->id, 'date_checkin_reel' => '2026-10-17 10:15:00',
        ])], $this->receptionniste, 'poste-a');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($this->receptionniste);
        $elements = collect($this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-b', 'limite' => 500]))
            ->assertOk()->json('data.elements'))->keyBy('id');

        $this->assertSame('sejours', $elements[$id]['table']);
        $this->assertSame('poste-a', $elements[$id]['poste_origine']);
        $this->assertSame($this->reservation->id, $elements[$id]['donnees']['reservation_id']);
        $this->assertNull($elements[$id]['donnees']['date_checkout_reel']);
    }

    #[Test]
    public function un_rejeu_de_l_arrivee_et_du_depart_ne_refait_rien(): void
    {
        $id = $this->uuid();
        $creation = $this->creation('sejours', $id, ['reservation_id' => $this->reservation->id, 'date_checkin_reel' => '2026-10-17 10:15:00']);
        $depart = $this->operation('sejours', 'modification', $id, ['date_checkout_reel' => '2026-10-19 09:40:00']);

        $this->pousser([$creation, $depart], $this->receptionniste);
        $this->pousser([$this->nouvelle($creation), $this->nouvelle($depart)], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise');

        $this->assertSame(1, Sejour::count());
        $this->assertSame('2026-10-19 09:40:00', Sejour::findOrFail($id)->date_checkout_reel->format('Y-m-d H:i:s'));
    }

    /**
     * @param  array<string, mixed>  $operation
     * @return array<string, mixed>
     */
    private function nouvelle(array $operation): array
    {
        return [...$operation, 'uuid_operation' => $this->uuid(), 'horodatage_client' => now()->addMinute()->toIso8601String()];
    }
}
