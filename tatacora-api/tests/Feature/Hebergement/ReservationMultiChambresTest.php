<?php

declare(strict_types=1);

namespace Tests\Feature\Hebergement;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\LigneReservation;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\DisponibiliteService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Domain\Hebergement\Services\SejourService;
use App\Models\User;
use App\Pwa\Livewire\Hebergement\Reservations;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * RÉSERVATION MULTI-CHAMBRES (décision du PO du 10/11/2026) : « pour UNE SEULE réservation un
 * client peut réserver UNE ou PLUSIEURS chambres ».
 *
 * La première chambre reste sur `reservations.unite_id` ; les suivantes sont des lignes de
 * service `hebergement`. Chaque cas emprunte le chemin réel : le Service sous verrou, la
 * disponibilité, l'arrivée / le départ, la facture, l'écran.
 */
final class ReservationMultiChambresTest extends TestCase
{
    use RefreshDatabase;

    private Client $client;

    private UniteHebergement $a;

    private UniteHebergement $b;

    private UniteHebergement $c;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        $twin = CategorieHebergement::create(['id' => (string) Str::uuid(), 'libelle' => 'Twin', 'capacite_max' => 2, 'tarif_base' => 22000]);
        $studio = CategorieHebergement::create(['id' => (string) Str::uuid(), 'libelle' => 'Studio', 'capacite_max' => 2, 'tarif_base' => 40000]);
        $this->a = UniteHebergement::create(['id' => (string) Str::uuid(), 'categorie_id' => $twin->id, 'numero' => 'BNG-3', 'statut' => 'libre']);
        $this->b = UniteHebergement::create(['id' => (string) Str::uuid(), 'categorie_id' => $studio->id, 'numero' => 'BNG-4', 'statut' => 'libre']);
        $this->c = UniteHebergement::create(['id' => (string) Str::uuid(), 'categorie_id' => $twin->id, 'numero' => 'BNG-5', 'statut' => 'libre']);
        $this->client = Client::create(['id' => (string) Str::uuid(), 'nom' => 'ISSA', 'prenom' => 'Robert', 'telephone' => '0123456789', 'type_client' => 'groupe']);
    }

    /** @return array<string, mixed> */
    private function charge(UniteHebergement $unite, string $arrivee = '2026-12-10', string $depart = '2026-12-12'): array
    {
        return [
            'client_id' => $this->client->id, 'unite_id' => $unite->id,
            'date_arrivee' => $arrivee, 'date_depart' => $depart,
            'acompte' => '0', 'remise_type' => 'aucune', 'remise_valeur' => '0',
        ];
    }

    private function ligneChambre(UniteHebergement $unite): array
    {
        return ['service' => LigneReservation::CHAMBRE, 'source_id' => $unite->id, 'quantite' => '1'];
    }

    #[Test]
    public function une_reservation_porte_plusieurs_chambres_et_son_total_les_somme(): void
    {
        $service = app(ReservationService::class);
        $reservation = $service->creer($this->charge($this->a));
        $service->remplacerLignes($reservation, [$this->ligneChambre($this->b)]);

        $reservation = $reservation->refresh()->load('lignes');

        $this->assertSame([$this->a->id, $this->b->id], $reservation->uniteIds());
        $this->assertSame('BNG-3, BNG-4', $reservation->numerosDesChambres());
        // (22 000 + 40 000) × 2 nuits.
        $this->assertSame('124000.00', $reservation->sousTotal());
        $ligne = $reservation->lignes->first();
        $this->assertSame('2.00', (string) $ligne->quantite);
        $this->assertSame('40000.00', (string) $ligne->prix_unitaire);
    }

    #[Test]
    public function une_chambre_supplementaire_prise_refuse_et_nomme_la_chambre(): void
    {
        $service = app(ReservationService::class);
        $premiere = $service->creer($this->charge($this->a));
        $service->remplacerLignes($premiere, [$this->ligneChambre($this->b)]);

        $autre = $service->creer($this->charge($this->c));

        try {
            $service->remplacerLignes($autre, [$this->ligneChambre($this->b)]);
            $this->fail('La chambre BNG-4 est prise : le refus était attendu.');
        } catch (ChevauchementDetecteException $e) {
            $this->assertStringContainsString('BNG-4', $e->getMessage());
        }

        // Et la chambre PRINCIPALE d'une nouvelle réservation ne peut pas être la
        // chambre supplémentaire d'une autre.
        $this->expectException(ChevauchementDetecteException::class);
        $service->creer($this->charge($this->b));
    }

    #[Test]
    public function une_chambre_deux_fois_ou_la_principale_redite_est_refusee(): void
    {
        $service = app(ReservationService::class);
        $reservation = $service->creer($this->charge($this->a));

        $this->expectException(\InvalidArgumentException::class);
        $service->remplacerLignes($reservation, [$this->ligneChambre($this->a)]);
    }

    #[Test]
    public function la_disponibilite_et_le_planning_voient_chaque_chambre(): void
    {
        $service = app(ReservationService::class);
        $reservation = $service->creer($this->charge($this->a));
        $service->remplacerLignes($reservation, [$this->ligneChambre($this->b)]);

        $dispo = app(DisponibiliteService::class);

        $this->assertFalse($dispo->uniteEstDisponible($this->b->id, '2026-12-10', '2026-12-12'));
        $this->assertTrue($dispo->uniteEstDisponible($this->b->id, '2026-12-12', '2026-12-14'));
        $this->assertTrue($dispo->uniteEstDisponible($this->b->id, '2026-12-10', '2026-12-12', $reservation->id));
        $this->assertSame([$this->c->id], $dispo->unitesDisponibles('2026-12-10', '2026-12-12')->pluck('id')->all());

        $planning = $dispo->planningOccupation('2026-12-01', '2026-12-31');
        $this->assertCount(1, $planning->get($this->a->id));
        $this->assertCount(1, $planning->get($this->b->id));
    }

    #[Test]
    public function l_arrivee_occupe_toutes_les_chambres_et_le_depart_les_passe_au_menage(): void
    {
        $service = app(ReservationService::class);
        $reservation = $service->creer($this->charge($this->a));
        $service->remplacerLignes($reservation, [$this->ligneChambre($this->b)]);

        $sejours = app(SejourService::class);
        $sejour = $sejours->checkin($reservation->refresh());

        $this->assertSame('occupee', $this->a->refresh()->statut);
        $this->assertSame('occupee', $this->b->refresh()->statut);
        $this->assertSame($sejour->id, $sejours->sejourEnCours($this->b)?->id);

        $sejours->checkout($sejour);

        $this->assertSame('nettoyage', $this->a->refresh()->statut);
        $this->assertSame('nettoyage', $this->b->refresh()->statut);
    }

    #[Test]
    public function l_annulation_libere_toutes_les_chambres(): void
    {
        $service = app(ReservationService::class);
        $reservation = $service->creer($this->charge($this->a));
        $service->remplacerLignes($reservation, [$this->ligneChambre($this->b)]);

        $service->annuler($reservation->refresh());

        $this->assertTrue(app(DisponibiliteService::class)->uniteEstDisponible($this->b->id, '2026-12-10', '2026-12-12'));
    }

    #[Test]
    public function la_modification_des_dates_reverifie_les_chambres_supplementaires(): void
    {
        $service = app(ReservationService::class);
        $premiere = $service->creer($this->charge($this->a));
        $service->remplacerLignes($premiere, [$this->ligneChambre($this->b)]);
        $service->creer($this->charge($this->c, '2026-12-12', '2026-12-14'));
        $autre = $service->creer($this->charge($this->a, '2026-12-14', '2026-12-16'));
        $service->remplacerLignes($autre, [$this->ligneChambre($this->c)]);

        // Allonger la première sur le 12→14 prend BNG-3/BNG-4… libres ; le 14→16 est pris par `$autre`
        // sur BNG-3 : le refus nomme la chambre.
        $this->expectException(ChevauchementDetecteException::class);
        $service->modifier($premiere->refresh(), ['date_depart' => '2026-12-15']);
    }

    #[Test]
    public function l_ecran_ajoute_et_retire_une_chambre_et_enregistre_la_reservation_complete(): void
    {
        $role = Role::where('libelle', 'gerant')->firstOrFail();
        $this->actingAs(User::create([
            'login' => 'gerant.multi', 'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $role->id, 'statut' => 'actif',
        ]));

        Livewire::test(Reservations::class)
            ->call('ouvrirCreationReservation')
            ->set('rClientId', $this->client->id)
            ->set('rUniteId', $this->a->id)
            ->set('rDateArrivee', '2026-12-10')
            ->set('rDateDepart', '2026-12-12')
            ->set('rRemiseType', 'aucune')
            ->call('ajouterChambre')
            ->call('ajouterChambre')
            ->set('rChambres.0.unite_id', $this->b->id)
            ->set('rChambres.1.unite_id', $this->c->id)
            ->call('retirerChambre', 1)
            ->assertSet('rChambres', [['unite_id' => $this->b->id]])
            ->call('enregistrerReservation')
            ->assertHasNoErrors();

        $reservation = Reservation::with('lignes')->firstOrFail();
        $this->assertSame($this->a->id, $reservation->unite_id);
        $this->assertSame([$this->a->id, $this->b->id], $reservation->uniteIds());
        $this->assertSame('124000.00', $reservation->sousTotal());
    }

    #[Test]
    public function l_ecran_refuse_une_chambre_prise_et_le_dit(): void
    {
        $service = app(ReservationService::class);
        $service->creer($this->charge($this->b));

        $role = Role::where('libelle', 'gerant')->firstOrFail();
        $this->actingAs(User::create([
            'login' => 'gerant.multi2', 'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $role->id, 'statut' => 'actif',
        ]));

        $rendu = Livewire::test(Reservations::class)
            ->call('ouvrirCreationReservation')
            ->set('rClientId', $this->client->id)
            ->set('rUniteId', $this->a->id)
            ->set('rDateArrivee', '2026-12-10')
            ->set('rDateDepart', '2026-12-12')
            ->set('rRemiseType', 'aucune')
            ->call('ajouterChambre')
            ->set('rChambres.0.unite_id', $this->b->id)
            ->call('enregistrerReservation');

        $rendu->assertHasErrors(['rUniteId']);
        $this->assertStringContainsString('BNG-4', (string) $rendu->errors()->first('rUniteId'));
    }
}
