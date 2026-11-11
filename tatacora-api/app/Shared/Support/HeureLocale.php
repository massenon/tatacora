<?php

declare(strict_types=1);

namespace App\Shared\Support;

use Carbon\CarbonImmutable;
use DateTimeInterface;

/**
 * L'UNIQUE endroit où un INSTANT (horodatage UTC de la base) devient une heure affichée.
 *
 * Décision du PO (09/11/2026) : le web affiche l'heure LOCALE du Bénin (Africa/Porto-Novo,
 * UTC+1, sans heure d'été), comme le poste. La base et `config('app.timezone')` restent en
 * UTC — aucune migration, aucune donnée décalée : on ne convertit qu'à l'AFFICHAGE.
 *
 * Une simple DATE (un jour sans heure : date d'arrivée, échéance, jour d'un exercice) ne
 * passe JAMAIS ici : la convertir la ferait glisser d'un jour. Seuls les horodatages
 * (`created_at`, `*_le`, `date_heure`, `now()`) la traversent.
 */
final class HeureLocale
{
    public const FUSEAU_PAR_DEFAUT = 'Africa/Porto-Novo';

    /** Le fuseau d'affichage (réglable par `tatacora.fuseau_affichage`, jamais `app.timezone`). */
    public static function fuseau(): string
    {
        $fuseau = config('tatacora.fuseau_affichage', self::FUSEAU_PAR_DEFAUT);

        return is_string($fuseau) && $fuseau !== '' ? $fuseau : self::FUSEAU_PAR_DEFAUT;
    }

    /** L'instant, exprimé à l'heure locale ; `null` reste `null`. */
    public static function convertir(DateTimeInterface|string|null $instant): ?CarbonImmutable
    {
        if ($instant === null || $instant === '') {
            return null;
        }

        // Une chaîne SANS fuseau est un horodatage de la base : de l'UTC.
        $utc = $instant instanceof DateTimeInterface
            ? CarbonImmutable::instance($instant)
            : CarbonImmutable::parse($instant, 'UTC');

        return $utc->setTimezone(self::fuseau());
    }

    /** Formate un instant à l'heure locale ; `null` reste `null` (les `?? '—'` du décor tiennent). */
    public static function formater(DateTimeInterface|string|null $instant, string $format = 'd/m/Y H:i'): ?string
    {
        return self::convertir($instant)?->format($format);
    }

    /** « Maintenant », à l'heure locale. */
    public static function maintenant(): CarbonImmutable
    {
        return CarbonImmutable::now()->setTimezone(self::fuseau());
    }
}
