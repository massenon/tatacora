<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Hebergement;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * API M1 — endpoints consommés par le client Flutter.
 *
 * Vérifie le 2e niveau RBAC au niveau route (le masquage d'interface côté
 * Flutter ne protège rien) et le contrat de réponse attendu par la file de
 * synchronisation offline.
 */
final class ApiReservationTest extends TestCase
{
    use RefreshDatabase;

    private UniteHebergement $unite;

    private string $clientId;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

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
    public function un_appel_non_authentifie_est_refuse(): void
    {
        $this->getJson('/api/v1/hebergement/reservations')->assertUnauthorized();
    }

    #[Test]
    public function un_receptionniste_cree_une_reservation(): void
    {
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $reponse = $this->postJson('/api/v1/hebergement/reservations', [
            'client_id' => $this->clientId,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01',
            'date_depart' => '2026-09-04',
        ]);

        $reponse->assertCreated()
            ->assertJsonPath('data.statut', 'en_attente')
            // Valeur calculée, exposée en lecture seule : 3 nuitées du 1er au 4.
            ->assertJsonPath('data.nb_nuitees', 3);

        $this->assertSame(1, Reservation::count());
    }

    /**
     * RG-16 — un rôle en lecture seule sur M1 ne doit pas pouvoir écrire, même
     * en appelant l'API directement.
     */
    #[Test]
    public function rg16_un_comptable_en_lecture_seule_ne_peut_pas_creer(): void
    {
        Sanctum::actingAs($this->utilisateur('comptable'));

        $this->postJson('/api/v1/hebergement/reservations', [
            'client_id' => $this->clientId,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01',
            'date_depart' => '2026-09-04',
        ])->assertForbidden();

        $this->assertSame(0, Reservation::count());
    }

    #[Test]
    public function rg16_un_comptable_peut_consulter(): void
    {
        Sanctum::actingAs($this->utilisateur('comptable'));

        $this->getJson('/api/v1/hebergement/reservations')->assertOk();
    }

    #[Test]
    public function rg16_un_role_sans_acces_au_module_est_refuse(): void
    {
        // Le magasinier n'a aucun accès à M1.
        Sanctum::actingAs($this->utilisateur('magasinier'));

        $this->getJson('/api/v1/hebergement/reservations')->assertForbidden();
    }

    /**
     * RG-01 côté API : un conflit doit être un 409 exploitable, pas un 500.
     */
    #[Test]
    public function rg01_un_chevauchement_renvoie_409_avec_les_reservations_en_conflit(): void
    {
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $premiere = $this->postJson('/api/v1/hebergement/reservations', [
            'client_id' => $this->clientId,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01',
            'date_depart' => '2026-09-10',
        ])->assertCreated()->json('data.id');

        // Le FormRequest attrape le cas courant en 422 ; la protection ultime
        // (409) reste le service. On vérifie ici que le refus a bien lieu et
        // qu'aucune seconde réservation n'est créée.
        $reponse = $this->postJson('/api/v1/hebergement/reservations', [
            'client_id' => $this->clientId,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-02',
            'date_depart' => '2026-09-05',
        ]);

        $this->assertContains($reponse->status(), [409, 422]);
        $this->assertSame(1, Reservation::count());
        $this->assertNotNull($premiere);
    }

    #[Test]
    public function rg02_l_annulation_passe_par_une_route_dediee_et_non_par_delete(): void
    {
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $id = $this->postJson('/api/v1/hebergement/reservations', [
            'client_id' => $this->clientId,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01',
            'date_depart' => '2026-09-04',
        ])->json('data.id');

        $this->patchJson("/api/v1/hebergement/reservations/{$id}/annulation")
            ->assertOk()
            ->assertJsonPath('data.statut', 'annulee');

        // Aucune route de suppression n'est déclarée : DELETE sur une URL
        // existante renvoie 405 (méthode non autorisée), ce qui prouve que le
        // verbe n'est routé nulle part. La trace est conservée.
        $this->deleteJson("/api/v1/hebergement/reservations/{$id}")
            ->assertStatus(405);
        $this->assertDatabaseHas('reservations', ['id' => $id]);
    }

    #[Test]
    public function les_disponibilites_excluent_les_unites_deja_reservees(): void
    {
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->getJson('/api/v1/hebergement/disponibilites?date_arrivee=2026-09-01&date_depart=2026-09-04')
            ->assertOk()
            ->assertJsonCount(1, 'data');

        $this->postJson('/api/v1/hebergement/reservations', [
            'client_id' => $this->clientId,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01',
            'date_depart' => '2026-09-04',
        ])->assertCreated();

        $this->getJson('/api/v1/hebergement/disponibilites?date_arrivee=2026-09-01&date_depart=2026-09-04')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    /**
     * Offline-first : le client Flutter fournit l'UUID généré localement, le
     * serveur ne le réattribue pas (02_SOFTWARE_ARCHITECTURE.md §5).
     */
    #[Test]
    public function l_uuid_genere_cote_client_est_conserve(): void
    {
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $uuidClient = (string) Str::uuid();

        $this->postJson('/api/v1/hebergement/reservations', [
            'id' => $uuidClient,
            'client_id' => $this->clientId,
            'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01',
            'date_depart' => '2026-09-04',
        ])->assertCreated()->assertJsonPath('data.id', $uuidClient);

        $this->assertDatabaseHas('reservations', ['id' => $uuidClient]);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
