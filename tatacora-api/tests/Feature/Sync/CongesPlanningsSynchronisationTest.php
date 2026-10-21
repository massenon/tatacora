<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Rh\Models\Conge;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Planning;
use App\Domain\Rh\Models\Service;
use App\Domain\Rh\Services\CongeService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Plannings (RG-13) et congés (RG-14) saisis sur un poste — 21/10/2026 : par
 * leurs services de domaine, rejoués sans doublon, et descendus aux autres postes.
 */
final class CongesPlanningsSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $rh;

    private Service $cuisine;

    private Employe $chef;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-21 09:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->rh = $this->creerUtilisateur('rh');
        $this->cuisine = Service::create(['libelle' => 'Cuisine']);
        $this->chef = Employe::create([
            'nom' => 'KOSSOU', 'prenom' => 'Bernard', 'poste' => 'Cuisinier', 'service_id' => $this->cuisine->id,
            'date_embauche' => '2025-01-06', 'salaire_base' => '85000.00', 'statut' => 'actif',
        ]);
        ParametreSysteme::create(['cle' => CongeService::CLE_PREAVIS, 'valeur' => '3', 'description' => 'Préavis']);
        ParametreSysteme::create(['cle' => CongeService::CLE_COUVERTURE, 'valeur' => '0', 'description' => 'Couverture']);
    }

    /**
     * @return array<string, mixed>
     */
    private function creneau(string $id, string $debut, string $fin, string $date = '2026-10-22'): array
    {
        return $this->creation('plannings', $id, [
            'employe_id' => $this->chef->id, 'service_id' => $this->cuisine->id,
            'date' => $date, 'heure_debut' => $debut, 'heure_fin' => $fin,
        ]);
    }

    #[Test]
    public function le_creneau_du_poste_est_ecrit_par_le_service_et_rejoue_sans_doublon(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->creneau($id, '08:00', '12:00')], $this->rh)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$this->creneau($id, '08:00', '12:00')], $this->rh)->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(1, Planning::query()->count());
    }

    #[Test]
    public function un_service_inconnu_par_son_identifiant_est_reconnu_par_son_libelle(): void
    {
        $id = $this->uuid();

        // Le poste n'a encore rien reçu : son identifiant de service lui est propre.
        $this->pousser([$this->creation('plannings', $id, [
            'employe_id' => $this->chef->id, 'service_id' => $this->uuid(), 'service_libelle' => 'Cuisine',
            'date' => '2026-10-22', 'heure_debut' => '08:00', 'heure_fin' => '12:00',
        ])], $this->rh)->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame($this->cuisine->id, Planning::query()->findOrFail($id)->service_id);

        // Ni identifiant ni libellé connus : le créneau est rejeté, jamais un service inventé.
        $this->pousser([$this->creation('plannings', $this->uuid(), [
            'employe_id' => $this->chef->id, 'service_id' => $this->uuid(), 'service_libelle' => 'Inexistant',
            'date' => '2026-10-23', 'heure_debut' => '08:00', 'heure_fin' => '12:00',
        ])], $this->rh)->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame(1, Planning::query()->count());
        $this->assertSame(1, Service::query()->count());
    }

    #[Test]
    public function rg13_deux_postes_ne_planifient_jamais_le_meme_employe_sur_le_meme_creneau(): void
    {
        $this->pousser([$this->creneau($this->uuid(), '08:00', '12:00')], $this->rh, 'poste-a');
        $this->pousser([$this->creneau($this->uuid(), '10:00', '14:00')], $this->rh, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->pousser([$this->creneau($this->uuid(), '12:00', '16:00')], $this->rh, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(2, Planning::query()->count());
    }

    #[Test]
    public function un_creneau_invalide_ou_hors_droit_est_rejete(): void
    {
        $this->pousser([$this->creneau($this->uuid(), '16:00', '08:00')], $this->rh)->assertJsonPath('resultats.0.statut', 'rejete');
        $this->pousser([$this->creation('plannings', $this->uuid(), [
            'employe_id' => $this->uuid(), 'service_id' => $this->cuisine->id,
            'date' => '2026-10-22', 'heure_debut' => '08:00', 'heure_fin' => '12:00',
        ])], $this->rh)->assertJsonPath('resultats.0.statut', 'rejete');
        $this->pousser([$this->creneau($this->uuid(), '08:00', '12:00')], $this->creerUtilisateur('cuisine'))
            ->assertJsonPath('resultats.0.statut', 'rejete');

        $this->assertSame(0, Planning::query()->count());
    }

    #[Test]
    public function la_demande_est_acceptee_puis_validee_ou_refusee_selon_rg14_et_un_rejeu_ne_change_rien(): void
    {
        $id = $this->uuid();
        $demande = $this->creation('conges', $id, [
            'employe_id' => $this->chef->id, 'type' => 'annuel', 'date_debut' => '2026-11-02', 'date_fin' => '2026-11-04',
        ]);
        $this->pousser([$demande], $this->rh)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$demande], $this->rh)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(1, Conge::query()->count());
        $this->assertSame('en_attente', Conge::findOrFail($id)->statut_validation);

        $decision = $this->operation('conges', 'modification', $id, ['statut_validation' => 'valide']);
        $this->pousser([$decision], $this->rh)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(['valide', $this->rh->id], [Conge::findOrFail($id)->statut_validation, Conge::findOrFail($id)->validateur_id]);

        $this->pousser([$decision], $this->rh)->assertJsonPath('resultats.0.statut', 'synchronise');
    }

    #[Test]
    public function un_preavis_insuffisant_rejette_la_decision_et_la_demande_reste_en_attente(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('conges', $id, [
            'employe_id' => $this->chef->id, 'type' => 'maladie', 'date_debut' => '2026-10-22', 'date_fin' => '2026-10-23',
        ])], $this->rh);

        $this->pousser([$this->operation('conges', 'modification', $id, ['statut_validation' => 'valide'])], $this->rh)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame('en_attente', Conge::findOrFail($id)->statut_validation);

        $this->pousser([$this->operation('conges', 'modification', $id, ['statut_validation' => 'refuse'])], $this->rh)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('refuse', Conge::findOrFail($id)->statut_validation);
    }

    #[Test]
    public function une_nature_hors_registre_et_un_champ_non_modifiable_sont_rejetes(): void
    {
        $this->pousser([$this->creation('conges', $this->uuid(), [
            'employe_id' => $this->chef->id, 'type' => 'vacances', 'date_debut' => '2026-11-02', 'date_fin' => '2026-11-04',
        ])], $this->rh)->assertJsonPath('resultats.0.statut', 'rejete');

        $id = $this->uuid();
        $this->pousser([$this->creation('conges', $id, [
            'employe_id' => $this->chef->id, 'type' => 'annuel', 'date_debut' => '2026-11-02', 'date_fin' => '2026-11-04',
        ])], $this->rh);
        $this->pousser([$this->operation('conges', 'modification', $id, ['date_fin' => '2026-12-31'])], $this->rh)
            ->assertJsonPath('resultats.0.statut', 'rejete');
    }

    #[Test]
    public function creneaux_et_conges_descendent_vers_les_autres_postes(): void
    {
        $idPlanning = $this->uuid();
        $idConge = $this->uuid();
        $this->pousser([
            $this->creneau($idPlanning, '08:00', '12:00'),
            $this->creation('conges', $idConge, ['employe_id' => $this->chef->id, 'type' => 'annuel', 'date_debut' => '2026-11-02', 'date_fin' => '2026-11-04']),
        ], $this->rh, 'poste-a');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($this->rh);
        $elements = [];
        $curseur = null;

        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        $planning = collect($elements)->firstWhere('table', 'plannings');
        $conge = collect($elements)->firstWhere('table', 'conges');
        $this->assertSame($idPlanning, $planning['id']);
        $this->assertSame(['2026-10-22', '08:00:00', '12:00:00'], [substr((string) $planning['donnees']['date'], 0, 10), $planning['donnees']['heure_debut'], $planning['donnees']['heure_fin']]);
        $this->assertSame($idConge, $conge['id']);
        $this->assertSame(['annuel', 'en_attente'], [$conge['donnees']['type'], $conge['donnees']['statut_validation']]);
    }
}
