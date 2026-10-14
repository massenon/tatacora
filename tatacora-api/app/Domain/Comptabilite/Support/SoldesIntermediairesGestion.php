<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Support;

/**
 * La cascade des Soldes Intermediaires de Gestion — Compte de Resultat
 * SYSCOHADA revise, Systeme Normal.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * Maitre : `prototype_v2/pages/m10-syscohada.html`, onglet « Compte de
 * resultat » ; cascade definie en `prototype_v2/assets/js/plan-comptable-syscohada.js`
 * l.89-138, calculee en `prototype_v2/assets/js/comptabilite-engine.js` l.493-555.
 *
 * ## L'IMPOT SUR LES SOCIETES N'EST JAMAIS CALCULE ICI (PA-19)
 *
 * `RS — Impots sur le resultat` est une rubrique comme les autres : elle
 * additionne ce qui a ete REELLEMENT COMPTABILISE en classe 89, exactement
 * comme `RK` additionne la classe 66. Aucun taux n'est lu, aucun taux n'est
 * suppose, et il n'existe dans ce service aucun chemin par lequel un taux
 * pourrait entrer.
 *
 * C'est ce qui rend PA-19 sans effet sur cet etat : le taux d'IS applicable au
 * Gite n'est pas tranche, mais on n'en a pas besoin pour restituer un compte de
 * resultat. Le jour ou le Comptable, muni du taux officiel de la DGI, passera
 * l'ecriture d'impot, `RS` cessera d'etre nul et `XI` deviendra un vrai resultat
 * net — sans une ligne de code de plus.
 *
 * Tant que rien n'est comptabilise en 89, `XI` vaut `XG + XH + RQ`, c'est-a-dire
 * un resultat AVANT impot. L'etat le DIT (`impotNonComptabilise`) au lieu de
 * laisser croire a un resultat net : c'est la difference entre « 0 » et « — »
 * de l'Article 7, portee sur la ligne ou elle coute le plus cher.
 *
 * ⚠ ECART DELIBERE — `MODULE_COMPTABILITE_COMPLET_PART3.md` §1.3
 * Le document : `CompteResultatService` lit `parametres_systeme.taux_impot_societes`
 * et calcule `impotResultat = max(0, RAO + HAO) * tauxIS`, en levant si le taux
 * est absent.
 * Ici : l'impot est LU des ecritures de classe 89, jamais calcule.
 * Raison : le maitre (autorite de l'Article 0) a retenu ce modele, et il est le
 * seul qui n'ait pas besoin d'une donnee reglementaire non confirmee. Calculer
 * l'impot serait aussi comptablement faux : un etat financier restitue ce qui
 * est comptabilise, il ne liquide pas l'impot a la place de l'administration.
 * La cle `taux_impot_societes` n'existe d'ailleurs NULLE PART dans ce depot —
 * ni au schema, ni au `RegistreParametres` : la branche de calcul du document
 * n'aurait jamais pu s'executer autrement qu'en levant.
 *
 * ## La convention de signe, et pourquoi elle est uniforme
 *
 * `montant = -(SOMME des soldes des comptes du prefixe)`, ou
 * `solde = debit - credit`. Un produit (solde crediteur) rend donc un montant
 * POSITIF, une charge (solde debiteur) un montant NEGATIF. Consequence : tous
 * les soldes intermediaires sont de simples ADDITIONS de leurs composants —
 * aucune soustraction, donc aucune erreur de signe possible dans la cascade.
 *
 * C'est aussi pourquoi `sens` ne sert qu'a l'AFFICHAGE (choisir la colonne
 * « Charges » ou « Produits / Solde » du maitre) et n'intervient jamais dans le
 * calcul.
 *
 * ## `XA` n'est repris dans AUCUN solde ulterieur
 *
 * La marge commerciale est un indicateur terminal : `XC` se recompose depuis
 * `XB` plus `RA + RB`, pas depuis `XA`. Additionner `XA` a la cascade
 * double-compterait les achats de marchandises. Le piege est signale ici parce
 * qu'il est invisible a la relecture de la seule liste des composants.
 */
final class SoldesIntermediairesGestion
{
    public const SENS_PRODUIT = 'produit';

    public const SENS_CHARGE = 'charge';

    public const SENS_SOLDE = 'solde';

    /** Le solde final de la cascade — le resultat net au sens SYSCOHADA. */
    public const CODE_RESULTAT_NET = 'XI';

    /**
     * Le resultat des activites ordinaires et le resultat HAO : leur somme est
     * le resultat AVANT impot, seul agregat que le maitre affiche en clair
     * (`m10-resultat.html` l.103 : « RÉSULTAT AVANT IMPÔT SUR LES SOCIÉTÉS »).
     *
     * @var list<string>
     */
    public const COMPOSANTS_RESULTAT_AVANT_IMPOT = ['XG', 'XH'];

    /**
     * La rubrique d'impot sur le resultat — classe 89, jamais un taux (PA-19).
     */
    public const CODE_IMPOT = 'RS';

    /**
     * La cascade, dans l'ordre d'affichage du maitre.
     *
     * Chaque entree porte soit `prefixes` (rubrique alimentee par des comptes),
     * soit `composants` (solde intermediaire, somme d'autres codes) — jamais les
     * deux, et jamais aucun des deux.
     *
     * @var list<array{code: string, libelle: string, sens: string, prefixes?: list<string>, composants?: list<string>}>
     */
    public const CASCADE = [
        ['code' => 'TA', 'libelle' => 'Ventes de marchandises', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['701']],
        ['code' => 'RA', 'libelle' => 'Achats de marchandises', 'sens' => self::SENS_CHARGE, 'prefixes' => ['601']],
        ['code' => 'RB', 'libelle' => 'Variation de stocks de marchandises', 'sens' => self::SENS_CHARGE, 'prefixes' => ['6031']],
        ['code' => 'XA', 'libelle' => 'MARGE COMMERCIALE', 'sens' => self::SENS_SOLDE, 'composants' => ['TA', 'RA', 'RB']],

        ['code' => 'TB', 'libelle' => 'Ventes de produits fabriqués', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['702']],
        ['code' => 'TC', 'libelle' => 'Travaux et services vendus', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['705', '706']],
        ['code' => 'TD', 'libelle' => 'Produits accessoires', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['707']],
        ['code' => 'XB', 'libelle' => "CHIFFRE D'AFFAIRES", 'sens' => self::SENS_SOLDE, 'composants' => ['TA', 'TB', 'TC', 'TD']],

        ['code' => 'TE', 'libelle' => 'Production stockée (ou déstockage)', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['73']],
        ['code' => 'TF', 'libelle' => 'Production immobilisée', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['72']],
        ['code' => 'TG', 'libelle' => "Subventions d'exploitation", 'sens' => self::SENS_PRODUIT, 'prefixes' => ['71']],
        ['code' => 'TH', 'libelle' => 'Autres produits', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['75']],
        ['code' => 'TI', 'libelle' => "Transferts de charges d'exploitation", 'sens' => self::SENS_PRODUIT, 'prefixes' => ['781']],
        ['code' => 'RC', 'libelle' => 'Achats de matières premières et fournitures liées', 'sens' => self::SENS_CHARGE, 'prefixes' => ['602']],
        ['code' => 'RD', 'libelle' => 'Variation de stocks de matières premières', 'sens' => self::SENS_CHARGE, 'prefixes' => ['6032']],
        ['code' => 'RE', 'libelle' => 'Autres achats', 'sens' => self::SENS_CHARGE, 'prefixes' => ['604', '605', '608']],
        ['code' => 'RF', 'libelle' => "Variation de stocks d'autres approvisionnements", 'sens' => self::SENS_CHARGE, 'prefixes' => ['6033']],
        ['code' => 'RG', 'libelle' => 'Transports', 'sens' => self::SENS_CHARGE, 'prefixes' => ['61']],
        ['code' => 'RH', 'libelle' => 'Services extérieurs', 'sens' => self::SENS_CHARGE, 'prefixes' => ['62', '63']],
        ['code' => 'RI', 'libelle' => 'Impôts et taxes', 'sens' => self::SENS_CHARGE, 'prefixes' => ['64']],
        ['code' => 'RJ', 'libelle' => 'Autres charges', 'sens' => self::SENS_CHARGE, 'prefixes' => ['65']],
        ['code' => 'XC', 'libelle' => 'VALEUR AJOUTÉE', 'sens' => self::SENS_SOLDE, 'composants' => [
            'XB', 'TE', 'TF', 'TG', 'TH', 'TI',
            'RA', 'RB', 'RC', 'RD', 'RE', 'RF', 'RG', 'RH', 'RI', 'RJ',
        ]],

        ['code' => 'RK', 'libelle' => 'Charges de personnel', 'sens' => self::SENS_CHARGE, 'prefixes' => ['66']],
        ['code' => 'XD', 'libelle' => "EXCÉDENT BRUT D'EXPLOITATION", 'sens' => self::SENS_SOLDE, 'composants' => ['XC', 'RK']],

        ['code' => 'TJ', 'libelle' => "Reprises d'amortissements, provisions et dépréciations", 'sens' => self::SENS_PRODUIT, 'prefixes' => ['791', '798']],
        ['code' => 'RL', 'libelle' => 'Dotations aux amortissements, provisions et dépréciations', 'sens' => self::SENS_CHARGE, 'prefixes' => ['681', '691']],
        ['code' => 'XE', 'libelle' => "RÉSULTAT D'EXPLOITATION", 'sens' => self::SENS_SOLDE, 'composants' => ['XD', 'TJ', 'RL']],

        ['code' => 'TK', 'libelle' => 'Revenus financiers et assimilés', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['77']],
        ['code' => 'TM', 'libelle' => 'Transferts de charges financières', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['787']],
        ['code' => 'RM', 'libelle' => 'Frais financiers et charges assimilées', 'sens' => self::SENS_CHARGE, 'prefixes' => ['67']],
        ['code' => 'RN', 'libelle' => 'Dotations aux provisions et dépréciations financières', 'sens' => self::SENS_CHARGE, 'prefixes' => ['697']],
        ['code' => 'XF', 'libelle' => 'RÉSULTAT FINANCIER', 'sens' => self::SENS_SOLDE, 'composants' => ['TK', 'TM', 'RM', 'RN']],

        ['code' => 'XG', 'libelle' => 'RÉSULTAT DES ACTIVITÉS ORDINAIRES', 'sens' => self::SENS_SOLDE, 'composants' => ['XE', 'XF']],

        ['code' => 'TN', 'libelle' => "Produits des cessions d'immobilisations", 'sens' => self::SENS_PRODUIT, 'prefixes' => ['82']],
        ['code' => 'TO', 'libelle' => 'Autres produits HAO', 'sens' => self::SENS_PRODUIT, 'prefixes' => ['84', '86', '88']],
        ['code' => 'RO', 'libelle' => "Valeurs comptables des cessions d'immobilisations", 'sens' => self::SENS_CHARGE, 'prefixes' => ['81']],
        ['code' => 'RP', 'libelle' => 'Autres charges HAO', 'sens' => self::SENS_CHARGE, 'prefixes' => ['83', '85']],
        ['code' => 'XH', 'libelle' => 'RÉSULTAT HORS ACTIVITÉS ORDINAIRES', 'sens' => self::SENS_SOLDE, 'composants' => ['TN', 'TO', 'RO', 'RP']],

        ['code' => 'RQ', 'libelle' => 'Participation des travailleurs', 'sens' => self::SENS_CHARGE, 'prefixes' => ['87']],
        // PA-19 — alimentee par la classe 89 REELLEMENT comptabilisee, jamais
        // par un taux. Voir l'entete de cette classe.
        ['code' => 'RS', 'libelle' => 'Impôts sur le résultat', 'sens' => self::SENS_CHARGE, 'prefixes' => ['89']],
        ['code' => 'XI', 'libelle' => 'RÉSULTAT NET', 'sens' => self::SENS_SOLDE, 'composants' => ['XG', 'XH', 'RQ', 'RS']],
    ];

    /**
     * TOUS les prefixes captes par la cascade.
     *
     * Sert la garde `comptesHorsRubrique` du `BilanService` : un compte
     * mouvemente qui n'entre ni au Bilan ni au Compte de Resultat est un compte
     * dont le solde n'apparait NULLE PART.
     *
     * @return list<string>
     */
    public static function tousLesPrefixes(): array
    {
        $prefixes = [];

        foreach (self::CASCADE as $rubrique) {
            foreach ($rubrique['prefixes'] ?? [] as $prefixe) {
                $prefixes[] = $prefixe;
            }
        }

        return $prefixes;
    }
}
