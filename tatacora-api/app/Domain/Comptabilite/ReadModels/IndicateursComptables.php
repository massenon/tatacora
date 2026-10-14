<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Les six indicateurs du bandeau de `m10-syscohada.html`
 * (`m10-syscohada-init.js` l.38-48), plus le bandeau d'exercice l.27-29.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 *
 * ## Les trois premiers SONT des soldes de la cascade, ils n'en sont pas une copie
 *
 * `chiffreAffaires`, `valeurAjoutee` et `excedentBrut` sont lus dans le Compte
 * de Resultat (`XB`, `XC`, `XD`), et `resultatNet` dans le meme etat (`XI`). Une
 * seconde agregation, meme « plus rapide », finirait par afficher un chiffre
 * d'affaires en tete d'ecran qui ne serait pas celui du tableau en dessous
 * (PA-121).
 *
 * ## `resultatNet` porte son drapeau, comme partout ailleurs
 *
 * Le maitre affiche « XI » ou « XI — avant impôt » selon que la classe 89 est
 * mouvementee ou non. Un resultat net annonce sans ce qualificatif serait la
 * non-conformite PA-49 : un intitule qui ne dit pas ce qui est calcule.
 *
 * ## `equilibre` porte sur DEUX etats, pas un
 *
 * Balance equilibree ET bilan equilibre — c'est la condition du bandeau rouge
 * « Comptabilité déséquilibrée » du maitre (`m10-syscohada-init.js` l.50-52).
 * Ne verifier que la balance laisserait passer une erreur de classification de
 * compte, qui n'apparait qu'au bilan.
 */
final readonly class IndicateursComptables
{
    /**
     * @param  array{statut: string}  $filtresAppliques
     */
    public function __construct(
        public string $exerciceId,
        public int $annee,
        public string $statutExercice,
        public string $chiffreAffaires,
        public string $valeurAjoutee,
        public string $excedentBrut,
        public string $resultatNet,
        public string $tresorerie,
        public string $totalBilan,
        public bool $equilibre,
        public bool $impotNonComptabilise,
        public ?string $motifResultatAvantImpot,
        public RepartitionStatuts $statuts,
        public array $filtresAppliques,
    ) {
    }
}
