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
 * ## DEFINITION FINALE (10/11/2026, avis de l'expert-comptable SYSCOHADA)
 *
 * Le resultat est celui de N SEUL, et tout montant de bilan est une VARIATION :
 * solde de cloture (balance, a-nouveaux compris) moins solde d'ouverture
 * (`BalanceGeneraleService::soldesOuverture` : journal AN, ou a-nouveaux
 * provisoires). Il n'y a plus de « niveau » dans le tableau, donc plus de report
 * de N-1 recompte.
 *
 *   CAFG        = resultat net de N (`Bilan::resultatExercice`, jamais le 131/139
 *                 reporte)
 *                 + DOTATIONS (681 + 687 + 691 + 697 + 85)
 *                 - REPRISES (781 + 787 + 791 + 797 + 798 + 86)
 *                 + valeur comptable des cessions (81) - produits des cessions (82)
 *                 - quote-part des subventions d'investissement virée au résultat
 *                   (799 : produit non encaisse)
 *   Exploitation  = CAFG - variation du BFR (stocks + creances - dettes circulantes ;
 *                   le 465 n'y est PAS)
 *   Investissement = produits des cessions (82) - acquisitions, avec
 *                 acquisitions = variation des immobilisations NETTES + dotations
 *                 aux AMORTISSEMENTS (681, 852) + VNC cedees - reprises sur
 *                 immobilisations (781, 787, 798, 862)
 *   Financement = apports (101, 102, 103, 105, 106, 109 + subventions
 *                 d'investissement RECUES : variation du 14 + quote-part 799 virée)
 *                 + emprunts (comptes 16 et 17 : dettes financieres et credit-bail)
 *                 + dettes liees a des participations et comptes de liaison (18,
 *                   ligne distincte, nulle sans groupe)
 *                 - dividendes verses, avec
 *                 dividendes verses = -(variation des capitaux propres hors resultat :
 *                 compte de l'exploitant 104, reserves 11, report 12, resultat
 *                 reporte 13 + variation des dividendes a payer 465)
 *   Variation de tresorerie = Exploitation + Investissement + Financement
 *                           = variation constatee aux comptes de classe 5.
 *
 * ### Les provisions (19, 15) n'entrent dans AUCUN flux
 *
 * Le 19 est une PROVISION FINANCIERE POUR RISQUES ET CHARGES, pas un emprunt : sa
 * variation passe par les dotations (691, 697, 85) et les reprises (791, 797, 86)
 * de la CAFG, et par rien d'autre. Meme regle pour le 15 (provisions
 * reglementees : 851 / 861). Une dotation aux PROVISIONS est reintegree a la CAFG
 * mais n'entre pas dans les acquisitions (aucune contrepartie parmi les
 * immobilisations) : seules les dotations dont la contrepartie est un
 * amortissement (681, 852) et les reprises sur immobilisations (781, 787, 798,
 * 862) s'y compensent. Un mouvement de 19 qui ne passerait pas par une dotation ou
 * une reprise (ex. D 121 / C 19) laisse un ECART : le controle de coherence le
 * dit, c'est son role.
 *
 * ### Ce que le plan comptable du depot dit, et ce que l'avis supposait
 *
 *  - Le 777 est « Gains sur cessions de titres de placement » (encaisse) : la
 *    quote-part des subventions virée au resultat est, au plan revise, le 799
 *    « Reprises de subventions d'investissement » ; c'est lui qui est retire de
 *    la CAFG. Le 799, comme le 797 et le 687, n'etait capte par aucune rubrique du
 *    compte de resultat : ils entrent maintenant dans la cascade des SIG.
 *  - Le 781 et le 787 sont des « Transferts de charges », comptes de l'avis ranges
 *    avec les reprises ; leur contrepartie est supposee etre une immobilisation (ou
 *    son amortissement). Un transfert dont la contrepartie serait une creance (BFR)
 *    fausserait le tableau : a confirmer avec le comptable.
 *  - Les reprises d'amortissements sont au 798 (absent de l'avis, ajoute ici : sans
 *    lui, une reprise d'amortissement laissait un ecart).
 *  - 18 : « dettes liees a des participations, comptes de liaison ». Ligne
 *    distincte (ressource de financement reelle quand un groupe existe, et elle
 *    garde les totaux equilibres) plutot qu'exclusion avec un ecart nomme ; nulle
 *    sans groupe, donc non affichee au web.
 *  - ECART NOMME : le TAFIRE n'a pas de ligne « subventions d'investissement
 *    recues » : elles restent dans « Augmentation de capital » (variation du 14
 *    + quote-part 799 virée, soit le montant effectivement recu).
 *
 * ### Le compte de l'exploitant (104) et le 465
 *
 * L'affectation du resultat de N-1 (D 131 / C 121, 111, 118, 465, 104 ; perte
 * D 129 / C 139) n'est PAS du resultat de N : c'est un mouvement des capitaux
 * propres, lu PAR COMPTES (classe 1) et non par une liste de pieces. Un benefice
 * affecte au 104 (D 131 / C 104) se compense (131 baisse, 104 monte) : aucun
 * decaissement. Un PRELEVEMENT personnel (D 104 / C 5xx) baisse les capitaux
 * propres : il est lu avec les dividendes (« dividendes verses et prelevements de
 * l'exploitant »). Le 465 reste HORS du BFR (au bilan il est dans le passif
 * circulant, mais le TAFIRE lit sa variation avec les capitaux propres) : ne sort
 * de tresorerie que ce qui est REGLE (D 465 / C 5xx). Un a-nouveau reporte sans
 * affectation ne varie pas (variation nulle).
 *
 * Preuve : la somme des soldes de tous les comptes est nulle a l'ouverture et a
 * la cloture, donc la somme des variations des classes 1 a 5 vaut le resultat
 * net de N (classes 6 a 8). Un ecart ne peut venir que d'un compte de classe 1 a
 * 5 qu'aucune rubrique ne capte (le Bilan le nomme dans `comptesHorsRubrique`)
 * ou d'un mouvement de provision sans dotation ni reprise.
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

        // Charges NON DECAISSEES reintegrees (dotations : amortissements,
        // provisions, depreciations, HAO) et produits NON ENCAISSES deduits
        // (reprises, transferts de charges).
        $dotations = $this->sommeDebitrice($lignes, RubriquesTafire::DOTATIONS);
        $reprises = $this->sommeCreditrice($lignes, RubriquesTafire::REPRISES);
        // La part de ces mouvements dont la contrepartie est une immobilisation
        // ou son amortissement : seule elle se compense dans les acquisitions.
        $dotationsAmortissements = $this->sommeDebitrice($lignes, RubriquesTafire::DOTATIONS_AMORTISSEMENTS);
        $reprisesSurImmobilisations = $this->sommeCreditrice($lignes, RubriquesTafire::REPRISES_SUR_IMMOBILISATIONS);
        $vncCessions = $this->sommeDebitrice($lignes, RubriquesTafire::VALEUR_COMPTABLE_CESSIONS);
        $produitsCessions = $this->sommeCreditrice($lignes, RubriquesTafire::PRODUITS_CESSIONS);
        // Quote-part des subventions d'investissement virée au resultat (D 14 /
        // C 799) : produit NON encaisse.
        $quotePartSubventions = $this->sommeCreditrice($lignes, RubriquesTafire::QUOTE_PART_SUBVENTIONS);

        $cafg = bcsub(
            bcsub(
                bcadd(bcsub(bcadd($resultatExercice, $dotations, self::PRECISION), $reprises, self::PRECISION), $vncCessions, self::PRECISION),
                $produitsCessions,
                self::PRECISION,
            ),
            $quotePartSubventions,
            self::PRECISION,
        );

        // --- RESSOURCES : CAFG, cessions, apports, emprunts ---
        //
        // Apports = variation du capital (101 a 109 hors 104) et des
        // subventions d'investissement (14) + quote-part virée (799) : la
        // subvention RECUE est la variation du 14 avant la quote-part qui l'a
        // diminue sans tresorerie. Pas de ligne dediee : ecart nomme en tete.
        $augmentationCapital = bcadd(
            $this->variationCreditrice($lignes, $ouverture, RubriquesTafire::APPORTS_CAPITAL),
            $quotePartSubventions,
            self::PRECISION,
        );
        // Emprunts = comptes 16 et 17 SEULS. Le 19 est une provision : aucun flux.
        $variationEmprunts = $this->variationCreditrice($lignes, $ouverture, RubriquesTafire::DETTES_FINANCIERES);
        $variationParticipations = $this->variationCreditrice($lignes, $ouverture, RubriquesTafire::DETTES_PARTICIPATIONS);
        $totalRessources = bcadd(
            bcadd(
                bcadd(bcadd($cafg, $produitsCessions, self::PRECISION), $augmentationCapital, self::PRECISION),
                $variationEmprunts,
                self::PRECISION,
            ),
            $variationParticipations,
            self::PRECISION,
        );

        // --- EMPLOIS : investissements et dividendes ---
        //
        // Acquisitions = variation des immobilisations NETTES + dotations aux
        // AMORTISSEMENTS + VNC cedees - reprises sur immobilisations (une sortie
        // d'actif amorti ne diminue pas les acquisitions). Les dotations aux
        // PROVISIONS n'y entrent pas : elles n'ont pas de contrepartie d'actif.
        $variationBrut = $this->variationDebitrice($lignes, $ouverture, RubriquesSyscohada::IMMOBILISATIONS_BRUTES);
        $variationAmort = $this->variationCreditrice($lignes, $ouverture, RubriquesSyscohada::AMORTISSEMENTS);
        $acquisitions = bcsub(
            bcadd(bcadd(bcsub($variationBrut, $variationAmort, self::PRECISION), $dotationsAmortissements, self::PRECISION), $vncCessions, self::PRECISION),
            $reprisesSurImmobilisations,
            self::PRECISION,
        );

        // Affectation du resultat de N-1 et compte de l'exploitant : mouvement
        // des capitaux propres lu PAR COMPTES (104, 11, 12, 13), jamais du
        // resultat de N. Ses contreparties sont, pour la part non distribuee,
        // d'autres comptes de capitaux propres (qui se compensent, y compris un
        // benefice affecte au 104) et, pour la part distribuee, les dividendes a
        // payer (465). Le decaissement est donc la variation des capitaux propres
        // + la variation des 465 (nul tant que rien n'est paye ; chaque reglement
        // D 465 / C 5xx le creuse ; un prelevement D 104 / C 5xx aussi).
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
        $fluxFinancement = bcsub(
            bcadd(bcadd($augmentationCapital, $variationEmprunts, self::PRECISION), $variationParticipations, self::PRECISION),
            $dividendesVerses,
            self::PRECISION,
        );

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
            quotePartSubventions: $quotePartSubventions,
            capaciteAutofinancementGlobale: $cafg,
            produitsCessions: $produitsCessions,
            augmentationCapital: $augmentationCapital,
            variationEmprunts: $variationEmprunts,
            variationDettesParticipations: $variationParticipations,
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
