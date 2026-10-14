<?php

declare(strict_types=1);

namespace App\Pwa\Support;

/**
 * Rendu et formatage sécurisé des valeurs de la table `parametres_systeme`.
 */
final class ValeurParametre
{
    public const TIRET = '—';

    public const TYPES = ['texte', 'booleen', 'entier', 'decimal', 'choix'];

    /**
     * Formate la valeur d'un paramètre système en fonction de son type.
     *
     * @param array{type: string, valeur: string|null} $parametre
     */
    public static function afficher(array $parametre): string
    {
        $valeur = $parametre['valeur'];

        if ($valeur === null || $valeur === '') {
            return self::TIRET;
        }

        return match ($parametre['type']) {
            'booleen' => filter_var($valeur, FILTER_VALIDATE_BOOLEAN) ? 'Oui' : 'Non',
            'texte', 'entier', 'decimal', 'choix' => $valeur,
            default => $valeur,
        };
    }

    /**
     * Vérifie si le type de paramètre est hors du registre géré.
     */
    public static function typeInconnu(string $type): bool
    {
        return ! in_array($type, self::TYPES, true);
    }
}
