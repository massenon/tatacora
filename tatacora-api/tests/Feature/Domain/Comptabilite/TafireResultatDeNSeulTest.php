<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\ReadModels\Tafire;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Services\TafireService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le TAFIRE part du résultat de N SEUL (10/11/2026) : la CAFG est
 * « résultat net de N + dotations − reprises + VNC − produits de cessions », le
 * 131/139 reporté de N-1 est un capital propre (jamais du résultat de N), et la
 * contrepartie d'une affectation du résultat de N-1 (D 131 / C 121, 111, 118,
 * 465) est un mouvement de capitaux propres du financement. Il reste ÉQUILIBRÉ
 * (variation calculée par les flux = variation constatée aux classes 5) dans
 * tous les cas : exercice inaugural, N-1 clôturé non affecté, N-1 non clôturé
 * (à-nouveaux provisoires), après affectation (bénéfice, perte, règlements).
 *
 * Les pièces d'affectation sont écrites ICI à la main (journal OD) : ce test ne
 * dépend d'aucun service d'affectation.
 */
final class TafireResultatDeNSeulTest extends TestCase
{
    use RefreshDatabase;

    private User $comptable;

    private ExerciceComptable $n1;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-20 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->comptable = User::create([
            'login' => 'comptable.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'comptable')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        $this->actingAs($this->comptable);
        $this->n1 = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
    }

    private function centre(string $libelle): string
    {
        return (string) CentreCout::query()->where('libelle', $libelle)->value('id');
    }

    /**
     * @param  list<array{0: string, 1: string, 2: string}>  $lignes  [compte, débit, crédit]
     */
    private function piece(string $date, string $libelle, array $lignes, string $journal = 'OD'): void
    {
        $structure = $this->centre('Structure');
        app(PasserEcritureService::class)->passerEtValider([
            'journal' => $journal, 'date' => $date, 'libelle' => $libelle,
            'lignes' => array_map(static fn (array $l): array => [
                'compte' => $l[0], 'debit' => $l[1], 'credit' => $l[2], 'centre_id' => $structure,
            ], $lignes),
        ]);
    }

    /** Une vente, une charge, une dotation, dans l'exercice de l'année. */
    private function exploiter(string $annee, string $vente, string $charge, string $dotation): void
    {
        $this->piece("{$annee}-03-10", 'Ventes', [['5711', $vente, '0.00'], ['7011', '0.00', $vente]]);
        $this->piece("{$annee}-03-11", 'Achats', [['6011', $charge, '0.00'], ['5711', '0.00', $charge]]);
        $this->piece("{$annee}-12-30", 'Dotation', [['6813', $dotation, '0.00'], ['2813', '0.00', $dotation]]);
    }

    private function cloturer(ExerciceComptable $exercice): void
    {
        $service = app(ClotureExerciceService::class);
        $service->demarrer($exercice, $this->comptable);
        $service->cloturer($exercice->refresh(), $this->comptable);
    }

    private function tafire(int $annee): Tafire
    {
        $exercice = ExerciceComptable::query()->where('annee', $annee)->firstOrFail();

        return app(TafireService::class)->genererPourExercice($exercice->id, ['validee']);
    }

    private function assertEquilibre(Tafire $t): void
    {
        $this->assertSame($t->variationTresorerieReelle, $t->variationTresorerieCalculee, 'écart ' . $t->ecart);
        $this->assertSame('0.00', $t->ecart);
        $this->assertTrue($t->coherent);
        // Les trois flux somment la variation de trésorerie.
        $this->assertSame(
            $t->variationTresorerieCalculee,
            bcadd(bcadd($t->fluxExploitation, $t->fluxInvestissement, 2), $t->fluxFinancement, 2),
        );
    }

    /** N-1 (2026) : capital, matériel, exploitation, dotation ; résultat +60 000. */
    private function exploiterNMoinsUn(): void
    {
        $this->piece('2026-01-02', 'Capital', [['5711', '5000000.00', '0.00'], ['1013', '0.00', '5000000.00']]);
        $this->piece('2026-02-01', 'Matériel', [['2311', '1200000.00', '0.00'], ['5711', '0.00', '1200000.00']]);
        $this->exploiter('2026', '110000.00', '30000.00', '20000.00');
    }

    /** N (2027) : −210 559 (40 000 − 230 559 − dotation 20 000) et un matériel de 300 000. */
    private function exploiterN(): void
    {
        $this->travelTo('2027-03-20 10:00:00');
        $this->exploiter('2027', '40000.00', '230559.00', '20000.00');
        $this->piece('2027-04-01', 'Matériel', [['2311', '300000.00', '0.00'], ['5711', '0.00', '300000.00']]);
    }

    /** L'affectation de N-1 (+60 000), écrite à la main : 10 000 report, 5 000 + 5 000 réserves, 40 000 dividendes. */
    private function affecterBenefice(): void
    {
        $this->piece('2027-05-10', 'Affectation du résultat N-1', [
            ['131', '60000.00', '0.00'],
            ['121', '0.00', '10000.00'],
            ['111', '0.00', '5000.00'],
            ['1181', '0.00', '5000.00'],
            ['465', '0.00', '40000.00'],
        ]);
    }

    #[Test]
    public function sans_exercice_precedent_la_cafg_part_du_resultat_de_n_et_le_tafire_est_equilibre(): void
    {
        $this->exploiterNMoinsUn();
        $t = $this->tafire(2026);

        $this->assertSame('60000.00', $t->resultatExercice);
        $this->assertSame('20000.00', $t->dotationsAmortissements);
        $this->assertSame('80000.00', $t->capaciteAutofinancementGlobale);
        $this->assertSame('5000000.00', $t->augmentationCapital);
        $this->assertSame('1200000.00', $t->acquisitionsImmobilisations);
        $this->assertSame('0.00', $t->dividendesVerses);
        $this->assertSame('3880000.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);
    }

    #[Test]
    public function n_moins_un_cloture_non_affecte_le_resultat_de_n_1_ne_se_recompte_pas(): void
    {
        $this->exploiterNMoinsUn();
        $this->cloturer($this->n1);
        $this->exploiterN();
        $t = $this->tafire(2027);

        // Le résultat de N SEUL ; le 131 de 60 000 reste au bilan, hors CAFG.
        $this->assertSame('-210559.00', $t->resultatExercice);
        $this->assertSame('-190559.00', $t->capaciteAutofinancementGlobale);
        // Les 5 M de capital et les 1,2 M de matériel sont de N-1 (à-nouveaux) : pas des flux de N.
        $this->assertSame('0.00', $t->augmentationCapital);
        $this->assertSame('300000.00', $t->acquisitionsImmobilisations);
        $this->assertSame('0.00', $t->variationAutresCapitauxPropres);
        $this->assertSame('0.00', $t->dividendesVerses);
        $this->assertSame('-490559.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);
    }

    #[Test]
    public function n_moins_un_non_cloture_les_a_nouveaux_provisoires_ne_sont_pas_des_flux(): void
    {
        $this->exploiterNMoinsUn();
        app(ClotureExerciceService::class)->demarrer($this->n1, $this->comptable);
        $this->exploiterN();
        $t = $this->tafire(2027);

        $this->assertSame('-210559.00', $t->resultatExercice);
        $this->assertSame('-190559.00', $t->capaciteAutofinancementGlobale);
        $this->assertSame('-490559.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);
    }

    #[Test]
    public function apres_affectation_du_benefice_la_distribution_est_un_flux_de_financement(): void
    {
        $this->exploiterNMoinsUn();
        $this->cloturer($this->n1);
        $this->exploiterN();
        $this->affecterBenefice();

        $t = $this->tafire(2027);

        // Le résultat de N est inchangé par l'affectation de N-1.
        $this->assertSame('-210559.00', $t->resultatExercice);
        $this->assertSame('-190559.00', $t->capaciteAutofinancementGlobale);
        // Capitaux propres : −60 000 (131) + 10 000 + 5 000 + 5 000 = −40 000 ; 465 : +40 000, rien payé.
        $this->assertSame('-40000.00', $t->variationAutresCapitauxPropres);
        $this->assertSame('40000.00', $t->variationDividendesAPayer);
        $this->assertSame('0.00', $t->dividendesVerses);
        $this->assertSame('-490559.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);

        // Règlement partiel des dividendes : 25 000 décaissés.
        $this->piece('2027-06-15', 'Règlement dividendes', [['465', '25000.00', '0.00'], ['5711', '0.00', '25000.00']]);
        $t = $this->tafire(2027);
        $this->assertSame('15000.00', $t->variationDividendesAPayer);
        $this->assertSame('25000.00', $t->dividendesVerses);
        $this->assertSame('-25000.00', $t->fluxFinancement);
        $this->assertSame('-515559.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);
    }

    #[Test]
    public function apres_affectation_avec_n_moins_un_non_cloture_le_tafire_reste_equilibre(): void
    {
        $this->exploiterNMoinsUn();
        app(ClotureExerciceService::class)->demarrer($this->n1, $this->comptable);
        $this->exploiterN();
        $this->affecterBenefice();
        $this->piece('2027-06-15', 'Règlement dividendes', [['465', '40000.00', '0.00'], ['5711', '0.00', '40000.00']]);

        $t = $this->tafire(2027);
        $this->assertSame('40000.00', $t->dividendesVerses);
        $this->assertSame('-530559.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);
    }

    #[Test]
    public function apres_affectation_d_une_perte_le_tafire_reste_equilibre_sans_distribution(): void
    {
        $this->piece('2026-01-02', 'Capital', [['5711', '5000000.00', '0.00'], ['1013', '0.00', '5000000.00']]);
        $this->exploiter('2026', '10000.00', '50000.00', '20000.00'); // −60 000
        $this->cloturer($this->n1);
        $this->exploiterN();
        $this->piece('2027-05-10', 'Affectation de la perte N-1', [['1291', '60000.00', '0.00'], ['139', '0.00', '60000.00']]);

        $t = $this->tafire(2027);
        $this->assertSame('-210559.00', $t->resultatExercice);
        $this->assertSame('0.00', $t->variationAutresCapitauxPropres);
        $this->assertSame('0.00', $t->dividendesVerses);
        $this->assertEquilibre($t);
    }
}
