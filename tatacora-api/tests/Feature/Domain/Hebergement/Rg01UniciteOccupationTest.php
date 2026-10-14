<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Hebergement;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * RG-01 — Unicité d'occupation d'une unité d'hébergement.
 *
 * Les quatre cas de 07_TESTING_QA.md §2 sont obligatoires avant toute mise en
 * recette : chevauchement total, chevauchement partiel (début et fin),
 * réservation adjacente valide (pas de faux positif), réservation annulée
 * ignorée. Ils sont tous couverts ici.
 *
 * Enjeu particulier depuis la bascule MySQL : la garantie n'est plus une
 * contrainte SQL déclarative mais du code applicatif. Ces tests sont donc la
 * seule chose qui prouve qu'elle fonctionne réellement.
 */
final class Rg01UniciteOccupationTest extends TestCase
{
    use RefreshDatabase;

    private ReservationService $service;

    private string $uniteId;

    private string $clientId;

    protected function setUp(): void
    {
        parent::setUp();

        $this->service = app(ReservationService::class);

        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow',
            'capacite_max' => 4,
            'tarif_base' => '25000.00',
        ]);

        $this->uniteId = UniteHebergement::create([
            'categorie_id' => $categorie->id,
            'numero' => 'B-01',
            'statut' => 'libre',
        ])->id;

        $this->clientId = Client::factory()->create()->id;
    }

    #[Test]
    public function rg01_un_chevauchement_total_est_rejete(): void
    {
        $this->reserver('2026-09-01', '2026-09-10');

        $this->expectException(ChevauchementDetecteException::class);
        $this->reserver('2026-09-01', '2026-09-10');
    }

    #[Test]
    public function rg01_un_chevauchement_partiel_sur_le_debut_est_rejete(): void
    {
        $this->reserver('2026-09-05', '2026-09-10');

        // Arrive avant, repart pendant le séjour existant.
        $this->expectException(ChevauchementDetecteException::class);
        $this->reserver('2026-09-01', '2026-09-07');
    }

    #[Test]
    public function rg01_un_chevauchement_partiel_sur_la_fin_est_rejete(): void
    {
        $this->reserver('2026-09-05', '2026-09-10');

        // Arrive pendant le séjour existant, repart après.
        $this->expectException(ChevauchementDetecteException::class);
        $this->reserver('2026-09-08', '2026-09-15');
    }

    #[Test]
    public function rg01_une_reservation_englobante_est_rejetee(): void
    {
        $this->reserver('2026-09-05', '2026-09-08');

        $this->expectException(ChevauchementDetecteException::class);
        $this->reserver('2026-09-01', '2026-09-15');
    }

    /**
     * Le faux positif à ne surtout pas produire : un départ le 4 et une arrivée
     * le 4 sont parfaitement valides — l'unité est libérée le matin, réoccupée
     * le soir. Une erreur de bornes (>= au lieu de >) refuserait des
     * réservations légitimes tous les jours, et le gîte perdrait des nuitées.
     */
    #[Test]
    public function rg01_une_reservation_adjacente_est_acceptee(): void
    {
        $premiere = $this->reserver('2026-09-01', '2026-09-04');
        $seconde = $this->reserver('2026-09-04', '2026-09-08');

        $this->assertNotSame($premiere->id, $seconde->id);
        $this->assertSame(2, Reservation::count());
    }

    #[Test]
    public function rg01_une_reservation_annulee_est_ignoree_dans_le_calcul(): void
    {
        $annulee = $this->reserver('2026-09-01', '2026-09-10');
        $this->service->annuler($annulee);

        // RG-02 : l'unité est libérée, la même période redevient réservable
        // sans qu'aucun traitement n'ait eu à propager quoi que ce soit.
        $nouvelle = $this->reserver('2026-09-01', '2026-09-10');

        $this->assertSame('annulee', $annulee->fresh()->statut);
        $this->assertSame('en_attente', $nouvelle->statut);
    }

    #[Test]
    public function rg01_une_autre_unite_sur_la_meme_periode_reste_libre(): void
    {
        $this->reserver('2026-09-01', '2026-09-10');

        $autreUnite = UniteHebergement::create([
            'categorie_id' => CategorieHebergement::first()->id,
            'numero' => 'B-02',
            'statut' => 'libre',
        ]);

        $seconde = $this->service->creer([
            'client_id' => $this->clientId,
            'unite_id' => $autreUnite->id,
            'date_arrivee' => '2026-09-01',
            'date_depart' => '2026-09-10',
            'statut' => 'en_attente',
            'acompte' => '0.00',
        ]);

        $this->assertSame($autreUnite->id, $seconde->unite_id);
    }

    #[Test]
    public function rg01_le_deplacement_d_une_reservation_ne_la_met_pas_en_conflit_avec_elle_meme(): void
    {
        $reservation = $this->reserver('2026-09-01', '2026-09-10');

        $modifiee = $this->service->modifier($reservation, [
            'date_arrivee' => '2026-09-02',
            'date_depart' => '2026-09-11',
        ]);

        $this->assertSame('2026-09-02', $modifiee->date_arrivee->toDateString());
    }

    #[Test]
    public function rg01_le_deplacement_sur_une_periode_occupee_est_rejete(): void
    {
        $premiere = $this->reserver('2026-09-01', '2026-09-04');
        $this->reserver('2026-09-10', '2026-09-15');

        $this->expectException(ChevauchementDetecteException::class);
        $this->service->modifier($premiere, [
            'date_arrivee' => '2026-09-11',
            'date_depart' => '2026-09-13',
        ]);
    }

    #[Test]
    public function rg01_l_exception_porte_les_identifiants_en_conflit(): void
    {
        $existante = $this->reserver('2026-09-01', '2026-09-10');

        try {
            $this->reserver('2026-09-02', '2026-09-05');
            $this->fail('Un chevauchement aurait dû être détecté.');
        } catch (ChevauchementDetecteException $e) {
            // Le client Flutter doit pouvoir désigner la réservation qui bloque,
            // pas seulement afficher « conflit » (07_TESTING_QA.md §3).
            $this->assertContains($existante->id, $e->identifiantsEnConflit);
            $this->assertSame($this->uniteId, $e->ressourceId);
        }
    }

    #[Test]
    public function rg01_aucune_reservation_fantome_n_est_creee_quand_le_conflit_est_detecte(): void
    {
        $this->reserver('2026-09-01', '2026-09-10');

        try {
            $this->reserver('2026-09-02', '2026-09-05');
        } catch (ChevauchementDetecteException) {
            // attendu
        }

        // La transaction doit avoir été annulée intégralement.
        $this->assertSame(1, Reservation::count());
    }

    private function reserver(string $arrivee, string $depart): Reservation
    {
        return $this->service->creer([
            'client_id' => $this->clientId,
            'unite_id' => $this->uniteId,
            'date_arrivee' => $arrivee,
            'date_depart' => $depart,
            'statut' => 'en_attente',
            'acompte' => '0.00',
        ]);
    }
}
