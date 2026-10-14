<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Support;

/**
 * Mise en forme FCFA pour une variable de message — `{montant}`, `{reste_du}`,
 * `{net}`.
 *
 * Une copie volontairement REDUITE de `App\Pwa\Support\MontantFcfa`, pas un
 * appel à elle : ce domaine ne dépend jamais de la couche de présentation
 * PWA (`02_SOFTWARE_ARCHITECTURE.md` §3 — un domaine ne référence que
 * `Shared/` ou lui-même), et l'API REST consommée par Flutter n'a aucune
 * raison de charger `app/Pwa/`. `bcadd`/`bcmul` évitent le flottant, comme
 * partout ailleurs dans ce dépôt.
 */
final class MontantNotification
{
    public static function format(string $montant): string
    {
        $demi = bccomp($montant, '0', 2) < 0 ? '-0.5' : '0.5';
        $arrondi = bcadd($montant, $demi, 0);
        $arrondi = $arrondi === '-0' ? '0' : $arrondi;
        $negatif = str_starts_with($arrondi, '-');
        $chiffres = ltrim($negatif ? substr($arrondi, 1) : $arrondi, '-');

        $morceaux = [];
        while (strlen($chiffres) > 3) {
            $morceaux[] = substr($chiffres, -3);
            $chiffres = substr($chiffres, 0, -3);
        }
        $morceaux[] = $chiffres;

        // La fine U+202F est CONSERVEE ici, deliberement (02/09/2026) : ce
        // formateur sert les canaux TEXTE (email, WhatsApp), rendus par les
        // clients de messagerie qui la couvrent — pas par les polices PDF de
        // dompdf, dont la lacune a fait basculer MontantFcfa vers U+00A0.
        return ($negatif ? '-' : '') . implode("\u{202F}", array_reverse($morceaux)) . ' FCFA';
    }
}
