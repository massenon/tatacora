<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Le Compte de Resultat d'un exercice — `m10-resultat.html` et l'onglet
 * « Compte de resultat » de `m10-syscohada.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## `resultatNet` EST un nombre, et `impotNonComptabilise` dit ce qu'il vaut
 *
 * Tant qu'aucune ecriture n'est passee en classe 89, `resultatNet` (XI) egale
 * `resultatAvantImpot` : c'est un resultat AVANT impot, pas un resultat net.
 * Le nombre est juste — il agrege ce qui est comptabilise — mais il ne porte
 * pas le nom qu'on croit.
 *
 * Le rendre `null` serait faux dans l'autre sens : le resultat de l'exercice
 * existe, il est calcule, et c'est lui qui entre au passif du bilan. Ce qui
 * n'existe pas, c'est la CHARGE D'IMPOT — et c'est exactement elle qui descend
 * a `0.00` avec `impotNonComptabilise = true` et `motifResultatAvantImpot`
 * renseigne. « 0 » quand la donnee vaut zero, le drapeau pour dire qu'aucune
 * liquidation n'a eu lieu (Article 7).
 *
 * ## Aucun taux d'IS n'entre ici (PA-19)
 *
 * Voir `SoldesIntermediairesGestion` : la charge d'impot est LUE des ecritures,
 * jamais derivee d'un taux. Ce read model n'a aucun champ de taux, et le
 * service qui le produit n'a aucune dependance vers `ParametreSystemeService` —
 * c'est structurel, pas une discipline a tenir.
 */
final readonly class CompteResultat
{
    /** Le code ferme du motif — la traduction appartient au client. */
    public const MOTIF_IMPOT_NON_COMPTABILISE = 'impot_non_comptabilise';

    /**
     * @param  list<LigneResultat>  $lignes
     * @param  array{statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public array $lignes,
        public string $resultatAvantImpot,
        public string $impotComptabilise,
        public string $resultatNet,
        public bool $impotNonComptabilise,
        public ?string $motifResultatAvantImpot,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
    ) {
    }

    /**
     * Le montant d'un code de la cascade — `XB`, `XC`, `XD`…
     *
     * Les indicateurs du hub sont TROIS soldes de cette cascade
     * (`m10-syscohada-init.js` l.38-48). Les relire ici, plutot que de les
     * recalculer par une agregation parallele, est la regle de PA-121 : une
     * courbe se calcule COMME le KPI, jamais a cote.
     *
     * Rend `null` sur un code inconnu — l'appelant decide, plutot que de
     * recevoir un `0.00` qui se lirait comme un solde nul.
     */
    public function montant(string $code): ?string
    {
        foreach ($this->lignes as $ligne) {
            if ($ligne->code === $code) {
                return $ligne->montant;
            }
        }

        return null;
    }
}
