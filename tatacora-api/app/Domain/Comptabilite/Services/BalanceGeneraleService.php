<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\ReadModels\BalanceGenerale;
use App\Domain\Comptabilite\ReadModels\LigneBalance;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
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
 *
 * ## Les À-NOUVEAUX PROVISOIRES de N+1 (lot 2, 20/10/2026)
 *
 * Tant que l'exercice PRÉCÉDENT n'est pas clôturé (ouvert, en clôture, ou
 * rouvert — qui repasse en clôture), ses soldes de
 * bilan (classes 1 à 5) et son résultat (en 131 ou 139) s'ajoutent à cette
 * balance — calculés à chaque lecture, donc « dynamiques » : une écriture
 * d'inventaire passée en N se voit aussitôt en N+1. Ils ne s'écrivent pas
 * (une écriture ne se supprime jamais, RG-11) ; la clôture de N les fige en
 * une pièce d'à-nouveaux (journal AN), et ils cessent alors d'être calculés.
 * Ils ne portent que sur les écritures VALIDÉES : un brouillon n'est pas
 * opposable.
 *
 * ## Avant ou après la clôture
 *
 * Par défaut, la balance EXCLUT le journal de clôture (`CL`) : les états qui
 * en découlent (compte de résultat, bilan, liste de contrôle) sont ceux de
 * l'exercice tel qu'il s'est déroulé, clôturé ou non. `apresCloture: true`
 * l'inclut — classes 6 à 8 soldées, résultat en 131/139 — pour reporter les
 * à-nouveaux et contrôler la clôture.
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
        bool $apresCloture = false,
    ): BalanceGenerale {
        $journalCloture = $apresCloture
            ? null
            : JournalComptable::query()->where('code', 'CL')->value('id');

        // L'agregation se fait en base : sommer en PHP exigerait de charger
        // toutes les ecritures de l'exercice, quand le resultat tient en une
        // ligne par compte mouvemente. `SUM()` sur `DECIMAL(15,2)` rend une
        // chaine exacte via PDO — jamais un float.
        $agregats = $this->portee->requete($exerciceId, $statuts)
            ->when($journalCloture !== null, fn ($q) => $q->where('ecritures_comptables.journal_id', '!=', $journalCloture))
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

        // Compte par compte : les mouvements de l'exercice, puis les
        // à-nouveaux provisoires de l'exercice précédent.
        /** @var array<string, array{compte_id: string, numero: string, libelle: string, classe: string, debit: string, credit: string}> $parCompte */
        $parCompte = [];

        foreach ($agregats as $agregat) {
            $numero = (string) $agregat->getAttribute('numero_compte');
            $parCompte[$numero] = [
                'compte_id' => (string) $agregat->getAttribute('compte_id'),
                'numero' => $numero,
                'libelle' => (string) $agregat->getAttribute('libelle'),
                'classe' => (string) $agregat->getAttribute('classe'),
                'debit' => bcadd((string) $agregat->getAttribute('total_debit'), '0', self::PRECISION),
                'credit' => bcadd((string) $agregat->getAttribute('total_credit'), '0', self::PRECISION),
            ];
        }

        $provisoiresDe = null;

        if (in_array('validee', $statuts, true)) {
            $provisoiresDe = $this->ajouterANouveauxProvisoires($exerciceId, $parCompte);
        }

        ksort($parCompte, SORT_STRING);

        $lignes = [];
        $totalDebit = '0.00';
        $totalCredit = '0.00';
        $totalSoldeDebiteur = '0.00';
        $totalSoldeCrediteur = '0.00';

        foreach ($parCompte as $compte) {
            $debit = $compte['debit'];
            $credit = $compte['credit'];
            $solde = bcsub($debit, $credit, self::PRECISION);

            // Exclusifs : un solde nul porte 0.00 aux deux colonnes. C'est un
            // zero CALCULE — le compte a bien ete mouvemente, ses mouvements se
            // compensent — et pas une absence de donnee (Article 7).
            $soldeDebiteur = bccomp($solde, '0.00', self::PRECISION) > 0 ? $solde : '0.00';
            $soldeCrediteur = bccomp($solde, '0.00', self::PRECISION) < 0
                ? bcsub('0.00', $solde, self::PRECISION)
                : '0.00';

            $lignes[] = new LigneBalance(
                compteId: $compte['compte_id'],
                numeroCompte: $compte['numero'],
                libelle: $compte['libelle'],
                classe: $compte['classe'],
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
            aNouveauxProvisoiresDe: $provisoiresDe,
        );
    }

    /**
     * Ajoute à [parCompte] les à-nouveaux provisoires de l'exercice précédent
     * — voir l'entête. Rend l'année de cet exercice, ou `null` s'il n'y en a
     * pas à ajouter (aucun exercice précédent, ou exercice précédent clôturé).
     *
     * @param  array<string, array{compte_id: string, numero: string, libelle: string, classe: string, debit: string, credit: string}>  $parCompte
     */
    private function ajouterANouveauxProvisoires(string $exerciceId, array &$parCompte): ?int
    {
        $exercice = ExerciceComptable::query()->find($exerciceId);
        $precedent = $exercice === null
            ? null
            : ExerciceComptable::query()->where('annee', $exercice->annee - 1)->first();

        // N-1 CLÔTURÉ : ses à-nouveaux sont écrits au journal AN (ou, pour une
        // clôture d'avant le lot 2, n'existent pas) — rien de provisoire.
        // Rouvert, il repasse en clôture : ses AN sont contre-passés et les
        // provisoires reviennent.
        if ($precedent === null || $precedent->statut === 'cloture') {
            return null;
        }

        // Récursif : N-1 porte lui-même les à-nouveaux de N-2 s'il y a lieu.
        $soldes = $this->genererPourExercice($precedent->id, ['validee']);
        $resultat = '0.00';
        $ajouts = [];

        foreach ($soldes->lignes as $ligne) {
            $net = bcsub($ligne->totalDebit, $ligne->totalCredit, self::PRECISION);

            if (in_array($ligne->classe, ['6', '7', '8'], true)) {
                // Le résultat : produits (créditeurs) − charges (débitrices).
                $resultat = bcsub($resultat, $net, self::PRECISION);

                continue;
            }

            $ajouts[] = [$ligne->compteId, $ligne->numeroCompte, $ligne->libelle, $ligne->classe, $net];
        }

        $signe = bccomp($resultat, '0.00', self::PRECISION);

        if ($signe !== 0) {
            $numero = $signe > 0 ? ComptesSyscohada::RESULTAT_BENEFICE : ComptesSyscohada::RESULTAT_PERTE;
            $compte = CompteComptable::query()->where('numero_compte', $numero)->first();

            if ($compte !== null) {
                $ajouts[] = [(string) $compte->id, $numero, (string) $compte->libelle, (string) $compte->classe, bcsub('0.00', $resultat, self::PRECISION)];
            }
        }

        foreach ($ajouts as [$compteId, $numero, $libelle, $classe, $net]) {
            if (bccomp($net, '0.00', self::PRECISION) === 0) {
                continue;
            }

            $parCompte[$numero] ??= [
                'compte_id' => $compteId, 'numero' => $numero, 'libelle' => $libelle, 'classe' => $classe,
                'debit' => '0.00', 'credit' => '0.00',
            ];

            if (bccomp($net, '0.00', self::PRECISION) > 0) {
                $parCompte[$numero]['debit'] = bcadd($parCompte[$numero]['debit'], $net, self::PRECISION);
            } else {
                $parCompte[$numero]['credit'] = bcadd($parCompte[$numero]['credit'], bcsub('0.00', $net, self::PRECISION), self::PRECISION);
            }
        }

        return $precedent->annee;
    }
}
