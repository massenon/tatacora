<?php

declare(strict_types=1);

namespace App\Pwa\Support;

/**
 * LES classes des boutons d'onglets — directive du Product Owner (retour
 * d'audit du 01/09/2026), au caractère près :
 *
 *   Inactif : `onglet-app px-3.5 py-2 rounded-lg text-[13px] font-semibold
 *              transition-all cursor-pointer bg-white text-slate-500 border
 *              border-slate-200 hover:bg-slate-50`
 *   Actif   : `onglet-app px-3.5 py-2 rounded-lg text-[13px] font-semibold
 *              transition-all cursor-pointer bg-[var(--navy)] text-white
 *              shadow-sm`
 *
 * C'est une DÉROGATION D'UNIFORMISATION, de la même famille que les entêtes
 * de tableaux bleu nuit (PA-168 (9)) : le maître varie ses onglets d'une page
 * à l'autre (`onglet px-3.5 py-2` en M10/M13, `px-4 py-2.5 text-[15px]` en
 * M1/M3…), le Product Owner impose UNE forme partout. Ne pas « corriger »
 * vers la variante locale du maître : la directive prévaut
 * (DIRECTIVE_CONFORMITE_100.md, l'arbitre du dépôt).
 *
 * UN SEUL AUTEUR : chaque vue appelait sa propre lambda `$classeOnglet`, et
 * neuf définitions écrites à neuf endroits avaient déjà divergé — c'est le
 * défaut que la règle « un référentiel a un seul auteur » nomme.
 */
final class Onglets
{
    public const ACTIF = 'onglet-app px-3.5 py-2 rounded-lg text-[13px] font-semibold transition-all cursor-pointer bg-[var(--navy)] text-white shadow-sm';

    public const INACTIF = 'onglet-app px-3.5 py-2 rounded-lg text-[13px] font-semibold transition-all cursor-pointer bg-white text-slate-500 border border-slate-200 hover:bg-slate-50';

    public static function classes(bool $actif): string
    {
        return $actif ? self::ACTIF : self::INACTIF;
    }
}
