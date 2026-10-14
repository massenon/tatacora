<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * L'etat de la procedure de cloture d'un exercice — `m10-cloture.html`.
 *
 * @see EF-M10-07 Cloture comptable periodique avec verrouillage
 * @see RG-11 Immutabilite d'une ecriture validee
 *
 * ## AUCUNE ACTION DE CLOTURE N'EST EXPOSEE, et le maitre non plus n'en a
 *
 * `m10-cloture.html` n'a AUCUN bouton : ni « Clôturer », ni « Valider », ni
 * « Reporter ». C'est une checklist de diagnostic en lecture seule — le fichier
 * ne contient pas un seul `addEventListener`. Cet etat en est la transcription
 * fidele.
 *
 * `actionExposee` vaut donc `false`, et `limitesNonVerifiables` dit pourquoi
 * l'action ne pourrait pas etre offerte meme si le maitre la demandait :
 *
 * - **Le report a nouveau n'existe nulle part** (Partie 4 §2.1 etape 6). Sans
 *   lui, cloturer laisserait l'exercice suivant sans aucun solde d'ouverture.
 * - **Le perimetre de la cloture n'est pas arbitre (PA-28)** : « Cloture
 *   Periodique » (mensuelle) et « Cloture d'Exercice » (annuelle) restent deux
 *   concepts distincts non tranches — le maitre l'ecrit lui-meme en tete de sa
 *   page.
 *
 * ## Trois listes, et la distinction est le livrable
 *
 * - `blocagesStructurels` : REELLEMENT VERIFIE a chaque appel — le journal, les
 *   comptes 131/139 et le centre de cloture existent-ils au referentiel
 *   (PART4 §2.2 leve sans eux) ? Ces blocages disparaissent seuls le jour ou
 *   l'element manquant est cree.
 * - `blocagesDeDonnees` : brouillons restants, balance ou bilan desequilibres.
 *   Ils se corrigent en SAISISSANT.
 * - `limitesNonVerifiables` : les deux ci-dessus, litterales et nommees comme
 *   telles. L'absence d'un MECANISME et l'absence d'un ARBITRAGE ne se
 *   constatent dans aucune table ; les deguiser en controle aurait produit un
 *   faux constat.
 *
 * `conditionsVerifiablesReunies` ne porte que les deux PREMIERES listes. Y
 * verser les limites litterales l'aurait fige a `false` par construction : le
 * champ n'apprendrait plus rien et affirmerait un etat qu'aucun controle n'a
 * produit — la forme meme de PA-59/60/61, retournee.
 *
 * Une cloture est IRREVERSIBLE et verrouille definitivement des ecritures. Un
 * bouton qui confirmerait sans ecrire serait exactement ce que l'Article 6
 * interdit ; un bouton qui ecrirait sans report a nouveau serait pire — il
 * produirait un exercice suivant faux, sans moyen de revenir en arriere.
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
