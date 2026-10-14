<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Comptabilite\Services\DeclarationTvaService;
use App\Shared\Parametres\Models\ParametreSysteme;
use Database\Seeders\TvaReferentielSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Déclaration de TVA — comptes 4431 (collectée) et 4452 (déductible).
 *
 * Module ajouté sur instruction du Consultant Technique (15/08/2026), absent
 * de la collection documentaire — voir PA-36.
 */
final class DeclarationTvaTest extends TestCase
{
    use RefreshDatabase;

    private DeclarationTvaService $declaration;

    private CalculTvaService $calcul;

    private string $exerciceId;

    private string $journalId;

    private string $centreId;

    protected function setUp(): void
    {
        parent::setUp();
        // Comptes de TVA du fichier du PO (plus semés par TvaReferentielSeeder).
        foreach ([['4431', 'T.V.A. facturée sur ventes'], ['4432', 'T.V.A. facturée sur prestations de services'], ['4452', 'T.V.A. récupérable sur achats']] as [$n, $l]) {
            \App\Domain\Comptabilite\Models\CompteComptable::firstOrCreate(['numero_compte' => $n], ['libelle' => $l, 'classe' => '4', 'nature' => 'passif']);
        }
        $this->seed(TvaReferentielSeeder::class);

        $this->declaration = app(DeclarationTvaService::class);
        $this->calcul = app(CalculTvaService::class);

        $this->exerciceId = (string) Str::uuid();
        DB::table('exercices_comptables')->insert([
            'id' => $this->exerciceId,
            'annee' => 2026,
            'date_debut' => '2026-01-01',
            'date_fin' => '2026-12-31',
            'statut' => 'ouvert',
        ]);

        // `journal_id` est NOT NULL : une écriture sans journal est inclassable
        // au Grand Livre. Le référentiel des journaux relève du sprint M10.
        $this->journalId = (string) Str::uuid();
        DB::table('journaux_comptables')->insert([
            'id' => $this->journalId,
            'code' => 'VT',
            'libelle' => 'Journal des ventes',
        ]);

        // `centre_id` est également NOT NULL : le schéma impose une imputation
        // analytique sur CHAQUE écriture, sans exception. C'est ce qui rend
        // possible le compte de résultat par activité (hébergement, bar,
        // restaurant…) exigé au module M10.
        $this->centreId = (string) Str::uuid();
        DB::table('centres_cout')->insert([
            'id' => $this->centreId,
            'libelle' => 'Hébergement',
            'type' => 'activite',
        ]);
    }

    // ---------------------------------------------------------------- Calcul

    #[Test]
    public function le_taux_provient_du_parametre_jamais_du_code(): void
    {
        $this->assertSame('18.00', $this->calcul->taux());

        // Changer le taux ne demande aucun déploiement : c'est une décision de
        // l'État, pas de l'équipe.
        ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_TAUX)->update(['valeur' => '20.00']);

        $this->assertSame('20.00', app(CalculTvaService::class)->taux());
    }

    #[Test]
    public function sans_taux_configure_le_service_refuse_de_calculer(): void
    {
        ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_TAUX)->delete();
        $calcul = app(CalculTvaService::class);

        $this->assertFalse($calcul->estConfigure());

        // Même discipline que le taux d'IS non fixé (PA-19) : refuser, jamais
        // retomber sur une valeur par défaut.
        $this->expectException(RuntimeException::class);
        $calcul->depuisHt('100000.00');
    }

    #[Test]
    public function la_tva_est_calculee_depuis_un_montant_hors_taxe(): void
    {
        // 100 000 × 18 % = 18 000
        $this->assertSame('18000.00', $this->calcul->depuisHt('100000.00'));
        $this->assertSame('118000.00', $this->calcul->htVersTtc('100000.00'));
    }

    #[Test]
    public function la_tva_est_extraite_d_un_montant_toutes_taxes(): void
    {
        // 118 000 TTC contient 18 000 de TVA — l'opération inverse doit être
        // exacte, sinon HT et TTC ne se répondent plus.
        $this->assertSame('18000.00', $this->calcul->depuisTtc('118000.00'));
        $this->assertSame('100000.00', $this->calcul->ttcVersHt('118000.00'));
    }

    #[Test]
    public function l_arrondi_au_centime_est_correct_sur_un_montant_non_rond(): void
    {
        // 25 000 TTC : TVA = 25000 × 18 / 118 = 3813,559322... → 3813,56
        $this->assertSame('3813.56', $this->calcul->depuisTtc('25000.00'));

        // Et le HT reconstitué complète exactement le TTC.
        $ht = $this->calcul->ttcVersHt('25000.00');
        $this->assertSame('21186.44', $ht);
        $this->assertSame(0, bccomp(bcadd($ht, '3813.56', 2), '25000.00', 2));
    }

    #[Test]
    public function les_montants_sont_compares_avec_bccomp_jamais_en_flottant(): void
    {
        $tva = $this->calcul->depuisHt('2364830.51');

        // Contrôle par bccomp, conformément à A1_MASTER_PROMPT.md §2.5.
        $this->assertSame(0, bccomp($tva, '425669.49', 2));
    }

    // ----------------------------------------------------------- Déclaration

    /**
     * MUTATION PROUVÉE : ignorer 4432 dans `pourPeriode()` rougit le premier
     * cas ; ignorer 4431 rougit le second.
     */
    #[Test]
    public function la_tva_collectee_voit_le_4432_seul(): void
    {
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE_PRESTATIONS, credit: '381.36', date: '2026-03-15');

        $declaration = $this->declaration->pourPeriode('2026-03-01', '2026-03-31');

        $this->assertSame('381.36', $declaration['tva_collectee']);
        $this->assertSame('381.36', $declaration['montant_a_payer']);
    }

    #[Test]
    public function la_tva_collectee_voit_le_4431_seul(): void
    {
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE, credit: '305.08', date: '2026-03-15');

        $declaration = $this->declaration->pourPeriode('2026-03-01', '2026-03-31');

        $this->assertSame('305.08', $declaration['tva_collectee']);
        $this->assertSame('305.08', $declaration['montant_a_payer']);
    }

    #[Test]
    public function la_declaration_agrege_les_comptes_4431_et_4452(): void
    {
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE, credit: '180000.00', date: '2026-03-15');
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_DEDUCTIBLE, debit: '54000.00', date: '2026-03-20');

        $declaration = $this->declaration->pourPeriode('2026-03-01', '2026-03-31');

        $this->assertSame('180000.00', $declaration['tva_collectee']);
        $this->assertSame('54000.00', $declaration['tva_deductible']);
        $this->assertSame('126000.00', $declaration['solde']);
        $this->assertSame('a_payer', $declaration['sens']);
        $this->assertSame('126000.00', $declaration['montant_a_payer']);
        $this->assertSame('0.00', $declaration['credit_reportable']);
    }

    /**
     * Le cas qu'il ne faut surtout pas traiter comme une dette négative.
     */
    #[Test]
    public function un_exces_de_tva_deductible_produit_un_credit_reportable(): void
    {
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE, credit: '30000.00', date: '2026-04-10');
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_DEDUCTIBLE, debit: '80000.00', date: '2026-04-12');

        $declaration = $this->declaration->pourPeriode('2026-04-01', '2026-04-30');

        $this->assertSame('credit_reportable', $declaration['sens']);
        // Exprimé en positif : « 50 000 F reportables », jamais « −50 000 à payer ».
        $this->assertSame('50000.00', $declaration['credit_reportable']);
        $this->assertSame('0.00', $declaration['montant_a_payer']);
    }

    #[Test]
    public function une_periode_sans_operation_donne_un_solde_neant(): void
    {
        $declaration = $this->declaration->pourPeriode('2026-05-01', '2026-05-31');

        $this->assertSame('neant', $declaration['sens']);
        $this->assertSame('0.00', $declaration['solde']);
    }

    #[Test]
    public function les_ecritures_hors_periode_sont_exclues(): void
    {
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE, credit: '90000.00', date: '2026-02-28');
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE, credit: '10000.00', date: '2026-03-15');

        $declaration = $this->declaration->pourPeriode('2026-03-01', '2026-03-31');

        $this->assertSame('10000.00', $declaration['tva_collectee']);
    }

    /**
     * Une écriture en brouillon n'est pas opposable : la déclarer reviendrait
     * à déclarer une opération non validée.
     */
    #[Test]
    public function les_ecritures_en_brouillon_sont_exclues_par_defaut(): void
    {
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE, credit: '50000.00', date: '2026-06-10', statut: 'brouillon');
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE, credit: '20000.00', date: '2026-06-11');

        $this->assertSame(
            '20000.00',
            $this->declaration->pourPeriode('2026-06-01', '2026-06-30')['tva_collectee'],
        );

        // Consultable explicitement, pour un contrôle avant validation.
        $this->assertSame(
            '70000.00',
            $this->declaration->pourPeriode('2026-06-01', '2026-06-30', ecrituresValideesUniquement: false)['tva_collectee'],
        );
    }

    #[Test]
    public function une_regularisation_au_debit_du_4431_diminue_la_tva_collectee(): void
    {
        // Cas réel : avoir émis sur une facture déjà comptabilisée.
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE, credit: '100000.00', date: '2026-07-05');
        $this->ecriture(DeclarationTvaService::COMPTE_TVA_COLLECTEE, debit: '18000.00', date: '2026-07-20');

        $this->assertSame(
            '82000.00',
            $this->declaration->pourPeriode('2026-07-01', '2026-07-31')['tva_collectee'],
        );
    }

    /**
     * Un compte manquant doit faire échouer la déclaration, jamais renvoyer 0.
     */
    #[Test]
    public function un_compte_de_tva_absent_du_plan_comptable_fait_echouer_la_declaration(): void
    {
        CompteComptable::where('numero_compte', DeclarationTvaService::COMPTE_TVA_COLLECTEE)->delete();

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/4431/');

        $this->declaration->pourPeriode('2026-03-01', '2026-03-31');
    }

    private function ecriture(
        string $numeroCompte,
        string $debit = '0.00',
        string $credit = '0.00',
        string $date = '2026-03-15',
        string $statut = 'validee',
    ): void {
        EcritureComptable::create([
            'exercice_id' => $this->exerciceId,
            'journal_id' => $this->journalId,
            'centre_id' => $this->centreId,
            'compte_id' => CompteComptable::where('numero_compte', $numeroCompte)->sole()->id,
            'date_ecriture' => $date,
            'libelle' => 'Écriture de test',
            'debit' => $debit,
            'credit' => $credit,
            'statut' => $statut,
        ]);
    }
}
