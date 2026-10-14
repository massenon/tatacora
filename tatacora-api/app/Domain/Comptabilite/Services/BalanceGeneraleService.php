<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\ReadModels\BalanceGenerale;
use App\Domain\Comptabilite\ReadModels\LigneBalance;
use Illuminate\Support\Facades\DB;

/**
 * Balance Generale — `MODULE_COMPTABILITE_COMPLET.md` §4, `m10-balance.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## Une seule requete agregee, et c'est un cas ou c'est LEGITIME
 *
 * PA-121 interdit de calculer un total par un agregat parallele a celui du
 * detail — les deux finissent par diverger. Ici il n'y a pas de detail
 * parallele : les totaux de pied de tableau sont sommes **a partir des lignes
 * rendues**, jamais par une seconde requete. Le pied fait donc mecaniquement la
 * somme de ce qui est affiche, comme le maitre (l.70-77).
 *
 * ## Un compte non mouvemente n'a pas de ligne
 *
 * Le `GROUP BY` porte sur les ecritures, pas sur le plan comptable : un compte
 * du referentiel jamais mouvemente n'apparait pas. C'est le sous-titre du
 * maitre (l.13 : « Soldes de tous les comptes **mouvementes** »), et la meme
 * regle qu'au Grand Livre (§3).
 */
class BalanceGeneraleService
{
    private const PRECISION = 2;

    public function __construct(
        private readonly PorteeEcrituresService $portee,
    ) {
    }

    /**
     * @param  list<string>  $statuts
     */
    public function genererPourExercice(
        string $exerciceId,
        array $statuts,
        string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES,
    ): BalanceGenerale {
        // L'agregation se fait en base : sommer en PHP exigerait de charger
        // toutes les ecritures de l'exercice, quand le resultat tient en une
        // ligne par compte mouvemente. `SUM()` sur `DECIMAL(15,2)` rend une
        // chaine exacte via PDO — jamais un float.
        $agregats = $this->portee->requete($exerciceId, $statuts)
            ->join('plan_comptable', 'ecritures_comptables.compte_id', '=', 'plan_comptable.id')
            ->groupBy(
                'plan_comptable.id',
                'plan_comptable.numero_compte',
                'plan_comptable.libelle',
                'plan_comptable.classe',
            )
            ->orderBy('plan_comptable.numero_compte')
            ->get([
                'plan_comptable.id AS compte_id',
                'plan_comptable.numero_compte',
                'plan_comptable.libelle',
                'plan_comptable.classe',
                DB::raw('SUM(ecritures_comptables.debit) AS total_debit'),
                DB::raw('SUM(ecritures_comptables.credit) AS total_credit'),
            ]);

        $lignes = [];
        $totalDebit = '0.00';
        $totalCredit = '0.00';
        $totalSoldeDebiteur = '0.00';
        $totalSoldeCrediteur = '0.00';

        foreach ($agregats as $agregat) {
            $debit = bcadd((string) $agregat->getAttribute('total_debit'), '0', self::PRECISION);
            $credit = bcadd((string) $agregat->getAttribute('total_credit'), '0', self::PRECISION);
            $solde = bcsub($debit, $credit, self::PRECISION);

            // Exclusifs : un solde nul porte 0.00 aux deux colonnes. C'est un
            // zero CALCULE — le compte a bien ete mouvemente, ses mouvements se
            // compensent — et pas une absence de donnee (Article 7).
            $soldeDebiteur = bccomp($solde, '0.00', self::PRECISION) > 0 ? $solde : '0.00';
            $soldeCrediteur = bccomp($solde, '0.00', self::PRECISION) < 0
                ? bcsub('0.00', $solde, self::PRECISION)
                : '0.00';

            $lignes[] = new LigneBalance(
                compteId: (string) $agregat->getAttribute('compte_id'),
                numeroCompte: (string) $agregat->getAttribute('numero_compte'),
                libelle: (string) $agregat->getAttribute('libelle'),
                classe: (string) $agregat->getAttribute('classe'),
                totalDebit: $debit,
                totalCredit: $credit,
                soldeDebiteur: $soldeDebiteur,
                soldeCrediteur: $soldeCrediteur,
            );

            $totalDebit = bcadd($totalDebit, $debit, self::PRECISION);
            $totalCredit = bcadd($totalCredit, $credit, self::PRECISION);
            $totalSoldeDebiteur = bcadd($totalSoldeDebiteur, $soldeDebiteur, self::PRECISION);
            $totalSoldeCrediteur = bcadd($totalSoldeCrediteur, $soldeCrediteur, self::PRECISION);
        }

        // Les DEUX egalites, en bccomp (§4). Ne verifier que la premiere
        // laisserait passer une erreur de repartition des soldes ; ne verifier
        // que la seconde laisserait passer une erreur de cumul.
        $equilibree = bccomp($totalDebit, $totalCredit, self::PRECISION) === 0
            && bccomp($totalSoldeDebiteur, $totalSoldeCrediteur, self::PRECISION) === 0;

        return new BalanceGenerale(
            exerciceId: $exerciceId,
            lignes: $lignes,
            totalDebit: $totalDebit,
            totalCredit: $totalCredit,
            totalSoldeDebiteur: $totalSoldeDebiteur,
            totalSoldeCrediteur: $totalSoldeCrediteur,
            equilibree: $equilibree,
            statuts: $this->portee->statuts($exerciceId, $statuts),
            filtresAppliques: ['statut' => $filtreStatut],
        );
    }
}
