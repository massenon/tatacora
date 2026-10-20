<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\ExerciceComptableService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Exploitation\Services\VerificationProductionService;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Le passage d'année — lot 1 (décision du Product Owner du 20/10/2026 :
 * « quand on bascule à N+1, toutes les données des modules sont
 * enregistrées »). Le 1er janvier, la première pièce de l'année ouvre son
 * exercice ; la tâche planifiée l'ouvre d'avance ; une date fantaisiste,
 * une année passée manquante ou un exercice clôturé n'ouvrent rien ; les
 * postes reçoivent les exercices et leur statut.
 */
final class PassageAnneeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-20 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->actingAs($this->utilisateur('comptable'));
    }

    private function piece(string $date): void
    {
        app(PasserEcritureService::class)->passerEtValider([
            'journal' => 'OD',
            'date' => $date,
            'libelle' => 'Vente du ' . $date,
            'lignes' => [
                ['compte' => '5711', 'debit' => '10000.00'],
                ['compte' => '7011', 'credit' => '10000.00', 'centre_id' => CentreCout::query()->where('libelle', 'Bar')->value('id') ?? CentreCout::query()->value('id')],
            ],
        ]);
    }

    #[Test]
    public function le_1er_janvier_la_premiere_piece_ouvre_l_exercice_et_c_est_trace(): void
    {
        $this->assertSame([2026], ExerciceComptable::query()->pluck('annee')->all());

        $this->travelTo('2027-01-01 00:30:00');
        $this->piece('2027-01-01');

        $exercice = ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
        $this->assertSame('ouvert', $exercice->statut);
        $this->assertSame('2027-01-01', $exercice->date_debut->format('Y-m-d'));
        $this->assertSame('2027-12-31', $exercice->date_fin->format('Y-m-d'));
        // 2026 reste ouvert (écritures d'inventaire en N pendant la saisie en N+1).
        $this->assertSame('ouvert', ExerciceComptable::query()->where('annee', 2026)->value('statut'));
        $this->assertSame(
            ['annee' => 2027, 'motif' => 'premiere_piece'],
            JournalAudit::query()->where('action', 'exercice_ouvert_automatiquement')->firstOrFail()->valeur_apres,
        );

        // La suivante n'ouvre rien de plus.
        $this->piece('2027-01-02');
        $this->assertSame(2, ExerciceComptable::query()->count());
    }

    #[Test]
    public function une_date_fantaisiste_ou_une_annee_passee_manquante_n_ouvre_rien(): void
    {
        foreach (['2031-05-04', '2019-03-02', '2027-01-15', '2026-02-30'] as $date) {
            try {
                $this->piece($date);
                $this->fail("La pièce du {$date} aurait dû être refusée.");
            } catch (RuntimeException $e) {
                $this->assertSame(__('depenses.exercice_absent', ['date' => $date]), $e->getMessage());
            }
        }

        $this->assertSame([2026], ExerciceComptable::query()->pluck('annee')->all());

        // En décembre, l'année suivante peut s'ouvrir d'avance.
        $this->travelTo('2026-12-30 18:00:00');
        $this->piece('2027-01-15');
        $this->assertTrue(ExerciceComptable::query()->where('annee', 2027)->exists());
    }

    #[Test]
    public function un_exercice_cloture_reste_cloture(): void
    {
        ExerciceComptable::query()->where('annee', 2026)->update(['statut' => 'cloture']);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage((string) __('depenses.exercice_clos', ['annee' => '2026', 'statut' => 'cloture']));
        try {
            $this->piece('2026-10-20');
        } finally {
            $this->assertSame('cloture', ExerciceComptable::query()->where('annee', 2026)->value('statut'));
            $this->assertSame(1, ExerciceComptable::query()->count());
        }
    }

    #[Test]
    public function la_tache_planifiee_ouvre_l_annee_en_cours_et_la_suivante_en_decembre(): void
    {
        ExerciceComptable::query()->delete();

        $this->artisan('tatacora:ouvrir-exercices')->assertSuccessful();
        $this->assertSame([2026], ExerciceComptable::query()->pluck('annee')->all());

        $this->travelTo('2026-12-01 00:05:00');
        $this->artisan('tatacora:ouvrir-exercices')->assertSuccessful();
        $this->artisan('tatacora:ouvrir-exercices')->assertSuccessful();
        $this->assertSame([2026, 2027], ExerciceComptable::query()->orderBy('annee')->pluck('annee')->all());

        $evenement = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())
            ->first(static fn ($e): bool => str_contains($e->getSummaryForDisplay(), 'tatacora:ouvrir-exercices'));
        $this->assertNotNull($evenement);
        $this->assertSame('5 0 * * *', $evenement->expression);
    }

    #[Test]
    public function assurer_ne_cree_qu_une_fois_et_refuse_une_annee_hors_bornes(): void
    {
        $service = app(ExerciceComptableService::class);
        $a = $service->assurer(2027, 'essai');
        $b = $service->assurer(2027, 'essai');
        $this->assertSame($a->id, $b->id);
        $this->assertSame(1, JournalAudit::query()->where('action', 'exercice_ouvert_automatiquement')->count());

        $this->expectException(RuntimeException::class);
        $service->assurer(1999, 'essai');
    }

    #[Test]
    public function la_verification_de_production_dit_l_exercice_du_jour(): void
    {
        $controle = fn (): array => collect(app(VerificationProductionService::class)->executer())->firstWhere('controle', 'exercice_comptable');

        $this->assertSame(VerificationProductionService::OK, $controle()['issue']);

        $this->travelTo('2026-12-02 09:00:00');
        $this->assertSame(VerificationProductionService::ATTENTION, $controle()['issue']);

        $this->travelTo('2027-01-01 09:00:00');
        $this->assertSame(VerificationProductionService::ECHEC, $controle()['issue']);
    }

    #[Test]
    public function les_exercices_et_leur_statut_descendent_vers_tout_compte(): void
    {
        ExerciceComptable::query()->where('annee', 2026)->update(['statut' => 'cloture', 'date_cloture' => now()]);
        $this->travel(10)->seconds();
        Sanctum::actingAs($this->utilisateur('barman'));

        $elements = collect($this->getJson('/api/v1/referentiels?poste_id=poste-a&limite=500')->assertOk()->json('data.elements'))
            ->where('table', 'exercices_comptables');

        $this->assertCount(1, $elements);
        $donnees = $elements->first()['donnees'];
        $this->assertSame(2026, (int) $donnees['annee']);
        $this->assertSame('cloture', $donnees['statut']);
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
