<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Tourisme\Models\ReservationTour;
use App\Models\User;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le tourisme en synchronisation — lot F4, décision du Product Owner du
 * 17/10/2026 (« les activités et réservations liées au tourisme … en
 * synchronisation »). Circuits et guides suivent les règles du catalogue ;
 * la réservation passe par `ReservationTourService` : capacité cumulée et
 * guide exclusif, arbitrés par le serveur entre plusieurs postes.
 */
final class TourismeSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $guide;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        // `guide` : M9 = 'C', M3 = 'L'.
        $this->guide = $this->creerUtilisateur('guide');
        $this->client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'groupe']);
    }

    #[Test]
    public function circuit_guide_et_reservation_d_un_poste_sont_ecrits_par_leurs_regles(): void
    {
        [$circuit, $guide, $resa] = [$this->uuid(), $this->uuid(), $this->uuid()];

        $this->pousser([
            $this->creation('circuits', $circuit, [
                'nom' => 'Chutes de Kota', 'theme' => 'nature', 'zone' => 'Atacora', 'duree' => null,
                'prix' => '15000.00', 'capacite_max' => 8,
            ]),
            $this->creation('guides', $guide, ['nom' => 'Moussa', 'zone_competence' => 'Atacora']),
            $this->creation('reservations_tour', $resa, [
                'circuit_id' => $circuit, 'client_id' => $this->client->id, 'guide_id' => $guide,
                'date_circuit' => '2026-10-20', 'nb_participants' => 4,
            ]),
        ], $this->guide, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.2.statut', 'synchronise');

        // Durée absente → vide (« indéterminée » pour le service).
        $this->assertSame('', Circuit::findOrFail($circuit)->duree);
        // Le tarif du guide n'est pas saisi au poste : 0, et SIGNALÉ.
        $this->assertSame('0.00', (string) Guide::findOrFail($guide)->tarif_jour);
        $this->assertTrue(AnomalieSynchronisation::query()
            ->where('entite_id', $guide)->where('type', AnomalieSynchronisation::GUIDE_SANS_TARIF)->exists());

        $this->assertSame('reservee', ReservationTour::findOrFail($resa)->statut);

        // Le poste d'origine est retenu (lot F4).
        $this->assertDatabaseHas('origines_synchronisation', ['table_concernee' => 'reservations_tour', 'entite_id' => $resa, 'poste_id' => 'poste-a']);
    }

    /**
     * Deux postes vendent hors ligne les dernières places du même départ : le
     * second est refusé avec la phrase du service — jamais un départ au-delà
     * de sa capacité.
     */
    #[Test]
    public function la_capacite_du_depart_est_arbitree_entre_deux_postes(): void
    {
        $circuit = Circuit::create(['nom' => 'Pendjari', 'theme' => 'faune', 'zone' => 'Nord', 'duree' => '1 jour', 'prix' => '30000', 'capacite_max' => 6]);
        $guide = Guide::create(['nom' => 'Issa', 'tarif_jour' => '10000']);

        $reservation = fn (int $n): array => $this->creation('reservations_tour', $this->uuid(), [
            'circuit_id' => $circuit->id, 'client_id' => $this->client->id, 'guide_id' => $guide->id,
            'date_circuit' => '2026-10-21', 'nb_participants' => $n,
        ]);

        $this->pousser([$reservation(4)], $this->guide, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');
        $refus = $this->pousser([$reservation(4)], $this->guide, 'poste-b')->assertJsonPath('resultats.0.statut', 'rejete');

        $this->assertNotEmpty($refus->json('resultats.0.motif'));
        $this->assertSame(4, (int) ReservationTour::query()->sum('nb_participants'));
    }

    #[Test]
    public function l_annulation_et_la_reaffectation_passent_par_le_service(): void
    {
        $circuit = Circuit::create(['nom' => 'Tanéka', 'theme' => 'culture', 'zone' => 'Copargo', 'duree' => '1 jour', 'prix' => '20000', 'capacite_max' => 10]);
        $issa = Guide::create(['nom' => 'Issa', 'tarif_jour' => '10000']);
        $awa = Guide::create(['nom' => 'Awa', 'tarif_jour' => '10000']);
        $id = $this->uuid();

        $this->pousser([$this->creation('reservations_tour', $id, [
            'circuit_id' => $circuit->id, 'client_id' => $this->client->id, 'guide_id' => $issa->id,
            'date_circuit' => '2026-10-22', 'nb_participants' => 2,
        ])], $this->guide);

        $this->pousser([$this->operation('reservations_tour', 'modification', $id, ['guide_id' => $awa->id])], $this->guide)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame($awa->id, ReservationTour::findOrFail($id)->guide_id);

        $this->pousser([$this->operation('reservations_tour', 'modification', $id, ['statut' => 'annulee'])], $this->guide)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('annulee', ReservationTour::findOrFail($id)->statut);

        // Tout autre champ : refusé (l'API n'offre aucune modification générique).
        $this->pousser([$this->operation('reservations_tour', 'modification', $id, ['nb_participants' => 9])], $this->guide)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.modification_non_synchronisable'));
    }

    #[Test]
    public function un_circuit_du_meme_nom_fusionne_au_lieu_de_se_doubler(): void
    {
        $existant = Circuit::create(['nom' => 'Chutes de Kota', 'theme' => 'nature', 'zone' => 'Atacora', 'duree' => '1 jour', 'prix' => '15000', 'capacite_max' => 8]);

        $this->pousser([$this->creation('circuits', $this->uuid(), [
            'nom' => 'chutes de KOTA ', 'theme' => 'nature', 'zone' => 'Atacora', 'prix' => '15000', 'capacite_max' => 8,
        ])], $this->guide)->assertJsonPath('resultats.0.fusionne_avec', $existant->id);

        $this->assertSame(1, Circuit::count());
    }
}
