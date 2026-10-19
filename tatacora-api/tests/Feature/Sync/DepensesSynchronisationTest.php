<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Depenses\Models\Depense;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Dépenses saisies hors connexion — lot S3, décisions du Product Owner du
 * 15/10/2026.
 *
 * Le poste pousse la dépense SOURCE (montants en francs entiers, centre de
 * coût joint au payload) ; la pièce CAI/BQ est produite par
 * `DepenseService`, à la date de la transaction, numérotée dans l'année de
 * cette date. L'écriture locale du poste ne monte jamais (D246).
 */
final class DepensesSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $comptable;

    private CentreCout $structure;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerLeDecor();

        // `comptable` : M10 = 'C', le droit de l'écran Dépenses.
        $this->comptable = $this->creerUtilisateur('comptable');
        $this->structure = CentreCout::where('libelle', 'Structure')->firstOrFail();
    }

    #[Test]
    public function la_depense_est_comptabilisee_par_le_serveur_a_la_date_de_la_transaction(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->depense($id)], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $id)
            ->assertJsonPath('resultats.0.numero', 'DEP-2026-00001')
            ->assertJsonPath('resultats.0.montant_total', '17500.00');

        $depense = Depense::findOrFail($id);
        $this->assertSame('2026-10-12', $depense->date_transaction->toDateString());
        $this->assertSame($this->comptable->id, $depense->utilisateur_id);
        $this->assertCount(2, $depense->lignes);
        $this->assertSame(['Marché', 'Services'], $depense->lignes->pluck('famille')->sort()->values()->all());

        // La pièce : journal CAI, datée du 12/10, crédit caisse 5711, débits
        // 6011 imputés au centre transmis par le poste.
        $piece = EcritureComptable::where('numero_piece', EcritureComptable::findOrFail($depense->ecriture_id)->numero_piece)->get();
        $this->assertCount(3, $piece);
        $this->assertSame(['2026-10-12'], $piece->map(fn ($e) => $e->date_ecriture->toDateString())->unique()->values()->all());
        $this->assertSame(JournalComptable::where('code', 'CAI')->value('id'), $piece->first()->journal_id);
        $caisse = CompteComptable::where('numero_compte', '5711')->value('id');
        $this->assertSame('17500.00', (string) $piece->firstWhere('compte_id', $caisse)?->credit);
        $this->assertSame([$this->structure->id], $piece->pluck('centre_id')->unique()->values()->all());
    }

    #[Test]
    public function le_centre_est_retrouve_par_son_libelle_et_jamais_devine(): void
    {
        $this->pousser([$this->depense($this->uuid(), ['centre_id' => $this->uuid(), 'centre_libelle' => ' structure '])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->pousser([$this->depense($this->uuid(), ['centre_id' => $this->uuid(), 'centre_libelle' => 'Piscine'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.depenses.centre_introuvable', ['centre' => 'Piscine']));

        $this->assertSame(1, Depense::count());
    }

    /** RG-12 tient toujours : sans centre cité ni centre par défaut du compte, refus. */
    #[Test]
    public function sans_centre_la_piece_est_refusee_par_rg12(): void
    {
        CompteComptable::query()->update(['centre_cout_defaut_id' => null]);

        $this->pousser([$this->depense($this->uuid(), ['centre_id' => null, 'centre_libelle' => null])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('depenses.centre_absent', ['numero' => '6011']));

        $this->assertSame(0, Depense::count());
        $this->assertSame(0, EcritureComptable::count());
    }

    #[Test]
    public function le_numero_suit_l_annee_de_la_transaction(): void
    {
        $this->ouvrirExercice(2025);

        $this->pousser([$this->depense($this->uuid(), ['date_transaction' => '2025-12-31'])], $this->comptable)
            ->assertJsonPath('resultats.0.numero', 'DEP-2025-00001');

        $this->pousser([$this->depense($this->uuid())], $this->comptable)
            ->assertJsonPath('resultats.0.numero', 'DEP-2026-00001');
    }

    #[Test]
    public function le_rejeu_ne_decaisse_jamais_deux_fois(): void
    {
        $operation = $this->depense($this->uuid());

        $this->pousser([$operation], $this->comptable);
        $this->pousser([$operation], $this->comptable)->assertJsonPath('resultats.0.rejeu_idempotent', true);

        $this->purgerLaMemoireDIdempotence();

        $this->pousser([$this->nouvelleTentative($operation)], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.document_deja_enregistre', true)
            ->assertJsonPath('resultats.0.numero', 'DEP-2026-00001');

        $this->assertSame(1, Depense::count());
        // Une seule pièce de trois lignes (deux charges, une trésorerie).
        $this->assertSame(1, EcritureComptable::query()->distinct()->count('numero_piece'));
        $this->assertSame(3, EcritureComptable::count());
    }

    #[Test]
    public function sans_ecriture_sur_m10_aucune_depense_n_est_synchronisee(): void
    {
        $barman = $this->creerUtilisateur('barman');

        $this->pousser([$this->depense($this->uuid())], $barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'));

        $this->assertDatabaseHas('journal_securite', ['utilisateur_id' => $barman->id, 'module_concerne' => 'M10']);
        $this->assertSame(0, Depense::count());
    }

    #[Test]
    public function les_refus_portent_les_phrases_du_service_et_de_la_validation(): void
    {
        $reponse = $this->pousser([
            $this->depense($this->uuid(), ['lignes' => []]),
            $this->depense($this->uuid(), ['tresorerie' => 'coffre']),
            $this->depense($this->uuid(), ['lignes' => [['libelle' => 'Riz', 'compte_charge' => '999999', 'montant' => 1000]]]),
        ], $this->comptable);

        $reponse->assertJsonPath('resultats.0.motif', __('depenses.sans_ligne'))
            ->assertJsonPath('resultats.1.motif', __('depenses.tresorerie_inconnue', ['code' => 'coffre']))
            ->assertJsonPath('resultats.2.statut', 'rejete')
            ->assertJsonStructure(['resultats' => [2 => ['erreurs' => ['lignes.0.compte_charge']]]]);

        $this->assertSame(0, Depense::count());
    }

    #[Test]
    public function une_depense_ne_se_modifie_pas_par_la_synchronisation(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->depense($id)], $this->comptable);

        $this->pousser([$this->operation('depenses', 'modification', $id, ['libelle' => 'Autre'])], $this->comptable)
            ->assertJsonPath('resultats.0.motif', __('sync.modification_non_synchronisable'));

        $this->assertSame('Marché du matin', Depense::findOrFail($id)->libelle);
    }

    /**
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function depense(string $id, array $surcharges = []): array
    {
        $payload = [
            'date_transaction' => '2026-10-12',
            'tresorerie' => 'caisse',
            'libelle' => 'Marché du matin',
            'centre_id' => $this->structure->id,
            'centre_libelle' => 'Structure',
            'lignes' => [
                ['libelle' => 'Tomates', 'compte_charge' => '6011', 'nature' => 'Tomate', 'famille' => 'Marché', 'montant' => 12500],
                ['libelle' => 'Taxi-moto', 'compte_charge' => '6011', 'nature' => 'Transport', 'famille' => 'Services', 'montant' => 5000],
            ],
            ...$surcharges,
        ];

        return $this->operationDatee('depenses', 'creation', $id, $payload, '2026-10-12T09:00:00+00:00');
    }
}
