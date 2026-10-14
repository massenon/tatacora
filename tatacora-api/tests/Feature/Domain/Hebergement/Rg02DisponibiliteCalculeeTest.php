<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Hebergement;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Events\ReservationAnnulee;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\DisponibiliteService;
use App\Domain\Hebergement\Services\ReservationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * RG-02 — Libération automatique après annulation.
 *
 * Le cas obligatoire de 07_TESTING_QA.md §2 : « annulation d'une réservation
 * libère bien l'unité dans une requête de disponibilité IMMÉDIATEMENT après ».
 * Immédiatement, c'est-à-dire sans job, sans propagation, sans cache à vider.
 */
final class Rg02DisponibiliteCalculeeTest extends TestCase
{
    use RefreshDatabase;

    private DisponibiliteService $disponibilite;

    private ReservationService $reservations;

    private UniteHebergement $unite;

    private string $clientId;

    protected function setUp(): void
    {
        parent::setUp();

        $this->disponibilite = app(DisponibiliteService::class);
        $this->reservations = app(ReservationService::class);

        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow',
            'capacite_max' => 4,
            'tarif_base' => '25000.00',
        ]);

        $this->unite = UniteHebergement::create([
            'categorie_id' => $categorie->id,
            'numero' => 'B-01',
            'statut' => 'libre',
        ]);

        $this->clientId = Client::factory()->create()->id;
    }

    #[Test]
    public function rg02_une_annulation_libere_l_unite_immediatement(): void
    {
        $reservation = $this->reserver('2026-09-01', '2026-09-10');

        $this->assertFalse(
            $this->disponibilite->uniteEstDisponible($this->unite->id, '2026-09-01', '2026-09-10'),
        );

        $this->reservations->annuler($reservation);

        // Aucun job, aucun cache à invalider : la disponibilité est recalculée
        // à chaque interrogation depuis les réservations actives.
        $this->assertTrue(
            $this->disponibilite->uniteEstDisponible($this->unite->id, '2026-09-01', '2026-09-10'),
        );
    }

    #[Test]
    public function rg02_l_unite_annulee_reapparait_dans_la_liste_des_disponibles(): void
    {
        $reservation = $this->reserver('2026-09-01', '2026-09-10');

        $this->assertCount(0, $this->disponibilite->unitesDisponibles('2026-09-01', '2026-09-10'));

        $this->reservations->annuler($reservation);

        $disponibles = $this->disponibilite->unitesDisponibles('2026-09-01', '2026-09-10');
        $this->assertCount(1, $disponibles);
        $this->assertSame($this->unite->id, $disponibles->first()->id);
    }

    #[Test]
    public function rg02_l_annulation_emet_l_evenement_attendu(): void
    {
        Event::fake([ReservationAnnulee::class]);

        $reservation = $this->reserver('2026-09-01', '2026-09-10');
        $this->reservations->annuler($reservation);

        Event::assertDispatched(
            ReservationAnnulee::class,
            fn (ReservationAnnulee $e): bool => $e->reservationId === $reservation->id,
        );
    }

    /**
     * `statut` sur l'unité est un état opérationnel, jamais la disponibilité.
     */
    #[Test]
    public function rg02_le_statut_de_l_unite_n_est_jamais_la_source_de_la_disponibilite(): void
    {
        $this->reserver('2026-09-01', '2026-09-10');

        // L'unité est réservée, alors que son statut opérationnel dit « libre ».
        // Lire `statut` pour répondre à la disponibilité donnerait la mauvaise
        // réponse — c'est exactement l'anti-pattern que RG-02 interdit.
        $this->assertSame('libre', $this->unite->fresh()->statut);
        $this->assertFalse(
            $this->disponibilite->uniteEstDisponible($this->unite->id, '2026-09-02', '2026-09-05'),
        );
    }

    #[Test]
    public function rg02_une_unite_hors_service_n_est_pas_commercialisable_meme_sans_reservation(): void
    {
        $this->unite->update(['statut' => 'hors_service']);

        $this->assertFalse(
            $this->disponibilite->uniteEstDisponible($this->unite->id, '2026-09-01', '2026-09-10'),
        );
        $this->assertCount(0, $this->disponibilite->unitesDisponibles('2026-09-01', '2026-09-10'));
    }

    #[Test]
    public function le_planning_d_occupation_exclut_les_reservations_annulees(): void
    {
        $reservation = $this->reserver('2026-09-01', '2026-09-10');

        $this->assertCount(1, $this->disponibilite->planningOccupation('2026-09-01', '2026-09-30'));

        $this->reservations->annuler($reservation);

        $this->assertCount(0, $this->disponibilite->planningOccupation('2026-09-01', '2026-09-30'));
    }

    /**
     * RG-01 repose désormais sur un verrou applicatif et non sur une contrainte
     * SQL. Ce test vérifie que le verrou est réellement émis : une régression
     * qui le retirerait laisserait tous les autres tests RG-01 au vert, puisque
     * ceux-ci s'exécutent sans concurrence.
     */
    #[Test]
    public function rg01_l_ecriture_emet_bien_un_verrou_pessimiste_en_transaction(): void
    {
        $requetes = [];
        DB::listen(function ($requete) use (&$requetes): void {
            $requetes[] = strtolower($requete->sql);
        });

        $this->reserver('2026-10-01', '2026-10-05');

        $verrous = array_filter(
            $requetes,
            fn (string $sql): bool => str_contains($sql, 'for update')
                && str_contains($sql, 'unites_hebergement'),
        );

        $this->assertNotEmpty(
            $verrous,
            'Aucun SELECT ... FOR UPDATE sur unites_hebergement : le verrou de RG-01 a disparu.',
        );
    }

    private function reserver(string $arrivee, string $depart): \App\Domain\Hebergement\Models\Reservation
    {
        return $this->reservations->creer([
            'client_id' => $this->clientId,
            'unite_id' => $this->unite->id,
            'date_arrivee' => $arrivee,
            'date_depart' => $depart,
            'statut' => 'en_attente',
            'acompte' => '0.00',
        ]);
    }
}
