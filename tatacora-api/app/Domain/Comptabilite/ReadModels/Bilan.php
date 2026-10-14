<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Le Bilan d'un exercice — `m10-bilan.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## Le Bilan N'A PAS BESOIN du taux d'IS, et la demonstration tient en trois lignes
 *
 * La partie double impose `SOMME(debit) = SOMME(credit)` sur tout l'exercice.
 * En separant les classes de bilan (1 a 5) des classes de gestion (6 a 8) :
 *
 *     Actif - Passif(hors resultat) = Produits - Charges = resultat de l'exercice
 *
 * Le poste « Resultat de l'exercice » du passif est donc, mathematiquement, la
 * grandeur qui equilibre le bilan — et c'est le resultat REELLEMENT
 * COMPTABILISE, impot compris s'il l'est et non compris s'il ne l'est pas.
 * Aucun taux n'intervient : PA-19 ne bloque pas cet etat.
 *
 * ⚠ La consequence, et elle est le coeur de l'honnetete de cet etat : tant que
 * rien n'est comptabilise en classe 89, ce poste porte un resultat AVANT impot.
 * `impotNonComptabilise` le dit, exactement comme sur le Compte de Resultat
 * (`comptabilite-engine.js` l.647 propage le meme drapeau au bilan). L'appeler
 * « resultat net » sans ce drapeau serait la non-conformite PA-49 : un intitule
 * qui ne dit pas ce qui est reellement calcule.
 *
 * Corollaire utile : le jour ou l'ecriture d'impot SERA passee, l'equilibre
 * continuera de tenir sans modification de code — la charge d'impot entre au
 * resultat et la dette d'impot au passif circulant, et les deux se compensent.
 *
 * ## `comptesHorsRubrique` — la garde que la repartition par prefixe EXIGE
 *
 * L'onglet du hub repartit par `type` : tout compte porte un type, donc la
 * repartition y est exhaustive par construction. La repartition par PREFIXE ne
 * l'est pas. Un compte ouvert demain sous un numero qu'aucune rubrique ne
 * capte — une TVA deductible en 445, un compte d'attente en 47 — disparaitrait
 * du bilan SANS RIEN DIRE, et l'ecart n'apparaitrait que comme un desequilibre
 * inexplicable sur l'ecran d'un comptable.
 *
 * Ce champ liste ces comptes avec leur solde. Il est vide sur le referentiel
 * actuel (`ATELIER_PLAN_COMPTABLE.md` §4 est integralement couvert), et c'est
 * precisement pourquoi il doit exister : une garde n'a de valeur que si elle
 * est posee AVANT le cas qu'elle attrape. Sans elle, la premiere personne a
 * ouvrir un compte hors nomenclature chercherait l'erreur dans les ecritures.
 *
 * ## `equilibre` est un CONSTAT, pas une garantie (PA-52)
 *
 * Il compare deux totaux en `bccomp`. Il ne dit rien de l'equilibre de chaque
 * piece : `ecritures_comptables` n'a aucun identifiant de piece, donc deux
 * pieces fausses en sens contraire rendraient `true`. L'equilibre n'est garanti
 * qu'A L'ECRITURE, par `EcritureComptableService::enregistrerPiece()` — c'est
 * une garantie de flux, pas d'etat, et elle tombe au premier import.
 */
final readonly class Bilan
{
    /**
     * @param  list<PosteBilan>  $actif
     * @param  list<PosteBilan>  $passif
     * @param  list<array{numero_compte: string, libelle: string, solde: string}>  $comptesHorsRubrique
     * @param  array{statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public array $actif,
        public array $passif,
        public array $comptesHorsRubrique,
        public string $totalActifBrut,
        public string $totalActifAmortissement,
        public string $totalActif,
        public string $totalPassif,
        public bool $equilibre,
        public string $ecart,
        public string $resultatExercice,
        public bool $impotNonComptabilise,
        public ?string $motifResultatAvantImpot,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
    ) {
    }
}
