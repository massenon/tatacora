<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\AffectationResultat;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\AffectationResultatService;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
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
 * L'AFFECTATION DU RÉSULTAT SELON LA FORME JURIDIQUE (09/11/2026, décision du PO :
 * « le Gîte est une ENTREPRISE INDIVIDUELLE », avis révisé de l'expert-comptable
 * SYSCOHADA).
 *
 * Entreprise individuelle (défaut) : ni réserve légale, ni dividendes, le compte de
 * l'exploitant (1041) reçoit le reste. Société (SARL, SA) : réserve légale
 * obligatoire (10 % du bénéfice net des pertes antérieures, plafond 20 % du capital),
 * dividendes encadrés par les capitaux propres, alerte sous la moitié du capital.
 * Ordre d'imputation d'une perte. Contre-passation : date du jour dans N ouvert,
 * refusée si un dividende est réglé. Changement de forme refusé si une affectation
 * est active.
 *
 * Les MUTATIONS prouvées de ce lot sont listées au journal des lots
 * (`docs/JOURNAL_DES_LOTS.md`) : chaque règle ci-dessous a un test qui rougit quand
 * on la retire.
 */
final class AffectationFormeJuridiqueTest extends TestCase
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
        $this->comptable = $this->utilisateur('comptable');
        $this->actingAs($this->comptable);
        $this->n1 = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
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

    private function forme(string $valeur): void
    {
        ParametreSysteme::query()->updateOrCreate(['cle' => FormeJuridique::CLE], ['valeur' => $valeur]);
    }

    private function service(): AffectationResultatService
    {
        return app(AffectationResultatService::class);
    }

    private function centre(string $libelle): string
    {
        return (string) CentreCout::query()->where('libelle', $libelle)->value('id');
    }

    /** Une vente (bar) et une charge (restaurant) dans l'exercice [$annee]. */
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

    /** Un solde de bilan en 2026 : [$compte] créditeur (ou débiteur) de [$montant], contrepartie en banque. */
    private function solde(string $compte, string $montant, bool $crediteur = true): void
    {
        $structure = $this->centre('Structure');
        app(PasserEcritureService::class)->passerEtValider(['journal' => 'OD', 'date' => '2026-01-05', 'libelle' => "Solde {$compte}", 'lignes' => $crediteur
            ? [['compte' => '5211', 'debit' => $montant], ['compte' => $compte, 'credit' => $montant, 'centre_id' => $structure]]
            : [['compte' => $compte, 'debit' => $montant, 'centre_id' => $structure], ['compte' => '5211', 'credit' => $montant]]]);
    }

    private function cloturer(): void
    {
        $service = app(ClotureExerciceService::class);
        $service->demarrer($this->n1, $this->comptable);
        $service->cloturer($this->n1->refresh(), $this->comptable);
    }

    /** Bénéfice de 70 000 en 2026, exercice clôturé. */
    private function benefice(): void
    {
        $this->exploiter('100000.00', '30000.00');
        $this->cloturer();
    }

    /** Perte de 60 000 en 2026 (10 000 de ventes, 70 000 de charges), exercice clôturé. */
    private function perte(): void
    {
        $this->exploiter('10000.00', '70000.00');
        $this->cloturer();
    }

    private function n(): ExerciceComptable
    {
        return ExerciceComptable::query()->where('annee', 2027)->firstOrFail();
    }

    /**
     * @param  array<string, string>  $montants
     * @return array<string, string>
     */
    private function ventilation(array $montants): array
    {
        return array_merge([
            'reserve_legale' => '0', 'autres_reserves' => '0', 'dividendes' => '0',
            'report_a_nouveau' => '0', 'imputation_report_crediteur' => '0', 'compte_exploitant' => '0',
        ], $montants);
    }

    private function affecter(array $montants, string $date = '2027-04-30'): AffectationResultat
    {
        return $this->service()->affecter($this->n1->refresh(), $this->ventilation($montants), $date, $this->comptable);
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

    /**
     * Les lignes de la pièce, par compte : [débit, crédit], dans l'ordre des numéros.
     *
     * @return array<string, array{0: string, 1: string}>
     */
    private function piece(AffectationResultat $affectation): array
    {
        $lignes = EcritureComptable::query()->where('numero_piece', $affectation->piece_affectation)->get()
            ->mapWithKeys(fn ($e): array => [$e->compte->numero_compte => [(string) $e->debit, (string) $e->credit]])->all();
        ksort($lignes, SORT_STRING);

        return $lignes;
    }

    /** @param array<string, array{0: string, 1: string}> $attendu */
    private function assertPiece(array $attendu, AffectationResultat $affectation): void
    {
        ksort($attendu, SORT_STRING);
        $this->assertSame($attendu, $this->piece($affectation));
    }

    // ------------------------------------------------------------------
    // Le réglage « forme juridique »
    // ------------------------------------------------------------------

    #[Test]
    public function la_forme_par_defaut_est_l_entreprise_individuelle_et_une_valeur_inconnue_y_retombe(): void
    {
        $this->assertSame(FormeJuridique::EntrepriseIndividuelle, FormeJuridique::courante(), 'aucune ligne en base : le défaut du Gîte');
        $this->assertFalse(FormeJuridique::courante()->estSociete());

        $this->forme('Societe-en-nom-collectif');
        $this->assertSame(FormeJuridique::EntrepriseIndividuelle, FormeJuridique::courante(), 'valeur inconnue : le sens prudent');

        $this->forme('sa');
        $this->assertSame(FormeJuridique::Sa, FormeJuridique::courante());
        $this->assertTrue(FormeJuridique::Sa->estSociete());
        $this->assertSame(['entreprise_individuelle', 'sarl', 'sa'], FormeJuridique::valeurs());
        $this->assertSame('Entreprise individuelle', FormeJuridique::EntrepriseIndividuelle->libelle());
    }

    #[Test]
    public function le_compte_de_l_exploitant_est_un_role_de_la_correspondance_avec_un_defaut_feuille_du_plan(): void
    {
        $this->assertTrue(RolesCorrespondance::existe('COMPTE_EXPLOITANT'));
        $this->assertSame('1041', RolesCorrespondance::defaut('COMPTE_EXPLOITANT'));
        $this->assertSame(['104'], RolesCorrespondance::ROLES['COMPTE_EXPLOITANT']['prefixes']);
        $this->assertNotNull(CompteComptable::query()->where('numero_compte', '1041')->first(), '1041 est une feuille du plan du dépôt');
        $this->assertNotNull(CompteComptable::query()->where('numero_compte', '104')->first(), '104 est une division : jamais imputée directement');

        // 104 (division) est refusé par la correspondance ; 1042 est admis.
        $this->refus(fn () => app(EnregistrerParametreService::class)->enregistrer(['compte_compte_exploitant' => '104']), '104');
        app(EnregistrerParametreService::class)->enregistrer(['compte_compte_exploitant' => '1042']);
        $this->assertSame('1042', app(\App\Domain\Comptabilite\Services\CorrespondanceComptesService::class)->compte('COMPTE_EXPLOITANT'));
    }

    #[Test]
    public function le_changement_de_forme_est_reserve_a_l_administrateur_et_refuse_tant_qu_une_affectation_est_active(): void
    {
        $this->benefice();
        $enregistrer = app(EnregistrerParametreService::class);
        $administrateur = $this->utilisateur('administrateur');

        // Sans affectation : l'administrateur peut changer ; une valeur hors registre est refusée.
        $this->actingAs($administrateur);
        $this->assertSame(['forme_juridique'], $enregistrer->enregistrer(['forme_juridique' => 'sarl']));
        $this->refus(fn () => $enregistrer->enregistrer(['forme_juridique' => 'gie']), 'La forme juridique « gie » n’existe pas');

        // Le comptable n'est pas administrateur.
        $this->actingAs($this->comptable);
        $this->refus(fn () => $enregistrer->enregistrer(['forme_juridique' => 'sa']), 'réservée aux Administrateurs');
        $this->assertSame(FormeJuridique::Sarl, FormeJuridique::courante());

        // Une affectation ACTIVE : le changement est refusé, avec la phrase lisible.
        $this->service()->affecter($this->n1->refresh(), $this->ventilation(['report_a_nouveau' => '70000']), '2027-04-30', $this->comptable);
        $this->actingAs($administrateur);
        $this->refus(
            fn () => $enregistrer->enregistrer(['forme_juridique' => 'entreprise_individuelle']),
            'ne peut pas être changée tant qu’une affectation du résultat est active',
        );
        $this->assertSame(FormeJuridique::Sarl, FormeJuridique::courante());
        // Réécrire la MÊME valeur n'est pas un changement.
        $enregistrer->enregistrer(['forme_juridique' => 'sarl']);

        // Contre-passée : le changement est de nouveau permis.
        $this->actingAs($this->comptable);
        $this->travelTo('2027-05-10 10:00:00');
        $this->service()->contrepasser($this->n1->refresh(), $this->comptable, 'Reprise avant changement de forme');
        $this->actingAs($administrateur);
        $enregistrer->enregistrer(['forme_juridique' => 'entreprise_individuelle']);
        $this->assertSame(FormeJuridique::EntrepriseIndividuelle, FormeJuridique::courante());
    }

    // ------------------------------------------------------------------
    // Entreprise individuelle
    // ------------------------------------------------------------------

    #[Test]
    public function l_entreprise_individuelle_n_offre_ni_dividende_ni_reserve_legale_et_propose_le_compte_de_l_exploitant(): void
    {
        $this->solde('1011', '500000.00');
        $this->benefice();
        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);

        $this->assertSame('entreprise_individuelle', $etat['forme']);
        $this->assertFalse($etat['estSociete']);
        $this->assertSame(['compte_exploitant', 'autres_reserves', 'report_a_nouveau'], $etat['postes']);
        $this->assertNotContains('dividendes', $etat['postes']);
        $this->assertNotContains('reserve_legale', $etat['postes']);
        $this->assertSame('compte_exploitant', $etat['posteDuReste']);
        $this->assertSame('70000.00', $etat['proposition']['compte_exploitant'], 'le reste, ici tout, va au compte de l’exploitant');
        $this->assertSame('0.00', $etat['proposition']['reserve_legale'], 'aucune réserve légale proposée, même avec un capital');
        $this->assertSame('0.00', $etat['proposition']['report_a_nouveau']);
        $this->assertFalse($etat['reserveLegalePropose']);
    }

    #[Test]
    public function le_benefice_d_une_entreprise_individuelle_se_ventile_entre_104_report_et_reserves_et_le_bilan_reste_equilibre(): void
    {
        $this->benefice();
        $affectation = $this->affecter(['compte_exploitant' => '50000', 'report_a_nouveau' => '15000', 'autres_reserves' => '5000']);

        $this->assertPiece([
            '131' => ['70000.00', '0.00'],
            '1041' => ['0.00', '50000.00'],
            '121' => ['0.00', '15000.00'],
            '1181' => ['0.00', '5000.00'],
        ], $affectation);
        $this->assertSame('50000.00', (string) $affectation->compte_exploitant);
        $this->assertSame('entreprise_individuelle', $affectation->forme_juridique);
        $this->assertSame('15000.00', (string) $affectation->report_a_nouveau_crediteur);

        $balance = app(BalanceGeneraleService::class)->genererPourExercice($this->n()->id, ['validee']);
        $this->assertTrue($balance->equilibree);
        $bilan = app(BilanService::class)->genererPourExercice($this->n()->id, ['validee']);
        $this->assertTrue($bilan->equilibre, 'le compte de l’exploitant est un compte de capitaux propres du bilan');
        $this->assertSame([], $bilan->comptesHorsRubrique);
        $this->assertSame('0.00', $bilan->resultatReporte);

        $audit = JournalAudit::query()->where('action', 'affectation_resultat')->firstOrFail();
        $this->assertSame('entreprise_individuelle', $audit->valeur_apres['forme_juridique']);
        $this->assertSame('50000.00', $audit->valeur_apres['ventilation']['compte_exploitant']);
    }

    #[Test]
    public function le_compte_de_l_exploitant_suit_la_correspondance(): void
    {
        app(EnregistrerParametreService::class)->enregistrer(['compte_compte_exploitant' => '1042']);
        $this->benefice();
        $affectation = $this->affecter(['compte_exploitant' => '70000']);

        $this->assertPiece(['131' => ['70000.00', '0.00'], '1042' => ['0.00', '70000.00']], $affectation);
    }

    #[Test]
    public function une_entreprise_individuelle_refuse_dividende_et_reserve_legale_avec_leurs_phrases(): void
    {
        $this->benefice();

        $this->refus(
            fn () => $this->affecter(['dividendes' => '10000', 'compte_exploitant' => '60000']),
            'Une entreprise individuelle ne verse pas de dividendes (compte 465)',
        );
        $this->refus(
            fn () => $this->affecter(['reserve_legale' => '7000', 'compte_exploitant' => '63000']),
            'Une entreprise individuelle n\'a pas de réserve légale',
        );
        $this->assertSame(0, AffectationResultat::query()->count());
        $this->assertSame(0, EcritureComptable::query()->where('compte_id', CompteComptable::query()->where('numero_compte', '465')->value('id'))->count());
    }

    #[Test]
    public function la_perte_d_une_entreprise_individuelle_se_debite_au_compte_de_l_exploitant_ou_au_report_ou_s_impute_dans_la_limite_du_solde(): void
    {
        $this->solde('121', '8000.00');
        $this->solde('1181', '5000.00');
        $this->perte();
        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);

        $this->assertSame(['compte_exploitant', 'autres_reserves', 'imputation_report_crediteur', 'report_a_nouveau'], $etat['postes']);
        $this->assertSame('60000.00', $etat['proposition']['compte_exploitant'], 'EI : le défaut d’une perte reste le compte de l’exploitant');
        $this->assertSame('0.00', $etat['proposition']['imputation_report_crediteur']);

        // Imputation au-delà du solde : refusée.
        $this->refus(
            fn () => $this->affecter(['imputation_report_crediteur' => '9000', 'compte_exploitant' => '51000']),
            'dépasse son solde créditeur (8000.00)',
        );

        // 8 000 sur le 121, 5 000 sur le 1181, 10 000 au report débiteur, 37 000 à l'exploitant.
        $affectation = $this->affecter(['imputation_report_crediteur' => '8000', 'autres_reserves' => '5000', 'report_a_nouveau' => '10000', 'compte_exploitant' => '37000']);
        $this->assertPiece([
            '139' => ['0.00', '60000.00'],
            '121' => ['8000.00', '0.00'],
            '1181' => ['5000.00', '0.00'],
            '1291' => ['10000.00', '0.00'],
            '1041' => ['37000.00', '0.00'],
        ], $affectation);
        $this->assertTrue(app(BalanceGeneraleService::class)->genererPourExercice($this->n()->id, ['validee'])->equilibree);
        $this->assertSame('37000.00', (string) $affectation->compte_exploitant);
    }

    #[Test]
    public function une_perte_d_entreprise_individuelle_sans_alerte_de_capital_et_tout_a_l_exploitant_par_defaut(): void
    {
        $this->solde('1011', '100000.00');
        $this->perte();

        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);
        $this->assertSame([], $etat['alertes'], 'l’article 664 ne vaut que pour une société');

        $affectation = $this->affecter(['compte_exploitant' => '60000']);
        $this->assertPiece(['139' => ['0.00', '60000.00'], '1041' => ['60000.00', '0.00']], $affectation);
        $audit = JournalAudit::query()->where('action', 'affectation_resultat')->firstOrFail();
        $this->assertSame([], $audit->valeur_apres['alertes']);
    }

    #[Test]
    public function une_societe_n_a_pas_de_compte_de_l_exploitant(): void
    {
        $this->forme('sarl');
        $this->benefice();

        $this->refus(
            fn () => $this->affecter(['compte_exploitant' => '70000']),
            'Le compte de l\'exploitant n\'existe que dans une entreprise individuelle',
        );
        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);
        $this->assertSame(['reserve_legale', 'autres_reserves', 'dividendes', 'report_a_nouveau'], $etat['postes']);
        $this->assertSame('report_a_nouveau', $etat['posteDuReste']);
    }

    // ------------------------------------------------------------------
    // SARL / SA : réserve légale obligatoire
    // ------------------------------------------------------------------

    #[Test]
    public function la_reserve_legale_est_obligatoire_et_bloquante_dans_une_societe(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '500000.00');
        $this->benefice();

        // 10 % de 70 000 = 7 000 ; 6 999.99 est refusé, 7 000 passe, davantage aussi.
        $this->refus(
            fn () => $this->affecter(['reserve_legale' => '6999.99', 'report_a_nouveau' => '63000.01']),
            'La réserve légale est obligatoire : elle doit recevoir au moins 7000.00',
        );
        $this->refus(
            fn () => $this->affecter(['report_a_nouveau' => '70000']),
            'la ventilation en prévoit 0.00',
        );
        $this->assertSame(0, AffectationResultat::query()->count());

        $affectation = $this->affecter(['reserve_legale' => '7000', 'report_a_nouveau' => '63000']);
        $this->assertSame('7000.00', (string) $affectation->reserve_legale);
    }

    #[Test]
    public function la_reserve_legale_obligatoire_s_arrete_au_plafond_de_vingt_pour_cent_du_capital(): void
    {
        $this->forme('sa');
        $this->solde('1011', '500000.00');
        // 99 500 déjà en réserve légale sur un plafond de 100 000 : il ne reste que 500 à constituer.
        $this->solde('111', '99500.00');
        $this->benefice();

        $this->refus(
            fn () => $this->affecter(['reserve_legale' => '499.99', 'report_a_nouveau' => '69500.01']),
            'doit recevoir au moins 500.00',
        );
        $affectation = $this->affecter(['reserve_legale' => '500', 'report_a_nouveau' => '69500']);
        $this->assertSame('500.00', (string) $affectation->reserve_legale);
    }

    #[Test]
    public function une_fois_le_plafond_atteint_aucune_reserve_legale_n_est_due(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '500000.00');
        $this->solde('111', '100000.00');
        $this->benefice();

        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);
        $this->assertTrue($etat['plafondReserveLegaleAtteint']);
        $affectation = $this->affecter(['report_a_nouveau' => '70000']);
        $this->assertSame('0.00', (string) $affectation->reserve_legale);
    }

    #[Test]
    public function la_base_de_la_reserve_legale_est_le_benefice_net_des_pertes_anterieures(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '500000.00');
        // 30 000 de pertes antérieures (report à nouveau débiteur) : base 70 000 − 30 000 = 40 000, minimum 4 000.
        $this->solde('1291', '30000.00', crediteur: false);
        $this->benefice();

        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);
        $this->assertSame('4000.00', $etat['proposition']['reserve_legale'], 'la proposition suit la base nette');
        $this->assertSame('66000.00', $etat['proposition']['report_a_nouveau']);

        $this->refus(
            fn () => $this->affecter(['reserve_legale' => '3999.99', 'report_a_nouveau' => '66000.01']),
            'doit recevoir au moins 4000.00 (10 % de 40000.00, le bénéfice net des pertes antérieures de 30000.00)',
        );
        $this->affecter(['reserve_legale' => '4000', 'report_a_nouveau' => '66000']);
        $this->assertSame(1, AffectationResultat::query()->count());
    }

    #[Test]
    public function des_pertes_anterieures_superieures_au_benefice_ne_laissent_aucune_reserve_legale_due(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '500000.00');
        $this->solde('1291', '90000.00', crediteur: false);
        $this->benefice();

        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);
        $this->assertSame('0.00', $etat['proposition']['reserve_legale']);
        $this->affecter(['report_a_nouveau' => '70000']);
        $this->assertSame(1, AffectationResultat::query()->count());
    }

    #[Test]
    public function sans_capital_determinable_rien_ne_bloque_mais_un_avertissement_est_donne_et_trace(): void
    {
        $this->forme('sarl');
        $this->benefice();

        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);
        $this->assertFalse($etat['reserveLegalePropose']);
        $this->assertCount(1, $etat['avertissements']);
        $this->assertStringContainsString('Le capital n\'est pas déterminable', $etat['avertissements'][0]);

        $this->affecter(['report_a_nouveau' => '70000']);
        $audit = JournalAudit::query()->where('action', 'affectation_resultat')->firstOrFail();
        $this->assertCount(1, $audit->valeur_apres['avertissements'], 'l’avertissement est écrit au journal d’audit');
    }

    // ------------------------------------------------------------------
    // SARL / SA : dividendes et alerte
    // ------------------------------------------------------------------

    #[Test]
    public function un_dividende_est_refuse_s_il_fait_passer_les_capitaux_propres_sous_le_capital_et_les_reserves_non_distribuables(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '500000.00');
        // 40 000 de pertes antérieures : capitaux propres = 500 000 − 40 000 + 70 000 = 530 000 ;
        // réserve légale obligatoire 10 % de 30 000 = 3 000 ; plancher = 500 000 + 3 000.
        $this->solde('1291', '40000.00', crediteur: false);
        $this->benefice();

        // 27 000 de dividendes : capitaux propres 503 000 = plancher, accepté (à la limite).
        // 27 001 : 502 999 < 503 000, refusé.
        $this->refus(
            fn () => $this->affecter(['reserve_legale' => '3000', 'dividendes' => '27001', 'report_a_nouveau' => '39999']),
            'La distribution de 27001.00 ferait passer les capitaux propres à 502999.00, sous le capital augmenté des réserves non distribuables (503000.00)',
        );
        $this->assertSame(0, AffectationResultat::query()->count());
        $affectation = $this->affecter(['reserve_legale' => '3000', 'dividendes' => '27000', 'report_a_nouveau' => '40000']);
        $this->assertSame('27000.00', (string) $affectation->dividendes);
    }

    #[Test]
    public function un_dividende_qui_entamerait_le_capital_apres_des_pertes_lourdes_est_refuse(): void
    {
        $this->forme('sa');
        $this->solde('1011', '500000.00');
        $this->solde('1291', '80000.00', crediteur: false);
        $this->benefice();

        // Capitaux propres 490 000 < capital 500 000 : aucun dividende, même de 1.
        $this->refus(
            fn () => $this->affecter(['dividendes' => '1', 'report_a_nouveau' => '69999']),
            'ferait passer les capitaux propres à 489999.00',
        );
        $this->affecter(['report_a_nouveau' => '70000']);
        $this->assertSame(1, AffectationResultat::query()->count());
    }

    #[Test]
    public function l_alerte_sous_la_moitie_du_capital_est_non_bloquante_visible_sur_la_carte_et_a_l_audit(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '100000.00');
        $this->perte();

        // Capitaux propres : 100 000 − 60 000 = 40 000 < 50 000.
        $etat = $this->service()->etat($this->n1->refresh(), $this->comptable);
        $this->assertCount(1, $etat['alertes']);
        $this->assertStringContainsString('ALERTE', $etat['alertes'][0]);
        $this->assertStringContainsString('art. 664', $etat['alertes'][0]);
        $this->assertStringContainsString('(40000.00)', $etat['alertes'][0]);
        $this->assertStringContainsString('(100000.00)', $etat['alertes'][0]);

        $this->hub($this->n1)->assertSeeHtml('id="affectation-alerte"')->assertSee('quatre mois');

        // Non bloquante : l'affectation passe, et l'alerte est au journal d'audit.
        $affectation = $this->affecter(['report_a_nouveau' => '60000']);
        $this->assertSame(1, AffectationResultat::query()->count());
        $audit = JournalAudit::query()->where('action', 'affectation_resultat')->firstOrFail();
        $this->assertCount(1, $audit->valeur_apres['alertes']);
        $this->assertStringContainsString('art. 664', $audit->valeur_apres['alertes'][0]);

        // Toujours visible sur la carte une fois l'affectation passée.
        $this->hub($this->n1)->assertSeeHtml('id="affectation-alerte"');
        $this->assertNotNull($affectation->piece_affectation);
    }

    #[Test]
    public function aucune_alerte_quand_les_capitaux_propres_restent_au_dessus_de_la_moitie_du_capital(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '100000.00');
        $this->exploiter('30000.00', '70000.00');
        $this->cloturer();

        // Perte de 40 000 : capitaux propres 60 000 ≥ 50 000.
        $this->assertSame([], $this->service()->etat($this->n1->refresh(), $this->comptable)['alertes']);
        $this->hub($this->n1)->assertDontSeeHtml('id="affectation-alerte"');
    }

    #[Test]
    public function l_alerte_ne_vaut_pas_pour_un_benefice(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '500000.00');
        $this->solde('1291', '400000.00', crediteur: false);
        $this->benefice();

        // Capitaux propres 170 000 < moitié du capital, mais le résultat est un bénéfice : pas d'alerte de perte.
        $this->assertSame([], $this->service()->etat($this->n1->refresh(), $this->comptable)['alertes']);
    }

    // ------------------------------------------------------------------
    // Ordre d'imputation d'une perte
    // ------------------------------------------------------------------

    #[Test]
    public function une_perte_de_societe_s_impute_d_abord_sur_le_report_creditaire_puis_les_reserves_facultatives_puis_le_report_debiteur(): void
    {
        $this->forme('sarl');
        $this->solde('121', '8000.00');
        $this->solde('1181', '5000.00');
        $this->solde('111', '9000.00');
        $this->perte();

        $v = $this->service()->etat($this->n1->refresh(), $this->comptable)['proposition'];
        $this->assertSame('8000.00', $v['imputation_report_crediteur'], '121 d’abord, jusqu’à son solde');
        $this->assertSame('5000.00', $v['autres_reserves'], 'puis 1181, jusqu’à son solde');
        $this->assertSame('47000.00', $v['report_a_nouveau'], 'le reste en report à nouveau débiteur (1291)');
        $this->assertSame('0.00', $v['reserve_legale'], 'jamais la réserve légale sans choix explicite');
        $this->assertSame('0.00', $v['dividendes']);

        // La proposition est passable telle quelle.
        $affectation = $this->affecter(array_map(fn (string $m): string => $m, $v));
        $this->assertPiece([
            '139' => ['0.00', '60000.00'],
            '121' => ['8000.00', '0.00'],
            '1181' => ['5000.00', '0.00'],
            '1291' => ['47000.00', '0.00'],
        ], $affectation);
    }

    #[Test]
    public function une_petite_perte_n_entame_que_le_report_creditaire_et_ne_touche_jamais_la_reserve_legale(): void
    {
        $this->forme('sarl');
        $this->solde('121', '8000.00');
        $this->solde('1181', '5000.00');
        $this->solde('111', '9000.00');
        $this->exploiter('10000.00', '14000.00');
        $this->cloturer();

        $v = $this->service()->etat($this->n1->refresh(), $this->comptable)['proposition'];
        $this->assertSame('4000.00', $v['imputation_report_crediteur']);
        $this->assertSame('0.00', $v['autres_reserves']);
        $this->assertSame('0.00', $v['report_a_nouveau']);

        // La réserve légale ne reçoit pas une perte, même sur choix : refusé.
        $this->refus(
            fn () => $this->affecter(['reserve_legale' => '4000']),
            'Une perte ne s\'affecte pas à la réserve légale',
        );
    }

    #[Test]
    public function sans_report_ni_reserves_toute_la_perte_d_une_societe_va_au_report_debiteur(): void
    {
        $this->forme('sarl');
        $this->perte();
        $v = $this->service()->etat($this->n1->refresh(), $this->comptable)['proposition'];
        $this->assertSame('60000.00', $v['report_a_nouveau']);
        $this->assertSame('0.00', $v['imputation_report_crediteur']);
        $this->assertSame('0.00', $v['autres_reserves']);
    }

    // ------------------------------------------------------------------
    // Contre-passation
    // ------------------------------------------------------------------

    #[Test]
    public function la_contrepassation_est_datee_du_jour_de_la_correction_dans_n_et_trace_la_reference_de_la_decision(): void
    {
        $this->benefice();
        $affectation = $this->affecter(['compte_exploitant' => '70000'], '2027-04-30');

        $this->travelTo('2027-06-15 09:00:00');
        $contre = $this->service()->contrepasser(
            $this->n1->refresh(),
            $this->comptable,
            'Décision de l’exploitant révisée',
            '  Décision du 15/06/2027  ',
        );

        $this->assertSame('Décision du 15/06/2027', $contre->reference_decision_contrepassation);
        $inverses = EcritureComptable::query()
            ->whereIn('ecriture_contrepassee_id', EcritureComptable::query()->where('numero_piece', $affectation->piece_affectation)->pluck('id'))
            ->get();
        $this->assertCount(2, $inverses);
        $this->assertSame(['2027-06-15'], $inverses->map(fn ($e) => $e->date_ecriture->toDateString())->unique()->values()->all(), 'le jour de la correction, pas celui de l’affectation');
        $this->assertSame($this->n()->id, (string) $inverses->first()->exercice_id);

        $audit = JournalAudit::query()->where('action', 'affectation_resultat_contrepassee')->firstOrFail();
        $this->assertSame('Décision du 15/06/2027', $audit->valeur_apres['reference_decision']);
        $this->assertSame('2027-06-15', $audit->valeur_apres['date_contrepassation']);
    }

    #[Test]
    public function la_reference_de_la_decision_est_facultative_et_bornee(): void
    {
        $this->benefice();
        $this->affecter(['compte_exploitant' => '70000'], '2027-04-30');
        $this->travelTo('2027-06-15 09:00:00');

        $this->refus(
            fn () => $this->service()->contrepasser($this->n1->refresh(), $this->comptable, 'Décision de l’exploitant révisée', str_repeat('x', 256)),
            'limitée à 255 caractères',
        );
        $contre = $this->service()->contrepasser($this->n1, $this->comptable, 'Décision de l’exploitant révisée');
        $this->assertNull($contre->reference_decision_contrepassation);
        $audit = JournalAudit::query()->where('action', 'affectation_resultat_contrepassee')->firstOrFail();
        $this->assertNull($audit->valeur_apres['reference_decision']);
    }

    #[Test]
    public function la_contrepassation_n_est_jamais_anterieure_a_la_piece_d_origine_ni_hors_de_n(): void
    {
        $this->benefice();
        $this->affecter(['compte_exploitant' => '70000'], '2027-09-30');

        // Aujourd'hui (20/10/2026) est hors de N : la date du jour ne tombe pas dans 2027.
        $this->refus(
            fn () => $this->service()->contrepasser($this->n1->refresh(), $this->comptable, 'Correction de la décision'),
            'se date du jour de la correction (2026-10-20) : elle doit tomber dans l\'exercice 2027',
        );

        // Dans N mais AVANT la pièce d'origine (30/09/2027) : refusé.
        $this->travelTo('2027-05-10 10:00:00');
        $this->refus(
            fn () => $this->service()->contrepasser($this->n1, $this->comptable, 'Correction de la décision'),
            'ne peut pas être datée avant la pièce d\'affectation (2027-09-30)',
        );
        $this->assertNotNull($this->service()->active($this->n1->id));

        // Le jour même de la pièce : accepté.
        $this->travelTo('2027-09-30 10:00:00');
        $this->service()->contrepasser($this->n1, $this->comptable, 'Correction de la décision');
        $this->assertNull($this->service()->active($this->n1->id));
    }

    #[Test]
    public function la_contrepassation_exige_un_exercice_n_ouvert(): void
    {
        $this->benefice();
        $this->affecter(['compte_exploitant' => '70000'], '2027-04-30');
        $this->travelTo('2027-06-15 09:00:00');
        app(ClotureExerciceService::class)->demarrer($this->n(), $this->comptable);

        $this->refus(
            fn () => $this->service()->contrepasser($this->n1->refresh(), $this->comptable, 'Correction de la décision'),
            'est en_cloture. La contre-passation ne se passe que dans un exercice ouvert',
        );
        $this->assertNotNull($this->service()->active($this->n1->id));
    }

    #[Test]
    public function la_contrepassation_est_refusee_si_un_dividende_est_deja_regle_en_tout_ou_partie(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '500000.00');
        $this->benefice();
        $this->affecter(['reserve_legale' => '7000', 'dividendes' => '20000', 'report_a_nouveau' => '43000']);
        $this->travelTo('2027-06-15 09:00:00');

        // Règlement partiel : 8 000 sur les 20 000 de dividendes à payer (D 465 / C banque).
        $reglement = app(PasserEcritureService::class)->passerEtValider(['journal' => 'OD', 'date' => '2027-06-01', 'libelle' => 'Règlement partiel du dividende', 'lignes' => [
            ['compte' => '465', 'debit' => '8000.00', 'centre_id' => $this->centre('Structure')],
            ['compte' => '5211', 'credit' => '8000.00'],
        ]]);

        $this->refus(
            fn () => $this->service()->contrepasser($this->n1->refresh(), $this->comptable, 'Reprise de la ventilation'),
            'un dividende est déjà réglé en tout ou partie (8000.00 réglé sur 20000.00). Annulez d\'abord le règlement',
        );
        $this->assertNotNull($this->service()->active($this->n1->id));

        // Le règlement annulé (contre-passé), la contre-passation de l'affectation passe.
        app(PasserEcritureService::class)->contrepasserPiece($reglement, 'Annulation du règlement');
        $this->service()->contrepasser($this->n1->refresh(), $this->comptable, 'Reprise de la ventilation');
        $this->assertNull($this->service()->active($this->n1->id));
    }

    #[Test]
    public function une_contrepassation_sans_dividende_n_est_pas_gênee_par_un_mouvement_du_465(): void
    {
        $this->benefice();
        $this->affecter(['compte_exploitant' => '70000']);
        $this->travelTo('2027-06-15 09:00:00');
        $this->service()->contrepasser($this->n1->refresh(), $this->comptable, 'Reprise de la ventilation');
        $this->assertNull($this->service()->active($this->n1->id));
    }

    // ------------------------------------------------------------------
    // Web : la carte selon la forme
    // ------------------------------------------------------------------

    private function hub(ExerciceComptable $exercice): \Livewire\Features\SupportTesting\Testable
    {
        return Livewire::withQueryParams(['exercice' => $exercice->id])->test(Hub::class, ['onglet' => 'clotures']);
    }

    #[Test]
    public function la_carte_web_d_une_entreprise_individuelle_n_offre_ni_dividende_ni_reserve_legale_ni_assemblee(): void
    {
        $this->benefice();

        $this->hub($this->n1->refresh())
            ->assertSee(__('comptabilite_pwa.affectation_date_ei'))
            ->assertDontSee(__('comptabilite_pwa.affectation_date'))
            ->assertSee('Compte de l\'exploitant')
            ->assertSeeHtml('id="affectation-compte_exploitant"')
            ->assertDontSeeHtml('id="affectation-dividendes"')
            ->assertDontSeeHtml('id="affectation-reserve_legale"')
            ->assertDontSee(__('comptabilite_pwa.affectation_reserve_proposee'))
            ->assertSee(__('comptabilite_pwa.affectation_forme', ['forme' => 'Entreprise individuelle']))
            ->assertSet('affectation.compte_exploitant', '70000.00');
    }

    #[Test]
    public function la_carte_web_d_une_societe_garde_l_assemblee_les_dividendes_et_la_reserve_legale(): void
    {
        $this->forme('sarl');
        $this->solde('1011', '500000.00');
        $this->benefice();

        $this->hub($this->n1->refresh())
            ->assertSee(__('comptabilite_pwa.affectation_date'))
            ->assertDontSee(__('comptabilite_pwa.affectation_date_ei'))
            ->assertSeeHtml('id="affectation-dividendes"')
            ->assertSeeHtml('id="affectation-reserve_legale"')
            ->assertDontSeeHtml('id="affectation-compte_exploitant"')
            ->assertSee(__('comptabilite_pwa.affectation_reserve_proposee'))
            ->assertSet('affectation.reserve_legale', '7000.00');
    }

    #[Test]
    public function la_carte_web_ei_passe_avec_le_reste_au_compte_de_l_exploitant_et_la_contrepassation_porte_la_reference(): void
    {
        $this->benefice();

        $this->hub($this->n1->refresh())
            ->set('affectation.autres_reserves', '5000')
            ->assertSet('affectation.compte_exploitant', '65000.00', 'le reste va au compte de l’exploitant')
            ->set('affectation.report_a_nouveau', '10000')
            ->assertSet('affectation.compte_exploitant', '55000.00')
            ->set('dateAffectation', '2027-04-30')
            ->call('demanderAffectation')
            ->call('passerAffectation')
            ->assertHasNoErrors();

        $affectation = AffectationResultat::query()->firstOrFail();
        $this->assertSame('55000.00', (string) $affectation->compte_exploitant);
        $this->assertSame('5000.00', (string) $affectation->autres_reserves);
        $this->assertSame('10000.00', (string) $affectation->report_a_nouveau_crediteur);

        $this->travelTo('2027-05-10 10:00:00');
        $this->hub($this->n1->refresh())
            ->assertSee(__('comptabilite_pwa.affectation_contrepasser_reference'))
            ->assertSee('Compte de l\'exploitant : ')
            ->set('motifContrepassationAffectation', 'Décision révisée par l’exploitant')
            ->set('referenceContrepassationAffectation', 'Décision de l’exploitant du 10/05/2027')
            ->call('contrepasserAffectation')
            ->assertHasNoErrors();

        $this->assertSame('Décision de l’exploitant du 10/05/2027', $affectation->refresh()->reference_decision_contrepassation);
    }
}
