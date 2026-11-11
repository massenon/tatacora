<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Support;

/**
 * Le registre des PREFIXES de comptes par rubrique SYSCOHADA revise.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## Pourquoi un seul endroit
 *
 * Le Bilan, le Compte de Resultat, le TAFIRE, les Notes Annexes et l'etat de
 * cloture lisent TOUS la meme Balance et repartissent ses lignes par prefixe.
 * Ecrite cinq fois, cette repartition finirait par diverger, et deux ecrans
 * afficheraient deux verites sur le meme exercice — c'est le raisonnement de
 * PA-121 (les series se calculent COMME le KPI) applique aux etats financiers.
 *
 * ## Les rubriques VIDES sont conservees, jamais supprimees
 *
 * `MODULE_COMPTABILITE_COMPLET_PART3.md` §1.2 : aucun compte de charge
 * financiere ni d'operation HAO n'est defini pour le profil TATACORA. La
 * rubrique reste presente et rend `0.00` — un zero CALCULE sur un perimetre de
 * comptes reellement balaye, pas une ligne omise. `MODULE_COMPTABILITE_COMPLET_PART2.md`
 * §2.3 pose explicitement la meme regle pour la Tresorerie-Passif : « rubrique
 * presente dans la structure pour extensibilite future, jamais supprimee du
 * modele meme si actuellement a zero ».
 *
 * C'est aussi ce qui fait que le jour ou un compte 674000 sera cree, il sera
 * capte sans modification de code : le balayage porte sur un prefixe, pas sur
 * une liste de numeros existants.
 */
final class RubriquesSyscohada
{
    /*
     * --- Comptes de gestion — Compte de Resultat (PART3 §1.2) ---
     */

    /** @var list<string> */
    public const PRODUITS_EXPLOITATION = ['706', '707', '758'];

    /** @var list<string> */
    public const CHARGES_EXPLOITATION = [
        '601', '602', '604', '605', '61', '622', '624', '625', '627', '628',
        '631', '632', '641', '645', '661', '664', '681',
    ];

    /** @var list<string> */
    public const PRODUITS_FINANCIERS = ['771'];

    /**
     * Vide en pratique : aucun emprunt n'est modelise chez TATACORA (PART3
     * §1.2). Le prefixe court `67` capte tout compte d'interet cree plus tard.
     *
     * @var list<string>
     */
    public const CHARGES_FINANCIERES = ['67'];

    /** @var list<string> */
    public const PRODUITS_HAO = ['82', '84', '86', '88'];

    /** @var list<string> */
    public const CHARGES_HAO = ['81', '83', '85', '87'];

    /*
     * --- Comptes de bilan (PART2 §1 et §2) ---
     */

    /** @var list<string> */
    public const IMMOBILISATIONS_BRUTES = ['231', '234', '244', '245'];

    /** @var list<string> */
    public const AMORTISSEMENTS = ['28'];

    /** @var list<string> */
    public const STOCKS = ['31', '32'];

    /**
     * Creances — clients (411) et creances sur l'Etat au titre de la TVA :
     * `445` (TVA recuperable sur immobilisations, achats, transport, services
     * exterieurs... — debitrice par nature) et `4449` (credit de TVA a
     * reporter). Sans elles, une TVA deductible comptabilisee tombait hors
     * nomenclature et le bilan se disait desequilibre (09/11/2026).
     *
     * @var list<string>
     */
    public const CREANCES = ['411', '4449', '445'];

    /** @var list<string> */
    public const TRESORERIE_ACTIF = ['521', '522', '55', '571', '572', '573'];

    /**
     * Capital (groupe 10, ecrit compte par compte : le plan n'a pas de compte
     * `10`) : 101 capital social, 102 capital par dotation, 103 capital
     * personnel, 104 COMPTE DE L'EXPLOITANT (entreprise individuelle : ses
     * apports crediteurs, ses prelevements debiteurs — un compte de CAPITAUX
     * PROPRES, jamais une dette), 105 primes, 106 ecarts de reevaluation, 109
     * capital souscrit non appele (debiteur, il diminue). 107 et 108 n'existent
     * pas au plan.
     *
     * @var list<string>
     */
    public const CAPITAL = ['101', '102', '103', '104', '105', '106', '109'];

    /**
     * Subventions d'investissement (14) : capitaux propres, nettes de la
     * quote-part virée au resultat (D 14 / C 799).
     *
     * @var list<string>
     */
    public const SUBVENTIONS_INVESTISSEMENT = ['14'];

    /**
     * Provisions reglementees et fonds assimiles (15) : capitaux propres, sans
     * flux de tresorerie (amortissements derogatoires : D 851 / C 151).
     *
     * @var list<string>
     */
    public const PROVISIONS_REGLEMENTEES = ['15'];

    /**
     * Emprunts et dettes assimilees (16) et dettes de location-acquisition (17) :
     * les « emprunts » du TAFIRE.
     *
     * @var list<string>
     */
    public const DETTES_FINANCIERES = ['16', '17'];

    /**
     * Dettes liees a des participations et comptes de liaison des etablissements
     * (18) : ressources stables a part, nulles sans groupe ni etablissement
     * (le Gite est une entreprise individuelle).
     *
     * @var list<string>
     */
    public const DETTES_PARTICIPATIONS = ['18'];

    /**
     * Provisions pour risques et charges (19) : PROVISION FINANCIERE, pas un
     * emprunt. Ressource assimilee du bilan ; AUCUN flux de financement : sa
     * variation vient des dotations (69, 85) et des reprises (79, 86) de la CAFG.
     *
     * @var list<string>
     */
    public const PROVISIONS_FINANCIERES = ['19'];

    /**
     * Reserves (groupe 11 : 111 legale, 112 statutaires, 113 reglementees, 118
     * autres) et report a nouveau (groupe 12 : 121 crediteur, 129 debiteur) —
     * capitaux propres, nets (un 129 debiteur diminue). Sans eux, l'AFFECTATION
     * DU RESULTAT (09/11/2026) creditait un compte hors nomenclature et le
     * bilan de l'exercice qui la porte se disait desequilibre du montant
     * affecte.
     *
     * @var list<string>
     */
    public const RESERVES = ['11'];

    /** @var list<string> */
    public const REPORT_A_NOUVEAU = ['12'];

    /**
     * Comptes de resultat de CLOTURE — tout le groupe 13 : 131 (benefice) et
     * 139 (perte) par defaut, mais l'administrateur peut rattacher les roles
     * `RESULTAT_BENEFICE` et `RESULTAT_PERTE` a un autre compte de la classe 13
     * (correspondance des comptes, 26/10/2026 ; la validation exige le prefixe
     * 13). Le prefixe 13 — et non la liste 131/139 — garde le bilan equilibre :
     * un resultat reporte sur un autre compte du groupe y reste compte.
     *
     * Ils sont vides tant qu'aucune cloture n'a eu lieu. Les inclure quand
     * meme dans les capitaux propres evite qu'un exercice deja cloture affiche
     * un bilan faux.
     *
     * @var list<string>
     */
    public const RESULTAT_REPORTE = ['13'];

    /**
     * Dettes circulantes — PART2 §2.2.
     *
     * ⚠ `4191` (clients — avances et acomptes recus, les arrhes de reservation
     * EF-M1-06) est une DETTE, pas une creance : c'est de l'argent recu d'avance
     * pour une prestation non encore rendue. PART2 §2.2 le classe bien au passif
     * circulant. Voir `TafireService` pour la contradiction de PART3 sur ce
     * meme compte, et sa preuve.
     *
     * `443` (TVA facturee — 4431 sur ventes, 4432 sur prestations...) et
     * `4441` (Etat, TVA due) sont des dettes envers l'Etat, creditrices par
     * nature : une vente avec TVA credite 4431/4432, et sans `443` ici ce
     * credit n'etait dans aucune rubrique — le bilan affichait un ecart egal
     * au solde de TVA collectee (09/11/2026). `4449` (credit de TVA a
     * reporter) est, lui, une creance : voir {@see self::CREANCES}.
     *
     * @var list<string>
     */
    public const DETTES_CIRCULANTES = ['401', '4191', '421', '422', '431', '443', '4441', '447'];

    /**
     * `465` — associes, dividendes a payer : une dette envers les associes,
     * creditee par l'affectation d'un benefice aux dividendes (09/11/2026).
     * Au BILAN (10/11/2026) c'est une dette du PASSIF CIRCULANT (« autres
     * dettes », avec une ligne « dont dividendes a payer »), comme toutes les
     * dettes a moins d'un an. Mais rubrique A PART de `DETTES_CIRCULANTES` pour
     * le TAFIRE : il lit la variation de `DETTES_CIRCULANTES` (BFR) et traite les
     * dividendes comme un mouvement des capitaux propres ; la meler au BFR le
     * fausserait (l'identite du TAFIRE ne change pas).
     *
     * @var list<string>
     */
    public const DETTES_ASSOCIES = ['465'];

    /**
     * Neant dans le profil TATACORA (PART2 §2.3) — aucun decouvert bancaire ni
     * credit de tresorerie modelise. La rubrique existe pour que le jour ou un
     * compte 561/565 sera ouvert, il ne tombe pas silencieusement hors bilan.
     *
     * @var list<string>
     */
    public const TRESORERIE_PASSIF = ['561', '564', '565', '566'];

    /**
     * TOUS les prefixes qui trouvent une place au Bilan.
     *
     * Sert la garde `comptesHorsRubrique` du `BilanService` : un compte
     * mouvemente qui ne releve d'aucun de ces prefixes NI d'aucune rubrique du
     * Compte de Resultat n'apparait nulle part, et son solde manquerait a
     * l'equilibre sans que rien ne le nomme.
     *
     * @return list<string>
     */
    public static function prefixesBilan(): array
    {
        return [
            ...self::IMMOBILISATIONS_BRUTES,
            ...self::AMORTISSEMENTS,
            ...self::STOCKS,
            ...self::CREANCES,
            ...self::TRESORERIE_ACTIF,
            ...self::CAPITAL,
            ...self::SUBVENTIONS_INVESTISSEMENT,
            ...self::PROVISIONS_REGLEMENTEES,
            ...self::RESERVES,
            ...self::REPORT_A_NOUVEAU,
            ...self::RESULTAT_REPORTE,
            ...self::DETTES_FINANCIERES,
            ...self::DETTES_PARTICIPATIONS,
            ...self::PROVISIONS_FINANCIERES,
            ...self::DETTES_CIRCULANTES,
            ...self::DETTES_ASSOCIES,
            ...self::TRESORERIE_PASSIF,
        ];
    }

    /**
     * Vrai si `$numeroCompte` releve de l'un des prefixes donnes.
     *
     * @param  list<string>  $prefixes
     */
    public static function releveDe(string $numeroCompte, array $prefixes): bool
    {
        foreach ($prefixes as $prefixe) {
            if (str_starts_with($numeroCompte, $prefixe)) {
                return true;
            }
        }

        return false;
    }
}
