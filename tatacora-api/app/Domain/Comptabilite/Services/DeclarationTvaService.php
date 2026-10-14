<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
use RuntimeException;

/**
 * Déclaration de TVA — agrégation des comptes de TVA sur une période (M10).
 *
 * ## Principe
 *
 * | Compte | Libellé | Sens du solde | Signification |
 * |---|---|---|---|
 * | **4431** | TVA collectée | Créditeur | TVA facturée aux clients, due à l'État |
 * | **4452** | TVA déductible | Débiteur | TVA payée aux fournisseurs, récupérable |
 *
 * `TVA due = collectée − déductible`. Si le résultat est négatif, il ne s'agit
 * pas d'une dette négative mais d'un **crédit de TVA reportable** sur la
 * période suivante — distinction essentielle : traiter un crédit comme une
 * dette de signe opposé ferait déclarer un montant à payer inexistant.
 *
 * ## Ce que ce service ne fait pas
 *
 * Il ne génère aucune écriture et ne télédéclare rien : il **lit** la
 * comptabilité et produit un état. La génération des écritures de TVA relève
 * des listeners `GenererEcritureDepuisFacture` / `DepuisAchat` (sprint M10
 * complet), et la télédéclaration DGI n'est pas au périmètre du CdCF.
 *
 * ## Statut documentaire
 *
 * **Aucun des éléments ci-dessous n'est spécifié dans la collection
 * documentaire** — ni les comptes 4431/4452, ni le taux, ni le principe de la
 * déclaration. Le module est construit sur instruction du Consultant Technique
 * du 15/08/2026. Il doit être rattaché à une EF de `05_MODULE_SPECIFICATIONS.md`
 * §M10 et validé par l'Architecte et le Product Owner avant mise en production.
 */
class DeclarationTvaService
{
    /**
     * Numéros de compte SYSCOHADA. Constantes et non paramètres : ce sont des
     * numéros normalisés du plan comptable révisé, pas des réglages locaux.
     * Le taux, lui, est bien un paramètre (il change par décision de l'État).
     */
    public const COMPTE_TVA_COLLECTEE = ComptesSyscohada::TVA_FACTUREE_BIENS;

    public const COMPTE_TVA_COLLECTEE_PRESTATIONS = ComptesSyscohada::TVA_FACTUREE_PRESTATIONS;

    public const COMPTE_TVA_DEDUCTIBLE = ComptesSyscohada::TVA_RECUPERABLE_ACHATS;

    private const PRECISION = 2;

    /**
     * Déclaration sur une période.
     *
     * @return array{
     *     periode: array{debut: string, fin: string},
     *     tva_collectee: string,
     *     tva_deductible: string,
     *     solde: string,
     *     sens: 'a_payer'|'credit_reportable'|'neant',
     *     montant_a_payer: string,
     *     credit_reportable: string
     * }
     */
    public function pourPeriode(string $dateDebut, string $dateFin, bool $ecrituresValideesUniquement = true): array
    {
        // TVA collectée = 4431 (biens, boissons revendues) + 4432 (prestations).
        $collectee = bcadd(
            $this->soldeCrediteur(self::COMPTE_TVA_COLLECTEE, $dateDebut, $dateFin, $ecrituresValideesUniquement),
            $this->soldeCrediteur(self::COMPTE_TVA_COLLECTEE_PRESTATIONS, $dateDebut, $dateFin, $ecrituresValideesUniquement),
            self::PRECISION,
        );
        $deductible = $this->soldeDebiteur(self::COMPTE_TVA_DEDUCTIBLE, $dateDebut, $dateFin, $ecrituresValideesUniquement);

        $solde = bcsub($collectee, $deductible, self::PRECISION);
        $comparaison = bccomp($solde, '0.00', self::PRECISION);

        return [
            'periode' => ['debut' => $dateDebut, 'fin' => $dateFin],
            'tva_collectee' => $collectee,
            'tva_deductible' => $deductible,
            'solde' => $solde,
            'sens' => match (true) {
                $comparaison > 0 => 'a_payer',
                $comparaison < 0 => 'credit_reportable',
                default => 'neant',
            },
            'montant_a_payer' => $comparaison > 0 ? $solde : '0.00',
            // Exprimé en positif : un crédit de 50 000 F se lit « 50 000 F
            // reportables », jamais « −50 000 F à payer ».
            'credit_reportable' => $comparaison < 0 ? bcmul($solde, '-1', self::PRECISION) : '0.00',
        ];
    }

    /**
     * Solde créditeur (crédits − débits) — sens naturel d'un compte de TVA
     * collectée.
     */
    public function soldeCrediteur(string $numeroCompte, string $dateDebut, string $dateFin, bool $valideesUniquement = true): string
    {
        $totaux = $this->totaux($numeroCompte, $dateDebut, $dateFin, $valideesUniquement);

        return bcsub($totaux['credit'], $totaux['debit'], self::PRECISION);
    }

    /**
     * Solde débiteur (débits − crédits) — sens naturel d'un compte de TVA
     * déductible.
     */
    public function soldeDebiteur(string $numeroCompte, string $dateDebut, string $dateFin, bool $valideesUniquement = true): string
    {
        $totaux = $this->totaux($numeroCompte, $dateDebut, $dateFin, $valideesUniquement);

        return bcsub($totaux['debit'], $totaux['credit'], self::PRECISION);
    }

    /**
     * @return array{debit: string, credit: string}
     */
    private function totaux(string $numeroCompte, string $dateDebut, string $dateFin, bool $valideesUniquement): array
    {
        $compte = CompteComptable::where('numero_compte', $numeroCompte)->first();

        if ($compte === null) {
            // Refus explicite plutôt qu'un zéro silencieux : une déclaration
            // affichant 0 F de TVA collectée parce que le compte 4431 n'existe
            // pas au plan comptable serait indétectable et catastrophique.
            throw new RuntimeException(__('comptabilite.compte_absent', ['compte' => $numeroCompte]));
        }

        $ecritures = EcritureComptable::query()
            ->where('compte_id', $compte->id)
            ->whereBetween('date_ecriture', [$dateDebut, $dateFin])
            // Une écriture en brouillon n'est pas opposable : la déclarer
            // reviendrait à déclarer une opération non validée.
            ->when($valideesUniquement, fn ($q) => $q->where('statut', 'validee'))
            ->get(['debit', 'credit']);

        $debit = '0.00';
        $credit = '0.00';

        foreach ($ecritures as $ecriture) {
            $debit = bcadd($debit, (string) $ecriture->debit, self::PRECISION);
            $credit = bcadd($credit, (string) $ecriture->credit, self::PRECISION);
        }

        return ['debit' => $debit, 'credit' => $credit];
    }
}
