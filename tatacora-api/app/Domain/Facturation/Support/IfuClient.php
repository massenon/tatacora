<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Support;

/**
 * L'IFU du CLIENT d'une facture — décision du PO du 07/11/2026 (point 2).
 *
 * UNE règle, au web comme au poste (miroir : `ifu_client.dart`) :
 *  - FACULTATIF : vide = client sans IFU (le boîtier — `buyer_ifu` facultatif — et
 *    e-MECeF — `client.ifu` facultatif — l'acceptent) ;
 *  - renseigné : EXACTEMENT 13 chiffres (espaces et séparateurs de saisie ôtés).
 *
 * Le nom envoyé à la normalisation d'un client sans IFU est « Client divers » si
 * aucun nom n'est saisi.
 */
final class IfuClient
{
    public const FORMAT = '/^[0-9]{13}$/';

    /** Retire les espaces, points et tirets d'une saisie ; `null` si rien ne reste. */
    public static function nettoyer(?string $saisie): ?string
    {
        $propre = preg_replace('/[\s.\-]+/u', '', trim((string) $saisie)) ?? '';

        return $propre === '' ? null : $propre;
    }

    /** Vide (null) = valide ; sinon exactement 13 chiffres. */
    public static function valide(?string $saisie): bool
    {
        $propre = self::nettoyer($saisie);

        // `strlen` : `$` accepte un retour à la ligne final.
        return $propre === null || (strlen($propre) === 13 && preg_match(self::FORMAT, $propre) === 1);
    }

    /** Le nom de l'acheteur à la normalisation : celui saisi, sinon « Client divers ». */
    public static function nomPourNormalisation(?string $nom, ?string $repli = null): string
    {
        $net = trim((string) $nom);

        if ($net !== '') {
            return mb_substr($net, 0, 100);
        }

        return $repli !== null && trim($repli) !== '' ? mb_substr(trim($repli), 0, 100) : __('facturation.ifu_client.nom_divers');
    }
}
