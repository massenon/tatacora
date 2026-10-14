<?php

declare(strict_types=1);

namespace App\Pwa\Support;

/**
 * Les couleurs des cinq services — celles du maître, à UN seul endroit.
 *
 * `tableau-de-bord.js` l.31 (`COULEURS_SERVICES`) et
 * `reservations-services.js` l.40+ portent les mêmes valeurs ; les recopier
 * dans chaque vue Blade ferait diverger les pastilles d'un écran à l'autre.
 * Le fond est la couleur du maître suffixée de son alpha `15`, exactement
 * comme lui (`${couleur}15`).
 */
final class CouleursServices
{
    /**
     * @var array<string, string>
     */
    private const COULEURS = [
        'hebergement' => '#14213D',
        'restauration' => '#ED6C02',
        'bar' => '#B8891E',
        'tourisme' => '#2E7D32',
        'vehicule' => '#1D4ED8',
    ];

    public static function texte(string $service): string
    {
        // Un service inconnu rend le gris neutre de l'écran, jamais une
        // couleur d'un autre service — l'erreur doit se voir, pas se déguiser.
        return self::COULEURS[$service] ?? '#64748B';
    }

    public static function fond(string $service): string
    {
        return self::texte($service).'15';
    }

    /**
     * Les cinq tracés SVG des tuiles de service — `reservations-services.js`
     * `SERVICES[].icone` (l.40-118), au caractère près. Un seul auteur pour
     * la couleur ET le tracé : les deux naissaient dans le même objet chez le
     * maître, les séparer dans deux registres aurait fini par les désaccorder
     * (Article 10).
     *
     * @var array<string, string>
     */
    private const ICONES = [
        'hebergement' => '<path stroke-linecap="round" stroke-linejoin="round" d="M2 4v16M2 8h18a2 2 0 012 2v10M2 17h20M6 8v-1a2 2 0 012-2h2a2 2 0 012 2v1"/>',
        'restauration' => '<path stroke-linecap="round" stroke-linejoin="round" d="M3 2v7c0 1.1.9 2 2 2h1a2 2 0 002-2V2M7 2v20M17 2a5 5 0 00-5 5v6h5m0-11v20"/>',
        'bar' => '<path stroke-linecap="round" stroke-linejoin="round" d="M8 21h8M12 15v6M19 3H5l7 9 7-9z"/>',
        'tourisme' => '<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M16.24 7.76l-2.12 6.36-6.36 2.12 2.12-6.36 6.36-2.12z"/>',
        'vehicule' => '<path stroke-linecap="round" stroke-linejoin="round" d="M14 16H9m10 0h3v-3.15a1 1 0 00-.84-.99L16 11l-2.7-3.6a1 1 0 00-.8-.4H5.24a2 2 0 00-1.8 1.1l-1.14 2.28A2 2 0 002 11v4a1 1 0 001 1h1"/><circle cx="6.5" cy="16.5" r="2.5"/><circle cx="16.5" cy="16.5" r="2.5"/>',
    ];

    /** Le tracé SVG (contenu de `<svg>…</svg>`) d'un service — jamais recopié en vue. */
    public static function icone(string $service): string
    {
        return self::ICONES[$service] ?? '<circle cx="12" cy="12" r="9"/>';
    }

    /**
     * Le libellé traduit d'un service — utilisé DIRECTEMENT dans la vue
     * (`{{ CouleursServices::libelle($service) }}`), jamais affecté à une
     * variable de vue à l'intérieur d'une boucle sur `$rServices` : voir
     * `FicheReservationServices` pour la raison.
     */
    public static function libelle(string $service): string
    {
        return __(match ($service) {
            'restauration' => 'accueil_pwa.services.restauration',
            'bar' => 'accueil_pwa.services.bar',
            'tourisme' => 'accueil_pwa.services.tourisme',
            'vehicule' => 'accueil_pwa.services.vehicule',
            default => 'accueil_pwa.services.hebergement',
        });
    }

    /**
     * Le mot qui suit « + Ajouter » dans le bloc de lignes d'un service.
     * Clés LITTÉRALES via `match`, jamais concaténées : une clé dynamique
     * est invisible aux gardes i18n (défaut réel, attrapé par
     * `MessagesUtilisateurTest` le 01/09/2026).
     */
    public static function labelLigne(string $service): string
    {
        return (string) __(match ($service) {
            'restauration' => 'pwa.reservations.label_ligne_restauration',
            'bar' => 'pwa.reservations.label_ligne_bar',
            'tourisme' => 'pwa.reservations.label_ligne_tourisme',
            'vehicule' => 'pwa.reservations.label_ligne_vehicule',
            default => 'pwa.reservations.label_ligne_hebergement',
        });
    }
}
