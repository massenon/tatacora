<?php

declare(strict_types=1);

namespace Tests\Unit\Domain\Comptabilite;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Shared\Parametres\Services\ParametreSystemeService;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Arithmétique de la TVA — PA-36, PA-37.
 *
 * ## Pourquoi ce test est unitaire et non `Feature`
 *
 * `07_TESTING_QA.md` §2 décrit une pyramide dont la base est le calcul pur.
 * Le calcul de TVA n'a besoin **ni de base de données, ni de HTTP** : il lui
 * faut un taux et un montant. Le faire passer par `RefreshDatabase` payait
 * 23 migrations pour vérifier une multiplication, et rendait coûteux d'ajouter
 * un cas de bord — c'est précisément ce qui fait qu'on ne les ajoute pas.
 *
 * Le seul paramètre externe (`parametres_systeme`) est fourni par un double
 * en mémoire : la lecture du paramètre est déjà couverte ailleurs, ce qui est
 * testé ici est le calcul.
 *
 * ## Ce qui est réellement en jeu
 *
 * Se tromper de sens HT/TTC sur un tarif à 25 000 F fait un écart de 3 813 F
 * par nuitée, et la facture part chez MECeF — où elle devient immuable (RG-03).
 * L'arrondi est appliqué **une seule fois** en fin de calcul, à 6 décimales
 * intermédiaires, pour que 100 lignes ne dérivent pas de plusieurs francs.
 */
final class CalculTvaServiceTest extends TestCase
{
    /**
     * Double en mémoire de la lecture de paramètres — aucune base.
     *
     * @param  array<string, string>  $parametres
     */
    private function service(array $parametres): CalculTvaService
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

        return new CalculTvaService($double);
    }

    private function a18Pourcent(string $convention = CalculTvaService::CONVENTION_HT): CalculTvaService
    {
        return $this->service([
            CalculTvaService::CLE_PARAMETRE_TAUX => '18.00',
            CalculTvaService::CLE_PARAMETRE_ACTIVE => 'true',
            CalculTvaService::CLE_PARAMETRE_CONVENTION => $convention,
        ]);
    }

    // ------------------------------------------------------- Calcul de base

    #[Test]
    public function la_tva_sur_une_base_hors_taxe_est_le_produit_par_le_taux(): void
    {
        $this->assertSame('4500.00', $this->a18Pourcent()->depuisHt('25000.00'));
    }

    #[Test]
    public function la_tva_incluse_dans_un_montant_ttc_se_calcule_sur_cent_dix_huit(): void
    {
        // 29 500 × 18 / 118 — surtout pas 29 500 × 18 / 100.
        $this->assertSame('4500.00', $this->a18Pourcent()->depuisTtc('29500.00'));
    }

    /**
     * L'erreur que ce service existe pour rendre impossible : appliquer le
     * calcul HT à un montant qui incluait déjà la taxe.
     */
    #[Test]
    public function les_deux_sens_ne_donnent_pas_le_meme_resultat_sur_le_meme_montant(): void
    {
        $tva = $this->a18Pourcent();

        $this->assertSame('4500.00', $tva->depuisHt('25000.00'));
        $this->assertSame('3813.56', $tva->depuisTtc('25000.00'));

        // 686,44 F d'écart par nuitée sur un tarif à 25 000 F.
        $this->assertSame('686.44', bcsub('4500.00', '3813.56', 2));
    }

    // --------------------------------------------------------- Invariants

    /**
     * @param  string  $montant  base du calcul
     */
    #[Test]
    #[DataProvider('montantsVaries')]
    public function ht_plus_tva_egale_toujours_ttc_au_centime_pres(string $montant): void
    {
        $tva = $this->a18Pourcent();

        $ttc = $tva->htVersTtc($montant);
        $taxe = $tva->depuisHt($montant);

        // bccomp, jamais une égalité flottante (règle projet).
        $this->assertSame(
            0,
            bccomp(bcadd($montant, $taxe, 2), $ttc, 2),
            "HT {$montant} + TVA {$taxe} ne redonne pas TTC {$ttc}",
        );
    }

    #[Test]
    #[DataProvider('montantsVaries')]
    public function la_conversion_ttc_vers_ht_est_coherente_avec_la_taxe_extraite(string $montant): void
    {
        $tva = $this->a18Pourcent();

        $ht = $tva->ttcVersHt($montant);
        $taxe = $tva->depuisTtc($montant);

        $this->assertSame(0, bccomp(bcadd($ht, $taxe, 2), $montant, 2));
    }

    /**
     * @return array<string, array{string}>
     */
    public static function montantsVaries(): array
    {
        return [
            'tarif nuitée' => ['25000.00'],
            'consommation bar' => ['1000.00'],
            'montant à décimales' => ['1234567.89'],
            'petit montant' => ['0.25'],
            'un franc' => ['1.00'],
            'zéro' => ['0.00'],
        ];
    }

    // ----------------------------------------------------------- Arrondi

    /**
     * L'arrondi commercial (demi vers le haut) appliqué une seule fois.
     */
    #[Test]
    public function le_demi_centime_est_arrondi_vers_le_haut(): void
    {
        // 0,25 × 18 / 100 = 0,045 exactement — pile sur le demi-centime.
        $this->assertSame('0.05', $this->a18Pourcent()->depuisHt('0.25'));
    }

    /**
     * Le cas que l'ajustement signé de `arrondir()` existe pour traiter : sur
     * un avoir, un ajustement toujours positif arrondirait vers zéro et non
     * vers le bas, faisant diverger l'avoir de la facture qu'il annule.
     */
    #[Test]
    public function un_montant_negatif_est_arrondi_dans_le_bon_sens(): void
    {
        $this->assertSame('-0.05', $this->a18Pourcent()->depuisHt('-0.25'));
    }

    /**
     * La raison des 6 décimales intermédiaires : sur une facture consolidée de
     * plusieurs dizaines de lignes, arrondir à chaque étape dérive.
     */
    #[Test]
    public function la_precision_intermediaire_evite_la_derive_sur_un_gros_montant(): void
    {
        // 1 234 567,89 × 18 / 100 = 222 222,2202
        $this->assertSame('222222.22', $this->a18Pourcent()->depuisHt('1234567.89'));
    }

    // ------------------------------------------------------- Commutateurs

    /**
     * Le défaut le plus important du service : **non assujetti par défaut**.
     * Une TVA appliquée sans décision explicite serait facturée à des clients
     * réels et certifiée chez MECeF avant que quiconque s'en aperçoive.
     */
    #[Test]
    public function la_tva_est_inactive_tant_qu_un_administrateur_ne_l_a_pas_activee(): void
    {
        $tva = $this->service([CalculTvaService::CLE_PARAMETRE_TAUX => '18.00']);

        $this->assertFalse($tva->estActive());

        $ventilation = $tva->ventiler('25000.00');

        $this->assertFalse($ventilation['tva_active']);
        $this->assertSame('0.00', $ventilation['tva']);
        $this->assertSame('25000.00', $ventilation['ht']);
        $this->assertSame('25000.00', $ventilation['ttc']);
    }

    #[Test]
    public function la_ventilation_en_convention_ht_ajoute_la_taxe_au_prix_catalogue(): void
    {
        $ventilation = $this->a18Pourcent(CalculTvaService::CONVENTION_HT)->ventiler('25000.00');

        $this->assertSame('25000.00', $ventilation['ht']);
        $this->assertSame('4500.00', $ventilation['tva']);
        $this->assertSame('29500.00', $ventilation['ttc']);
        $this->assertSame('ht', $ventilation['convention']);
    }

    #[Test]
    public function la_ventilation_en_convention_ttc_extrait_la_taxe_du_prix_catalogue(): void
    {
        $ventilation = $this->a18Pourcent(CalculTvaService::CONVENTION_TTC)->ventiler('25000.00');

        // Le prix affiché ne bouge pas : c'est tout l'intérêt de la convention.
        $this->assertSame('25000.00', $ventilation['ttc']);
        $this->assertSame('3813.56', $ventilation['tva']);
        $this->assertSame('21186.44', $ventilation['ht']);
        $this->assertSame('ttc', $ventilation['convention']);
    }

    /**
     * L'invariant qui protège la facture : quelle que soit la convention, la
     * ventilation se recompose exactement.
     */
    #[Test]
    #[DataProvider('conventionsEtMontants')]
    public function la_ventilation_se_recompose_exactement(string $convention, string $montant): void
    {
        $ventilation = $this->a18Pourcent($convention)->ventiler($montant);

        $this->assertSame(
            0,
            bccomp(bcadd($ventilation['ht'], $ventilation['tva'], 2), $ventilation['ttc'], 2),
            "Convention {$convention}, montant {$montant} : "
            . "{$ventilation['ht']} + {$ventilation['tva']} ≠ {$ventilation['ttc']}",
        );
    }

    /**
     * @return array<string, array{string, string}>
     */
    public static function conventionsEtMontants(): array
    {
        $cas = [];

        foreach (['ht', 'ttc'] as $convention) {
            foreach (['25000.00', '1000.00', '1234567.89', '0.25', '333.33'] as $montant) {
                $cas["{$convention} — {$montant}"] = [$convention, $montant];
            }
        }

        return $cas;
    }

    #[Test]
    public function la_convention_tolere_la_casse_et_les_espaces(): void
    {
        $tva = $this->service([
            CalculTvaService::CLE_PARAMETRE_TAUX => '18.00',
            CalculTvaService::CLE_PARAMETRE_ACTIVE => 'true',
            CalculTvaService::CLE_PARAMETRE_CONVENTION => '  TTC  ',
        ]);

        $this->assertSame('ttc', $tva->convention());
    }

    // ------------------------------------------------------------- Refus

    /**
     * Règle projet : aucune donnée réglementaire n'est devinée.
     */
    #[Test]
    public function sans_taux_configure_le_service_refuse_de_calculer(): void
    {
        $tva = $this->service([CalculTvaService::CLE_PARAMETRE_ACTIVE => 'true']);

        $this->assertFalse($tva->estConfigure());
        $this->expectException(RuntimeException::class);
        $tva->depuisHt('25000.00');
    }

    /**
     * Un repli silencieux sur « HT » ferait facturer 18 % de trop sur des
     * tarifs qui les incluaient déjà.
     */
    #[Test]
    public function une_convention_illisible_est_refusee_et_non_interpretee(): void
    {
        $tva = $this->service([
            CalculTvaService::CLE_PARAMETRE_TAUX => '18.00',
            CalculTvaService::CLE_PARAMETRE_ACTIVE => 'true',
            CalculTvaService::CLE_PARAMETRE_CONVENTION => 'hors-taxes',
        ]);

        $this->expectException(RuntimeException::class);
        $tva->ventiler('25000.00');
    }

    /**
     * Un taux différent doit traverser tout le calcul sans qu'aucune valeur
     * ne soit codée en dur quelque part.
     */
    #[Test]
    public function le_taux_n_est_jamais_code_en_dur_dans_le_calcul(): void
    {
        $tva = $this->service([
            CalculTvaService::CLE_PARAMETRE_TAUX => '5.50',
            CalculTvaService::CLE_PARAMETRE_ACTIVE => 'true',
            CalculTvaService::CLE_PARAMETRE_CONVENTION => 'ht',
        ]);

        $this->assertSame('1375.00', $tva->depuisHt('25000.00'));
        $this->assertSame('5.50', $tva->ventiler('25000.00')['taux']);
    }
}
