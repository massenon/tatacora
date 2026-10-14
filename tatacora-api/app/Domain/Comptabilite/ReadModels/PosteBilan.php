<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\ReadModels;

/**
 * Un poste du Bilan — `m10-bilan.html` l.84-100.
 *
 * `brut`, `amortissement` et `net` existent sur TOUS les postes, y compris ceux
 * qui ne s'amortissent jamais : un poste de tresorerie porte `amortissement`
 * a `0.00`. Rendre le champ absent sur ces postes obligerait le client a deux
 * mises en page, et la colonne « Amort./Depr. » du maitre attend une valeur a
 * chaque ligne. Cote passif, `brut` et `net` sont egaux — un passif ne
 * s'amortit pas — et c'est `net` qui fait foi partout.
 *
 * `prefixes` dit QUELS comptes alimentent le poste. C'est la seule facon de
 * comprendre un montant inattendu sans ouvrir le grand livre, et le maitre
 * l'affiche sous chaque libelle (`m10-syscohada-etats.js` l.125 et l.139).
 */
final readonly class PosteBilan
{
    public const SECTION_ACTIF = 'actif';

    public const SECTION_PASSIF = 'passif';

    /**
     * @param  list<string>  $prefixes
     */
    public function __construct(
        public string $section,
        public string $code,
        public string $libelle,
        public string $brut,
        public string $amortissement,
        public string $net,
        public array $prefixes = [],
    ) {
    }
}
