<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Vehicules;

use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Enregistrement d'un entretien ou d'une carburation — EF-M8-05.
 *
 * `POST /api/v1/vehicules/entretiens` n'avait AUCUN test avant le lot 0b
 * (PA-159) : la validation vivait en ligne dans le contrôleur et rien ne
 * fixait son contrat. L'extraction vers `EnregistrerEntretienRequest` +
 * `ParcVehiculeService` reprend les règles à l'identique — ce fichier fige ce
 * contrat pour que la PWA puisse s'y appuyer via `ReglesDeLApi`.
 */
final class ApiEntretienTest extends TestCase
{
    use RefreshDatabase;

    private Vehicule $prado;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->prado = Vehicule::create([
            'categorie' => '4x4', 'immatriculation' => 'AB 1234 RB', 'annee' => 2019,
            'transmission' => 'automatique', 'capacite' => 7,
            'tarif_jour' => '65000.00', 'statut' => 'disponible',
        ]);
    }

    #[Test]
    public function l_api_enregistre_un_entretien_et_le_journalise(): void
    {
        Sanctum::actingAs($this->utilisateur('vehicules'));

        $reponse = $this->postJson('/api/v1/vehicules/entretiens', [
            'vehicule_id' => $this->prado->id,
            'type' => 'entretien',
            'date' => '2026-08-20',
            'cout' => '45000.00',
        ]);

        $reponse->assertCreated()->assertJsonStructure(['data' => ['id']]);

        $this->assertDatabaseHas('entretiens_vehicule', [
            'id' => $reponse->json('data.id'),
            'vehicule_id' => $this->prado->id,
            'type' => 'entretien',
            'cout' => '45000.00',
        ]);

        // RG-15 étendue aux référentiels (lot 0b) : l'écriture passée par le
        // service laisse sa trace, comme toute écriture sensible.
        $entree = JournalAudit::where('entite_concernee', 'entretiens_vehicule')
            ->where('entite_id', $reponse->json('data.id'))
            ->sole();

        $this->assertSame('creation', $entree->action);
    }

    #[Test]
    public function le_type_est_un_registre_ferme(): void
    {
        Sanctum::actingAs($this->utilisateur('vehicules'));

        $this->postJson('/api/v1/vehicules/entretiens', [
            'vehicule_id' => $this->prado->id,
            'type' => 'reparation',
            'date' => '2026-08-20',
            'cout' => '45000.00',
        ])->assertUnprocessable()->assertJsonValidationErrors('type');
    }

    #[Test]
    public function un_cout_negatif_est_refuse(): void
    {
        Sanctum::actingAs($this->utilisateur('vehicules'));

        $this->postJson('/api/v1/vehicules/entretiens', [
            'vehicule_id' => $this->prado->id,
            'type' => 'carburation',
            'date' => '2026-08-20',
            'cout' => '-1000.00',
        ])->assertUnprocessable()->assertJsonValidationErrors('cout');
    }

    #[Test]
    public function un_role_sans_ecriture_sur_m8_est_refuse(): void
    {
        // `magasinier` : M8 = '-' à la matrice RBAC.
        Sanctum::actingAs($this->utilisateur('magasinier'));

        $this->postJson('/api/v1/vehicules/entretiens', [
            'vehicule_id' => $this->prado->id,
            'type' => 'entretien',
            'date' => '2026-08-20',
            'cout' => '45000.00',
        ])->assertForbidden();

        $this->assertDatabaseCount('entretiens_vehicule', 0);
    }

    #[Test]
    public function l_api_exige_un_jeton(): void
    {
        $this->postJson('/api/v1/vehicules/entretiens', [])->assertUnauthorized();
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
