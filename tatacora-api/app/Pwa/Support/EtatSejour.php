<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Domain\Hebergement\Models\Reservation;
use Carbon\CarbonImmutable;

/**
 * Calcul dynamique de l'état d'un séjour (À venir, En cours, Terminé, Annulé).
 */
final class EtatSejour
{
    public const A_VENIR = 'a_venir';

    public const EN_COURS = 'en_cours';

    public const TERMINE = 'termine';

    public const ANNULEE = 'annulee';

    public const HISTORIQUE = [
        self::A_VENIR => ['libelle' => 'À venir', 'classe' => 'bg-blue-50 text-blue-700'],
        self::EN_COURS => ['libelle' => 'En cours', 'classe' => 'bg-emerald-50 text-emerald-700'],
        self::TERMINE => ['libelle' => 'Terminée', 'classe' => 'bg-slate-100 text-slate-600'],
        self::ANNULEE => ['libelle' => 'Annulée', 'classe' => 'bg-red-50 text-red-700'],
    ];

    public const PLAN = [
        self::TERMINE => ['libelle' => 'Terminé', 'bg' => '#F3F4F6', 'c' => '#6B7280'],
        self::EN_COURS => ['libelle' => 'En cours', 'bg' => '#E8F5E9', 'c' => '#2E7D32'],
        self::A_VENIR => ['libelle' => 'À venir', 'bg' => '#FDF3E0', 'c' => '#B8891E'],
        self::ANNULEE => ['libelle' => 'Annulée', 'bg' => '#FDECEC', 'c' => '#C62828'],
    ];

    /**
     * Détermine l'état exact du séjour à la date de référence.
     */
    public static function de(Reservation $reservation, CarbonImmutable $aujourdHui): string
    {
        if (! $reservation->estActive()) {
            return self::ANNULEE;
        }

        $arrivee = CarbonImmutable::parse($reservation->date_arrivee->toDateString());
        $depart = CarbonImmutable::parse($reservation->date_depart->toDateString());

        if ($depart->lessThanOrEqualTo($aujourdHui)) {
            return self::TERMINE;
        }

        if ($arrivee->greaterThan($aujourdHui)) {
            return self::A_VENIR;
        }

        return self::EN_COURS;
    }
}
