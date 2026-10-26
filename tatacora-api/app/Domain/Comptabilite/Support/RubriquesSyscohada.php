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

    /** @var list<string> */
    public const CREANCES = ['411'];

    /** @var list<string> */
    public const TRESORERIE_ACTIF = ['521', '522', '55', '571', '572', '573'];

    /** @var list<string> */
    public const CAPITAL = ['101'];

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
     * @var list<string>
     */
    public const DETTES_CIRCULANTES = ['401', '4191', '421', '422', '431', '447'];

    /**
     * Neant dans le profil TATACORA (PART2 §2.3) — aucun decouvert bancaire ni
     * credit de tresorerie modelise. La rubrique existe pour que le jour ou un
     * compte 561/565 sera ouvert, il ne tombe pas silencieusement hors bilan.
     *
     * @var list<string>
     */
    public const TRESORERIE_PASSIF = ['561', '564', '565', '566'];

    /**
     * La DOTATION aux amortissements de l'exercice — charge non decaissee,
     * reintegree a la CAFG (PART3 §2.2).
     *
     * @var list<string>
     */
    public const DOTATIONS_AMORTISSEMENTS = ['681'];

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
            ...self::RESULTAT_REPORTE,
            ...self::DETTES_CIRCULANTES,
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
