<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Support;

use Illuminate\Support\Carbon;

/**
 * Les petites règles de MISE EN PAGE de la proforma, en un seul endroit côté serveur (le poste a les
 * mêmes dans `mise_en_page_proforma.dart`, confrontées par `rejouer_proforma.php`) :
 * date longue française (« 02 Novembre 2026 ») et milliers séparés par une espace insécable.
 */
final class MiseEnPageProforma
{
    public const MOIS = [
        1 => 'Janvier', 2 => 'Février', 3 => 'Mars', 4 => 'Avril', 5 => 'Mai', 6 => 'Juin',
        7 => 'Juillet', 8 => 'Août', 9 => 'Septembre', 10 => 'Octobre', 11 => 'Novembre', 12 => 'Décembre',
    ];

    /**
     * Le vert de l'en-tête du tableau : le jeton `AppColors.vert700` du thème du poste (Tailwind green-700),
     * confronté au source Dart par `ProformaPdfTest`. dompdf ne lit pas de variable CSS : la valeur est posée
     * ICI, une seule fois, et la vue la reçoit — jamais écrite dans la vue.
     */
    public const JETON_VERT_ENTETE = '#15803D';

    public static function dateLongue(Carbon $date): string
    {
        return sprintf('%02d %s %d', $date->day, self::MOIS[$date->month], $date->year);
    }

    public static function montant(int $montant): string
    {
        return number_format($montant, 0, '', "\u{00A0}");
    }
}
