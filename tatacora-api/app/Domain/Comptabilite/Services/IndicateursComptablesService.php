<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\ReadModels\IndicateursComptables;
use App\Domain\Comptabilite\Support\RubriquesSyscohada;
use LogicException;

/**
 * Le bandeau d'indicateurs de `m10-syscohada.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * Aucun de ces six chiffres n'est calcule ici : tous sont LUS du Compte de
 * Resultat, du Bilan ou de la Balance. Ce service n'est qu'un assembleur —
 * c'est deliberé, et c'est la seule facon de garantir que le bandeau et les
 * onglets qu'il surplombe disent la meme chose (PA-121).
 */
class IndicateursComptablesService
{
    private const PRECISION = 2;

    private const ZERO = '0.00';

    public function __construct(
        private readonly BalanceGeneraleService $balance,
        private readonly CompteResultatService $compteResultat,
        private readonly BilanService $bilan,
    ) {
    }

    /**
     * @param  list<string>  $statuts
     */
    public function genererPourExercice(
        ExerciceComptable $exercice,
        array $statuts,
        string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES,
    ): IndicateursComptables {
        $balance = $this->balance->genererPourExercice($exercice->id, $statuts, $filtreStatut);
        $resultat = $this->compteResultat->genererPourExercice($exercice->id, $statuts, $filtreStatut);
        $bilan = $this->bilan->genererPourExercice($exercice->id, $statuts, $filtreStatut);

        // La tresorerie NETTE, pas le seul actif : un decouvert bancaire ouvert
        // un jour doit la diminuer, pas disparaitre.
        $tresorerie = self::ZERO;

        foreach ($balance->lignes as $ligne) {
            if (RubriquesSyscohada::releveDe($ligne->numeroCompte, RubriquesSyscohada::TRESORERIE_ACTIF)) {
                $tresorerie = bcadd($tresorerie, bcsub($ligne->totalDebit, $ligne->totalCredit, self::PRECISION), self::PRECISION);

                continue;
            }

            if (RubriquesSyscohada::releveDe($ligne->numeroCompte, RubriquesSyscohada::TRESORERIE_PASSIF)) {
                $tresorerie = bcsub($tresorerie, bcsub($ligne->totalCredit, $ligne->totalDebit, self::PRECISION), self::PRECISION);
            }
        }

        return new IndicateursComptables(
            exerciceId: $exercice->id,
            annee: $exercice->annee,
            statutExercice: $exercice->statut,
            chiffreAffaires: $this->solde($resultat->montant('XB'), 'XB'),
            valeurAjoutee: $this->solde($resultat->montant('XC'), 'XC'),
            excedentBrut: $this->solde($resultat->montant('XD'), 'XD'),
            resultatNet: $resultat->resultatNet,
            tresorerie: $tresorerie,
            totalBilan: $bilan->totalActif,
            equilibre: $balance->equilibree && $bilan->equilibre,
            impotNonComptabilise: $resultat->impotNonComptabilise,
            motifResultatAvantImpot: $resultat->motifResultatAvantImpot,
            statuts: $balance->statuts,
            filtresAppliques: $balance->filtresAppliques,
        );
    }

    /**
     * Un code absent de la cascade est une erreur de PROGRAMMATION.
     *
     * Retomber sur `0.00` afficherait un chiffre d'affaires nul en tete d'ecran
     * le jour ou quelqu'un renommerait un code — exactement l'indicateur qui
     * affirme un etat qu'il n'a pas verifie (PA-59/60/61). Message sans accent :
     * il ne peut pas atteindre un ecran.
     */
    private function solde(?string $montant, string $code): string
    {
        if ($montant === null) {
            throw new LogicException(sprintf('Code de solde inconnu dans la cascade SIG : %s.', $code));
        }

        return $montant;
    }
}
