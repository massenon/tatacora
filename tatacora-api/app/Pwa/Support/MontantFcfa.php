<?php

declare(strict_types=1);

namespace App\Pwa\Support;

/**
 * Mise en forme exacte et sans flottant des montants monétaires en Francs CFA (XOF).
 */
final class MontantFcfa
{
    /**
     * L'insecable CLASSIQUE (U+00A0), plus la fine (U+202F) — 02/09/2026.
     *
     * La fine avait ete mesuree sur `Intl.NumberFormat('fr-FR')` du maitre,
     * et c'etait juste POUR L'ECRAN. Mais ce formateur est l'auteur unique
     * des montants, y compris ceux des treize gabarits PDF en Helvetica :
     * l'encodage WinAnsi de cette police n'a AUCUN glyphe pour U+202F, et
     * dompdf imprimait « 1?500 » sur les documents remis — constate par le
     * Product Owner sur la fiche des prix. U+00A0 existe dans WinAnsi
     * (0xA0), dans DejaVu et au navigateur : un seul separateur que toutes
     * les cibles savent rendre, plutot que deux verites selon le papier.
     * Ne jamais revenir a U+202F sans regenerer un PDF et le LIRE.
     */
    public const SEPARATEUR = "\u{00A0}";

    public const TIRET = '—';

    /**
     * Le suffixe monétaire affiché, PARTOUT — décision du Product Owner du
     * 11/09/2026 (PA-186) : « on maintient FCFA dans tout ». Il remplace le
     * « F » que la PWA écrivait jusque-là ; le client Flutter écrit le même.
     * Ne pas le raccourcir en « F » pour gagner une colonne : c'est une
     * décision, pas une abréviation de confort.
     */
    public const SUFFIXE = 'FCFA';

    /**
     * Formate un montant en XOF (arrondi à l'unité, groupes séparés par
     * l'insécable, puis une espace et « FCFA »).
     */
    public static function format(string $montant): string
    {
        return self::groupe(self::arrondi($montant)) . ' ' . self::SUFFIXE;
    }

    /**
     * Rend le montant formaté ou un tiret si le montant vaut zéro.
     */
    public static function formatOuTiret(string $montant): string
    {
        $arrondi = self::arrondi($montant);

        return bccomp($arrondi, '0', 0) === 0
            ? self::TIRET
            : self::groupe($arrondi) . ' ' . self::SUFFIXE;
    }

    /**
     * Rend le montant formaté ou une chaîne vide si le montant est égal à zéro.
     */
    public static function formatOuVide(string $montant): string
    {
        return bccomp($montant, '0.00', 2) === 0 ? '' : self::format($montant);
    }

    /**
     * Indique si un montant est strictement négatif.
     */
    public static function estNegatif(string $montant): bool
    {
        return bccomp($montant, '0.00', 2) < 0;
    }

    private static function arrondi(string $montant): string
    {
        $demi = bccomp($montant, '0', 2) < 0 ? '-0.5' : '0.5';
        $arrondi = bcadd($montant, $demi, 0);

        return $arrondi === '-0' ? '0' : $arrondi;
    }

    private static function groupe(string $entier): string
    {
        $signe = '';

        if (str_starts_with($entier, '-')) {
            $signe = '-';
            $entier = substr($entier, 1);
        }

        $morceaux = [];

        while (strlen($entier) > 3) {
            $morceaux[] = substr($entier, -3);
            $entier = substr($entier, 0, -3);
        }

        $morceaux[] = $entier;

        return $signe . implode(self::SEPARATEUR, array_reverse($morceaux));
    }
}
