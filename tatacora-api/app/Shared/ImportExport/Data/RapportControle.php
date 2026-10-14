<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Data;

/**
 * Le rapport de contrôle d'un fichier d'import — ce que l'écran affiche
 * (bandeau conforme/non conforme, lignes ERREUR/AVERTIS.) et ce que
 * l'application consomme (les lignes converties, prêtes pour les services).
 *
 * Chaque anomalie : `['ligne' => int, 'colonne' => ?string, 'message' => string]`
 * — le numéro de ligne compte COMME EXCEL (l'en-tête est la ligne 1), parce
 * que c'est son fichier que l'utilisateur va corriger, pas notre index.
 */
final class RapportControle
{
    /**
     * @param  list<array{ligne: int, colonne: ?string, message: string}>  $erreurs
     * @param  list<array{ligne: int, colonne: ?string, message: string}>  $avertissements
     * @param  list<array<string, mixed>>  $lignes  lignes valides, converties
     * @param  array{total: int, valides: int, en_erreur: int}  $resume
     */
    public function __construct(
        public readonly bool $ok,
        public readonly array $erreurs,
        public readonly array $avertissements,
        public readonly array $lignes,
        public readonly array $resume,
    ) {
    }
}
