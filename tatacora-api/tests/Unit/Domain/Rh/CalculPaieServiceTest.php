<?php

declare(strict_types=1);

namespace Tests\Unit\Domain\Rh;

use App\Domain\Rh\Services\CalculPaieService;
use App\Shared\Parametres\Services\ParametreSystemeService;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Calcul de paie — EF-M13-07.
 *
 * Unitaire : un bulletin de paie est de l'arithmétique sur des taux. Le faire
 * passer par `RefreshDatabase` rendrait coûteux d'écrire les cas de bord — or
 * ce sont précisément les bornes de tranches du barème ITS qui font la
 * différence entre un bulletin juste et une déclaration sociale erronée.
 *
 * Les valeurs de référence viennent de `ATELIER_PLAN_COMPTABLE.md` §5, dont
 * les sources sont citées (cnss.bj pour la CNSS, recoupement CGI pour l'ITS).
 */
final class CalculPaieServiceTest extends TestCase
{
    /**
     * @param  array<string, string>  $parametres
     */
    private function service(array $parametres = []): CalculPaieService
    {
        $double = new class ($parametres) extends ParametreSystemeService {
            /**
             * @param  array<string, string>  $valeurs
             */
            public function __construct(private readonly array $valeurs)
            {
            }

            public function get(string $cle, ?string $defaut = null): ?string
            {
                return $this->valeurs[$cle] ?? $defaut;
            }

            public function estRenseigne(string $cle): bool
            {
                return isset($this->valeurs[$cle]);
            }
        };

        return new CalculPaieService($double);
    }

    /** Uniquement les taux réellement confirmés à la source. */
    private function avecTauxConfirmes(): CalculPaieService
    {
        return $this->service([
            CalculPaieService::CLE_CNSS_SALARIE => '3.6',
            CalculPaieService::CLE_CNSS_PENSION_EMPLOYEUR => '6.4',
            CalculPaieService::CLE_CNSS_PRESTATIONS_FAMILIALES => '9',
            CalculPaieService::CLE_VPS => '4',
        ]);
    }

    // ------------------------------------------------------------- Barème ITS

    /**
     * @param  string  $imposable  revenu imposable mensuel
     * @param  string  $attendu  impôt dû
     */
    #[Test]
    #[DataProvider('tranchesDuBareme')]
    public function le_bareme_its_est_progressif_par_tranches(string $imposable, string $attendu): void
    {
        $this->assertSame($attendu, $this->avecTauxConfirmes()->impotSurTraitements($imposable));
    }

    /**
     * Valeurs calculées à la main depuis le barème confirmé
     * (`ATELIER_PLAN_COMPTABLE.md` §5.3), tranche par tranche.
     *
     * @return array<string, array{string, string}>
     */
    public static function tranchesDuBareme(): array
    {
        return [
            // Exonéré jusqu'à 60 000.
            'zéro' => ['0.00', '0.00'],
            'sous le seuil d\'exonération' => ['59999.00', '0.00'],
            'pile sur le seuil' => ['60000.00', '0.00'],
            // 1 F au-dessus : 10 % de 1 F, arrondi au franc.
            'un franc au-dessus du seuil' => ['60001.00', '0.00'],
            // 100 000 → 10 % × 40 000 = 4 000.
            'milieu de 2e tranche' => ['100000.00', '4000.00'],
            // 150 000 → 10 % × 90 000 = 9 000.
            'haut de 2e tranche' => ['150000.00', '9000.00'],
            // 200 000 → 9 000 + 15 % × 50 000 = 16 500.
            'milieu de 3e tranche' => ['200000.00', '16500.00'],
            // 250 000 → 9 000 + 15 % × 100 000 = 24 000.
            'haut de 3e tranche' => ['250000.00', '24000.00'],
            // 400 000 → 24 000 + 19 % × 150 000 = 52 500.
            'milieu de 4e tranche' => ['400000.00', '52500.00'],
            // 500 000 → 24 000 + 19 % × 250 000 = 71 500.
            'plafond confirmé' => ['500000.00', '71500.00'],
        ];
    }

    /**
     * **Le refus le plus important de ce service.**
     *
     * Deux sources divergent au-delà de 500 000 F : taux unique de 30 %, ou
     * palier supplémentaire à 40 % au-delà de 1 M. Extrapoler la dernière
     * tranche produirait un bulletin plausible et faux.
     */
    #[Test]
    public function au_dela_du_plafond_confirme_le_calcul_est_refuse(): void
    {
        $service = $this->avecTauxConfirmes();

        // 500 000 passe...
        $this->assertSame('71500.00', $service->impotSurTraitements('500000.00'));

        // ...500 000,01 ne passe pas.
        $this->expectException(RuntimeException::class);
        $service->impotSurTraitements('500000.01');
    }

    // --------------------------------------------------- Retenues salariales

    /**
     * L'assiette de l'ITS est le brut **moins** la CNSS salariale : appliquer
     * le barème au brut surtaxerait chaque bulletin.
     */
    #[Test]
    public function l_its_porte_sur_le_brut_moins_la_cnss_et_non_sur_le_brut(): void
    {
        $bulletin = $this->avecTauxConfirmes()->retenuesSalariales('130000.00');

        // 3,6 % de 130 000 = 4 680.
        $this->assertSame('4680.00', $bulletin['cnss_salarie']);
        $this->assertSame('125320.00', $bulletin['revenu_imposable']);

        // 10 % × (125 320 − 60 000) = 6 532.
        $this->assertSame('6532.00', $bulletin['its']);
        $this->assertSame('11212.00', $bulletin['total_retenues']);
        $this->assertSame('118788.00', $bulletin['net_a_payer']);
    }

    /**
     * Le net à payer se recompose exactement : brut − retenues. C'est la
     * vérification qu'un employé fera lui-même sur son bulletin.
     */
    #[Test]
    #[DataProvider('salairesReels')]
    public function le_net_a_payer_se_recompose_exactement(string $brut): void
    {
        $bulletin = $this->avecTauxConfirmes()->retenuesSalariales($brut);

        $this->assertSame(
            0,
            bccomp(bcadd($bulletin['net_a_payer'], $bulletin['total_retenues'], 2), $brut, 2),
        );
    }

    /**
     * Fourchette réelle des salaires TATACORA
     * (`SEEDER_TEST_LARAVEL.md` §3bis : 55 000 à 130 000 F).
     *
     * @return array<string, array{string}>
     */
    public static function salairesReels(): array
    {
        return [
            'SMIG 2026' => ['52000.00'],
            'bas de grille' => ['55000.00'],
            'milieu de grille' => ['85000.00'],
            'haut de grille' => ['130000.00'],
        ];
    }

    /**
     * Un salaire au SMIG reste sous le seuil d'exonération une fois la CNSS
     * déduite : aucun ITS ne doit être prélevé.
     */
    #[Test]
    public function un_salaire_au_smig_n_est_pas_imposable(): void
    {
        $bulletin = $this->avecTauxConfirmes()->retenuesSalariales('52000.00');

        // 52 000 − 3,6 % = 50 128, sous les 60 000 exonérés.
        $this->assertSame('50128.00', $bulletin['revenu_imposable']);
        $this->assertSame('0.00', $bulletin['its']);
    }

    // -------------------------------------------------- Charges patronales

    /**
     * **Le second refus, et le plus lourd de conséquences.**
     *
     * `ATELIER_PLAN_COMPTABLE.md` §5.1 : le taux de risques professionnels est
     * « 1 % à 4 %, variable selon l'activité », et 2 % n'est qu'« une
     * hypothèse raisonnable en attendant confirmation ». Sur une masse
     * salariale annuelle, l'écart entre 1 % et 4 % est un redressement.
     */
    #[Test]
    public function les_charges_patronales_sont_refusees_sans_taux_de_risques_professionnels(): void
    {
        $service = $this->avecTauxConfirmes();

        $this->assertFalse($service->tauxEstConfigure(CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS));

        $this->expectException(RuntimeException::class);
        $service->chargesPatronales('130000.00');
    }

    /**
     * Une fois le taux confirmé et renseigné, le calcul reprend sans qu'aucune
     * ligne de code ne change — c'est tout l'intérêt du paramétrage exigé par
     * le CdCF (« jamais codés en dur »).
     */
    #[Test]
    public function les_charges_patronales_se_calculent_des_que_le_taux_est_renseigne(): void
    {
        $service = $this->service([
            CalculPaieService::CLE_CNSS_PENSION_EMPLOYEUR => '6.4',
            CalculPaieService::CLE_CNSS_PRESTATIONS_FAMILIALES => '9',
            CalculPaieService::CLE_VPS => '4',
            CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS => '2',
        ]);

        $charges = $service->chargesPatronales('130000.00');

        $this->assertSame('8320.00', $charges['pension']);              // 6,4 %
        $this->assertSame('11700.00', $charges['prestations_familiales']); // 9 %
        $this->assertSame('5200.00', $charges['vps']);                     // 4 %
        $this->assertSame('2600.00', $charges['risques_professionnels']);  // 2 %
        // 21,4 % au total.
        $this->assertSame('27820.00', $charges['total']);
    }

    /**
     * **VPS — le prélèvement qui manquait.**
     *
     * Le Versement Patronal sur Salaires n'existait nulle part au dépôt : la
     * charge patronale était donc minorée de 4 % du brut, y compris dans sa
     * partie réputée confirmée. Taxe directe à la charge de l'employeur,
     * assise sur le brut total sans plafond.
     */
    #[Test]
    public function le_vps_est_calcule_a_quatre_pour_cent_du_brut_sans_plafond(): void
    {
        $service = $this->avecTauxConfirmes();

        $this->assertSame('5200.00', $service->chargesPatronalesConfirmees('130000.00')['vps']);
        // Sans plafond : le taux s'applique aussi bien sur un salaire élevé.
        $this->assertSame('40000.00', $service->chargesPatronalesConfirmees('1000000.00')['vps']);
    }

    /**
     * Le VPS est à la charge de l'employeur : il ne doit jamais réduire le net
     * à payer. L'inscrire en retenue produirait un bulletin faux.
     */
    #[Test]
    public function le_vps_n_apparait_jamais_dans_les_retenues_salariales(): void
    {
        $retenues = $this->avecTauxConfirmes()->retenuesSalariales('130000.00');

        $this->assertArrayNotHasKey('vps', $retenues);
        // Les seules retenues sont CNSS salarié et ITS.
        $this->assertSame(
            bcadd($retenues['cnss_salarie'], $retenues['its'], 2),
            $retenues['total_retenues'],
        );
    }

    /**
     * La part confirmée — 19,4 % — se calcule **sans** le taux de risques
     * professionnels. Un seul taux manquant ne doit pas suspendre la paie
     * mensuelle entière.
     */
    #[Test]
    public function la_part_confirmee_des_charges_patronales_se_calcule_sans_le_taux_manquant(): void
    {
        $service = $this->avecTauxConfirmes();

        $this->assertFalse($service->tauxEstConfigure(CalculPaieService::CLE_CNSS_RISQUES_PROFESSIONNELS));

        $confirmees = $service->chargesPatronalesConfirmees('130000.00');

        // 6,4 % + 9 % + 4 % = 19,4 % de 130 000.
        $this->assertSame('25220.00', $confirmees['total']);
    }

    /**
     * L'incertitude est chiffrée, jamais moyennée. Retenir 2,5 % « au milieu »
     * serait exactement l'hypothèse que le projet refuse.
     */
    #[Test]
    public function l_incertitude_sur_les_risques_professionnels_est_chiffree_sans_valeur_centrale(): void
    {
        $fourchette = $this->avecTauxConfirmes()->fourchetteRisquesProfessionnels('130000.00');

        $this->assertSame('1300.00', $fourchette['minimum']);   // 1 %
        $this->assertSame('5200.00', $fourchette['maximum']);   // 4 %
        $this->assertSame('3900.00', $fourchette['ecart']);
        $this->assertArrayNotHasKey('moyenne', $fourchette);
        $this->assertArrayNotHasKey('valeur_probable', $fourchette);
    }

    /**
     * Sans le taux VPS paramétré, aucune charge patronale n'est calculée : le
     * VPS suit la même règle que les autres taux, il n'est pas codé en dur.
     */
    #[Test]
    public function aucune_charge_patronale_sans_taux_vps_parametre(): void
    {
        $service = $this->service([
            CalculPaieService::CLE_CNSS_PENSION_EMPLOYEUR => '6.4',
            CalculPaieService::CLE_CNSS_PRESTATIONS_FAMILIALES => '9',
        ]);

        $this->expectException(RuntimeException::class);
        $service->chargesPatronalesConfirmees('130000.00');
    }

    // --------------------------------------------------------------- Refus

    #[Test]
    public function aucun_calcul_n_est_possible_sans_taux_cnss_salarie(): void
    {
        $this->expectException(RuntimeException::class);
        $this->service()->retenuesSalariales('100000.00');
    }

    /**
     * Le taux est paramétrable, jamais codé en dur : le faire varier doit
     * changer le résultat sans toucher au code.
     */
    #[Test]
    public function aucun_taux_n_est_code_en_dur(): void
    {
        $service = $this->service([CalculPaieService::CLE_CNSS_SALARIE => '5']);

        $this->assertSame('5000.00', $service->retenuesSalariales('100000.00')['cnss_salarie']);
    }
}
