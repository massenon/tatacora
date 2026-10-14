<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Crm;

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\ClientHistoriqueService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
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
 * API M3 — référentiel client, segmentation et historique consolidé.
 *
 * @see EF-M3-01 Fiche client unique
 * @see EF-M3-02 Historique consolidé
 * @see EF-M3-03 Segmentation
 * @see RG-18 Détection de doublon avertissante
 */
final class ApiClientTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function rg18_la_creation_reussit_malgre_un_doublon_et_renvoie_un_avertissement(): void
    {
        Client::factory()->create([
            'nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '01 97 35 59 74',
        ]);

        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $reponse = $this->postJson('/api/v1/crm/clients', [
            'nom' => 'KORA',
            'prenom' => 'Awa',
            'telephone' => '01 97 35 59 74',
            'type_client' => 'particulier',
        ]);

        // 201, pas 422 : RG-18 avertit, elle ne bloque pas.
        $reponse->assertCreated()
            ->assertJsonPath('data.nom_complet', 'Awa KORA');

        $this->assertStringContainsString(
            'RG-18',
            (string) $reponse->json('meta.avertissement_doublon'),
        );
        $this->assertSame(2, Client::count());
    }

    #[Test]
    public function rg18_la_creation_sans_doublon_ne_produit_aucun_avertissement(): void
    {
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->postJson('/api/v1/crm/clients', [
            'nom' => 'MENSAH',
            'telephone' => '01 22 22 22 22',
            'type_client' => 'particulier',
        ])->assertCreated()->assertJsonPath('meta.avertissement_doublon', null);
    }

    #[Test]
    public function rg18_la_pre_verification_signale_sans_bloquer(): void
    {
        Client::factory()->create(['nom' => 'KORA', 'telephone' => '01 97 35 59 74']);

        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->getJson('/api/v1/crm/clients/doublons?nom=KORA&telephone=0197355974')
            ->assertOk()
            ->assertJsonCount(1, 'doublons_potentiels')
            ->assertJsonPath('bloquant', false);
    }

    #[Test]
    public function ef_m3_03_la_segmentation_filtre_par_type_de_client(): void
    {
        Client::factory()->count(3)->create(['type_client' => 'particulier']);
        Client::factory()->create(['type_client' => 'agence']);

        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->getJson('/api/v1/crm/clients?type_client=agence')
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }

    /**
     * EF-M3-02 — le point le plus délicat du module.
     */
    #[Test]
    public function ef_m3_02_l_historique_declare_explicitement_ses_sources_indisponibles(): void
    {
        $client = Client::factory()->create();
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $reponse = $this->getJson("/api/v1/crm/clients/{$client->id}")->assertOk();

        // M1 est livré, les trois autres domaines sources ne le sont pas.
        $reponse->assertJsonPath('historique.sources.sejours.statut', 'disponible')
            ->assertJsonPath('historique.sources.factures.statut', 'en_attente_de_module')
            ->assertJsonPath('historique.sources.locations.statut', 'en_attente_de_module')
            ->assertJsonPath('historique.sources.circuits.statut', 'en_attente_de_module');

        // Le drapeau qui interdit de lire « aucune facture » comme
        // « ce client ne doit rien ».
        $reponse->assertJsonPath('historique.complet', false);
    }

    #[Test]
    public function ef_m3_02_l_historique_consolide_les_sejours_du_client(): void
    {
        $client = Client::factory()->create();
        $unite = $this->unite();
        $reservations = app(ReservationService::class);

        $reservations->creer([
            'client_id' => $client->id, 'unite_id' => $unite->id,
            'date_arrivee' => '2026-09-01', 'date_depart' => '2026-09-04',
            'statut' => 'en_attente', 'acompte' => '0.00',
        ]);
        $annulee = $reservations->creer([
            'client_id' => $client->id, 'unite_id' => $unite->id,
            'date_arrivee' => '2026-10-01', 'date_depart' => '2026-10-03',
            'statut' => 'en_attente', 'acompte' => '0.00',
        ]);
        $reservations->annuler($annulee);

        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->getJson("/api/v1/crm/clients/{$client->id}")
            ->assertOk()
            ->assertJsonCount(2, 'historique.sejours')
            ->assertJsonPath('historique.statistiques.nb_sejours', 1)
            ->assertJsonPath('historique.statistiques.nb_sejours_annules', 1)
            // 3 nuitées du 1er au 4 ; le séjour annulé ne compte pas.
            ->assertJsonPath('historique.statistiques.nb_nuitees_totales', 3);
    }

    #[Test]
    public function l_historique_ne_denormalise_rien_sur_la_fiche_client(): void
    {
        $client = Client::factory()->create();

        // Aucune colonne de synthèse n'existe sur `clients` : les compteurs
        // sont calculés à la demande (EF-M3-02, « pas une dénormalisation »).
        $colonnes = array_keys($client->getAttributes());

        foreach (['nb_sejours', 'nb_nuitees', 'derniere_visite', 'historique'] as $interdite) {
            $this->assertNotContains($interdite, $colonnes);
        }

        $this->assertSame(
            ['nb_sejours', 'nb_sejours_annules', 'nb_nuitees_totales'],
            array_keys(app(ClientHistoriqueService::class)->statistiques($client->id)),
        );
    }

    #[Test]
    public function rg16_un_role_sans_acces_a_m3_est_refuse(): void
    {
        // Le magasinier n'a aucun accès à M3.
        Sanctum::actingAs($this->utilisateur('magasinier'));

        $this->getJson('/api/v1/crm/clients')->assertForbidden();
    }

    #[Test]
    public function rg16_un_comptable_consulte_mais_ne_cree_pas(): void
    {
        Sanctum::actingAs($this->utilisateur('comptable'));

        $this->getJson('/api/v1/crm/clients')->assertOk();

        $this->postJson('/api/v1/crm/clients', [
            'nom' => 'TEST', 'telephone' => '01 00 00 00 00', 'type_client' => 'particulier',
        ])->assertForbidden();
    }

    #[Test]
    public function ef_m3_03_un_type_de_client_hors_segmentation_est_refuse(): void
    {
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->postJson('/api/v1/crm/clients', [
            'nom' => 'TEST',
            'telephone' => '01 00 00 00 00',
            'type_client' => 'vip',
        ])->assertStatus(422)->assertJsonValidationErrors('type_client');
    }

    private function unite(): UniteHebergement
    {
        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow', 'capacite_max' => 4, 'tarif_base' => '25000.00',
        ]);

        return UniteHebergement::create([
            'categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre',
        ]);
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
