<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Support;

/**
 * Les prefixes de comptes que le TAFIRE lit EN PLUS de ceux de
 * {@see RubriquesSyscohada} (10/11/2026, TAFIRE redefini sur le resultat de N
 * seul). Registre a part pour ne pas toucher a celui du Bilan.
 *
 * Les capitaux propres sont lus PAR COMPTES de la classe 1, jamais par une
 * liste de pieces : n'importe quelle piece d'affectation du resultat (D 131 /
 * C 121, 111, 118, 465 ; perte D 129 / C 139) y est donc comprise, quels que
 * soient les comptes que la correspondance parametrable lui donne, pourvu
 * qu'ils restent dans la classe 1 (dividendes a payer : 465).
 */
final class RubriquesTafire
{
    /** Reprises d'amortissements : produit non encaisse, deduit de la CAFG. @var list<string> */
    public const REPRISES = ['781'];

    /** Valeur comptable des immobilisations cedees (charge non decaissee). @var list<string> */
    public const VALEUR_COMPTABLE_CESSIONS = ['81'];

    /** Produits des cessions d'immobilisations (encaisses : flux d'investissement). @var list<string> */
    public const PRODUITS_CESSIONS = ['82'];

    /** Capital, primes (10) et subventions d'investissement (14) : apports de l'exercice. @var list<string> */
    public const APPORTS_CAPITAL = ['10', '14'];

    /** Reserves (11), report a nouveau (12), resultat reporte (13), provisions reglementees (15). @var list<string> */
    public const AUTRES_CAPITAUX_PROPRES = ['11', '12', '13', '15'];

    /** Emprunts et dettes financieres (16 a 19). @var list<string> */
    public const DETTES_FINANCIERES = ['16', '17', '18', '19'];

    /** Associes, dividendes a payer. @var list<string> */
    public const DIVIDENDES_A_PAYER = ['465'];
}
