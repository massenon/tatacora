<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

use App\Domain\Comptabilite\Models\EcritureComptable;

/**
 * Une ligne de Grand Livre : l'ecriture, plus le solde progressif a cette
 * ligne — `m10-grand-livre.html`, colonne « Solde progressif ».
 *
 * `soldeProgressif` est **signe** : positif = debiteur, negatif = crediteur,
 * comme `MODULE_COMPTABILITE_COMPLET.md` §3 l'ecrit. Le maitre affiche la
 * valeur absolue suivie de `(D)` ou `(C)` (l.78) ; c'est un choix de rendu, le
 * signe reste porte par la donnee.
 */
final readonly class LigneGrandLivre
{
    public function __construct(
        public EcritureComptable $ecriture,
        public string $soldeProgressif,
    ) {
    }
}
