<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

use App\Domain\Comptabilite\Models\CompteComptable;

/**
 * Le Grand Livre d'un compte sur un exercice — `m10-grand-livre.html`.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## Le solde d'OUVERTURE est INCONNU, et il ne vaut pas zero
 *
 * `MODULE_COMPTABILITE_COMPLET.md` §3 place `solde_ouverture` dans la reponse
 * et renvoie son calcul au **report a nouveau**, decrit en Partie 4 (cloture).
 * Ce report **n'existe nulle part dans ce depot** : aucun service, aucun job,
 * aucune migration ne genere de solde d'ouverture.
 *
 * Rendre `0` serait affirmer que le compte partait de zero au premier jour de
 * l'exercice — une affirmation qu'aucun calcul n'a produite, sur l'ecran meme
 * ou un comptable lit le solde d'un compte. C'est la famille PA-59/60/61 :
 * l'indicateur qui dit « tout va bien » pendant que rien n'a eu lieu, et
 * l'Article 7 de `DIRECTIVE_CONFORMITE_100.md` tranche dans l'autre sens :
 * « — » quand la donnee n'existe pas, « 0 » quand elle vaut zero.
 *
 * Consequence en chaine : le solde de CLOTURE vaut ouverture + mouvements. Une
 * ouverture inconnue rend la cloture inconnue. Seul `soldeMouvements` est
 * calcule — et il est nomme pour ce qu'il est : le cumul des mouvements de
 * l'exercice, pas le solde du compte.
 *
 * Le jour ou le report a nouveau sera livre (Partie 4), les deux champs nuls
 * deviendront des montants et `motifSoldesIndisponibles` deviendra `null`. Rien
 * d'autre ne bouge.
 */
final readonly class GrandLivre
{
    /**
     * Le report a nouveau n'est implemente nulle part — Partie 4, cloture.
     * Code ferme, destine a etre traduit par le client : le serveur ne dicte
     * pas la phrase affichee.
     */
    public const MOTIF_REPORT_ABSENT = 'report_a_nouveau_absent';

    /**
     * @param  list<LigneGrandLivre>  $lignes
     * @param  array{statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public CompteComptable $compte,
        public array $lignes,
        public string $soldeMouvements,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
        public ?string $soldeOuverture = null,
        public ?string $soldeCloture = null,
        public ?string $motifSoldesIndisponibles = self::MOTIF_REPORT_ABSENT,
    ) {
    }

    /**
     * Le compte est-il sans aucun mouvement sur l'exercice ?
     *
     * Le maitre a un etat vide nomme pour ce cas (l.29 : « Ce compte n'a aucun
     * mouvement sur l'exercice. »). Une liste vide est donc une reponse
     * legitime, jamais un 404 : le compte existe, c'est son activite qui est
     * nulle — et les deux ne se disent pas de la meme facon.
     */
    public function estSansMouvement(): bool
    {
        return $this->lignes === [];
    }
}
