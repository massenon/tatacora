<?php

declare(strict_types=1);

namespace App\Shared\Auth\Support;

/**
 * Fabrique les deux secrets à usage humain du lot « mot de passe perdu » :
 * le mot de passe TEMPORAIRE et le CODE DE SECOURS (décision du PO du 29/10/2026).
 *
 * ## Aléa
 *
 * `random_int()` (CSPRNG du système), jamais `rand()`/`mt_rand()`/`Str::random()`
 * pour les caractères : un secret prédictible n'en est pas un.
 *
 * ## Pas de caractère ambigu
 *
 * Ni `0`/`O`, ni `1`/`l`/`I` : un mot de passe lu à voix haute ou recopié d'un
 * papier ne doit pas dépendre d'une police. Les alphabets sont des CONSTANTES,
 * sans caractère de ponctuation : un temporaire se dicte.
 */
final class GenerateurDeSecret
{
    /** Majuscules sans `I` ni `O`. */
    public const MAJUSCULES = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

    /** Minuscules sans `l` ni `o`. */
    public const MINUSCULES = 'abcdefghijkmnpqrstuvwxyz';

    /** Chiffres sans `0` ni `1`. */
    public const CHIFFRES = '23456789';

    /** Longueur du mot de passe temporaire (≥ 12 exigé par le PO). */
    public const LONGUEUR_TEMPORAIRE = 14;

    /** Le code de secours : 5 groupes de 5 caractères = 25 (≥ 20 exigé), ~125 bits. */
    public const GROUPES_CODE = 5;

    public const TAILLE_GROUPE = 5;

    /**
     * Un mot de passe temporaire : au moins une majuscule, une minuscule et un
     * chiffre, mélangés (Fisher-Yates sur `random_int`).
     */
    public static function motDePasseTemporaire(): string
    {
        $tous = self::MAJUSCULES.self::MINUSCULES.self::CHIFFRES;
        $caracteres = [
            self::tirer(self::MAJUSCULES),
            self::tirer(self::MINUSCULES),
            self::tirer(self::CHIFFRES),
        ];

        while (count($caracteres) < self::LONGUEUR_TEMPORAIRE) {
            $caracteres[] = self::tirer($tous);
        }

        for ($i = count($caracteres) - 1; $i > 0; $i--) {
            $j = random_int(0, $i);
            [$caracteres[$i], $caracteres[$j]] = [$caracteres[$j], $caracteres[$i]];
        }

        return implode('', $caracteres);
    }

    /**
     * Un code de secours lisible : `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`, majuscules
     * et chiffres sans ambiguïté (32 symboles : 5 bits par caractère).
     */
    public static function codeDeSecours(): string
    {
        $alphabet = self::MAJUSCULES.self::CHIFFRES;
        $groupes = [];

        for ($g = 0; $g < self::GROUPES_CODE; $g++) {
            $groupe = '';
            for ($i = 0; $i < self::TAILLE_GROUPE; $i++) {
                $groupe .= self::tirer($alphabet);
            }
            $groupes[] = $groupe;
        }

        return implode('-', $groupes);
    }

    /**
     * La forme comparée d'un code saisi : majuscules, sans tiret ni espace.
     * Le code se recopie souvent avec ou sans ses tirets.
     */
    public static function normaliserCode(string $saisie): string
    {
        return strtoupper((string) preg_replace('/[\s\-]+/', '', $saisie));
    }

    private static function tirer(string $alphabet): string
    {
        return $alphabet[random_int(0, strlen($alphabet) - 1)];
    }
}
