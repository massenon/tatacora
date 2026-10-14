<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Une ligne de Balance Generale — quatre colonnes de montants, comme
 * `m10-balance.html` l.21-23 et `MODULE_COMPTABILITE_COMPLET.md` §4.
 *
 * `soldeDebiteur` et `soldeCrediteur` sont EXCLUSIFS : un compte dont le solde
 * est nul porte `0.00` aux deux. C'est bien un zero calcule, pas une absence —
 * le compte a ete mouvemente, ses mouvements se compensent.
 */
final readonly class LigneBalance
{
    public function __construct(
        public string $compteId,
        public string $numeroCompte,
        public string $libelle,
        public string $classe,
        public string $totalDebit,
        public string $totalCredit,
        public string $soldeDebiteur,
        public string $soldeCrediteur,
    ) {
    }
}
