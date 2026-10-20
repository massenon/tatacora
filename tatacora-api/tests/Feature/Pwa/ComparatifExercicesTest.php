<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\ExerciceComptableService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Models\User;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Pwa\Support\MontantFcfa;
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
 * Lot 3 (20/10/2026) — la NAVIGATION entre exercices et la consultation
 * COMPARATIVE N / N-1 du hub Comptabilité : colonne N-1 au compte de
 * résultat et au bilan, liens N-1 / N+1, statut de l'exercice consulté dit
 * à l'écran, à-nouveaux provisoires signalés, et la saisie d'inventaire du
 * comptable dans un exercice en clôture.
 */
final class ComparatifExercicesTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private ExerciceComptable $n1;

    private ExerciceComptable $n;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2027-02-10 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->comptable = User::create([
            'login' => 'comptable.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'comptable')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        $this->actingAs($this->comptable);

        $this->n1 = ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
        // 2026 : l'exercice précédent, encore ouvert (écritures tardives).
        $this->n = app(ExerciceComptableService::class)->ouvrir(2026);

        $bar = (string) CentreCout::query()->where('libelle', 'Bar')->value('id');
        $passer = app(PasserEcritureService::class);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-06-10', 'libelle' => 'Ventes bar 2026', 'lignes' => [
            ['compte' => '5711', 'debit' => '80000.00'],
            ['compte' => '7011', 'credit' => '80000.00', 'centre_id' => $bar],
        ]]);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => '2027-01-15', 'libelle' => 'Ventes bar 2027', 'lignes' => [
            ['compte' => '5711', 'debit' => '25000.00'],
            ['compte' => '7011', 'credit' => '25000.00', 'centre_id' => $bar],
        ]]);
    }

    private function hub(ExerciceComptable $exercice, string $onglet): \Livewire\Features\SupportTesting\Testable
    {
        return Livewire::withQueryParams(['exercice' => $exercice->id])->test(Hub::class, ['onglet' => $onglet]);
    }

    #[Test]
    public function le_compte_de_resultat_et_le_bilan_portent_la_colonne_n_moins_1(): void
    {
        $colonne = __('comptabilite_pwa.colonne_exercice_precedent', ['annee' => 2026]);

        $this->hub($this->n1, 'resultat')
            ->assertSee($colonne)
            ->assertSeeInOrder(['XI', MontantFcfa::format('25000.00'), MontantFcfa::format('80000.00')]);

        $this->hub($this->n1, 'bilan')
            ->assertSee($colonne);

        // 2026 n'a pas d'exercice précédent : pas de colonne.
        $this->hub($this->n, 'resultat')
            ->assertDontSee(__('comptabilite_pwa.colonne_exercice_precedent', ['annee' => 2025]));
    }

    #[Test]
    public function la_navigation_mene_a_n_moins_1_et_n_plus_1(): void
    {
        $this->hub($this->n1, 'journal')
            ->assertSee(__('comptabilite_pwa.exercice_precedent', ['annee' => 2026]))
            ->assertSeeHtml('exercice='.$this->n->id);

        $this->hub($this->n, 'journal')
            ->assertSeeHtml('exercice='.$this->n1->id)
            ->assertSeeHtml('id="navigation-exercices"');
    }

    #[Test]
    public function la_balance_dit_ses_a_nouveaux_provisoires(): void
    {
        $this->hub($this->n1, 'balance')
            ->assertSee(__('comptabilite_pwa.a_nouveaux_provisoires', ['annee' => 2026]));
        $this->hub($this->n, 'balance')
            ->assertDontSeeHtml('id="a-nouveaux-provisoires"');
    }

    #[Test]
    public function le_statut_de_l_exercice_consulte_est_dit_et_l_inventaire_passe_en_cloture(): void
    {
        $this->hub($this->n, 'journal')->assertDontSeeHtml('id="bandeau-statut-exercice"');

        app(ClotureExerciceService::class)->demarrer($this->n, $this->comptable);
        $this->hub($this->n, 'journal')
            ->assertSee(__('comptabilite_pwa.bandeau_en_cloture', ['annee' => 2026]));

        // L'écriture d'inventaire du comptable, saisie au hub, passe en clôture.
        $structure = (string) CentreCout::query()->where('libelle', 'Structure')->value('id');
        $piece = fn (string $journal) => $this->hub($this->n, 'saisie')
            ->call('ouvrirFormulairePiece')
            ->set('journalCode', $journal)
            ->set('dateEcriture', '2026-12-31')
            ->set('libellePiece', 'Inventaire de fin d\'exercice')
            ->set('lignesPiece', [
                ['compte' => '6011', 'libelle' => '', 'centre_id' => $structure, 'debit' => '5000', 'credit' => ''],
                ['compte' => '5711', 'libelle' => '', 'centre_id' => '', 'debit' => '', 'credit' => '5000'],
            ])
            ->call('enregistrerPieceValidee');

        $piece('OD')->assertHasNoErrors();
        $this->assertTrue(EcritureComptable::query()->where('exercice_id', $this->n->id)->where('libelle', 'Inventaire de fin d\'exercice')->exists());

        // Les journaux de la clôture ne se saisissent pas à la main.
        $piece('CL')->assertHasErrors(['journalCode']);
        $this->hub($this->n, 'saisie')->call('ouvrirFormulairePiece')->assertDontSeeHtml('<option value="CL">');

        app(ClotureExerciceService::class)->cloturer($this->n->refresh(), $this->comptable);
        $this->hub($this->n, 'journal')
            ->assertSee(__('comptabilite_pwa.bandeau_cloture', ['annee' => 2026]));

        // Clôturé : la saisie du hub est refusée, même au comptable.
        $piece('OD')->assertHasErrors(['piece']);
    }
}
