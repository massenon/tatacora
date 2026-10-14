<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Data;

/**
 * Un module importable — sa déclaration complète, portée par le registre
 * fermé `ReferentielsImport`.
 */
final class ModuleImport
{
    /**
     * @param  string  $cle  identifiant fermé (`m6-stocks`…) — celui du maître
     * @param  string  $module  code RBAC du module source (`M6`…)
     * @param  string  $identifiant  champ dont le doublon se contrôle
     * @param  bool  $doublonExistantBloquant  `true` quand la base porte une
     *                                         contrainte UNIQUE (l'import échouerait) — le doublon avec
     *                                         l'existant devient une erreur, jamais un simple avertissement
     * @param  list<ColonneImport>  $colonnes
     */
    public function __construct(
        public readonly string $cle,
        public readonly string $module,
        public readonly string $nom,
        public readonly string $description,
        public readonly string $identifiant,
        public readonly array $colonnes,
        public readonly bool $doublonExistantBloquant = false,
    ) {
    }

    public function colonne(string $champ): ?ColonneImport
    {
        foreach ($this->colonnes as $colonne) {
            if ($colonne->champ === $champ) {
                return $colonne;
            }
        }

        return null;
    }
}
