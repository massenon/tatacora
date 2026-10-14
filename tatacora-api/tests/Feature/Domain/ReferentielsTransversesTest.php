<?php

declare(strict_types=1);

namespace Tests\Feature\Domain;

use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Policies\FournisseurPolicy;
use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Policies\ClientPolicy;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Service as ServiceRh;
use App\Domain\Rh\Policies\EmployePolicy;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Services\ClassificationConflitService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Sprint 1 — référentiels transverses (Clients, Fournisseurs, Employés/Services)
 * et squelette Shared/Sync.
 */
final class ReferentielsTransversesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function les_trois_referentiels_sont_persistables(): void
    {
        $client = Client::factory()->create();
        $fournisseur = Fournisseur::create(['raison_sociale' => 'SOBEBRA']);
        $service = ServiceRh::create(['libelle' => 'Restauration']);
        $employe = Employe::create([
            'nom' => 'AMEGAN',
            'prenom' => 'Kokou',
            'poste' => 'Cuisinier',
            'service_id' => $service->id,
            'date_embauche' => '2026-01-15',
            'salaire_base' => '85000.00',
            'statut' => 'actif',
        ]);

        $this->assertDatabaseHas('clients', ['id' => $client->id]);
        $this->assertDatabaseHas('fournisseurs', ['id' => $fournisseur->id]);
        $this->assertDatabaseHas('employes', ['id' => $employe->id]);
        $this->assertSame('Restauration', $employe->service->libelle);
    }

    /**
     * RG-15 — les référentiels portent des colonnes d'audit, donc le trait
     * Auditable doit les alimenter comme il le fait pour Reservation/Facture.
     */
    #[Test]
    public function rg15_les_referentiels_audites_alimentent_le_journal(): void
    {
        $this->actingAs($this->utilisateur('gerant'));

        $client = Client::factory()->create();

        $this->assertSame(
            1,
            JournalAudit::where('entite_concernee', 'clients')->where('entite_id', $client->id)->count(),
        );
    }

    /**
     * `services` n'a volontairement pas de colonnes d'audit
     * (03_DATABASE_ENGINEERING.md §12) : lui appliquer le trait échouerait en SQL.
     */
    #[Test]
    public function le_referentiel_services_n_est_pas_audite_par_conception(): void
    {
        $this->actingAs($this->utilisateur('rh'));

        $service = ServiceRh::create(['libelle' => 'Réception']);

        $this->assertDatabaseHas('services', ['id' => $service->id]);
        $this->assertSame(0, JournalAudit::where('entite_concernee', 'services')->count());
    }

    #[Test]
    public function rg16_la_policy_client_suit_la_matrice_du_role(): void
    {
        $policy = new ClientPolicy();

        // Réceptionniste : M3 = 'C'
        $this->assertTrue($policy->create($this->utilisateur('receptionniste')));

        // Comptable : M3 = 'L' — consultation oui, création non
        $comptable = $this->utilisateur('comptable', 'comptable.test');
        $this->assertTrue($policy->viewAny($comptable));
        $this->assertFalse($policy->create($comptable));

        // Magasinier : M3 = '-' — aucun accès
        $magasinier = $this->utilisateur('magasinier', 'magasinier.test');
        $this->assertFalse($policy->viewAny($magasinier));
    }

    #[Test]
    public function rg16_les_policies_fournisseur_et_employe_suivent_leur_module(): void
    {
        // Achats : M7 = 'C' pour le rôle achats, '-' pour le guide
        $this->assertTrue((new FournisseurPolicy())->create($this->utilisateur('achats')));
        $this->assertFalse((new FournisseurPolicy())->viewAny($this->utilisateur('guide', 'guide.test')));

        // RH : M13 = 'C' pour rh, 'L' pour comptable
        $this->assertTrue((new EmployePolicy())->create($this->utilisateur('rh', 'rh.test')));

        $comptable = $this->utilisateur('comptable', 'comptable2.test');
        $this->assertTrue((new EmployePolicy())->viewAny($comptable));
        $this->assertFalse((new EmployePolicy())->update($comptable));
    }

    /**
     * Aucune suppression physique sur un référentiel référencé par des
     * transactions — 03_DATABASE_ENGINEERING.md §15.
     */
    #[Test]
    public function aucune_policy_n_autorise_la_suppression_par_defaut(): void
    {
        $administrateur = $this->utilisateur('administrateur');

        $this->assertFalse((new ClientPolicy())->delete($administrateur));
        $this->assertFalse((new FournisseurPolicy())->delete($administrateur));
        $this->assertFalse((new EmployePolicy())->delete($administrateur));
    }

    /**
     * RG-17 — jamais de résolution automatique sur une table financière.
     */
    #[Test]
    public function rg17_aucune_table_financiere_n_autorise_la_resolution_automatique(): void
    {
        $service = new ClassificationConflitService();

        foreach (ClassificationConflitService::TABLES_FINANCIERES as $table) {
            $this->assertFalse(
                $service->autoriseResolutionAutomatique($table),
                "La table financière {$table} ne doit JAMAIS être résolue automatiquement.",
            );
            $this->assertSame('arbitrage_manuel', $service->traitementPour($table));
        }
    }

    #[Test]
    public function rg17_les_tables_de_plage_sont_rejetees_et_non_arbitrees(): void
    {
        $service = new ClassificationConflitService();

        foreach (ClassificationConflitService::TABLES_STRUCTURELLES as $table) {
            $this->assertSame('rejet_structurel', $service->traitementPour($table));
        }
    }

    #[Test]
    public function rg17_un_referentiel_non_financier_reste_resoluble_automatiquement(): void
    {
        $service = new ClassificationConflitService();

        $this->assertTrue($service->autoriseResolutionAutomatique('clients'));
        $this->assertTrue($service->autoriseResolutionAutomatique('fournisseurs'));
    }

    private function utilisateur(string $role, ?string $login = null): User
    {
        return User::create([
            'login' => $login ?? $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
