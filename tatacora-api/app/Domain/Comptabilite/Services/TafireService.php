<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\ReadModels\LigneBalance;
use App\Domain\Comptabilite\ReadModels\Tafire;
use App\Domain\Comptabilite\Support\RubriquesSyscohada;
use App\Domain\Comptabilite\Support\RubriquesTafire;

/**
 * TAFIRE — `MODULE_COMPTABILITE_COMPLET_PART3.md` §2, `m10-flux-tresorerie.html`.
 *
 * ## DEFINITION (10/11/2026) — resultat net de N SEUL, flux = VARIATIONS
 *
 * Tout montant de bilan est une VARIATION : solde de cloture (balance, a-nouveaux
 * compris) moins solde d'ouverture (`BalanceGeneraleService::soldesOuverture` :
 * journal AN, ou a-nouveaux provisoires). Il n'y a plus de « niveau » dans le
 * tableau, donc plus de report de N-1 recompte.
 *
 *   CAFG        = resultat net de N (`Bilan::resultatExercice`, jamais le 131/139
 *                 reporte) + dotations (681) - reprises (781)
 *                 + valeur comptable des cessions (81) - produits des cessions (82)
 *   Exploitation  = CAFG - variation du BFR (stocks + creances - dettes circulantes)
 *   Investissement = produits des cessions (82) - acquisitions, avec
 *                 acquisitions = variation des immobilisations NETTES + dotations
 *                 + VNC cedees - reprises
 *   Financement = augmentation de capital (comptes 10 et 14) + variation des
 *                 emprunts (16 a 19) - dividendes verses, avec
 *                 dividendes verses = -(variation des capitaux propres 11, 12, 13,
 *                 15 + variation des dividendes a payer 465)
 *   Variation de tresorerie = Exploitation + Investissement + Financement
 *                           = variation constatee aux comptes de classe 5.
 *
 * L'AFFECTATION du resultat de N-1 (D 131 / C 121, 111, 118, 465 ; perte D 129 /
 * C 139) n'est PAS du resultat de N : c'est un mouvement des capitaux propres,
 * lu PAR COMPTES (classe 1) et non par une liste de pieces. Le 131/139 qui
 * baisse se compense avec les reserves/report qui montent ; la part mise en
 * distribution passe en 465 (dette de financement, hors BFR) ; ne sort de
 * tresorerie que ce qui est REGLE (D 465 / C 5xx) : le TAFIRE reste equilibre
 * avant comme apres chaque reglement. Un a-nouveau reporte sans affectation ne
 * varie pas (variation nulle).
 *
 * Preuve : la somme des soldes de tous les comptes est nulle a l'ouverture et a
 * la cloture, donc la somme des variations des classes 1 a 5 vaut le resultat
 * net de N (classes 6 a 8). Un ecart ne peut venir que d'un compte de classe 1 a
 * 5 qu'aucune rubrique ne capte (le Bilan le nomme dans `comptesHorsRubrique`).
 *
 * Les prefixes propres au TAFIRE sont dans `RubriquesTafire`.
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

        // Soldes d'OUVERTURE (a-nouveaux ecrits au journal AN, ou provisoires),
        // deja compris dans la balance : on ne retient que les VARIATIONS.
        // Les a-nouveaux ne sont dans la balance que pour les ecritures
        // validees ; sans elles, rien a retrancher.
        $ouverture = in_array('validee', $statuts, true)
            ? $this->balance->soldesOuverture($exerciceId)['soldes']
            : [];

        // --- CAFG : part du resultat de N SEUL ---
        //
        // `Bilan::resultatExercice` = produits - charges des classes 6 a 8 de
        // CET exercice (jamais le 131/139 reporte de N-1, qui est un capital
        // propre, voir `Bilan::resultatReporte`).
        $resultatExercice = $bilan->resultatExercice;

        // Charge NON DECAISSEE : reintegree. Debitrice par nature (681).
        $dotations = $this->sommeDebitrice($lignes, RubriquesSyscohada::DOTATIONS_AMORTISSEMENTS);
        $reprises = $this->sommeCreditrice($lignes, RubriquesTafire::REPRISES);
        $vncCessions = $this->sommeDebitrice($lignes, RubriquesTafire::VALEUR_COMPTABLE_CESSIONS);
        $produitsCessions = $this->sommeCreditrice($lignes, RubriquesTafire::PRODUITS_CESSIONS);

        $cafg = bcsub(
            bcadd(bcsub(bcadd($resultatExercice, $dotations, self::PRECISION), $reprises, self::PRECISION), $vncCessions, self::PRECISION),
            $produitsCessions,
            self::PRECISION,
        );

        // --- RESSOURCES : CAFG, cessions, apports de capital, emprunts ---
        $augmentationCapital = $this->variationCreditrice($lignes, $ouverture, RubriquesTafire::APPORTS_CAPITAL);
        $variationEmprunts = $this->variationCreditrice($lignes, $ouverture, RubriquesTafire::DETTES_FINANCIERES);
        $totalRessources = bcadd(
            bcadd(bcadd($cafg, $produitsCessions, self::PRECISION), $augmentationCapital, self::PRECISION),
            $variationEmprunts,
            self::PRECISION,
        );

        // --- EMPLOIS : investissements et dividendes ---
        //
        // Acquisitions = variation des immobilisations NETTES + dotations + VNC
        // cedees - reprises (une sortie d'actif amorti ne diminue pas les
        // acquisitions).
        $variationBrut = $this->variationDebitrice($lignes, $ouverture, RubriquesSyscohada::IMMOBILISATIONS_BRUTES);
        $variationAmort = $this->variationCreditrice($lignes, $ouverture, RubriquesSyscohada::AMORTISSEMENTS);
        $acquisitions = bcsub(
            bcadd(bcadd(bcsub($variationBrut, $variationAmort, self::PRECISION), $dotations, self::PRECISION), $vncCessions, self::PRECISION),
            $reprises,
            self::PRECISION,
        );

        // Affectation du resultat de N-1 : mouvement des capitaux propres lu
        // PAR COMPTES (11, 12, 13, 15), jamais du resultat de N. Ses
        // contreparties sont, pour la part non distribuee, d'autres comptes de
        // capitaux propres (qui se compensent) et, pour la part distribuee, les
        // dividendes a payer (465). Le decaissement est donc la variation des
        // capitaux propres + la variation des 465 (nul tant que rien n'est
        // paye ; chaque reglement D 465 / C 5xx le creuse).
        $variationAutres = $this->variationCreditrice($lignes, $ouverture, RubriquesTafire::AUTRES_CAPITAUX_PROPRES);
        $variationDividendes = $this->variationCreditrice($lignes, $ouverture, RubriquesTafire::DIVIDENDES_A_PAYER);
        $dividendesVerses = bcsub('0.00', bcadd($variationAutres, $variationDividendes, self::PRECISION), self::PRECISION);
        $totalEmplois = bcadd($acquisitions, $dividendesVerses, self::PRECISION);

        // --- BESOIN EN FONDS DE ROULEMENT (variations) ---
        $variationStocks = $this->variationDebitrice($lignes, $ouverture, RubriquesSyscohada::STOCKS);
        $variationCreances = $this->variationDebitrice($lignes, $ouverture, RubriquesSyscohada::CREANCES);
        $variationDettes = $this->variationCreditrice($lignes, $ouverture, RubriquesSyscohada::DETTES_CIRCULANTES);

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

        $fluxExploitation = bcsub($cafg, $variationBfr, self::PRECISION);
        $fluxInvestissement = bcsub($produitsCessions, $acquisitions, self::PRECISION);
        $fluxFinancement = bcsub(bcadd($augmentationCapital, $variationEmprunts, self::PRECISION), $dividendesVerses, self::PRECISION);

        // La tresorerie NETTE : l'actif moins le passif de tresorerie. Ne
        // retenir que l'actif ferait apparaitre un decouvert bancaire comme une
        // ressource, le jour ou un compte 56 sera ouvert. C'est la VARIATION
        // constatee aux classes 5 (cloture - ouverture).
        $variationReelle = bcsub(
            $this->variationDebitrice($lignes, $ouverture, RubriquesSyscohada::TRESORERIE_ACTIF),
            $this->variationCreditrice($lignes, $ouverture, RubriquesSyscohada::TRESORERIE_PASSIF),
            self::PRECISION,
        );

        $ecart = bcsub($variationCalculee, $variationReelle, self::PRECISION);

        return new Tafire(
            exerciceId: $exerciceId,
            resultatExercice: $resultatExercice,
            dotationsAmortissements: $dotations,
            reprisesAmortissements: $reprises,
            valeurComptableCessions: $vncCessions,
            capaciteAutofinancementGlobale: $cafg,
            produitsCessions: $produitsCessions,
            augmentationCapital: $augmentationCapital,
            variationEmprunts: $variationEmprunts,
            totalRessources: $totalRessources,
            acquisitionsImmobilisations: $acquisitions,
            variationAutresCapitauxPropres: $variationAutres,
            variationDividendesAPayer: $variationDividendes,
            dividendesVerses: $dividendesVerses,
            totalEmplois: $totalEmplois,
            fluxExploitation: $fluxExploitation,
            fluxInvestissement: $fluxInvestissement,
            fluxFinancement: $fluxFinancement,
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

    /**
     * Variation d'une rubrique debitrice : solde de cloture (balance, a-nouveaux
     * compris) moins solde d'ouverture.
     *
     * @param  list<LigneBalance>  $lignes
     * @param  array<string, string>  $ouverture  debit - credit par compte
     * @param  list<string>  $prefixes
     */
    private function variationDebitrice(array $lignes, array $ouverture, array $prefixes): string
    {
        $total = $this->sommeDebitrice($lignes, $prefixes);

        foreach ($ouverture as $numero => $net) {
            if (RubriquesSyscohada::releveDe((string) $numero, $prefixes)) {
                $total = bcsub($total, $net, self::PRECISION);
            }
        }

        return $total;
    }

    /**
     * @param  list<LigneBalance>  $lignes
     * @param  array<string, string>  $ouverture
     * @param  list<string>  $prefixes
     */
    private function variationCreditrice(array $lignes, array $ouverture, array $prefixes): string
    {
        return bcsub('0.00', $this->variationDebitrice($lignes, $ouverture, $prefixes), self::PRECISION);
    }
}
