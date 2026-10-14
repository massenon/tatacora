<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\ReadModels\Analytique;
use App\Domain\Comptabilite\ReadModels\LigneAnalytique;
use Illuminate\Support\Facades\DB;

/**
 * Comptabilite analytique par centre de cout — `m10-analytique.html`.
 *
 * @see EF-M10-03 Comptabilite analytique par centre de cout/activite
 * @see RG-12 Centre de cout obligatoire sur toute ecriture
 *
 * ## La ventilation lit la CLASSE, pas la `nature`
 *
 * `plan_comptable.nature` est nullable (`PlanComptableService` compte d'ailleurs
 * les comptes qui en sont depourvus). S'en servir ferait disparaitre de
 * l'analytique tout compte dont la nature n'a pas ete saisie — silencieusement,
 * et en minorant une marge. `classe` est NOT NULL et porte la meme information
 * pour ce calcul : classe 7 = produit, classe 6 = charge.
 *
 * La classe 8 (HAO) se repartit selon le SENS REEL du solde, comme chez le
 * maitre (`comptabilite-engine.js` l.676-689) : une cession d'immobilisation
 * (82, crediteur) est un produit, sa valeur comptable (81, debiteur) une
 * charge. Les classer en bloc mettrait un produit de cession dans les charges.
 *
 * ## Un centre sans mouvement n'a pas de ligne
 *
 * Meme regle qu'a la Balance et au Grand Livre : le `GROUP BY` porte sur les
 * ecritures. Un centre du referentiel jamais mouvemente n'apparait pas —
 * afficher « Tourisme : 0 F de marge » laisserait croire a une activite
 * deficitaire quand il n'y a simplement eu aucune operation.
 */
class AnalytiqueService
{
    private const PRECISION = 2;

    private const ZERO = '0.00';

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
    ): Analytique {
        // Agregation en base par (centre, classe) : la ventilation n'a besoin
        // de rien d'autre, et charger les ecritures pour sommer en PHP serait
        // proportionnel au volume de l'exercice quand le resultat tient en
        // quelques dizaines de lignes.
        $agregats = $this->portee->requete($exerciceId, $statuts)
            ->join('plan_comptable', 'ecritures_comptables.compte_id', '=', 'plan_comptable.id')
            ->join('centres_cout', 'ecritures_comptables.centre_id', '=', 'centres_cout.id')
            ->groupBy('centres_cout.id', 'centres_cout.libelle', 'centres_cout.type', 'plan_comptable.classe')
            ->orderBy('centres_cout.libelle')
            ->get([
                'centres_cout.id AS centre_id',
                'centres_cout.libelle AS centre_libelle',
                'centres_cout.type AS centre_type',
                'plan_comptable.classe AS classe',
                DB::raw('SUM(ecritures_comptables.debit) AS total_debit'),
                DB::raw('SUM(ecritures_comptables.credit) AS total_credit'),
                DB::raw('COUNT(*) AS nombre_lignes'),
            ]);

        /** @var array<string, array{libelle: string, type: string|null, produits: string, charges: string, lignes: int}> $parCentre */
        $parCentre = [];

        foreach ($agregats as $agregat) {
            $centreId = (string) $agregat->getAttribute('centre_id');
            $classe = (string) $agregat->getAttribute('classe');
            $debit = bcadd((string) $agregat->getAttribute('total_debit'), '0', self::PRECISION);
            $credit = bcadd((string) $agregat->getAttribute('total_credit'), '0', self::PRECISION);

            $parCentre[$centreId] ??= [
                'libelle' => (string) $agregat->getAttribute('centre_libelle'),
                'type' => $agregat->getAttribute('centre_type') === null
                    ? null
                    : (string) $agregat->getAttribute('centre_type'),
                'produits' => self::ZERO,
                'charges' => self::ZERO,
                'lignes' => 0,
            ];

            $parCentre[$centreId]['lignes'] += (int) $agregat->getAttribute('nombre_lignes');

            // `net = debit - credit`. Un produit est crediteur (net negatif),
            // une charge debitrice (net positif).
            $net = bcsub($debit, $credit, self::PRECISION);
            $estProduit = $classe === '7'
                || ($classe === '8' && bccomp($net, self::ZERO, self::PRECISION) < 0);

            if ($estProduit) {
                $parCentre[$centreId]['produits'] = bcadd(
                    $parCentre[$centreId]['produits'],
                    bcsub(self::ZERO, $net, self::PRECISION),
                    self::PRECISION,
                );

                continue;
            }

            if ($classe === '6' || $classe === '8') {
                $parCentre[$centreId]['charges'] = bcadd(
                    $parCentre[$centreId]['charges'],
                    $net,
                    self::PRECISION,
                );
            }

            // Les classes 1 a 5 sont des comptes de BILAN : elles portent bien
            // un centre (RG-12 l'impose a toute ecriture) mais ne sont ni un
            // produit ni une charge. Les compter fausserait chaque marge — un
            // encaissement en banque n'est pas un produit, c'est la
            // contrepartie d'un produit deja compte.
        }

        $centres = [];
        $totalProduits = self::ZERO;
        $totalCharges = self::ZERO;

        foreach ($parCentre as $centreId => $donnees) {
            $resultat = bcsub($donnees['produits'], $donnees['charges'], self::PRECISION);

            $centres[] = new LigneAnalytique(
                centreId: $centreId,
                libelle: $donnees['libelle'],
                type: $donnees['type'],
                produits: $donnees['produits'],
                charges: $donnees['charges'],
                resultat: $resultat,
                tauxMarge: $this->tauxMarge($resultat, $donnees['produits']),
                nombreLignes: $donnees['lignes'],
            );

            $totalProduits = bcadd($totalProduits, $donnees['produits'], self::PRECISION);
            $totalCharges = bcadd($totalCharges, $donnees['charges'], self::PRECISION);
        }

        // Tri par marge decroissante, comme le maitre (`comptabilite-engine.js`
        // l.705). `bccomp` et non `<=>` : comparer deux chaines de montants avec
        // l'operateur natif ferait un tri lexicographique, ou « 9.00 » passerait
        // avant « 80000.00 ».
        usort(
            $centres,
            static fn (LigneAnalytique $a, LigneAnalytique $b): int => bccomp($b->resultat, $a->resultat, self::PRECISION),
        );

        return new Analytique(
            exerciceId: $exerciceId,
            centres: $centres,
            totalProduits: $totalProduits,
            totalCharges: $totalCharges,
            totalResultat: bcsub($totalProduits, $totalCharges, self::PRECISION),
            repartitionStructureEffectuee: false,
            motifNatureDesMarges: Analytique::MOTIF_SANS_REPARTITION,
            ventilationGarantieParSchema: true,
            statuts: $this->portee->statuts($exerciceId, $statuts),
            filtresAppliques: ['statut' => $filtreStatut],
        );
    }

    /**
     * Le taux de marge en POURCENTAGE, a une decimale — ou `null`.
     *
     * `null` quand le centre n'a aucun produit : ce n'est pas un taux de zero,
     * c'est une absence de taux (Article 7). C'est aussi ce qui rend la
     * division par zero impossible, plutot que de la rattraper apres coup.
     */
    private function tauxMarge(string $resultat, string $produits): ?string
    {
        if (bccomp($produits, self::ZERO, self::PRECISION) === 0) {
            return null;
        }

        // Une decimale, comme le maitre (`Math.round(x * 1000) / 10`). Le calcul
        // reste en `bc*` de bout en bout : passer par un `float` sur des
        // montants a 15 chiffres significatifs perdrait de la precision avant
        // meme l'arrondi.
        return bcdiv(bcmul($resultat, '100', 3), $produits, 1);
    }
}
