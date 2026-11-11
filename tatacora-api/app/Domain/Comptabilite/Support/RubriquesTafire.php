<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Support;

/**
 * Les prefixes de comptes que le TAFIRE lit EN PLUS de ceux de
 * {@see RubriquesSyscohada} (TAFIRE redefini sur le resultat de N seul, puis
 * avis de l'expert-comptable SYSCOHADA du 10/11/2026). Registre a part pour ne
 * pas toucher a celui du Bilan.
 *
 * Chaque numero est un compte du plan comptable du depot
 * (`database/data/plan-comptable-syscohada-revise.csv`). Ce que le plan ne dit
 * pas est signale ici, jamais invente :
 *  - 777 est « Gains sur cessions de titres de placement » (un produit
 *    ENCAISSE) et non la quote-part des subventions d'investissement : cette
 *    quote-part, au plan revise, est le 799 « Reprises de subventions
 *    d'investissement » ;
 *  - 781 et 787 sont des « Transferts de charges » (et non des reprises
 *    d'amortissements : celles-ci sont au 798).
 *
 * Les capitaux propres sont lus PAR COMPTES de la classe 1, jamais par une
 * liste de pieces : n'importe quelle piece d'affectation du resultat (D 131 /
 * C 121, 111, 118, 465, 104 ; perte D 129 / C 139) y est donc comprise, quels que
 * soient les comptes que la correspondance parametrable lui donne, pourvu
 * qu'ils restent dans la classe 1 (dividendes a payer : 465).
 */
final class RubriquesTafire
{
    /**
     * DOTATIONS de l'exercice, charges non decaissees reintegrees a la CAFG :
     * amortissements d'exploitation (681) et a caractere financier (687),
     * provisions et depreciations d'exploitation (691) et financieres (697),
     * dotations HAO (85 : provisions reglementees 851, amortissements 852,
     * depreciations 853, provisions pour risques et charges 854, autres 858).
     *
     * @var list<string>
     */
    public const DOTATIONS = ['681', '687', '691', '697', '85'];

    /**
     * REPRISES de l'exercice, produits non encaisses deduits de la CAFG :
     * transferts de charges d'exploitation (781) et financieres (787), reprises
     * de provisions et depreciations d'exploitation (791) et financieres (797),
     * reprises d'amortissements (798), reprises HAO (86).
     *
     * @var list<string>
     */
    public const REPRISES = ['781', '787', '791', '797', '798', '86'];

    /**
     * Les dotations dont la contrepartie est un AMORTISSEMENT (compte 28) :
     * amortissements d'exploitation (681) et HAO (852). Seules elles entrent dans
     * le calcul des acquisitions (variation des immobilisations NETTES + ces
     * dotations + VNC cedees - ces reprises). Une dotation aux PROVISIONS
     * (691, 697, 85 hors 852) n'a aucune contrepartie parmi les immobilisations :
     * elle est reintegree a la CAFG et c'est tout.
     *
     * @var list<string>
     */
    public const DOTATIONS_AMORTISSEMENTS = ['681', '852'];

    /**
     * Les reprises et transferts dont la contrepartie est une IMMOBILISATION ou
     * son amortissement : reprises d'amortissements (798) et HAO (862), transferts
     * de charges d'exploitation (781) et financieres (787) portes a l'actif
     * immobilise. Elles se compensent dans les acquisitions, comme les dotations
     * aux amortissements. Les reprises de PROVISIONS (791, 797, 86 hors 862) n'ont
     * pas de contrepartie d'immobilisation : CAFG seule.
     *
     * @var list<string>
     */
    public const REPRISES_SUR_IMMOBILISATIONS = ['781', '787', '798', '862'];

    /**
     * Quote-part des subventions d'investissement virée au resultat (799,
     * D 14 / C 799) : produit NON encaisse, retire de la CAFG. La subvention
     * REÇUE (D 5 / C 14) reste une ressource de financement ; faute de ligne
     * dediee, elle se lit avec les apports (voir `TafireService`).
     *
     * @var list<string>
     */
    public const QUOTE_PART_SUBVENTIONS = ['799'];

    /** Valeur comptable des immobilisations cedees (charge non decaissee). @var list<string> */
    public const VALEUR_COMPTABLE_CESSIONS = ['81'];

    /** Produits des cessions d'immobilisations (encaisses : flux d'investissement). @var list<string> */
    public const PRODUITS_CESSIONS = ['82'];

    /**
     * Capital et primes (101, 102, 103, 105, 106, 109) et subventions
     * d'investissement (14) : apports. Le 104 (compte de l'exploitant) n'y est
     * PAS : ses apports et ses prelevements sont des mouvements de capitaux
     * propres, lus avec les dividendes (voir `AUTRES_CAPITAUX_PROPRES`).
     *
     * @var list<string>
     */
    public const APPORTS_CAPITAL = ['101', '102', '103', '105', '106', '109', '14'];

    /**
     * Compte de l'exploitant (104), reserves (11), report a nouveau (12),
     * resultat reporte (13) : les mouvements de capitaux propres hors resultat de
     * N. Le 15 (provisions reglementees) n'y est plus : sa variation est sans
     * tresorerie (dotation 851 / reprise 861 de la CAFG), la lire ici la
     * compterait deux fois en dividendes.
     *
     * @var list<string>
     */
    public const AUTRES_CAPITAUX_PROPRES = ['104', '11', '12', '13'];

    /**
     * Les « emprunts » du TAFIRE : emprunts et dettes assimilees (16) et dettes de
     * location-acquisition (17). Le 19 (provisions pour risques et charges) n'en
     * est PAS : une provision n'est pas un emprunt.
     *
     * @var list<string>
     */
    public const DETTES_FINANCIERES = ['16', '17'];

    /**
     * Dettes liees a des participations et comptes de liaison (18) : ligne
     * DISTINCTE des emprunts (ni emprunt, ni provision), nulle sans groupe.
     *
     * @var list<string>
     */
    public const DETTES_PARTICIPATIONS = ['18'];

    /** Associes, dividendes a payer. @var list<string> */
    public const DIVIDENDES_A_PAYER = ['465'];
}
