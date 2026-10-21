<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Rh\Models\Conge;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Planning;
use App\Domain\Rh\Models\Service;
use App\Domain\Rh\Services\CongeService;
use App\Models\User;
use App\Pwa\Livewire\Rh\CongesPlannings;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « Congés & Plannings » (M13), écran créé le 21/10/2026 : il n'écrit que par
 * `PlanningService` (RG-13) et `CongeService` (RG-14), et chaque refus de ces
 * services s'affiche tel quel.
 */
final class CongesPlanningsPwaTest extends TestCase
{
    use RefreshDatabase;

    private Service $cuisine;

    private Employe $chef;

    private Employe $aide;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-21 09:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->cuisine = Service::create(['libelle' => 'Cuisine']);
        $this->chef = $this->employe('KOSSOU', 'Bernard');
        $this->aide = $this->employe('ADJOVI', 'Rose');
    }

    private function employe(string $nom, string $prenom): Employe
    {
        return Employe::create([
            'nom' => $nom, 'prenom' => $prenom, 'poste' => 'Cuisinier',
            'service_id' => $this->cuisine->id, 'date_embauche' => '2025-01-06',
            'salaire_base' => '85000.00', 'statut' => 'actif',
        ]);
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

    private function parametres(string $preavis = '7', string $couverture = '1'): void
    {
        ParametreSysteme::create(['cle' => CongeService::CLE_PREAVIS, 'valeur' => $preavis, 'description' => 'Préavis']);
        ParametreSysteme::create(['cle' => CongeService::CLE_COUVERTURE, 'valeur' => $couverture, 'description' => 'Couverture']);
    }

    /**
     * @return \Livewire\Features\SupportTesting\Testable<CongesPlannings>
     */
    private function planifier(?string $debut = '08:00', ?string $fin = '16:00'): \Livewire\Features\SupportTesting\Testable
    {
        return Livewire::test(CongesPlannings::class)
            ->call('ouvrirPlanification')
            ->set('employePlanning', $this->chef->id)
            ->set('servicePlanning', $this->cuisine->id)
            ->set('datePlanning', '2026-10-21')
            ->set('heureDebutPlanning', $debut)
            ->set('heureFinPlanning', $fin)
            ->call('enregistrerPlanning');
    }

    #[Test]
    public function l_ecran_se_charge_et_liste_le_planning_du_jour(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $this->planifier()->assertHasNoErrors();

        $this->get(route('pwa.conges-plannings'))->assertOk()
            ->assertSee('KOSSOU')->assertSee('08:00')->assertSee('16:00');
        $this->assertSame(1, Planning::query()->count());
    }

    #[Test]
    public function rg13_un_chevauchement_est_refuse_avec_la_phrase_du_service_et_un_creneau_adjacent_passe(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $this->planifier('08:00', '12:00')->assertHasNoErrors();

        $this->planifier('10:00', '14:00')->assertHasErrors(['employePlanning']);
        $this->assertSame(1, Planning::query()->count());

        $this->planifier('12:00', '18:00')->assertHasNoErrors();
        $this->assertSame(2, Planning::query()->count());
    }

    #[Test]
    public function un_creneau_inverse_est_refuse_avant_toute_ecriture(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $this->planifier('16:00', '08:00')->assertHasErrors(['heureFinPlanning']);
        $this->assertSame(0, Planning::query()->count());
    }

    #[Test]
    public function une_demande_de_conge_est_toujours_acceptee_puis_validee_selon_rg14(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $this->parametres('7', '1');

        Livewire::test(CongesPlannings::class)
            ->call('ouvrirDemandeConge')
            ->set('employeConge', $this->chef->id)
            ->set('typeConge', 'annuel')
            ->set('debutConge', '2026-11-10')
            ->set('finConge', '2026-11-12')
            ->call('enregistrerConge')
            ->assertHasNoErrors();

        $conge = Conge::query()->firstOrFail();
        $this->assertSame('en_attente', $conge->statut_validation);

        Livewire::test(CongesPlannings::class)->call('validerConge', $conge->id)->assertHasNoErrors();
        $this->assertSame('valide', $conge->refresh()->statut_validation);
        $this->assertNotNull($conge->validateur_id);
    }

    #[Test]
    public function rg14_un_preavis_insuffisant_ou_un_parametre_absent_refuse_la_validation_et_la_demande_reste(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $conge = app(CongeService::class)->demander([
            'employe_id' => $this->chef->id, 'type' => 'annuel',
            'date_debut' => '2026-10-23', 'date_fin' => '2026-10-24',
        ]);

        // Aucun paramètre : jamais deviné.
        Livewire::test(CongesPlannings::class)->call('validerConge', $conge->id)->assertHasErrors(['conge-' . $conge->id]);
        $this->assertSame('en_attente', $conge->refresh()->statut_validation);

        // Préavis de 7 jours exigé, 2 respectés.
        $this->parametres('7', '1');
        Livewire::test(CongesPlannings::class)->call('validerConge', $conge->id)->assertHasErrors(['conge-' . $conge->id]);
        $this->assertSame('en_attente', $conge->refresh()->statut_validation);
    }

    #[Test]
    public function un_refus_conserve_la_demande_et_ne_se_rejoue_pas(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $conge = app(CongeService::class)->demander([
            'employe_id' => $this->aide->id, 'type' => 'maladie',
            'date_debut' => '2026-11-02', 'date_fin' => '2026-11-03',
        ]);

        Livewire::test(CongesPlannings::class)->call('refuserConge', $conge->id)->assertHasNoErrors();
        $this->assertSame('refuse', $conge->refresh()->statut_validation);
        $this->assertSame(1, Conge::query()->count());

        Livewire::test(CongesPlannings::class)->call('refuserConge', $conge->id)->assertHasErrors(['conge-' . $conge->id]);
    }

    #[Test]
    public function un_employe_en_conge_valide_n_est_pas_planifiable(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $this->parametres('0', '0');
        $conge = app(CongeService::class)->demander([
            'employe_id' => $this->chef->id, 'type' => 'annuel',
            'date_debut' => '2026-10-21', 'date_fin' => '2026-10-22',
        ]);
        app(CongeService::class)->valider($conge, auth()->user());

        $this->planifier()->assertHasErrors(['employePlanning']);
        $this->assertSame(0, Planning::query()->count());
    }

    #[Test]
    public function un_role_en_lecture_voit_l_ecran_mais_n_ecrit_rien(): void
    {
        $this->actingAs($this->utilisateur('comptable'));
        $conge = app(CongeService::class)->demander([
            'employe_id' => $this->aide->id, 'type' => 'annuel',
            'date_debut' => '2026-11-02', 'date_fin' => '2026-11-03',
        ]);

        $niveau = auth()->user()->niveauSurModule('M13');

        if ($niveau === 'C') {
            $this->markTestSkipped('Le rôle de test écrit sur M13.');
        }

        $this->get(route('pwa.conges-plannings'))->assertStatus($niveau === 'L' ? 200 : 403);

        if ($niveau === 'L') {
            Livewire::test(CongesPlannings::class)->call('ouvrirPlanification')->assertStatus(403);
            Livewire::test(CongesPlannings::class)->call('validerConge', $conge->id)->assertStatus(403);
            Livewire::test(CongesPlannings::class)->call('refuserConge', $conge->id)->assertStatus(403);
        }

        $this->assertSame('en_attente', $conge->refresh()->statut_validation);
    }

    #[Test]
    public function un_role_sans_acces_a_m13_ne_voit_pas_l_ecran(): void
    {
        $this->actingAs($this->utilisateur('cuisine'));

        $this->get(route('pwa.conges-plannings'))->assertStatus(403);
    }
}
