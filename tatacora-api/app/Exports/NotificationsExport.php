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
 * Export tableur de l'écran M12 — Notifications.
 *
 * Même contrat que `TourismeExport` : les lignes viennent de l'écran, donc du
 * filtre affiché (PA-119), et les entêtes portent la casse du maître.
 *
 * L'onglet « file » est exportable depuis le 01/09/2026 : la file d'attente
 * est réelle (voir `App\Domain\Notifications\Services\
 * FileAttenteNotificationsService`).
 *
 * @see PA-119 Un export porte sur ce qui est affiché, et il DIT son filtre
 */
class NotificationsExport implements FromArray, ShouldAutoSize, WithHeadings, WithStyles, WithTitle
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
            'file' => [
                __('notifications_pwa.col_destinataire'),
                __('notifications_pwa.col_declencheur'),
                __('notifications_pwa.col_canal'),
                __('notifications_pwa.champ_objet'),
                __('notifications_pwa.champ_message'),
                __('notifications_pwa.col_envoi_systeme'),
            ],
            'declencheurs' => [
                __('notifications_pwa.col_declencheur'),
                __('notifications_pwa.col_public'),
                __('notifications_pwa.col_module'),
                __('notifications_pwa.col_modeles'),
                __('notifications_pwa.col_variables'),
            ],
            'canaux' => [
                __('notifications_pwa.col_canal'),
                __('notifications_pwa.col_etat'),
                __('notifications_pwa.col_blocage'),
                __('notifications_pwa.col_limite'),
                __('notifications_pwa.col_cible'),
            ],
            'journal' => [
                __('notifications_pwa.col_date'),
                __('notifications_pwa.col_destinataire'),
                __('notifications_pwa.col_declencheur'),
                __('notifications_pwa.col_canal'),
                __('notifications_pwa.col_statut'),
            ],
            default => [
                __('notifications_pwa.col_declencheur'),
                __('notifications_pwa.col_canal'),
                __('notifications_pwa.champ_objet'),
                __('notifications_pwa.champ_message'),
                __('notifications_pwa.col_etat'),
            ],
        };
    }

    public function title(): string
    {
        return match ($this->onglet) {
            'modeles' => __('notifications_pwa.onglet_modeles'),
            'declencheurs' => __('notifications_pwa.onglet_declencheurs'),
            'journal' => __('notifications_pwa.onglet_journal'),
            'canaux' => __('notifications_pwa.onglet_canaux'),
            default => __('notifications_pwa.onglet_file'),
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
