<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Support;

/**
 * La description FACULTATIVE d'un plat (décision du PO du 30/10/2026).
 *
 * Une seule règle, partagée par l'API (`EnregistrerPlatRequest`), la PWA
 * (`Restauration::enregistrerPlat`) et la synchronisation (qui passe par la
 * requête) : texte libre de 500 caractères au plus, normalisé par
 * {@see self::normaliser()} — espaces de bord retirés, chaîne vide = `null`.
 * Le poste rejoue la même règle (`description_plat.dart`), confrontée à ce
 * fichier par `tool/restaurant/rejouer_description_plat.php`.
 */
final class DescriptionPlat
{
    public const MAX = 500;

    /** @var list<string> */
    public const REGLES = ['nullable', 'string', 'max:' . self::MAX];

    /**
     * `null` pour « pas de description » : une chaîne vide ou faite d'espaces
     * n'est pas une description.
     */
    public static function normaliser(mixed $valeur): ?string
    {
        if (! is_string($valeur)) {
            return null;
        }

        $nette = trim($valeur);

        return $nette === '' ? null : $nette;
    }
}
