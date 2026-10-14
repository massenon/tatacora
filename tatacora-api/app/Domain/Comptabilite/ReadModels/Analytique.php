<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * La comptabilite analytique d'un exercice — `m10-analytique.html` et l'onglet
 * « Analytique » de `m10-syscohada.html`.
 *
 * @see EF-M10-03 Comptabilite analytique par centre de cout/activite
 * @see RG-12 Centre de cout obligatoire sur toute ecriture
 *
 * ## Ce sont des MARGES SUR COUTS DIRECTS, jamais des resultats nets
 *
 * `repartitionStructureEffectuee` est `false`, et ce n'est pas un « pas encore » :
 * aucune cle de repartition des charges de structure n'existe dans ce depot, ni
 * au schema ni dans aucun document. Les charges du centre « Structure » (paie,
 * entretien general, frais bancaires) restent donc chez lui.
 *
 * Le maitre l'ecrit lui-meme sous son tableau (`m10-syscohada-etats.js`
 * l.191-195). Appeler « resultat » ce qui est une marge sur couts directs
 * ferait croire qu'une filiere est rentable alors qu'elle ne porte aucune part
 * des frais communs — c'est la discipline PA-49 : l'intitule dit ce qui est
 * REELLEMENT calcule.
 *
 * ## `tauxMarge` est `null`, jamais `0`, quand il n'y a aucun produit
 *
 * Un centre sans produit n'a pas un taux de marge de zero : il n'en a pas.
 * « Structure » est exactement ce cas — il ne genere aucun produit par nature.
 * Le maitre affiche « — » (`m10-analytique.html` l.50-52). Article 7.
 *
 * ## La ventilation est garantie par le SCHEMA, pas par un compteur
 *
 * Le maitre compte les lignes sans centre analytique et les affiche en rouge.
 * Ici ce compteur ne pourrait JAMAIS s'allumer : `ecritures_comptables.centre_id`
 * est NOT NULL (RG-12 portee par la base, pas seulement par du code). Un
 * compteur structurellement bloque a zero serait exactement l'indicateur qui
 * affirme un etat qu'il n'a pas verifie (PA-59/60/61) — il rassurerait sans
 * jamais rien mesurer. Il n'est donc pas emis ; `ventilationGarantieParSchema`
 * nomme la raison a sa place.
 */
final readonly class Analytique
{
    /** Le code ferme du motif — la traduction appartient au client. */
    public const MOTIF_SANS_REPARTITION = 'charges_de_structure_non_reparties';

    /**
     * @param  list<LigneAnalytique>  $centres
     * @param  array{statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public array $centres,
        public string $totalProduits,
        public string $totalCharges,
        public string $totalResultat,
        public bool $repartitionStructureEffectuee,
        public string $motifNatureDesMarges,
        public bool $ventilationGarantieParSchema,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
    ) {
    }
}
