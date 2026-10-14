<?php

declare(strict_types=1);

namespace App\Domain\Rh\Services;

use App\Shared\Parametres\Services\ParametreSystemeService;
use RuntimeException;

/**
 * Calcul de paie — EF-M13-07.
 *
 * @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
 *
 * ## Aucun taux n'est codé en dur — exigence explicite du CdCF
 *
 * `05_MODULE_SPECIFICATIONS.md` §M13, **point de vigilance juridique** : « les
 * taux de charges sociales (CNSS) et barèmes fiscaux doivent être des
 * paramètres système modifiables, **jamais codés en dur**, la réglementation
 * pouvant évoluer indépendamment des cycles de release ».
 *
 * ## Ce qui est calculable, et ce qui ne l'est pas
 *
 * `ATELIER_PLAN_COMPTABLE.md` §5 distingue nettement les taux **confirmés à
 * la source** de ceux qui ne le sont pas. Cette distinction est reproduite
 * telle quelle dans le code :
 *
 * | Élément | Statut | Conséquence ici |
 * |---|---|---|
 * | CNSS salarié 3,6 % | Confirmé sur cnss.bj | Calculé |
 * | CNSS employeur pension 6,4 % + familiales 9 % | Confirmé sur cnss.bj | Calculé |
 * | **VPS — Versement Patronal sur Salaires 4 %** | Confirmé (2 % pour l'enseignement privé, 4 % sinon) | Calculé |
 * | CNSS employeur **risques professionnels** | **1 % à 4 %, non confirmé** pour l'hôtellerie-restauration | **Refus de calculer** |
 * | Barème ITS jusqu'à 500 000 F | Confirmé, 4 tranches | Calculé |
 * | Barème ITS **au-delà de 500 000 F** | **Deux sources divergent** (30 % unique vs tranche à 40 %) | **Refus de calculer** |
 *
 * ## Le VPS n'est pas une retenue
 *
 * Le Versement Patronal sur Salaires est une **taxe directe à la charge de
 * l'employeur**, assise sur le total des salaires bruts **sans plafond**, à
 * déclarer et payer au plus tard le 10 du mois suivant. Il ne figure jamais au
 * débit du salarié : l'inscrire en retenue produirait un bulletin faux et un
 * net à payer minoré. Il est donc absent de `retenuesSalariales()` par
 * construction.
 *
 * ## Refuser sans tout bloquer
 *
 * `chargesPatronales()` refuse toujours tant que le taux de risques
 * professionnels n'est pas renseigné — c'est le contrat historique et il ne
 * change pas. Mais 19,4 % du brut sont désormais établis : les laisser
 * inaccessibles bloquerait la paie mensuelle entière pour un seul taux
 * manquant. `chargesPatronalesConfirmees()` expose donc la part certaine, et
 * `fourchetteRisquesProfessionnels()` chiffre l'incertitude restante au lieu
 * de la masquer. Voir PA-53.
 *
 * Les deux refus suivent la première règle du projet : aucune donnée
 * réglementaire n'est devinée. C'est la même discipline que
 * `CompteResultatService` sur le taux d'IS (PA-19) — un bulletin de paie faux
 * n'est pas une approximation, c'est une déclaration sociale erronée.
 *
 * `ATELIER_PLAN_COMPTABLE.md` note qu'aucun employé actuel n'approche 500 000 F
 * de salaire ; le refus ne bloque donc personne aujourd'hui, mais il se
 * déclenchera au premier recrutement de cadre — exactement au moment où la
 * question doit être tranchée.
 */
class CalculPaieService
{
    private const PRECISION = 2;

    /** Précision intermédiaire, pour n'arrondir qu'au dernier moment. */
    private const PRECISION_CALCUL = 6;

    // --- Taux confirmés (cnss.bj), néanmoins paramétrables.
    public const CLE_CNSS_SALARIE = 'taux_cnss_salarie';

    public const CLE_CNSS_PENSION_EMPLOYEUR = 'taux_cnss_pension_employeur';

    public const CLE_CNSS_PRESTATIONS_FAMILIALES = 'taux_cnss_prestations_familiales';

    /**
     * VPS — Versement Patronal sur Salaires.
     *
     * 4 % pour les entreprises ordinaires, 2 % pour les structures
     * d'enseignement privé. Le Gîte Chez Noël relève de l'hôtellerie : 4 %.
     * Assiette = total des salaires bruts, **sans plafond**.
     */
    public const CLE_VPS = 'taux_vps';

    /** **Non confirmé** pour l'hôtellerie-restauration : aucun repli. */
    public const CLE_CNSS_RISQUES_PROFESSIONNELS = 'taux_cnss_risques_professionnels';

    /**
     * Bornes réglementaires du taux de risques professionnels.
     *
     * Servent à **chiffrer l'incertitude**, jamais à en déduire une valeur :
     * prendre la moyenne serait exactement l'hypothèse que le projet refuse.
     */
    public const RISQUES_PROFESSIONNELS_TAUX_MIN = '1';

    public const RISQUES_PROFESSIONNELS_TAUX_MAX = '4';

    /** Plafond au-delà duquel le barème ITS n'est pas tranché. */
    public const PLAFOND_ITS_CONFIRME = '500000.00';

    /**
     * Barème ITS confirmé — `ATELIER_PLAN_COMPTABLE.md` §5.3.
     *
     * Tranches en `[plancher, plafond, taux]`. Le haut de barème
     * (au-delà de 500 000 F) est **absent volontairement** : deux sources
     * divergent, et inventer la tranche produirait un bulletin faux.
     *
     * @var list<array{string, string, string}>
     */
    private const BAREME_ITS = [
        ['0.00', '60000.00', '0'],
        ['60000.00', '150000.00', '10'],
        ['150000.00', '250000.00', '15'],
        ['250000.00', '500000.00', '19'],
    ];

    public function __construct(
        private readonly ParametreSystemeService $parametres,
    ) {
    }

    /**
     * Retenues salariales et net à payer.
     *
     * @param  string  $brut  salaire brut du mois, primes incluses
     * @return array{brut: string, cnss_salarie: string, revenu_imposable: string, its: string, total_retenues: string, net_a_payer: string}
     *
     * @throws RuntimeException si un taux n'est pas paramétré, ou si le revenu
     *                          imposable dépasse le barème confirmé
     */
    public function retenuesSalariales(string $brut): array
    {
        $cnss = $this->arrondir(
            $this->pourcentage($brut, $this->taux(self::CLE_CNSS_SALARIE)),
        );

        // Le revenu imposable est le brut MOINS la cotisation salariale :
        // appliquer le barème au brut surtaxerait chaque bulletin.
        $imposable = bcsub($brut, $cnss, self::PRECISION);

        $its = $this->impotSurTraitements($imposable);
        $retenues = bcadd($cnss, $its, self::PRECISION);

        return [
            'brut' => $brut,
            'cnss_salarie' => $cnss,
            'revenu_imposable' => $imposable,
            'its' => $its,
            'total_retenues' => $retenues,
            // Valeur CALCULÉE, jamais un champ de formulaire soumis.
            'net_a_payer' => bcsub($brut, $retenues, self::PRECISION),
        ];
    }

    /**
     * Impôt sur les Traitements et Salaires — barème progressif par tranches.
     *
     * @throws RuntimeException au-delà du plafond confirmé
     */
    public function impotSurTraitements(string $revenuImposable): string
    {
        if (bccomp($revenuImposable, self::PLAFOND_ITS_CONFIRME, self::PRECISION) > 0) {
            // Refus explicite plutôt qu'une extrapolation de la dernière
            // tranche : deux sources divergent (30 % unique vs palier à 40 %
            // au-delà de 1 M). Voir PA-53.
            throw new RuntimeException(__('rh.bareme_its_non_confirme', [
                'plafond' => self::PLAFOND_ITS_CONFIRME,
                'revenu' => $revenuImposable,
            ]));
        }

        $impot = '0.00';

        foreach (self::BAREME_ITS as [$plancher, $plafond, $taux]) {
            if (bccomp($revenuImposable, $plancher, self::PRECISION) <= 0) {
                break;
            }

            // Part du revenu tombant dans cette tranche — progressif, jamais
            // un taux unique appliqué au total.
            $borneHaute = bccomp($revenuImposable, $plafond, self::PRECISION) < 0
                ? $revenuImposable
                : $plafond;

            $assiette = bcsub($borneHaute, $plancher, self::PRECISION);
            $impot = bcadd($impot, $this->pourcentage($assiette, $taux), self::PRECISION_CALCUL);
        }

        return $this->arrondir($impot);
    }

    /**
     * Charges patronales — **refuse de calculer** tant que le taux de risques
     * professionnels applicable à l'hôtellerie-restauration n'est pas confirmé.
     *
     * `ATELIER_PLAN_COMPTABLE.md` §5.1 : « 1 % à 4 %, variable selon
     * l'activité […] une valeur de 2 % est une **hypothèse raisonnable en
     * attendant confirmation** ». Une hypothèse n'est pas une source : sur une
     * masse salariale annuelle, l'écart entre 1 % et 4 % est un redressement.
     *
     * @return array{pension: string, prestations_familiales: string, vps: string, risques_professionnels: string, total: string}
     *
     * @throws RuntimeException tant que le taux n'est pas renseigné
     */
    public function chargesPatronales(string $brut): array
    {
        $confirmees = $this->chargesPatronalesConfirmees($brut);

        // Aucun repli : le paramètre est absent tant que la CNSS n'a pas
        // confirmé la catégorie de risque du secteur.
        $risques = $this->arrondir($this->pourcentage($brut, $this->taux(self::CLE_CNSS_RISQUES_PROFESSIONNELS)));

        return [
            'pension' => $confirmees['pension'],
            'prestations_familiales' => $confirmees['prestations_familiales'],
            'vps' => $confirmees['vps'],
            'risques_professionnels' => $risques,
            'total' => bcadd($confirmees['total'], $risques, self::PRECISION),
        ];
    }

    /**
     * Part **certaine** de la charge patronale : CNSS pension 6,4 %,
     * prestations familiales 9 %, VPS 4 % — soit 19,4 % du brut.
     *
     * Calculable sans le taux de risques professionnels. C'est ce qui permet
     * d'établir une paie mensuelle et de comptabiliser une charge minorée
     * mais exacte, plutôt que de tout suspendre à un seul taux manquant.
     *
     * @return array{pension: string, prestations_familiales: string, vps: string, total: string}
     *
     * @throws RuntimeException si l'un des trois taux confirmés n'est pas paramétré
     */
    public function chargesPatronalesConfirmees(string $brut): array
    {
        $pension = $this->arrondir($this->pourcentage($brut, $this->taux(self::CLE_CNSS_PENSION_EMPLOYEUR)));
        $familiales = $this->arrondir($this->pourcentage($brut, $this->taux(self::CLE_CNSS_PRESTATIONS_FAMILIALES)));
        $vps = $this->arrondir($this->pourcentage($brut, $this->taux(self::CLE_VPS)));

        return [
            'pension' => $pension,
            'prestations_familiales' => $familiales,
            'vps' => $vps,
            'total' => bcadd(bcadd($pension, $familiales, self::PRECISION), $vps, self::PRECISION),
        ];
    }

    /**
     * Chiffre l'incertitude portée par le taux de risques professionnels.
     *
     * Ne renvoie **aucune valeur centrale** : l'écart entre les deux bornes est
     * exactement ce qu'un redressement viendrait réclamer, et le publier est
     * plus utile que de le dissimuler derrière une moyenne.
     *
     * @return array{minimum: string, maximum: string, ecart: string, taux_min: string, taux_max: string}
     */
    public function fourchetteRisquesProfessionnels(string $brut): array
    {
        $min = $this->arrondir($this->pourcentage($brut, self::RISQUES_PROFESSIONNELS_TAUX_MIN));
        $max = $this->arrondir($this->pourcentage($brut, self::RISQUES_PROFESSIONNELS_TAUX_MAX));

        return [
            'minimum' => $min,
            'maximum' => $max,
            'ecart' => bcsub($max, $min, self::PRECISION),
            'taux_min' => self::RISQUES_PROFESSIONNELS_TAUX_MIN,
            'taux_max' => self::RISQUES_PROFESSIONNELS_TAUX_MAX,
        ];
    }

    public function tauxEstConfigure(string $cle): bool
    {
        return filled($this->parametres->get($cle));
    }

    // ------------------------------------------------------------- Internes

    /**
     * @throws RuntimeException si le taux n'est pas paramétré
     */
    private function taux(string $cle): string
    {
        $valeur = $this->parametres->get($cle);

        if (blank($valeur)) {
            throw new RuntimeException(__('rh.taux_absent', ['cle' => $cle]));
        }

        return $valeur;
    }

    private function pourcentage(string $montant, string $taux): string
    {
        return bcdiv(bcmul($montant, $taux, self::PRECISION_CALCUL), '100', self::PRECISION_CALCUL);
    }

    /**
     * Arrondi commercial au franc près — le FCFA n'a pas de subdivision en
     * circulation, un bulletin au centime serait impayable en espèces.
     */
    private function arrondir(string $montant): string
    {
        $ajustement = bccomp($montant, '0', self::PRECISION_CALCUL) >= 0 ? '0.5' : '-0.5';

        return bcadd(bcadd($montant, $ajustement, 0), '0', self::PRECISION);
    }
}
