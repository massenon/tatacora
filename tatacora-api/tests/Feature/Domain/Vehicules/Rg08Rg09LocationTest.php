<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Vehicules;

use App\Domain\Crm\Models\Client;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ContratLocationService;
use App\Models\User;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Location de véhicules — RG-08, RG-09, EF-M8-02/03/04.
 *
 * `07_TESTING_QA.md` §2 rend obligatoires, pour RG-08, les mêmes cas que
 * RG-01 : chevauchement total, partiel des deux côtés, **location adjacente
 * valide** (pas de faux positif). Pour RG-09 : location hors moto sans pièces
 * → rejet, location moto sans permis → acceptée.
 */
final class Rg08Rg09LocationTest extends TestCase
{
    use RefreshDatabase;

    private Vehicule $prado;

    private Vehicule $moto;

    private Client $client;

    private User $responsable;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->responsable = $this->utilisateur('vehicules');
        $this->actingAs($this->responsable);

        $this->client = Client::factory()->create();

        // Immatriculation et tarif confirmés contre le prototype réel
        // (SPEC_ECRAN_M8_VEHICULES.md §1).
        $this->prado = Vehicule::create([
            'categorie' => '4x4', 'immatriculation' => 'AB 1234 RB', 'annee' => 2019,
            'transmission' => 'automatique', 'capacite' => 7,
            'tarif_jour' => '65000.00', 'statut' => 'disponible',
        ]);

        $this->moto = Vehicule::create([
            'categorie' => 'moto', 'immatriculation' => 'MT 0001 RB', 'annee' => 2022,
            'transmission' => 'manuelle', 'capacite' => 2,
            'tarif_jour' => '8000.00', 'statut' => 'disponible',
        ]);
    }

    private function service(): ContratLocationService
    {
        return app(ContratLocationService::class);
    }

    // ------------------------------------------------------------- RG-08

    #[Test]
    public function rg08_un_chevauchement_total_est_refuse(): void
    {
        $this->louer($this->prado, '2026-09-01', '2026-09-10');

        $this->assertThrows(
            fn () => $this->louer($this->prado, '2026-09-01', '2026-09-10'),
            ChevauchementDetecteException::class,
        );

        $this->assertSame(1, ContratLocation::count());
    }

    #[Test]
    public function rg08_un_chevauchement_partiel_est_refuse_des_deux_cotes(): void
    {
        $this->louer($this->prado, '2026-09-05', '2026-09-10');

        // Déborde par le début...
        $this->assertThrows(
            fn () => $this->louer($this->prado, '2026-09-03', '2026-09-07'),
            ChevauchementDetecteException::class,
        );

        // ...et par la fin.
        $this->assertThrows(
            fn () => $this->louer($this->prado, '2026-09-08', '2026-09-12'),
            ChevauchementDetecteException::class,
        );

        // ...ainsi qu'une plage strictement englobante.
        $this->assertThrows(
            fn () => $this->louer($this->prado, '2026-09-01', '2026-09-20'),
            ChevauchementDetecteException::class,
        );

        $this->assertSame(1, ContratLocation::count());
    }

    /**
     * Le faux positif que la convention de bornes semi-ouvertes existe pour
     * éviter : un retour le 10 et un départ le 10 ne se chevauchent pas. Une
     * erreur de bornes (`>=` / `<=`) refuserait des locations parfaitement
     * valides — et serait signalée par les clients, jamais par les tests.
     */
    #[Test]
    public function rg08_une_location_adjacente_reste_valide(): void
    {
        $this->louer($this->prado, '2026-09-01', '2026-09-10');

        $suivante = $this->louer($this->prado, '2026-09-10', '2026-09-15');

        $this->assertSame(2, ContratLocation::count());
        $this->assertSame('2026-09-10', $suivante->date_debut->toDateString());
    }

    #[Test]
    public function rg08_deux_vehicules_differents_ne_se_bloquent_pas(): void
    {
        $this->louer($this->prado, '2026-09-01', '2026-09-10');
        $this->louer($this->moto, '2026-09-01', '2026-09-10', permis: null);

        $this->assertSame(2, ContratLocation::count());
    }

    /**
     * La lecture de disponibilité (EF-M8-02) doit refléter exactement la même
     * règle que le verrou — sinon un planning afficherait « libre » sur une
     * période que la création refuse.
     */
    #[Test]
    public function la_disponibilite_affichee_est_coherente_avec_le_verrou(): void
    {
        $service = $this->service();

        $this->assertTrue($service->estDisponible($this->prado->id, '2026-09-01', '2026-09-10'));

        $this->louer($this->prado, '2026-09-01', '2026-09-10');

        $this->assertFalse($service->estDisponible($this->prado->id, '2026-09-05', '2026-09-07'));
        // Adjacent : libre, cohérent avec le test précédent.
        $this->assertTrue($service->estDisponible($this->prado->id, '2026-09-10', '2026-09-15'));
    }

    // ------------------------------------------------------------- RG-09

    /**
     * « La location d'un véhicule (hors moto) est subordonnée à
     * l'enregistrement préalable d'une pièce d'identité **et** d'un permis de
     * conduire valides. »
     */
    #[Test]
    public function rg09_un_4x4_sans_permis_est_refuse(): void
    {
        $this->assertThrows(
            fn () => $this->louer($this->prado, '2026-09-01', '2026-09-05', permis: null),
            RuntimeException::class,
        );

        $this->assertSame(0, ContratLocation::count());
    }

    #[Test]
    public function rg09_une_moto_sans_permis_est_acceptee(): void
    {
        $contrat = $this->louer($this->moto, '2026-09-01', '2026-09-05', permis: null);

        $this->assertDatabaseHas('contrats_location', ['id' => $contrat->id]);
        $this->assertNull($contrat->permis_conduire);
        // La pièce d'identité, elle, a bien été exigée et enregistrée.
        $this->assertSame('CNI-123', $contrat->piece_identite);
    }

    /**
     * La pièce d'identité, elle, n'a aucune exemption : RG-09 ne la
     * conditionne pas à la catégorie.
     */
    #[Test]
    public function rg09_la_piece_d_identite_est_exigee_meme_pour_une_moto(): void
    {
        $this->assertThrows(
            fn () => $this->louer($this->moto, '2026-09-01', '2026-09-05', piece: null, permis: null),
            RuntimeException::class,
        );
    }

    /**
     * La condition vit dans `Vehicule::exigePermis()`, pas dupliquée : c'est
     * ce qui garantit que la validation HTTP, le service et l'écran Flutter
     * répondent la même chose.
     */
    #[Test]
    public function rg09_la_regle_est_portee_par_le_modele_et_non_recopiee(): void
    {
        $this->assertFalse($this->moto->exigePermis());
        $this->assertTrue($this->prado->exigePermis());

        // PA-50 : `scooter` et `velo` existent dans l'enum mais ne sont PAS
        // dispensés par RG-09 telle qu'écrite. Le test fige le comportement
        // actuel pour que la question reste visible plutôt qu'oubliée.
        $velo = Vehicule::create([
            'categorie' => 'velo', 'immatriculation' => 'VL 0001 RB', 'annee' => 2024,
            'transmission' => 'aucune', 'capacite' => 1,
            'tarif_jour' => '2000.00', 'statut' => 'disponible',
        ]);

        $this->assertTrue(
            $velo->exigePermis(),
            'RG-09 ne dispense que « moto » ; élargir la liste demande un arbitrage (PA-50).',
        );
    }

    // -------------------------------------------------- Statut opérationnel

    /**
     * Un véhicule en entretien n'est pas louable, même si son calendrier est
     * vide — c'est précisément parce qu'il est immobilisé qu'il l'est.
     */
    #[Test]
    public function un_vehicule_en_entretien_ne_peut_pas_etre_loue(): void
    {
        $this->prado->update(['statut' => 'entretien']);

        $this->assertThrows(
            fn () => $this->louer($this->prado->fresh(), '2026-09-01', '2026-09-05'),
            RuntimeException::class,
        );
    }

    /**
     * En revanche, `statut = 'loue'` n'interdit pas une location **future** :
     * le statut est opérationnel, il n'est pas la disponibilité (RG-02).
     */
    #[Test]
    public function un_vehicule_marque_loue_reste_reservable_pour_une_periode_libre(): void
    {
        $this->prado->update(['statut' => 'loue']);

        $contrat = $this->louer($this->prado->fresh(), '2026-12-01', '2026-12-05');

        $this->assertDatabaseHas('contrats_location', ['id' => $contrat->id]);
        $this->assertSame('loue', $this->prado->fresh()->statut);
    }

    // ------------------------------------------------------------- Calculs

    #[Test]
    public function le_montant_est_calcule_au_tarif_journalier_jamais_saisi(): void
    {
        $contrat = $this->louer($this->prado, '2026-09-01', '2026-09-04');

        $this->assertSame(3, $contrat->nombreJours());
        // 3 × 65 000, en bcmul.
        $this->assertSame('195000.00', $contrat->montant());
    }

    // ---------------------------------------------------------------- API

    #[Test]
    public function l_api_refuse_un_chevauchement_en_409_et_non_en_422(): void
    {
        $this->louer($this->prado, '2026-09-01', '2026-09-10');

        Sanctum::actingAs($this->responsable);

        $reponse = $this->postJson('/api/v1/vehicules/contrats', [
            'vehicule_id' => $this->prado->id,
            'client_id' => $this->client->id,
            'date_debut' => '2026-09-05',
            'date_fin' => '2026-09-07',
            'piece_identite' => 'CNI-123',
            'permis_conduire' => 'PC-456',
        ]);

        // 409 : la demande est valide, c'est l'état concurrent qui la refuse.
        $reponse->assertStatus(409)->assertJsonStructure(['message', 'contrats_en_conflit']);
    }

    #[Test]
    public function l_api_refuse_un_4x4_sans_permis_en_validation(): void
    {
        Sanctum::actingAs($this->responsable);

        $this->postJson('/api/v1/vehicules/contrats', [
            'vehicule_id' => $this->prado->id,
            'client_id' => $this->client->id,
            'date_debut' => '2026-09-01',
            'date_fin' => '2026-09-05',
            'piece_identite' => 'CNI-123',
        ])->assertStatus(422)->assertJsonValidationErrors('permis_conduire');
    }

    #[Test]
    public function l_api_accepte_une_moto_sans_permis(): void
    {
        Sanctum::actingAs($this->responsable);

        $this->postJson('/api/v1/vehicules/contrats', [
            'vehicule_id' => $this->moto->id,
            'client_id' => $this->client->id,
            'date_debut' => '2026-09-01',
            'date_fin' => '2026-09-05',
            'piece_identite' => 'CNI-123',
        ])->assertStatus(201)->assertJsonPath('data.montant', '32000.00');
    }

    /**
     * RG-16, 2ᵉ niveau : un appel direct sans droit sur M8 doit être refusé.
     */
    #[Test]
    public function l_api_est_refusee_a_un_role_sans_droit_sur_m8(): void
    {
        $sansAcces = Role::all()->first(fn (Role $role): bool => $role->niveauSurModule('M8') === '-');

        if ($sansAcces === null) {
            $this->markTestSkipped('Tous les rôles ont accès à M8 dans la matrice.');
        }

        Sanctum::actingAs($this->compteAvecRole($sansAcces));

        $this->getJson('/api/v1/vehicules')->assertForbidden();
    }

    /**
     * PA-50 rendu visible : aucune route ne permet d'annuler un contrat, faute
     * de colonne `statut`. Un contrat erroné bloque son véhicule.
     */
    #[Test]
    public function pa50_aucune_route_d_annulation_de_contrat_n_existe(): void
    {
        $contrat = $this->louer($this->prado, '2026-09-01', '2026-09-10');

        Sanctum::actingAs($this->responsable);

        $this->deleteJson("/api/v1/vehicules/contrats/{$contrat->id}")->assertNotFound();
        $this->patchJson("/api/v1/vehicules/contrats/{$contrat->id}/annulation")->assertNotFound();

        // Le véhicule reste bloqué : c'est le comportement actuel, documenté.
        $this->assertFalse(
            $this->service()->estDisponible($this->prado->id, '2026-09-02', '2026-09-04'),
        );
    }

    // ------------------------------------------------------------- Helpers

    private function louer(
        Vehicule $vehicule,
        string $debut,
        string $fin,
        ?string $piece = 'CNI-123',
        ?string $permis = 'PC-456',
    ): ContratLocation {
        return $this->service()->creer([
            'vehicule_id' => $vehicule->id,
            'client_id' => $this->client->id,
            'date_debut' => $debut,
            'date_fin' => $fin,
            'piece_identite' => $piece,
            'permis_conduire' => $permis,
        ]);
    }

    private function utilisateur(string $role): User
    {
        return $this->compteAvecRole(Role::where('libelle', $role)->firstOrFail());
    }

    private function compteAvecRole(Role $role): User
    {
        return User::create([
            'login' => $role->libelle . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $role->id,
            'statut' => 'actif',
        ]);
    }
}
