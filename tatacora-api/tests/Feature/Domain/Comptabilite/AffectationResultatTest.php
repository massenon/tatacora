<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\AffectationResultat;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\AffectationResultatService;
use App\Domain\Comptabilite\Services\ArchiveClotureService;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\CompteResultatService;
use App\Domain\Comptabilite\Services\EtatClotureService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Comptabilite\Support\FormeJuridique;
use App\Domain\Comptabilite\Support\RolesCorrespondance;
use App\Models\User;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * L'AFFECTATION DU RÉSULTAT d'un exercice clôturé (09/11/2026, demande du PO :
 * « ajoute l'affectation du résultat ») — de la vente à la clôture de N, bout en
 * bout : vente → clôture de N-1 → affectation (pièce OD datée dans N) → bilan de
 * N équilibré, « résultat reporté » à zéro, clôture de N juste ; et chaque règle
 * de refus, les droits, l'unicité, la contre-passation.
 *
 * Les MUTATIONS prouvées de ce lot (rapport de livraison) : retirer le contrôle
 * « somme = résultat » rougit `une_somme_differente_du_resultat_est_refusee` et
 * la carte web ; retirer l'unicité rougit `une_seconde_affectation_active_est_refusee`.
 */
final class AffectationResultatTest extends TestCase
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
        // Ce fichier éprouve les règles d'une SOCIÉTÉ (réserve légale, dividendes) : la
        // forme par défaut du Gîte, l'entreprise individuelle, a son propre fichier
        // (`AffectationFormeJuridiqueTest`).
        ParametreSysteme::query()->updateOrCreate(['cle' => FormeJuridique::CLE], ['valeur' => 'sarl']);
        $this->comptable = $this->utilisateur('comptable');
        $this->actingAs($this->comptable);
        $this->n1 = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
    }

    /** Le jour de la correction : une contre-passation se date d'AUJOURD'HUI, dans l'exercice qui porte l'affectation. */
    private function aujourdhuiEn2027(): void
    {
        $this->travelTo('2027-05-10 10:00:00');
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

    private function centre(string $libelle): string
    {
        return (string) CentreCout::query()->where('libelle', $libelle)->value('id');
    }

    private function service(): AffectationResultatService
    {
        return app(AffectationResultatService::class);
    }

    /** Une vente (bar) et une charge (restaurant) en 2026. */
    private function exploiter(string $vente, string $charge, string $annee = '2026'): void
    {
        $passer = app(PasserEcritureService::class);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => "{$annee}-03-10", 'libelle' => 'Ventes bar', 'lignes' => [
            ['compte' => '5711', 'debit' => $vente],
            ['compte' => '7011', 'credit' => $vente, 'centre_id' => $this->centre('Bar')],
        ]]);
        $passer->passerEtValider(['journal' => 'CAI', 'date' => "{$annee}-03-11", 'libelle' => 'Achats', 'lignes' => [
            ['compte' => '6011', 'debit' => $charge, 'centre_id' => $this->centre('Restaurant')],
            ['compte' => '5711', 'credit' => $charge],
        ]]);
    }

    /** Un apport en capital (1011) en 2026, pour que le capital soit déterminable. */
    private function capital(string $montant): void
    {
        app(PasserEcritureService::class)->passerEtValider(['journal' => 'OD', 'date' => '2026-01-05', 'libelle' => 'Capital', 'lignes' => [
            ['compte' => '5211', 'debit' => $montant],
            ['compte' => '1011', 'credit' => $montant, 'centre_id' => $this->centre('Structure')],
        ]]);
    }

    private function cloturer(ExerciceComptable $exercice): void
    {
        $service = app(ClotureExerciceService::class);
        $service->demarrer($exercice, $this->comptable);
        $service->cloturer($exercice->refresh(), $this->comptable);
    }

    /** Bénéfice de 70 000 en 2026, exercice clôturé. */
    private function benefice(): void
    {
        $this->exploiter('100000.00', '30000.00');
        $this->cloturer($this->n1);
    }

    private function n(): ExerciceComptable
    {
        return ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
    }

    /** @return array<string, string> soldes débit − crédit des comptes non soldés */
    private function soldes(ExerciceComptable $exercice): array
    {
        $b = app(BalanceGeneraleService::class)->genererPourExercice($exercice->id, ['validee']);
        $this->assertTrue($b->equilibree, 'balance équilibrée');

        return collect($b->lignes)
            ->mapWithKeys(fn ($l): array => [$l->numeroCompte => bcsub($l->totalDebit, $l->totalCredit, 2)])
            ->reject(fn (string $s): bool => bccomp($s, '0', 2) === 0)
            ->all();
    }

    /** @return array<string, string> */
    private function ventilation(string $rl = '0', string $ar = '0', string $div = '0', string $ran = '0', string $imp = '0', string $ce = '0'): array
    {
        return ['reserve_legale' => $rl, 'autres_reserves' => $ar, 'dividendes' => $div, 'report_a_nouveau' => $ran, 'imputation_report_crediteur' => $imp, 'compte_exploitant' => $ce];
    }

    private function refus(callable $geste, string $attendu): void
    {
        try {
            $geste();
        } catch (RuntimeException $e) {
            $this->assertStringContainsString($attendu, $e->getMessage());

            return;
        }

        $this->fail('Le refus « ' . $attendu . ' » n’a pas eu lieu.');
    }

    // ------------------------------------------------------------------
    // De la vente à la clôture de N : bénéfice
    // ------------------------------------------------------------------

    #[Test]
    public function de_la_vente_a_l_affectation_le_bilan_de_n_reste_equilibre_et_le_resultat_reporte_tombe_a_zero(): void
    {
        $this->benefice();
        $n = $this->n();

        // Avant : le résultat de 2026 reste en 131 dans 2027 (à-nouveaux écrits).
        $this->assertSame('-70000.00', $this->soldes($n)['131']);
        $avant = app(BilanService::class)->genererPourExercice($n->id, ['validee']);
        $this->assertSame('70000.00', $avant->resultatReporte);
        $bilan2026Avant = app(BilanService::class)->genererPourExercice($this->n1->id, ['validee']);

        $affectation = $this->service()->affecter(
            $this->n1->refresh(),
            $this->ventilation(rl: '7000', ar: '3000', div: '20000', ran: '40000'),
            '2027-04-30',
            $this->comptable,
            'Assemblée générale du 30/04/2027',
        );

        // La pièce : OD, datée dans 2027, validée, 131 débité, quatre postes crédités.
        $piece = EcritureComptable::query()->where('numero_piece', $affectation->piece_affectation)->get();
        $this->assertSame($n->id, (string) $piece->first()->exercice_id);
        $this->assertSame('OD', $piece->first()->journal->code);
        $this->assertSame(['2027-04-30'], $piece->map(fn ($e) => $e->date_ecriture->toDateString())->unique()->values()->all());
        $this->assertTrue($piece->every(fn ($e) => $e->statut === 'validee'));
        $parCompte = $piece->mapWithKeys(fn ($e): array => [$e->compte->numero_compte => [(string) $e->debit, (string) $e->credit]])->all();
        $this->assertSame([
            '131' => ['70000.00', '0.00'],
            '111' => ['0.00', '7000.00'],
            '1181' => ['0.00', '3000.00'],
            '465' => ['0.00', '20000.00'],
            '121' => ['0.00', '40000.00'],
        ], $parCompte);
        $this->assertSame('70000.00', (string) $affectation->resultat);
        $this->assertSame($this->comptable->id, $affectation->affectee_par);

        // Après : 131 soldé, le bilan de 2027 est équilibré, résultat reporté = 0.
        $soldes = $this->soldes($n);
        $this->assertArrayNotHasKey('131', $soldes);
        $this->assertSame('-7000.00', $soldes['111']);
        $this->assertSame('-40000.00', $soldes['121']);
        $apres = app(BilanService::class)->genererPourExercice($n->id, ['validee']);
        $this->assertTrue($apres->equilibre);
        $this->assertSame('0.00', $apres->ecart);
        $this->assertSame('0.00', $apres->resultatReporte, 'Résultat reporté tombé à 0 après affectation intégrale');
        $this->assertSame('0.00', $apres->resultatExercice);
        $this->assertSame($avant->totalActif, $apres->totalActif, 'l’actif ne bouge pas : l’affectation déplace des capitaux propres');

        // Le comparatif N-1 (2026) et le résultat de 2027 restent justes.
        $bilan2026Apres = app(BilanService::class)->genererPourExercice($this->n1->id, ['validee']);
        $this->assertSame($bilan2026Avant->resultatExercice, $bilan2026Apres->resultatExercice);
        $this->assertSame($bilan2026Avant->totalPassif, $bilan2026Apres->totalPassif);
        $this->assertSame('0.00', app(CompteResultatService::class)->genererPourExercice($n->id, ['validee'])->resultatNet);

        // L'audit : qui, quand, montants, motif.
        $audit = JournalAudit::query()->where('action', 'affectation_resultat')->firstOrFail();
        $this->assertSame($this->comptable->id, $audit->utilisateur_id);
        $this->assertSame('70000.00', $audit->valeur_apres['resultat']);
        $this->assertSame('Assemblée générale du 30/04/2027', $audit->valeur_apres['motif']);
        $this->assertSame($affectation->piece_affectation, $audit->valeur_apres['piece']);
    }

    #[Test]
    public function la_cloture_de_n_reste_juste_apres_l_affectation(): void
    {
        $this->benefice();
        $this->service()->affecter($this->n1->refresh(), $this->ventilation(rl: '7000', ran: '63000'), '2027-04-30', $this->comptable);
        $n = $this->n();
        $this->exploiter('50000.00', '10000.00', '2027');

        $service = app(ClotureExerciceService::class);
        $service->demarrer($n, $this->comptable);

        // L'état de clôture de N : résultat à reporter = celui de N seul (40 000),
        // 131/139 de la balance = résultat net calculé (rien d'autre que N).
        $etat = app(EtatClotureService::class)->genererPourExercice($n->refresh(), ['validee', 'brouillon']);
        $this->assertSame('40000.00', $etat->resultatAReporter);
        $this->assertTrue($etat->conditionsVerifiablesReunies);

        $cloture = $service->cloturer($n->refresh(), $this->comptable);
        $this->assertSame('40000.00', (string) $cloture->resultat);

        // CL/AN de N : 131 = résultat de N seul ; réserves et report de N-1 reportés.
        $suivant = ExerciceComptable::query()->where('annee', 2028)->firstOrFail();
        $an = EcritureComptable::query()->where('numero_piece', $cloture->piece_a_nouveaux)->get()
            ->mapWithKeys(fn ($e): array => [$e->compte->numero_compte => bcsub((string) $e->credit, (string) $e->debit, 2)])->all();
        $this->assertSame('40000.00', $an['131']);
        $this->assertSame('7000.00', $an['111']);
        $this->assertSame('63000.00', $an['121']);
        $this->assertTrue(app(BilanService::class)->genererPourExercice($suivant->id, ['validee'])->equilibre);
        $this->assertTrue(app(BilanService::class)->genererPourExercice($n->id, ['validee'])->equilibre);
        // 2027 clôturé : résultat reporté de 2028 = le résultat de 2027 seul.
        $this->assertSame('40000.00', app(BilanService::class)->genererPourExercice($suivant->id, ['validee'])->resultatReporte);
    }

    #[Test]
    public function l_archive_legale_de_n_moins_1_reste_valide_apres_l_affectation(): void
    {
        $this->benefice();
        $archives = app(ArchiveClotureService::class);
        $cloture = $archives->archiver(app(ClotureExerciceService::class)->clotureActive($this->n1->id), $this->comptable);
        $this->service()->affecter($this->n1->refresh(), $this->ventilation(ran: '70000'), '2027-04-30', $this->comptable);

        $this->assertFileExists($archives->zip($cloture->refresh()), 'l’archive de 2026 est toujours vérifiée puis délivrée');
    }

    #[Test]
    public function la_reserve_legale_est_proposee_a_dix_pour_cent_sous_le_plafond_de_vingt_pour_cent_du_capital(): void
    {
        $this->capital('500000.00');
        $this->benefice();
        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);

        $this->assertTrue($etat['reserveLegalePropose']);
        $this->assertSame('7000.00', $etat['proposition']['reserve_legale']);
        $this->assertSame('63000.00', $etat['proposition']['report_a_nouveau'], 'le report à nouveau reçoit le reste');
        $this->assertSame('70000.00', $etat['resultat']);
        $this->assertSame('2027-01-01', $etat['dateParDefaut'], 'N n’a pas commencé : le premier jour de N');
    }

    #[Test]
    public function la_reserve_legale_proposee_s_arrete_au_plafond_puis_disparait(): void
    {
        $this->aujourdhuiEn2027();
        $this->capital('500000.00');
        // 99 500 déjà en réserve légale sur un plafond de 100 000 : il reste 500.
        app(PasserEcritureService::class)->passerEtValider(['journal' => 'OD', 'date' => '2026-01-06', 'libelle' => 'Réserve existante', 'lignes' => [
            ['compte' => '5211', 'debit' => '99500.00'],
            ['compte' => '111', 'credit' => '99500.00', 'centre_id' => $this->centre('Structure')],
        ]]);
        $this->benefice();
        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);
        $this->assertSame('500.00', $etat['proposition']['reserve_legale']);
        $this->assertSame('69500.00', $etat['proposition']['report_a_nouveau']);

        // Plafond atteint : plus de proposition, l'écran le dit.
        $this->service()->affecter($this->n1, $this->ventilation(rl: '500', ran: '69500'), '2027-04-30', $this->comptable);
        $this->service()->contrepasser($this->n1, $this->comptable, 'Reprise de la ventilation');
        app(PasserEcritureService::class)->passerEtValider(['journal' => 'OD', 'date' => '2027-05-01', 'libelle' => 'Complément', 'lignes' => [
            ['compte' => '5211', 'debit' => '500.00'],
            ['compte' => '111', 'credit' => '500.00', 'centre_id' => $this->centre('Structure')],
        ]]);
        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);
        $this->assertTrue($etat['plafondReserveLegaleAtteint']);
        $this->assertSame('0.00', $etat['proposition']['reserve_legale']);
        $this->assertSame('70000.00', $etat['proposition']['report_a_nouveau']);
    }

    #[Test]
    public function sans_capital_determinable_aucune_reserve_legale_n_est_proposee(): void
    {
        $this->benefice();
        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);

        $this->assertFalse($etat['reserveLegalePropose']);
        $this->assertSame('0.00', $etat['proposition']['reserve_legale']);
        $this->assertSame('70000.00', $etat['proposition']['report_a_nouveau']);
    }

    // ------------------------------------------------------------------
    // Perte
    // ------------------------------------------------------------------

    #[Test]
    public function une_perte_se_reporte_a_nouveau_debiteur_et_solde_le_139(): void
    {
        $this->exploiter('10000.00', '30000.00');
        $this->cloturer($this->n1);
        $n = $this->n();
        $this->assertSame('20000.00', $this->soldes($n)['139']);

        $affectation = $this->service()->affecter($this->n1->refresh(), $this->ventilation(ran: '20000'), '2027-03-31', $this->comptable);

        $this->assertSame('-20000.00', (string) $affectation->resultat);
        $piece = EcritureComptable::query()->where('numero_piece', $affectation->piece_affectation)->get()
            ->mapWithKeys(fn ($e): array => [$e->compte->numero_compte => [(string) $e->debit, (string) $e->credit]])->all();
        $this->assertSame(['139' => ['0.00', '20000.00'], '1291' => ['20000.00', '0.00']], $piece);
        $soldes = $this->soldes($n);
        $this->assertArrayNotHasKey('139', $soldes);
        $this->assertSame('20000.00', $soldes['1291']);
        $bilan = app(BilanService::class)->genererPourExercice($n->id, ['validee']);
        $this->assertTrue($bilan->equilibre);
        $this->assertSame('0.00', $bilan->resultatReporte);
    }

    #[Test]
    public function une_perte_s_impute_sur_les_reserves_dans_la_limite_de_leur_solde(): void
    {
        // 15 000 de réserves facultatives (1181) existantes, perte de 20 000.
        app(PasserEcritureService::class)->passerEtValider(['journal' => 'OD', 'date' => '2026-01-06', 'libelle' => 'Réserves', 'lignes' => [
            ['compte' => '5211', 'debit' => '15000.00'],
            ['compte' => '1181', 'credit' => '15000.00', 'centre_id' => $this->centre('Structure')],
        ]]);
        $this->exploiter('10000.00', '30000.00');
        $this->cloturer($this->n1);

        $this->refus(
            fn () => $this->service()->affecter($this->n1->refresh(), $this->ventilation(ar: '20000'), '2027-03-31', $this->comptable),
            'dépasse son solde créditeur',
        );

        $this->service()->affecter($this->n1, $this->ventilation(ar: '15000', ran: '5000'), '2027-03-31', $this->comptable);
        $soldes = $this->soldes($this->n());
        $this->assertArrayNotHasKey('1181', $soldes, 'réserves entièrement imputées');
        $this->assertSame('5000.00', $soldes['1291']);
        $this->assertArrayNotHasKey('139', $soldes);
    }

    #[Test]
    public function pas_de_dividende_ni_de_reserve_legale_sur_une_perte(): void
    {
        $this->exploiter('10000.00', '30000.00');
        $this->cloturer($this->n1);

        $this->refus(
            fn () => $this->service()->affecter($this->n1->refresh(), $this->ventilation(div: '20000'), '2027-03-31', $this->comptable),
            'Aucun dividende ne se verse sur une perte',
        );
        $this->refus(
            fn () => $this->service()->affecter($this->n1, $this->ventilation(rl: '20000'), '2027-03-31', $this->comptable),
            'ne s\'affecte pas à la réserve légale',
        );
        $this->assertSame(0, AffectationResultat::query()->count());
    }

    // ------------------------------------------------------------------
    // Refus
    // ------------------------------------------------------------------

    #[Test]
    public function une_somme_differente_du_resultat_est_refusee(): void
    {
        $this->benefice();

        foreach (['69999', '70001'] as $total) {
            $this->refus(
                fn () => $this->service()->affecter($this->n1->refresh(), $this->ventilation(ran: $total), '2027-04-30', $this->comptable),
                'elle doit l\'égaler exactement',
            );
        }

        $this->refus(
            fn () => $this->service()->affecter($this->n1, $this->ventilation(rl: '7000', ran: '62999.99'), '2027-04-30', $this->comptable),
            'écart 0.01',
        );
        $this->assertSame(0, AffectationResultat::query()->count());
        $this->assertSame(0, EcritureComptable::query()->where('journal_id', \App\Domain\Comptabilite\Models\JournalComptable::query()->where('code', 'OD')->value('id'))->count());
        // Le centime près passe.
        $this->service()->affecter($this->n1, $this->ventilation(rl: '7000.50', ran: '62999.50'), '2027-04-30', $this->comptable);
        $this->assertSame(1, AffectationResultat::query()->count());
    }

    #[Test]
    public function un_montant_negatif_ou_illisible_est_refuse(): void
    {
        $this->benefice();

        $this->refus(
            fn () => $this->service()->affecter($this->n1->refresh(), $this->ventilation(rl: '-1000', ran: '71000'), '2027-04-30', $this->comptable),
            'ne peut pas être négatif',
        );
        $this->refus(
            fn () => $this->service()->affecter($this->n1, $this->ventilation(ran: 'abc'), '2027-04-30', $this->comptable),
            'n\'est pas lisible',
        );
    }

    #[Test]
    public function l_exercice_doit_etre_cloture(): void
    {
        $this->exploiter('100000.00', '30000.00');
        $this->refus(
            fn () => $this->service()->affecter($this->n1->refresh(), $this->ventilation(ran: '70000'), '2027-04-30', $this->comptable),
            'n\'est pas clôturé',
        );
        $this->assertNull($this->service()->etat($this->n1), 'pas de carte tant que N-1 n\'est pas clôturé');

        app(ClotureExerciceService::class)->demarrer($this->n1, $this->comptable);
        $this->refus(
            fn () => $this->service()->affecter($this->n1->refresh(), $this->ventilation(ran: '70000'), '2027-04-30', $this->comptable),
            'n\'est pas clôturé',
        );
    }

    #[Test]
    public function un_resultat_nul_ne_s_affecte_pas(): void
    {
        $this->exploiter('30000.00', '30000.00');
        $this->cloturer($this->n1);

        $this->refus(
            fn () => $this->service()->affecter($this->n1->refresh(), $this->ventilation(), '2027-04-30', $this->comptable),
            'est nul',
        );
    }

    #[Test]
    public function la_date_doit_tomber_dans_l_exercice_ouvert_qui_suit(): void
    {
        $this->benefice();
        $v = $this->ventilation(ran: '70000');

        $this->refus(fn () => $this->service()->affecter($this->n1->refresh(), $v, '2026-12-31', $this->comptable), 'doit tomber dans l\'exercice 2027');
        $this->refus(fn () => $this->service()->affecter($this->n1, $v, '2028-01-02', $this->comptable), 'doit tomber dans l\'exercice 2027');
        $this->refus(fn () => $this->service()->affecter($this->n1, $v, '2027-02-30', $this->comptable), 'n\'est pas une date valide');

        app(ClotureExerciceService::class)->demarrer($this->n(), $this->comptable);
        $this->refus(fn () => $this->service()->affecter($this->n1, $v, '2027-04-30', $this->comptable), 'dans un exercice ouvert');
    }

    #[Test]
    public function une_seconde_affectation_active_est_refusee_une_contrepassee_peut_etre_refaite(): void
    {
        $this->aujourdhuiEn2027();
        $this->benefice();
        $premiere = $this->service()->affecter($this->n1->refresh(), $this->ventilation(ran: '70000'), '2027-04-30', $this->comptable);

        $this->refus(
            fn () => $this->service()->affecter($this->n1, $this->ventilation(ran: '70000'), '2027-05-02', $this->comptable),
            'est déjà affecté (pièce ' . $premiere->piece_affectation . ')',
        );
        $this->assertSame(1, AffectationResultat::query()->count());

        $this->service()->contrepasser($this->n1, $this->comptable, 'Erreur de ventilation à corriger');
        $seconde = $this->service()->affecter($this->n1, $this->ventilation(rl: '7000', ran: '63000'), '2027-05-02', $this->comptable);

        $this->assertSame(2, AffectationResultat::query()->count());
        $this->assertSame(1, AffectationResultat::query()->whereNull('contrepassee_le')->count());
        $this->assertNotSame($premiere->piece_affectation, $seconde->piece_affectation);
        $this->assertSame($seconde->id, $this->service()->active($this->n1->id)->id);
        $this->assertArrayNotHasKey('131', $this->soldes($this->n()));
    }

    #[Test]
    public function le_comptable_et_le_gerant_affectent_et_contrepassent_l_administrateur_non(): void
    {
        $this->aujourdhuiEn2027();
        $this->benefice();
        $admin = $this->utilisateur('administrateur');
        $gerant = $this->utilisateur('gerant');
        $this->actingAs($admin);

        $this->refus(
            fn () => $this->service()->affecter($this->n1->refresh(), $this->ventilation(ran: '70000'), '2027-04-30', $admin),
            'Seul le comptable ou le gérant',
        );

        // Le gérant passe l'affectation (équivalence `User::ROLES_COMPTABILITE_SENSIBLE`)...
        $this->service()->affecter($this->n1, $this->ventilation(ran: '70000'), '2027-04-30', $gerant);
        $this->assertSame(1, AffectationResultat::query()->whereNull('contrepassee_le')->count());
        $this->assertTrue($this->service()->etat($this->n1->refresh(), $gerant)['peutAffecter']);
        $this->assertFalse($this->service()->etat($this->n1, $admin)['peutAffecter']);

        // ... l'administrateur ne la contre-passe pas, le gérant oui.
        $this->refus(
            fn () => $this->service()->contrepasser($this->n1, $admin, 'Motif assez long'),
            'Seul le comptable ou le gérant',
        );
        $this->assertSame(1, AffectationResultat::query()->whereNull('contrepassee_le')->count());
        $this->service()->contrepasser($this->n1, $gerant, 'Motif assez long');
        $this->assertSame(0, AffectationResultat::query()->whereNull('contrepassee_le')->count());
    }

    // ------------------------------------------------------------------
    // Contre-passation
    // ------------------------------------------------------------------

    #[Test]
    public function la_contrepassation_exige_un_motif_inverse_la_piece_et_rouvre_le_131(): void
    {
        $this->aujourdhuiEn2027();
        $this->benefice();
        $n = $this->n();
        $affectation = $this->service()->affecter($this->n1->refresh(), $this->ventilation(rl: '7000', ran: '63000'), '2027-04-30', $this->comptable);

        $this->refus(fn () => $this->service()->contrepasser($this->n1, $this->comptable, 'court'), '10 caractères au moins');

        $contre = $this->service()->contrepasser($this->n1, $this->comptable, 'Ventilation rejetée par l\'assemblée');
        $this->assertNotNull($contre->contrepassee_le);
        $this->assertSame('Ventilation rejetée par l\'assemblée', $contre->motif_contrepassation);
        $this->assertNull($this->service()->active($this->n1->id));

        // La pièce d'origine est intacte (RG-11) ; ses inverses la compensent.
        $origine = EcritureComptable::query()->where('numero_piece', $affectation->piece_affectation)->get();
        $this->assertCount(3, $origine);
        $this->assertSame(3, EcritureComptable::query()->whereIn('ecriture_contrepassee_id', $origine->pluck('id'))->count());
        $this->assertSame('-70000.00', $this->soldes($n)['131'], '131 retrouve le résultat de 2026');
        $this->assertSame('70000.00', app(BilanService::class)->genererPourExercice($n->id, ['validee'])->resultatReporte);

        $audit = JournalAudit::query()->where('action', 'affectation_resultat_contrepassee')->firstOrFail();
        $this->assertSame('Ventilation rejetée par l\'assemblée', $audit->valeur_apres['motif']);

        $this->refus(fn () => $this->service()->contrepasser($this->n1, $this->comptable, 'Une seconde fois, motif long'), 'aucune affectation active');
    }

    #[Test]
    public function rouvrir_n_moins_1_est_refuse_tant_que_l_affectation_est_active(): void
    {
        $this->aujourdhuiEn2027();
        $this->benefice();
        $this->service()->affecter($this->n1->refresh(), $this->ventilation(ran: '70000'), '2027-04-30', $this->comptable);
        $clotures = app(ClotureExerciceService::class);

        $this->refus(
            fn () => $clotures->rouvrir($this->n1->refresh(), $this->comptable, 'Correction d\'un compte de 2026'),
            'son résultat est affecté',
        );

        $this->service()->contrepasser($this->n1, $this->comptable, 'Avant réouverture de 2026');
        $clotures->rouvrir($this->n1->refresh(), $this->comptable, 'Correction d\'un compte de 2026');
        $this->assertSame('en_cloture', $this->n1->refresh()->statut);
        // L'à-nouveau de 2027 est contre-passé à son tour (le 131 qui reste est le provisoire calculé).
        $an = EcritureComptable::query()->where('exercice_id', $this->n()->id)->where('journal_id', \App\Domain\Comptabilite\Models\JournalComptable::query()->where('code', 'AN')->value('id'))->whereNull('ecriture_contrepassee_id')->get();
        $this->assertTrue($an->isNotEmpty());
        $this->assertTrue($an->every(fn ($e) => EcritureComptable::query()->where('ecriture_contrepassee_id', $e->id)->exists()));
    }

    #[Test]
    public function contrepasser_est_refuse_si_l_exercice_qui_porte_l_affectation_est_cloture(): void
    {
        $this->benefice();
        $this->service()->affecter($this->n1->refresh(), $this->ventilation(ran: '70000'), '2027-04-30', $this->comptable);
        $this->exploiter('1000.00', '500.00', '2027');
        $this->cloturer($this->n());

        $this->refus(
            fn () => $this->service()->contrepasser($this->n1->refresh(), $this->comptable, 'Trop tard pour corriger'),
            'est clôturé',
        );
    }

    // ------------------------------------------------------------------
    // Correspondance paramétrable
    // ------------------------------------------------------------------

    #[Test]
    public function les_comptes_viennent_de_la_correspondance_et_leurs_defauts_existent_au_plan(): void
    {
        foreach (['RESERVE_LEGALE' => '111', 'AUTRES_RESERVES' => '1181', 'DIVIDENDES_A_PAYER' => '465', 'REPORT_A_NOUVEAU_CREDITEUR' => '121', 'REPORT_A_NOUVEAU_DEBITEUR' => '1291'] as $role => $defaut) {
            $this->assertSame($defaut, RolesCorrespondance::defaut($role));
            $this->assertNotNull(CompteComptable::query()->where('numero_compte', $defaut)->first(), "le plan du dépôt porte $defaut");
        }

        // Rattacher les « autres réserves » au 1188 puis les dividendes au 465 :
        // c'est la correspondance, pas le code ; la pièce suit.
        app(EnregistrerParametreService::class)->enregistrer(['compte_autres_reserves' => '1188']);
        $this->benefice();
        $affectation = $this->service()->affecter($this->n1->refresh(), $this->ventilation(ar: '1000', ran: '69000'), '2027-04-30', $this->comptable);
        $comptes = EcritureComptable::query()->where('numero_piece', $affectation->piece_affectation)->get()
            ->map(fn ($e): string => $e->compte->numero_compte)->sort()->values()->all();
        $this->assertSame(['121', '131', '1188'], $comptes);

        // Une division est refusée par la correspondance elle-même (comme 118).
        $this->expectException(RuntimeException::class);
        app(EnregistrerParametreService::class)->enregistrer(['compte_autres_reserves' => '118']);
    }

    // ------------------------------------------------------------------
    // Web (Livewire)
    // ------------------------------------------------------------------

    private function hub(ExerciceComptable $exercice): \Livewire\Features\SupportTesting\Testable
    {
        return Livewire::withQueryParams(['exercice' => $exercice->id])->test(Hub::class, ['onglet' => 'clotures']);
    }

    #[Test]
    public function la_carte_web_propose_confirme_passe_et_contrepasse(): void
    {
        $this->aujourdhuiEn2027();
        $this->capital('500000.00');
        $this->benefice();

        $hub = $this->hub($this->n1->refresh())
            ->assertSee(__('comptabilite_pwa.affectation_titre', ['annee' => 2026]))
            ->assertSeeHtml('id="affectation-resultat"')
            ->assertSee(__('comptabilite_pwa.affectation_reserve_proposee'))
            ->assertSet('affectation.reserve_legale', '7000.00')
            ->assertSet('affectation.report_a_nouveau', '63000.00')
            ->assertSee(__('comptabilite_pwa.affectation_somme_ok'));

        // Contrôle en direct : changer un poste recalcule le report à nouveau,
        // une saisie qui ne s'équilibre plus le dit.
        $hub->set('affectation.dividendes', '10000')
            ->assertSet('affectation.report_a_nouveau', '53000.00')
            ->assertSee(__('comptabilite_pwa.affectation_somme_ok'))
            ->set('affectation.report_a_nouveau', '1000')
            ->assertSee(__('comptabilite_pwa.affectation_somme_ecart', ['ecart' => \App\Pwa\Support\MontantFcfa::format('52000.00')]));

        // Passer exige la confirmation, puis les règles du service s'appliquent.
        $hub->call('demanderAffectation')
            ->assertSee(__('comptabilite_pwa.affectation_confirmer_titre', ['annee' => 2026]))
            ->call('passerAffectation')
            ->assertHasErrors('affectation');
        $this->assertSame(0, AffectationResultat::query()->count());

        $hub->set('affectation.report_a_nouveau', '53000')
            ->set('dateAffectation', '2027-04-30')
            ->call('demanderAffectation')
            ->call('passerAffectation')
            ->assertHasNoErrors();

        $affectation = AffectationResultat::query()->firstOrFail();
        $this->assertSame('10000.00', (string) $affectation->dividendes);
        $this->assertSame('2027-04-30', $affectation->date_approbation->toDateString());

        // L'état : « Affectation passée le … par … (pièce n° …) » + contre-passation.
        $this->hub($this->n1->refresh())
            ->assertSee(__('comptabilite_pwa.affectation_passee', [
                'date' => \App\Shared\Support\HeureLocale::formater($affectation->affectee_le, 'd/m/Y H:i'),
                'auteur' => $this->comptable->login,
                'piece' => $affectation->piece_affectation,
            ]))
            ->assertDontSee(__('comptabilite_pwa.affectation_passer'))
            ->set('motifContrepassationAffectation', 'court')
            ->call('contrepasserAffectation')
            ->assertHasErrors('affectation')
            ->set('motifContrepassationAffectation', 'Ventilation à revoir en assemblée')
            ->call('contrepasserAffectation')
            ->assertHasNoErrors();

        $this->assertNull($this->service()->active($this->n1->id));
        $this->hub($this->n1)->assertSee(__('comptabilite_pwa.affectation_passer'));
    }

    #[Test]
    public function la_carte_se_lit_aussi_depuis_n_et_n_existe_pas_avant_la_cloture(): void
    {
        $this->exploiter('100000.00', '30000.00');
        $this->hub($this->n1->refresh())->assertDontSeeHtml('id="affectation-resultat"');

        $this->cloturer($this->n1);
        $this->hub($this->n())->assertSeeHtml('id="affectation-resultat"')
            ->assertSee(__('comptabilite_pwa.affectation_titre', ['annee' => 2026]));
    }

    #[Test]
    public function la_web_refuse_l_administrateur_avec_la_phrase_du_service_et_ouvre_au_gerant(): void
    {
        $this->benefice();
        $this->actingAs($this->utilisateur('gerant'));

        $this->hub($this->n1->refresh())
            ->assertSee(__('comptabilite_pwa.affectation_passer'))
            ->assertDontSee(__('comptabilite_pwa.affectation_reserve_comptable'));

        $this->actingAs($this->utilisateur('administrateur'));

        $this->hub($this->n1->refresh())
            ->assertSee(__('comptabilite_pwa.affectation_reserve_comptable'))
            ->assertDontSee(__('comptabilite_pwa.affectation_passer'))
            ->call('passerAffectation')
            ->assertHasErrors('affectation');
        $this->assertSame(0, AffectationResultat::query()->count());
    }

    #[Test]
    public function la_web_refuse_une_seconde_affectation_et_une_somme_fausse(): void
    {
        $this->benefice();
        $this->hub($this->n1->refresh())
            ->set('affectation.report_a_nouveau', '69999')
            ->call('passerAffectation')
            ->assertHasErrors('affectation');
        $this->assertSame(0, AffectationResultat::query()->count());

        $this->hub($this->n1)->call('passerAffectation')->assertHasNoErrors();
        $this->hub($this->n1)->call('passerAffectation');
        $this->assertSame(1, AffectationResultat::query()->count());
    }
}
