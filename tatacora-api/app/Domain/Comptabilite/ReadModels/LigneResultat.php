<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Une ligne du Compte de Resultat — rubrique alimentee par des comptes, ou
 * solde intermediaire de gestion.
 *
 * Les deux se rendent dans le meme tableau chez le maitre
 * (`m10-syscohada-etats.js` l.86-101) : une rubrique porte son montant dans la
 * colonne « Charges » ou « Produits / Solde » selon `sens`, un solde porte le
 * sien dans la colonne de droite avec un fond distinct.
 *
 * `montant` est SIGNE selon la convention unique de la cascade : positif pour
 * un produit, negatif pour une charge (voir `SoldesIntermediairesGestion`). Le
 * maitre affiche sa valeur absolue ; la valeur signee descend ici pour que le
 * client n'ait pas a redecider du signe — deux regles de signe, une au serveur
 * et une a l'ecran, finiraient par diverger.
 *
 * `prefixes` est rendu parce que le maitre l'affiche en gris sous le libelle
 * (`m10-syscohada-etats.js` l.97) : il dit QUELS comptes alimentent la ligne,
 * ce qui est la seule facon de comprendre un montant inattendu sans ouvrir le
 * grand livre. Il est vide sur un solde intermediaire, qui n'agrege aucun
 * compte directement.
 */
final readonly class LigneResultat
{
    /**
     * @param  list<string>  $prefixes
     * @param  list<string>  $composants
     */
    public function __construct(
        public string $code,
        public string $libelle,
        public string $sens,
        public string $montant,
        public bool $estSolde,
        public array $prefixes = [],
        public array $composants = [],
    ) {
    }
}
