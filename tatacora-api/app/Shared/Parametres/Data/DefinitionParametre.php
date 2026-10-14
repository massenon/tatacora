<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Data;

/**
 * Un paramètre modifiable, tel que l'écran Paramètres le présente et tel que
 * le service l'accepte — les deux depuis la MÊME déclaration.
 *
 * Deux listes (une pour l'affichage, une pour la validation) finiraient par
 * diverger, et la divergence prendrait la forme d'un champ que l'écran propose
 * et que le serveur refuse sans que personne comprenne pourquoi.
 */
final class DefinitionParametre
{
    /**
     * @param  'texte'|'booleen'|'entier'|'decimal'|'choix'  $type
     * @param  list<string>  $regles  règles de validation Laravel
     * @param  list<string>  $choix  valeurs admises, pour le type `choix`
     * @param  array<string, string>  $choixLibelles  valeur stockée => libellé affiché,
     *         pour le type `choix` quand la valeur stockée est un code technique
     *         (`reel_normal`) et non le libellé du maître (« Réel normal »).
     *         Vide : la valeur stockée EST le libellé (`ht`, `ttc`).
     */
    public function __construct(
        public readonly string $cle,
        public readonly string $groupe,
        public readonly string $libelle,
        public readonly string $type,
        public readonly array $regles = [],
        public readonly array $choix = [],
        public readonly ?string $aide = null,
        public readonly array $choixLibelles = [],
    ) {
    }

    /**
     * Le libellé d'affichage d'une valeur de type `choix` — la valeur stockée
     * elle-même quand aucune carte de libellés n'est déclarée.
     *
     * UN SEUL AUTEUR : l'écran Paramètres et l'en-tête des états (régime
     * fiscal) affichent tous deux par cette méthode — deux cartes finiraient
     * par diverger au premier renommage.
     */
    public function libelleDuChoix(string $valeur): string
    {
        return $this->choixLibelles[$valeur] ?? $valeur;
    }
}
