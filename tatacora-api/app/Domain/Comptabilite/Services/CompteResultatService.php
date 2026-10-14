<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\ReadModels\CompteResultat;
use App\Domain\Comptabilite\ReadModels\LigneResultat;
use App\Domain\Comptabilite\Support\SoldesIntermediairesGestion;
use LogicException;

/**
 * Compte de Resultat SYSCOHADA revise, Systeme Normal.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * Maitre : `m10-resultat.html` (vue simple) et l'onglet « Compte de resultat »
 * de `m10-syscohada.html` (cascade complete). Un SEUL service sert les deux :
 * les trois resultats successifs du document (`MODULE_COMPTABILITE_COMPLET_PART3.md`
 * §1.1 — exploitation, financier, RAO, HAO) sont exactement les codes `XE`,
 * `XF`, `XG`, `XH` de la cascade. La structure du document est une PROJECTION
 * de la cascade, pas un second modele — les calculer separement aurait produit
 * deux verites sur le meme exercice (PA-121).
 *
 * ## Il calcule depuis la BALANCE, jamais depuis les ecritures
 *
 * La Balance agrege deja une ligne par compte mouvemente, avec la meme portee
 * (exercice, statuts) et le meme `bccomp`. Relire les ecritures ici ferait une
 * seconde agregation parallele : le jour ou la portee changerait, le compte de
 * resultat et la balance afficheraient deux totaux differents sur le meme
 * ecran. C'est le raisonnement de PA-121, applique aux etats financiers.
 *
 * ## PA-19 : aucun taux d'impot n'entre dans ce service
 *
 * Il n'a AUCUNE dependance vers `ParametreSystemeService`, et la rubrique `RS`
 * est alimentee par la classe 89 comme n'importe quelle autre rubrique l'est
 * par sa classe. Le refus de deviner n'est donc pas une garde qu'on pourrait
 * oublier : il n'y a simplement aucun chemin par lequel un taux pourrait
 * arriver. Voir `SoldesIntermediairesGestion` pour l'ecart assume avec
 * `MODULE_COMPTABILITE_COMPLET_PART3.md` §1.3.
 */
class CompteResultatService
{
    private const PRECISION = 2;

    public function __construct(
        private readonly BalanceGeneraleService $balance,
    ) {
    }

    /**
     * @param  list<string>  $statuts
     */
    public function genererPourExercice(
        string $exerciceId,
        array $statuts,
        string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES,
    ): CompteResultat {
        $balance = $this->balance->genererPourExercice($exerciceId, $statuts, $filtreStatut);

        /** @var array<string, string> $valeurs */
        $valeurs = [];
        $lignes = [];

        foreach (SoldesIntermediairesGestion::CASCADE as $rubrique) {
            $estSolde = isset($rubrique['composants']);

            // Les deux branches lisent des cles MUTUELLEMENT EXCLUSIVES du
            // registre — `composants` sur un solde, `prefixes` sur une
            // rubrique. L'extraction prealable rend cette exclusivite explicite
            // pour l'analyse statique, qui ne peut pas la deduire de
            // `$estSolde` seul.
            $composants = $rubrique['composants'] ?? [];
            $prefixes = $rubrique['prefixes'] ?? [];

            $montant = $estSolde
                ? $this->sommerComposants($rubrique['code'], $composants, $valeurs)
                : $this->sommerPrefixes($balance->lignes, $prefixes);

            $valeurs[$rubrique['code']] = $montant;

            $lignes[] = new LigneResultat(
                code: $rubrique['code'],
                libelle: $rubrique['libelle'],
                sens: $rubrique['sens'],
                montant: $montant,
                estSolde: $estSolde,
                prefixes: $prefixes,
                composants: $composants,
            );
        }

        $resultatAvantImpot = $this->sommerComposants(
            'resultat_avant_impot',
            SoldesIntermediairesGestion::COMPOSANTS_RESULTAT_AVANT_IMPOT,
            $valeurs,
        );

        $impot = $valeurs[SoldesIntermediairesGestion::CODE_IMPOT];
        $resultatNet = $valeurs[SoldesIntermediairesGestion::CODE_RESULTAT_NET];

        // `bccomp` et jamais `=== '0.00'` : la chaine rendue par `bcadd` sur une
        // somme vide et celle rendue par une compensation exacte peuvent
        // differer par leur signe (« -0.00 »), alors que les deux valent zero.
        $impotNonComptabilise = bccomp($impot, '0.00', self::PRECISION) === 0;

        return new CompteResultat(
            exerciceId: $exerciceId,
            lignes: $lignes,
            resultatAvantImpot: $resultatAvantImpot,
            impotComptabilise: $impot,
            resultatNet: $resultatNet,
            impotNonComptabilise: $impotNonComptabilise,
            motifResultatAvantImpot: $impotNonComptabilise
                ? CompteResultat::MOTIF_IMPOT_NON_COMPTABILISE
                : null,
            statuts: $balance->statuts,
            filtresAppliques: $balance->filtresAppliques,
        );
    }

    /**
     * La contribution SIGNEE au resultat des comptes relevant de `$prefixes`.
     *
     * `montant = -(debit - credit)` : un produit rend un montant positif, une
     * charge un montant negatif. C'est ce qui permet a toute la cascade d'etre
     * une addition (voir `SoldesIntermediairesGestion`).
     *
     * @param  list<\App\Domain\Comptabilite\ReadModels\LigneBalance>  $lignesBalance
     * @param  list<string>  $prefixes
     */
    private function sommerPrefixes(array $lignesBalance, array $prefixes): string
    {
        $total = '0.00';

        foreach ($lignesBalance as $ligne) {
            if (! \App\Domain\Comptabilite\Support\RubriquesSyscohada::releveDe($ligne->numeroCompte, $prefixes)) {
                continue;
            }

            // credit - debit : l'oppose du solde, donc la contribution au
            // resultat, en une seule soustraction plutot qu'une soustraction
            // suivie d'une negation.
            $total = bcadd(
                $total,
                bcsub($ligne->totalCredit, $ligne->totalDebit, self::PRECISION),
                self::PRECISION,
            );
        }

        return $total;
    }

    /**
     * @param  list<string>  $composants
     * @param  array<string, string>  $valeurs
     */
    private function sommerComposants(string $code, array $composants, array $valeurs): string
    {
        $total = '0.00';

        foreach ($composants as $composant) {
            if (! array_key_exists($composant, $valeurs)) {
                // Erreur de PROGRAMMATION, pas d'utilisateur : un solde
                // reference un code qui n'a pas encore ete calcule, donc la
                // cascade est mal ordonnee. Message non traduit et sans
                // accent — il ne peut pas atteindre un ecran.
                throw new LogicException(sprintf(
                    'Cascade SIG mal ordonnee : le solde %s reference %s, non encore calcule.',
                    $code,
                    $composant,
                ));
            }

            $total = bcadd($total, $valeurs[$composant], self::PRECISION);
        }

        return $total;
    }
}
