<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\ReadModels\Bilan;
use App\Domain\Comptabilite\ReadModels\Tafire;
use App\Domain\Comptabilite\Services\BilanService;
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
 *
 * AVIS DE L'EXPERT-COMPTABLE (10/11/2026, le Gîte est une entreprise
 * individuelle) : le compte 19 est une PROVISION FINANCIÈRE (aucun flux de
 * financement ; sa variation passe par les dotations 681, 687, 691, 697, 85 et les
 * reprises 781, 787, 791, 797, 798, 86 de la CAFG) ; les « emprunts » sont les
 * comptes 16 et 17 ; le 18 a sa ligne ; la quote-part de subvention virée au
 * résultat (799) sort de la CAFG ; le compte de l'exploitant (104) est un capital
 * propre dont les prélèvements se lisent avec les dividendes. Chaque scénario
 * ci-dessous reste ÉQUILIBRÉ (flux = variation des classes 5) ET le bilan aussi.
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

    private function bilan(int $annee): Bilan
    {
        $exercice = ExerciceComptable::query()->where('annee', $annee)->firstOrFail();

        return app(BilanService::class)->genererPourExercice($exercice->id, ['validee']);
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

    /** Capital 5 M et résultat de base : 110 000 − 30 000 = +80 000 avant tout le reste (2026). */
    private function baseExploitant(): void
    {
        $this->piece('2026-01-02', 'Capital', [['5711', '5000000.00', '0.00'], ['1013', '0.00', '5000000.00']]);
        $this->piece('2026-03-10', 'Ventes', [['5711', '110000.00', '0.00'], ['7011', '0.00', '110000.00']]);
        $this->piece('2026-03-11', 'Achats', [['6011', '30000.00', '0.00'], ['5711', '0.00', '30000.00']]);
    }

    #[Test]
    public function une_provision_financiere_dotee_n_entre_dans_aucun_flux_de_financement(): void
    {
        $this->baseExploitant();
        // Dotation financière (697) à une provision pour risques et charges (19) : rien ne sort de la caisse.
        $this->piece('2026-12-30', 'Provision financière', [['6971', '30000.00', '0.00'], ['1988', '0.00', '30000.00']]);

        $t = $this->tafire(2026);

        $this->assertSame('50000.00', $t->resultatExercice);
        $this->assertSame('30000.00', $t->dotationsAmortissements); // 697 : réintégrée à la CAFG
        $this->assertSame('80000.00', $t->capaciteAutofinancementGlobale);
        // Le 19 N'EST PAS un emprunt : aucun flux de financement, aucune acquisition.
        $this->assertSame('0.00', $t->variationEmprunts);
        $this->assertSame('0.00', $t->variationDettesParticipations);
        $this->assertSame('0.00', $t->acquisitionsImmobilisations);
        $this->assertSame('5000000.00', $t->fluxFinancement); // le capital seul
        $this->assertSame('5080000.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);

        // Le bilan range le 19 (« Dettes financières et ressources assimilées ») et s'équilibre.
        $b = $this->bilan(2026);
        $this->assertTrue($b->equilibre, 'écart ' . $b->ecart);
        $this->assertSame([], $b->comptesHorsRubrique);
        $dettesFinancieres = collect($b->passif)->firstWhere('code', 'dettes_financieres');
        $this->assertSame('30000.00', $dettesFinancieres->net);
    }

    #[Test]
    public function une_provision_financiere_reprise_reste_equilibree_dans_l_exercice_puis_au_suivant(): void
    {
        $this->baseExploitant();
        $this->piece('2026-12-30', 'Provision financière', [['6971', '30000.00', '0.00'], ['1988', '0.00', '30000.00']]);
        // Reprise partielle dans le même exercice : D 19 / C 797.
        $this->piece('2026-12-31', 'Reprise partielle', [['1988', '10000.00', '0.00'], ['7971', '0.00', '10000.00']]);
        $t = $this->tafire(2026);
        $this->assertSame('10000.00', $t->reprisesAmortissements);
        $this->assertSame('0.00', $t->variationEmprunts);
        // 60 000 de résultat (80 000 − 30 000 + 10 000) + 30 000 dotés − 10 000 repris.
        $this->assertSame('80000.00', $t->capaciteAutofinancementGlobale);
        $this->assertEquilibre($t);
        $this->assertTrue($this->bilan(2026)->equilibre);

        // N-1 clôturé avec 20 000 de provision restants ; reprise du solde en N (2027).
        $this->cloturer($this->n1);
        $this->travelTo('2027-03-20 10:00:00');
        $this->piece('2027-06-30', 'Reprise du solde', [['1988', '20000.00', '0.00'], ['7911', '0.00', '20000.00']]);
        $t = $this->tafire(2027);
        $this->assertSame('20000.00', $t->resultatExercice);
        $this->assertSame('0.00', $t->capaciteAutofinancementGlobale); // 20 000 de produit non encaissé, déduit
        $this->assertSame('0.00', $t->variationEmprunts);
        $this->assertSame('0.00', $t->fluxFinancement);
        $this->assertSame('0.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);
        $this->assertTrue($this->bilan(2027)->equilibre);
    }

    #[Test]
    public function chaque_dotation_et_chaque_reprise_de_l_avis_est_reintegree_ou_deduite_de_la_cafg(): void
    {
        $this->baseExploitant();
        // Une dotation par compte de l'avis, toutes sans trésorerie, contreparties : provisions ou amortissements.
        $this->piece('2026-12-01', '681', [['6813', '1000.00', '0.00'], ['2813', '0.00', '1000.00']]);
        $this->piece('2026-12-02', '687', [['687', '2000.00', '0.00'], ['1988', '0.00', '2000.00']]);
        $this->piece('2026-12-03', '691', [['6911', '4000.00', '0.00'], ['1988', '0.00', '4000.00']]);
        $this->piece('2026-12-04', '697', [['6971', '8000.00', '0.00'], ['1988', '0.00', '8000.00']]);
        $this->piece('2026-12-05', '85 (854)', [['854', '16000.00', '0.00'], ['1988', '0.00', '16000.00']]);
        $t = $this->tafire(2026);
        $this->assertSame('31000.00', $t->dotationsAmortissements);
        $this->assertEquilibre($t);

        // Une reprise par compte : 791, 797, 798 (D 28), 86 (864), 787 / 781 (vers l'actif immobilisé).
        $this->piece('2026-12-10', '791', [['1988', '100.00', '0.00'], ['7911', '0.00', '100.00']]);
        $this->piece('2026-12-11', '797', [['1988', '200.00', '0.00'], ['7971', '0.00', '200.00']]);
        $this->piece('2026-12-12', '798', [['2813', '400.00', '0.00'], ['798', '0.00', '400.00']]);
        $this->piece('2026-12-13', '864', [['1988', '800.00', '0.00'], ['864', '0.00', '800.00']]);
        $t = $this->tafire(2026);
        $this->assertSame('1500.00', $t->reprisesAmortissements);
        $this->assertEquilibre($t);
        $this->assertTrue($this->bilan(2026)->equilibre);

        // Un transfert de charges (781) porté à l'actif immobilisé : le décaissement est celui de l'investissement.
        $this->piece('2026-12-14', 'Frais engagés', [['6011', '5000.00', '0.00'], ['5711', '0.00', '5000.00']]);
        $this->piece('2026-12-15', 'Transfert vers l\'immobilisation', [['2311', '5000.00', '0.00'], ['781', '0.00', '5000.00']]);
        $t = $this->tafire(2026);
        $this->assertSame('6500.00', $t->reprisesAmortissements);
        $this->assertEquilibre($t);
        $this->assertTrue($this->bilan(2026)->equilibre);
    }

    #[Test]
    public function une_subvention_d_investissement_recue_est_un_apport_et_sa_quote_part_virée_sort_de_la_cafg(): void
    {
        $this->baseExploitant();
        // Reçue : 500 000 en banque, au 14.
        $this->piece('2026-04-01', 'Subvention reçue', [['5711', '500000.00', '0.00'], ['1416', '0.00', '500000.00']]);
        $avant = $this->tafire(2026);
        $this->assertSame('5500000.00', $avant->augmentationCapital); // capital + subvention reçue
        $this->assertSame('0.00', $avant->quotePartSubventions);
        $this->assertEquilibre($avant);

        // Quote-part virée au résultat : 100 000 (D 14 / C 799), produit NON encaissé.
        $this->piece('2026-12-31', 'Quote-part virée', [['1416', '100000.00', '0.00'], ['799', '0.00', '100000.00']]);
        $t = $this->tafire(2026);

        $this->assertSame('180000.00', $t->resultatExercice);
        $this->assertSame('100000.00', $t->quotePartSubventions);
        // CAFG : 180 000 − 100 000 (produit non encaissé) = 80 000, comme avant la quote-part.
        $this->assertSame('80000.00', $t->capaciteAutofinancementGlobale);
        // Apports : la subvention REÇUE (variation du 14 : 400 000, plus la quote-part virée : 100 000).
        $this->assertSame('5500000.00', $t->augmentationCapital);
        $this->assertSame('5580000.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);

        $b = $this->bilan(2026);
        $this->assertTrue($b->equilibre, 'écart ' . $b->ecart);
        $this->assertSame([], $b->comptesHorsRubrique);
    }

    #[Test]
    public function une_dotation_hao_aux_provisions_aux_amortissements_et_aux_provisions_reglementees_reste_equilibree(): void
    {
        $this->baseExploitant();
        $this->piece('2026-02-01', 'Matériel', [['2311', '1200000.00', '0.00'], ['5711', '0.00', '1200000.00']]);
        $this->piece('2026-12-20', 'Provision HAO', [['854', '20000.00', '0.00'], ['1988', '0.00', '20000.00']]);
        $this->piece('2026-12-21', 'Amortissement HAO', [['852', '15000.00', '0.00'], ['2813', '0.00', '15000.00']]);
        $this->piece('2026-12-22', 'Amortissement dérogatoire', [['851', '10000.00', '0.00'], ['151', '0.00', '10000.00']]);

        $t = $this->tafire(2026);
        $this->assertSame('35000.00', $t->resultatExercice);
        $this->assertSame('45000.00', $t->dotationsAmortissements);
        $this->assertSame('80000.00', $t->capaciteAutofinancementGlobale);
        // Les acquisitions : 1 200 000 de matériel, rien de plus (852 se compense, 854 et 851 n'y sont pas).
        $this->assertSame('1200000.00', $t->acquisitionsImmobilisations);
        // Le 15 (provisions réglementées) n'est PAS un dividende.
        $this->assertSame('0.00', $t->dividendesVerses);
        $this->assertSame('0.00', $t->variationAutresCapitauxPropres);
        $this->assertEquilibre($t);
        $this->assertTrue($this->bilan(2026)->equilibre);
    }

    #[Test]
    public function les_dettes_liees_a_des_participations_ont_leur_ligne_distincte_des_emprunts(): void
    {
        $this->baseExploitant();
        $this->piece('2026-05-01', 'Dette de participation', [['5711', '300000.00', '0.00'], ['1811', '0.00', '300000.00']]);
        $this->piece('2026-05-02', 'Emprunt', [['5711', '700000.00', '0.00'], ['162', '0.00', '700000.00']]);

        $t = $this->tafire(2026);
        $this->assertSame('300000.00', $t->variationDettesParticipations);
        $this->assertSame('700000.00', $t->variationEmprunts); // 16 et 17 seulement
        $this->assertSame('6000000.00', $t->fluxFinancement);
        $this->assertEquilibre($t);
        $this->assertTrue($this->bilan(2026)->equilibre);
    }

    #[Test]
    public function le_compte_de_l_exploitant_est_un_capital_propre_et_ses_mouvements_equilibrent_le_tafire(): void
    {
        $this->exploiterNMoinsUn(); // résultat +60 000
        $this->cloturer($this->n1);
        $this->exploiterN();
        // Affectation du bénéfice de N-1 au compte de l'exploitant, écrite à la main : D 131 / C 1042.
        $this->piece('2027-05-10', 'Affectation à l\'exploitant', [['131', '60000.00', '0.00'], ['1042', '0.00', '60000.00']]);

        $t = $this->tafire(2027);
        // 131 baisse, 104 monte : rien ne sort, rien n'est un apport.
        $this->assertSame('0.00', $t->dividendesVerses);
        $this->assertSame('0.00', $t->augmentationCapital);
        $this->assertSame('-490559.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);

        $b = $this->bilan(2027);
        $this->assertTrue($b->equilibre, 'écart ' . $b->ecart);
        $this->assertSame([], $b->comptesHorsRubrique);
        $this->assertContains('104', collect($b->passif)->firstWhere('code', 'capitaux_propres')->prefixes);

        // Un prélèvement personnel (D 104 / C 5711) : un décaissement de financement, lu avec les dividendes.
        $this->piece('2027-06-15', 'Prélèvement personnel', [['1043', '25000.00', '0.00'], ['5711', '0.00', '25000.00']]);
        $t = $this->tafire(2027);
        $this->assertSame('25000.00', $t->dividendesVerses);
        $this->assertSame('-25000.00', $t->fluxFinancement);
        $this->assertSame('-515559.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);
        $this->assertTrue($this->bilan(2027)->equilibre);

        // Un apport de l'exploitant en compte (D 5711 / C 1041) : une ressource, pas une augmentation de capital.
        $this->piece('2027-07-01', 'Apport en compte', [['5711', '40000.00', '0.00'], ['1041', '0.00', '40000.00']]);
        $t = $this->tafire(2027);
        // Prélèvement 25 000 puis apport 40 000 : le financement net est +15 000.
        $this->assertSame('15000.00', $t->fluxFinancement);
        $this->assertSame('-15000.00', $t->dividendesVerses);
        $this->assertSame('0.00', $t->augmentationCapital);
        $this->assertSame('-475559.00', $t->variationTresorerieReelle);
        $this->assertEquilibre($t);
        $this->assertTrue($this->bilan(2027)->equilibre);
    }

    #[Test]
    public function le_465_est_au_passif_circulant_du_bilan_mais_hors_du_bfr_du_tafire(): void
    {
        $this->exploiterNMoinsUn();
        $this->cloturer($this->n1);
        $this->exploiterN();
        $this->affecterBenefice();

        $t = $this->tafire(2027);
        // L'identité du TAFIRE ne change pas : le 465 n'est pas une dette du BFR.
        $this->assertSame('0.00', $t->variationDettes);
        $this->assertSame('40000.00', $t->variationDividendesAPayer);
        $this->assertEquilibre($t);

        $b = $this->bilan(2027);
        $this->assertSame('40000.00', $b->dividendesAPayer);
        $circulant = collect($b->passif)->firstWhere('code', 'passif_circulant');
        $this->assertSame('40000.00', $circulant->net, 'le 465 est dans le passif circulant du bilan');
        $this->assertContains('465', $circulant->prefixes);
        $this->assertTrue($b->equilibre, 'écart ' . $b->ecart);
    }
}
