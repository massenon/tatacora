<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Hebergement;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\Sejour;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\DisponibiliteService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Domain\Hebergement\Services\SejourService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Check-in, check-out et cycle opérationnel de l'unité — PA-159 lot 0b, T5.
 *
 * ## Ce qui manquait était le GESTE, pas le schéma
 *
 * `sejours.date_checkin_reel` et `date_checkout_reel` existaient depuis la
 * migration d'origine, et `Sejour::estEnCours()` en dérivait déjà l'état.
 * Aucune route, aucun service ne les écrivait. La note du dépôt qui disait
 * « le check-in/check-out n'existe nulle part » était fausse à moitié — et
 * c'est cette moitié qui avait fait refuser un écran (PA-118).
 *
 * ## Le cœur de ce fichier : DEUX sources, DEUX questions
 *
 * `unites_hebergement.statut` répond à « prête à recevoir maintenant ? ».
 * `DisponibiliteService` répond à « libre du 1er au 4 ? ». Les confondre
 * contredit RG-02, et les tests ci-dessous le démontrent plutôt que de le
 * répéter.
 *
 * @see EF-M1-03 Check-in
 * @see EF-M1-04 Check-out
 * @see RG-02 Disponibilité toujours calculée, jamais stockée
 */
final class SejourCheckinCheckoutTest extends TestCase
{
    use RefreshDatabase;

    private SejourService $sejours;

    private UniteHebergement $bungalow;

    private Reservation $reservation;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->sejours = app(SejourService::class);
        $this->actingAs($this->utilisateur('receptionniste'));

        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow',
            'capacite_max' => 2,
            'tarif_base' => '25000.00',
        ]);

        $this->bungalow = UniteHebergement::create([
            'categorie_id' => $categorie->id,
            'numero' => 'B-01',
            'statut' => 'libre',
        ]);

        $client = Client::create([
            'nom' => 'NABOGOU',
            'prenom' => 'Noël',
            'telephone' => '+22997000000',
            'type_client' => 'particulier',
        ]);

        $this->reservation = app(ReservationService::class)->creer([
            'client_id' => $client->id,
            'unite_id' => $this->bungalow->id,
            'date_arrivee' => now()->toDateString(),
            'date_depart' => now()->addDays(3)->toDateString(),
            'statut' => 'confirmee',
            'acompte' => '10000.00',
        ]);
    }

    // ------------------------------------------------------------ Le geste

    #[Test]
    public function ef_m1_03_le_checkin_ecrit_l_arrivee_reelle_et_occupe_l_unite(): void
    {
        $sejour = $this->sejours->checkin($this->reservation, [
            ['nom' => 'NABOGOU Noël', 'piece' => 'CNI 123456'],
        ]);

        $this->assertNotNull($sejour->date_checkin_reel);
        $this->assertNull($sejour->date_checkout_reel);
        $this->assertTrue($sejour->estEnCours());
        $this->assertCount(1, $sejour->occupants);

        $this->assertSame('en_cours', $this->reservation->refresh()->statut);
        $this->assertSame('occupee', $this->bungalow->refresh()->statut);
    }

    #[Test]
    public function ef_m1_04_le_checkout_libere_l_unite_VERS_LE_NETTOYAGE_pas_vers_libre(): void
    {
        $sejour = $this->sejours->checkin($this->reservation);
        $clos = $this->sejours->checkout($sejour);

        $this->assertNotNull($clos->date_checkout_reel);
        $this->assertFalse($clos->estEnCours());
        $this->assertSame('terminee', $this->reservation->refresh()->statut);

        // Déclarer l'unité libre ici ferait accueillir un client dans une
        // chambre non faite, et personne ne saurait lesquelles restent à traiter.
        $this->assertSame('nettoyage', $this->bungalow->refresh()->statut);
    }

    #[Test]
    public function le_menage_est_le_troisieme_geste_du_cycle_et_il_existe(): void
    {
        $this->sejours->checkout($this->sejours->checkin($this->reservation));

        $remise = $this->sejours->marquerNettoyee($this->bungalow->refresh());

        $this->assertSame('libre', $remise->statut);

        // Sans ce geste, toute unité libérée resterait en nettoyage
        // indéfiniment : un indicateur bloqué que personne ne rouvrirait.
        $this->expectException(RuntimeException::class);
        $this->sejours->marquerNettoyee($remise);
    }

    // ------------------------------------------------- Les deux sources (RG-02)

    #[Test]
    public function rg02_le_statut_de_l_unite_ne_repond_PAS_a_la_question_de_disponibilite(): void
    {
        $disponibilites = app(DisponibiliteService::class);
        $debut = now()->addDays(30)->toDateString();
        $fin = now()->addDays(32)->toDateString();

        // Unité occupée AUJOURD'HUI par un séjour en cours…
        $this->sejours->checkin($this->reservation);
        $this->assertSame('occupee', $this->bungalow->refresh()->statut);

        // … et pourtant disponible dans un mois. Lire `statut` pour répondre
        // aurait rendu « non ».
        $this->assertTrue($disponibilites->uniteEstDisponible($this->bungalow->id, $debut, $fin));
    }

    #[Test]
    public function rg02_une_unite_libre_au_statut_peut_etre_deja_prise_sur_la_periode(): void
    {
        $disponibilites = app(DisponibiliteService::class);

        // Aucun check-in : le statut vaut toujours `libre`…
        $this->assertSame('libre', $this->bungalow->refresh()->statut);

        // … alors que la période est déjà réservée.
        $this->assertFalse($disponibilites->uniteEstDisponible(
            $this->bungalow->id,
            now()->addDay()->toDateString(),
            now()->addDays(2)->toDateString(),
        ));
    }

    #[Test]
    public function le_sejour_en_cours_dit_QUI_occupe_l_unite_ce_que_le_statut_ne_dit_pas(): void
    {
        $this->assertNull($this->sejours->sejourEnCours($this->bungalow));

        $this->sejours->checkin($this->reservation);

        $enCours = $this->sejours->sejourEnCours($this->bungalow->refresh());

        $this->assertNotNull($enCours);
        $this->assertSame('NABOGOU', $enCours->reservation->client->nom);

        $this->sejours->checkout($enCours);
        $this->assertNull($this->sejours->sejourEnCours($this->bungalow->refresh()));
    }

    // ------------------------------------------------------------- Les refus

    #[Test]
    public function une_seconde_arrivee_sur_la_meme_reservation_est_refusee(): void
    {
        $this->sejours->checkin($this->reservation);

        $this->expectException(RuntimeException::class);

        $this->sejours->checkin($this->reservation);
        $this->assertSame(1, Sejour::count());
    }

    #[Test]
    public function une_reservation_annulee_n_ouvre_aucun_sejour(): void
    {
        app(ReservationService::class)->annuler($this->reservation);

        $this->expectException(RuntimeException::class);

        $this->sejours->checkin($this->reservation->refresh());
    }

    #[Test]
    public function un_second_depart_sur_le_meme_sejour_est_refuse(): void
    {
        $sejour = $this->sejours->checkout($this->sejours->checkin($this->reservation));

        $this->expectException(RuntimeException::class);

        $this->sejours->checkout($sejour);
    }

    #[Test]
    public function une_unite_hors_service_ne_voit_pas_son_statut_ecrase_par_une_arrivee(): void
    {
        $this->bungalow->update(['statut' => 'hors_service']);

        try {
            $this->sejours->checkin($this->reservation);
            $this->fail('Une arrivée sur une unité hors service aurait dû être refusée.');
        } catch (RuntimeException) {
            $this->addToAssertionCount(1);
        }

        $this->assertSame('hors_service', $this->bungalow->refresh()->statut);
        $this->assertSame(0, Sejour::count());
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
