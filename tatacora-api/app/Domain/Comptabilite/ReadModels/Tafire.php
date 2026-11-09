<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * TAFIRE — Tableau Financier des Ressources et Emplois, l'equivalent SYSCOHADA
 * du tableau des flux de tresorerie (`m10-flux-tresorerie.html`).
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## `coherent` N'EST PAS OPTIONNEL — c'est la preuve du tableau
 *
 * `MODULE_COMPTABILITE_COMPLET_PART3.md` §2.2 : « Doit etre recoupe avec la
 * variation reelle des soldes de tresorerie — ecart = signal d'erreur de calcul
 * quelque part dans la chaine, PAS une "difference normale" ». §2.3 le repete :
 * alerte bloquante a l'export.
 *
 * L'egalite n'a rien d'empirique, elle se demontre par la partie double :
 *
 *     Somme(solde de tous les comptes) = 0
 *     => variation de T = resultat de N + variation des capitaux propres + dotations
 *                      - variation des immobilisations nettes - variation du BFR
 *                      (voir l'en-tete de `TafireService`)
 *
 * et c'est terme pour terme `Ressources - Emplois - Variation du BFR`. Un ecart
 * ne peut donc venir que d'un compte mal classe ou absent d'une rubrique — pas
 * d'un arrondi. C'est ce qui autorise a l'afficher comme une anomalie, et non
 * comme une tolerance.
 *
 * ## Champs nommes « amortissements » qui portent plus (10/11/2026)
 *
 * `dotationsAmortissements` et `reprisesAmortissements` gardent leur nom (et la
 * cle `dotations_amortissements` / `reprises_amortissements` de l'API) mais
 * portent TOUTES les dotations et reprises de la CAFG : amortissements,
 * provisions et depreciations, HAO (voir `RubriquesTafire::DOTATIONS` et
 * `REPRISES`). `variationEmprunts` ne porte plus que les comptes 16 et 17 ; le
 * 18 a sa ligne (`variationDettesParticipations`) et le 19 aucune.
 *
 * ## La CAFG part du resultat REELLEMENT comptabilise
 *
 * Elle reprend `Bilan::resultatExercice` (resultat net de N SEUL depuis le
 * 10/11/2026 ; le 131/139 reporte de N-1 est un capital propre), jamais une
 * seconde formule (PA-121). Definition complete : en-tete de `TafireService`.
 * Tant qu'aucun impot n'est comptabilise en classe 89, ce resultat est un
 * resultat AVANT impot et `impotNonComptabilise` le dit — la CAFG est alors
 * surevaluee du montant de l'impot qui sera du. Ne pas le signaler laisserait
 * lire une capacite d'autofinancement pour ce qu'elle n'est pas.
 */
final readonly class Tafire
{
    /**
     * @param  array{statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public string $resultatExercice,
        public string $dotationsAmortissements,
        public string $reprisesAmortissements,
        public string $valeurComptableCessions,
        public string $quotePartSubventions,
        public string $capaciteAutofinancementGlobale,
        public string $produitsCessions,
        public string $augmentationCapital,
        public string $variationEmprunts,
        public string $variationDettesParticipations,
        public string $totalRessources,
        public string $acquisitionsImmobilisations,
        public string $variationAutresCapitauxPropres,
        public string $variationDividendesAPayer,
        public string $dividendesVerses,
        public string $totalEmplois,
        public string $fluxExploitation,
        public string $fluxInvestissement,
        public string $fluxFinancement,
        public string $variationStocks,
        public string $variationCreances,
        public string $variationDettes,
        public string $variationBesoinFondsRoulement,
        public string $variationTresorerieCalculee,
        public string $variationTresorerieReelle,
        public string $ecart,
        public bool $coherent,
        public bool $impotNonComptabilise,
        public ?string $motifResultatAvantImpot,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
    ) {
    }
}
