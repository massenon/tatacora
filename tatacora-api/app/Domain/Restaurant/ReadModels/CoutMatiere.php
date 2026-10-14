<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\ReadModels;

/**
 * Coût matière d'une fiche technique — EF-M4-02.
 *
 * ## Pourquoi un objet plutôt qu'un montant
 *
 * Parce qu'un coût matière a **trois** états et non deux, et que les confondre
 * fausse la seule décision que ce chiffre sert à prendre — fixer un prix de
 * vente :
 *
 * - un montant, quand tous les ingrédients ont un coût moyen pondéré connu ;
 * - `null` avec `incomplet = true`, quand au moins un ingrédient n'a jamais
 *   été réceptionné et porte donc un CMP à zéro ;
 * - `null` avec `composition_vide = true`, quand la recette n'a aucune ligne.
 *
 * Rendre `0` dans les deux derniers cas afficherait « coût matière : 0 F » sur
 * la fiche d'un plat dont on ignore ce qu'il coûte — et la marge affichée
 * juste à côté vaudrait alors le prix de vente entier. C'est la forme exacte
 * de PA-126 : un zéro plausible sur l'écran où l'on décide.
 *
 * @see EF-M4-02 Fiches techniques (ingrédients, quantités, coût matière)
 */
final readonly class CoutMatiere
{
    /**
     * @param  string|null  $montant  `numeric-string` à 2 décimales, ou null si non calculable
     * @param  list<string>  $articlesSansCout  libellés des articles au CMP inconnu
     */
    public function __construct(
        public ?string $montant,
        public bool $incomplet,
        public bool $compositionVide,
        public array $articlesSansCout,
    ) {
    }

    public static function compositionVide(): self
    {
        return new self(montant: null, incomplet: false, compositionVide: true, articlesSansCout: []);
    }

    /**
     * @param  list<string>  $articlesSansCout
     */
    public static function incomplet(array $articlesSansCout): self
    {
        return new self(montant: null, incomplet: true, compositionVide: false, articlesSansCout: $articlesSansCout);
    }

    public static function connu(string $montant): self
    {
        return new self(montant: $montant, incomplet: false, compositionVide: false, articlesSansCout: []);
    }

    /**
     * Marge brute sur un prix de vente, ou `null` si le coût est inconnu.
     *
     * Un prix de vente moins un coût inconnu n'est pas une marge : c'est le
     * prix de vente. Le taire est le seul comportement honnête.
     */
    public function marge(string $prixVente): ?string
    {
        return $this->montant === null ? null : bcsub($prixVente, $this->montant, 2);
    }
}
