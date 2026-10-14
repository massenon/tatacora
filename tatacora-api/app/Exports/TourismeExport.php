<?php

declare(strict_types=1);

namespace App\Exports;

use Maatwebsite\Excel\Concerns\FromArray;
use Maatwebsite\Excel\Concerns\ShouldAutoSize;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithStyles;
use Maatwebsite\Excel\Concerns\WithTitle;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

/**
 * Export tableur de l'écran M9 — Tourisme.
 *
 * Même contrat que `LocationsExport` : les lignes viennent de l'écran, donc
 * du filtre affiché (PA-119), et les entêtes portent la casse du maître.
 *
 * La version précédente relisait `ReservationTour::…->get()` sans reprendre un
 * filtre, et lisait `$item->acompte` — une colonne qui n'existe pas sur
 * `reservations_tour` : toutes les lignes sortaient avec un acompte de zéro
 * et un « reste à payer » égal au montant entier.
 *
 * @see PA-119 Un export porte sur ce qui est affiché, et il DIT son filtre
 */
class TourismeExport implements FromArray, ShouldAutoSize, WithHeadings, WithStyles, WithTitle
{
    /**
     * @param  list<array<int, string>>  $lignes lignes déjà filtrées par l'écran
     */
    public function __construct(
        private readonly string $onglet,
        private readonly array $lignes,
        private readonly string $filtre,
    ) {
    }

    /**
     * @return list<string>
     */
    public static function entetesDe(string $onglet): array
    {
        return match ($onglet) {
            'reservations' => [
                __('tourisme.pwa.col_numero'),
                __('tourisme.pwa.col_client'),
                __('tourisme.pwa.col_circuit'),
                __('tourisme.pwa.col_depart'),
                __('tourisme.pwa.col_personnes'),
                __('tourisme.pwa.col_prix'),
                __('tourisme.pwa.col_montant'),
                __('tourisme.pwa.col_acompte'),
                __('tourisme.pwa.col_reste'),
            ],
            'catalogue' => [
                __('tourisme.pwa.col_prestation'),
                __('tourisme.pwa.col_type'),
                __('tourisme.pwa.col_duree'),
                __('tourisme.pwa.col_zone_theme'),
                __('tourisme.pwa.col_prix_catalogue'),
                __('tourisme.pwa.col_indicatif'),
                __('tourisme.pwa.col_departs_planifies'),
            ],
            default => [
                __('tourisme.pwa.col_numero'),
                __('tourisme.pwa.col_circuit'),
                __('tourisme.pwa.col_depart'),
                __('tourisme.pwa.col_guide'),
                __('tourisme.pwa.col_vehicule'),
                __('tourisme.pwa.col_remplissage'),
                __('tourisme.pwa.col_prix'),
                __('tourisme.pwa.col_ca'),
                __('tourisme.pwa.col_etat'),
            ],
        };
    }

    public function title(): string
    {
        return match ($this->onglet) {
            'reservations' => __('tourisme.pwa.onglet_reservations'),
            'catalogue' => __('tourisme.pwa.onglet_catalogue'),
            default => __('tourisme.pwa.onglet_departs'),
        };
    }

    /**
     * @return list<array<int, string>>
     */
    public function array(): array
    {
        return array_merge([[$this->filtre]], $this->lignes);
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        return self::entetesDe($this->onglet);
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function styles(Worksheet $sheet): array
    {
        return [
            1 => [
                'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF'], 'size' => 11],
                'fill' => ['fillType' => Fill::FILL_SOLID, 'startColor' => ['rgb' => '14213D']],
                'alignment' => ['vertical' => Alignment::VERTICAL_CENTER],
            ],
            2 => [
                'font' => ['italic' => true, 'size' => 9, 'color' => ['rgb' => '64748B']],
            ],
        ];
    }
}
