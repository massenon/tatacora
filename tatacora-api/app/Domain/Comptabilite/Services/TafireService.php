<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\ReadModels\LigneBalance;
use App\Domain\Comptabilite\ReadModels\Tafire;
use App\Domain\Comptabilite\Support\RubriquesSyscohada;

/**
 * TAFIRE — `MODULE_COMPTABILITE_COMPLET_PART3.md` §2, `m10-flux-tresorerie.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ⚠ ECART DELIBERE — `MODULE_COMPTABILITE_COMPLET_PART3.md` §2.3
 * Le document : `variationCreances = variationSoldeExercice(['4111','4191'])`
 * et `variationDettesFournisseurs = variationSoldeExercice(['4011'])` SEUL.
 * Ici : le BFR compte 411 aux creances, et 401, 4191, 421, 431 et 447 aux
 * dettes.
 * Raison : le §2.3 OMET les dettes de personnel (421), sociales (431) et
 * fiscales (447). La demonstration par la partie double (entete de `Tafire`)
 * impose que TOUTES les dettes circulantes entrent au BFR ; il en manque trois,
 * donc le recoupement du §2.2 echoue sur un exercice pourtant juste — et §2.2
 * demande precisement de traiter tout ecart comme une anomalie. Le tableau
 * accuserait donc les ecritures d'une erreur qui serait la sienne. Mesure :
 * sur le grand livre de `ApiEtatsFinanciersTest`, la version du document rend
 * un ecart de 40 000 F, exactement la dette CNSS omise.
 *
 * ⚠ Ce qui N'EST PAS un ecart, contrairement a ce que cette note affirmait
 * d'abord : le classement de `4191`. Compter les arrhes clients parmi les
 * creances avec un solde SIGNE (debit - credit) donne le meme total que les
 * compter parmi les dettes — la mesure l'a montre, `coherent` restant `true`
 * dans les deux cas. C'est une difference de PRESENTATION, pas d'arithmetique.
 * Elle reste reelle et tranchee ailleurs : `MODULE_COMPTABILITE_COMPLET_PART2.md`
 * §2.2 range 4191 au passif circulant, et c'est ce que le Bilan applique —
 * de l'argent recu d'avance pour une prestation non rendue est une dette.
 *
 * La contradiction du document est portee au rapport de lot, pas tranchee
 * seule. C'est le controle de coherence, exige par le document lui-meme, qui
 * departage — et une mutation le verifie.
 */
class TafireService
{
    private const PRECISION = 2;

    private const ZERO = '0.00';

    public function __construct(
        private readonly BalanceGeneraleService $balance,
        private readonly BilanService $bilan,
    ) {
    }

    /**
     * @param  list<string>  $statuts
     */
    public function genererPourExercice(
        string $exerciceId,
        array $statuts,
        string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES,
    ): Tafire {
        $balance = $this->balance->genererPourExercice($exerciceId, $statuts, $filtreStatut);
        $bilan = $this->bilan->genererPourExercice($exerciceId, $statuts, $filtreStatut);
        $lignes = $balance->lignes;

        // --- RESSOURCES ---
        //
        // Le resultat vient du Bilan, jamais d'une seconde agregation : c'est la
        // MEME grandeur qui equilibre le bilan et qui ouvre la CAFG. Deux
        // formules finiraient par diverger et les deux etats afficheraient deux
        // resultats sur le meme exercice (PA-121).
        $resultatExercice = $bilan->resultatExercice;

        // Charge NON DECAISSEE : elle a diminue le resultat sans sortir de
        // tresorerie, on la reintegre. Debitrice par nature (compte 681).
        $dotations = $this->sommeDebitrice($lignes, RubriquesSyscohada::DOTATIONS_AMORTISSEMENTS);
        $cafg = bcadd($resultatExercice, $dotations, self::PRECISION);

        $augmentationCapital = $this->sommeCreditrice($lignes, RubriquesSyscohada::CAPITAL);
        $totalRessources = bcadd($cafg, $augmentationCapital, self::PRECISION);

        // --- EMPLOIS ---
        $acquisitions = $this->sommeDebitrice($lignes, RubriquesSyscohada::IMMOBILISATIONS_BRUTES);
        $totalEmplois = $acquisitions;

        // --- BESOIN EN FONDS DE ROULEMENT ---
        $variationStocks = $this->sommeDebitrice($lignes, RubriquesSyscohada::STOCKS);
        $variationCreances = $this->sommeDebitrice($lignes, RubriquesSyscohada::CREANCES);
        $variationDettes = $this->sommeCreditrice($lignes, RubriquesSyscohada::DETTES_CIRCULANTES);

        $variationBfr = bcsub(
            bcadd($variationStocks, $variationCreances, self::PRECISION),
            $variationDettes,
            self::PRECISION,
        );

        // --- VARIATION DE TRESORERIE ---
        $variationCalculee = bcsub(
            bcsub($totalRessources, $totalEmplois, self::PRECISION),
            $variationBfr,
            self::PRECISION,
        );

        // La tresorerie NETTE : l'actif moins le passif de tresorerie. Ne
        // retenir que l'actif ferait apparaitre un decouvert bancaire comme une
        // ressource, le jour ou un compte 56 sera ouvert.
        $variationReelle = bcsub(
            $this->sommeDebitrice($lignes, RubriquesSyscohada::TRESORERIE_ACTIF),
            $this->sommeCreditrice($lignes, RubriquesSyscohada::TRESORERIE_PASSIF),
            self::PRECISION,
        );

        $ecart = bcsub($variationCalculee, $variationReelle, self::PRECISION);

        return new Tafire(
            exerciceId: $exerciceId,
            resultatExercice: $resultatExercice,
            dotationsAmortissements: $dotations,
            capaciteAutofinancementGlobale: $cafg,
            augmentationCapital: $augmentationCapital,
            totalRessources: $totalRessources,
            acquisitionsImmobilisations: $acquisitions,
            totalEmplois: $totalEmplois,
            variationStocks: $variationStocks,
            variationCreances: $variationCreances,
            variationDettes: $variationDettes,
            variationBesoinFondsRoulement: $variationBfr,
            variationTresorerieCalculee: $variationCalculee,
            variationTresorerieReelle: $variationReelle,
            ecart: $ecart,
            coherent: bccomp($ecart, self::ZERO, self::PRECISION) === 0,
            impotNonComptabilise: $bilan->impotNonComptabilise,
            motifResultatAvantImpot: $bilan->motifResultatAvantImpot,
            statuts: $balance->statuts,
            filtresAppliques: $balance->filtresAppliques,
        );
    }

    /**
     * @param  list<LigneBalance>  $lignes
     * @param  list<string>  $prefixes
     */
    private function sommeDebitrice(array $lignes, array $prefixes): string
    {
        $total = self::ZERO;

        foreach ($lignes as $ligne) {
            if (RubriquesSyscohada::releveDe($ligne->numeroCompte, $prefixes)) {
                $total = bcadd($total, bcsub($ligne->totalDebit, $ligne->totalCredit, self::PRECISION), self::PRECISION);
            }
        }

        return $total;
    }

    /**
     * @param  list<LigneBalance>  $lignes
     * @param  list<string>  $prefixes
     */
    private function sommeCreditrice(array $lignes, array $prefixes): string
    {
        $total = self::ZERO;

        foreach ($lignes as $ligne) {
            if (RubriquesSyscohada::releveDe($ligne->numeroCompte, $prefixes)) {
                $total = bcadd($total, bcsub($ligne->totalCredit, $ligne->totalDebit, self::PRECISION), self::PRECISION);
            }
        }

        return $total;
    }
}
