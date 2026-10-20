<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * L'etat de la procedure de cloture d'un exercice — `m10-cloture.html`.
 *
 * @see EF-M10-07 Cloture comptable periodique avec verrouillage
 * @see RG-11 Immutabilite d'une ecriture validee
 *
 * ## L'action de clôture est exposée (lot 2, 20/10/2026)
 *
 * Jusqu'au 20/10/2026, `m10-cloture.html` était une checklist en lecture
 * seule : aucun report à nouveau n'existait et le périmètre (mensuel ou
 * annuel, PA-28) n'était pas arbitré. Le PO a tranché — clôture ANNUELLE,
 * réouverture par le comptable — et `ClotureExerciceService` porte le geste
 * (onglet « Clôtures » du hub). `actionExposee` vaut `true` ; les étapes 2 à
 * 5 se lisent sur la clôture réelle (statut de l'exercice, clôture active,
 * balance après clôture). La page `pwa.comptabilite.cloture` reste, elle, un
 * diagnostic sans bouton.
 *
 * ## Trois listes, et la distinction est le livrable
 *
 * - `blocagesStructurels` : REELLEMENT VERIFIE a chaque appel — le journal, les
 *   comptes 131/139 et le centre de cloture existent-ils au referentiel
 *   (PART4 §2.2 leve sans eux) ? Ces blocages disparaissent seuls le jour ou
 *   l'element manquant est cree.
 * - `blocagesDeDonnees` : brouillons restants, balance ou bilan desequilibres.
 *   Ils se corrigent en SAISISSANT.
 * - `limitesNonVerifiables` : ce qui ne se constate dans aucune table,
 *   littéral et nommé comme tel (vide depuis le lot 2).
 *
 * `conditionsVerifiablesReunies` ne porte que les deux PREMIERES listes. Y
 * verser les limites litterales l'aurait fige a `false` par construction : le
 * champ n'apprendrait plus rien et affirmerait un etat qu'aucun controle n'a
 * produit — la forme meme de PA-59/60/61, retournee.
 *
 * Une clôture verrouille des écritures : elle ÉCRIT son report à nouveau
 * (journal AN) en même temps, et ne se défait que par contre-passation, au
 * comptable seul (`ClotureExerciceService::rouvrir`).
 *
 * ## Les etapes portent un ETAT, et « non verifiable » n'est pas « conforme »
 *
 * L'inventaire physique (M6) n'est pas lisible depuis M10. L'annoncer conforme
 * serait l'indicateur qui affirme un etat qu'il n'a pas verifie (PA-59/60/61) ;
 * l'annoncer bloquant accuserait a tort. Il est `non_verifiable`, avec son
 * motif.
 */
final readonly class EtatCloture
{
    public const ETAT_CONFORME = 'conforme';

    public const ETAT_BLOQUE = 'bloque';

    public const ETAT_NON_VERIFIABLE = 'non_verifiable';

    public const ETAT_NON_ATTEINT = 'non_atteint';

    /**
     * @param  list<EtapeCloture>  $etapes
     * @param  list<string>  $blocagesStructurels
     * @param  list<string>  $blocagesDeDonnees
     * @param  list<string>  $limitesNonVerifiables
     * @param  list<string>  $avertissements
     * @param  array{statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public int $annee,
        public string $statutExercice,
        public array $etapes,
        public array $blocagesStructurels,
        public array $blocagesDeDonnees,
        public array $limitesNonVerifiables,
        public array $avertissements,
        public bool $conditionsVerifiablesReunies,
        public bool $actionExposee,
        public string $resultatAReporter,
        public string $compteDeDestination,
        public bool $impotNonComptabilise,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
    ) {
    }
}
