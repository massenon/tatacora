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
 * Export tableur de l'écran M8 — Véhicules & Locations.
 *
 * ## Il exporte CE QUI EST AFFICHÉ, jamais la table entière (PA-119)
 *
 * La version précédente relisait `Vehicule::all()` et
 * `ContratLocation::with(...)->get()` sans reprendre un seul filtre de
 * l'écran : quelqu'un qui filtrait sur une catégorie puis exportait recevait
 * le registre complet, et l'envoyait au comptable en croyant l'avoir vérifié.
 * Les lignes sont désormais CALCULÉES PAR L'ÉCRAN et passées telles quelles ;
 * le filtre est écrit en première ligne du fichier.
 *
 * ## Les entêtes sont la casse du maître
 *
 * `Véhicule`, pas `VÉHICULE`. La classe `uppercase` du maître est une règle
 * CSS : elle ne s'applique ni au tableur ni au PDF, et une majuscule écrite en
 * dur ressort telle quelle sur le document remis.
 *
 * @see PA-119 Un export porte sur ce qui est affiché, et il DIT son filtre
 * @see RG-19 Convention d'export
 */
class LocationsExport implements FromArray, ShouldAutoSize, WithHeadings, WithStyles, WithTitle
{
    /**
     * @param  list<array<int, string>>  $lignes lignes déjà filtrées par l'écran
     * @param  string  $filtre description lisible du filtre appliqué
     */
    public function __construct(
        private readonly string $onglet,
        private readonly array $lignes,
        private readonly string $filtre,
    ) {
    }

    /**
     * Les entêtes d'un onglet — partagées avec le document PDF, pour que les
     * deux formats ne puissent pas diverger.
     *
     * @return list<string>
     */
    public static function entetesDe(string $onglet): array
    {
        return match ($onglet) {
            'parc', 'planning' => [
                __('vehicules.pwa.col_vehicule'),
                __('vehicules.pwa.col_categorie'),
                __('vehicules.pwa.col_places'),
                __('vehicules.pwa.col_permis'),
                __('vehicules.pwa.col_tarif'),
                __('vehicules.pwa.col_montant'),
                __('vehicules.pwa.col_disponibilite'),
            ],
            'immo' => [
                __('vehicules.pwa.col_vehicule'),
                __('vehicules.pwa.col_motif'),
                __('vehicules.pwa.col_du'),
                __('vehicules.pwa.champ_cout'),
                __('vehicules.pwa.col_enregistre_par'),
            ],
            default => [
                __('vehicules.pwa.col_numero'),
                __('vehicules.pwa.col_vehicule'),
                __('vehicules.pwa.col_client'),
                __('vehicules.pwa.champ_depart'),
                __('vehicules.pwa.champ_restitution'),
                __('vehicules.pwa.col_jours'),
                __('vehicules.pwa.col_montant'),
                __('vehicules.pwa.col_acompte'),
                __('vehicules.pwa.col_reste'),
                __('vehicules.pwa.col_etat'),
            ],
        };
    }

    public function title(): string
    {
        return match ($this->onglet) {
            'parc', 'planning' => __('vehicules.pwa.onglet_parc'),
            'immo' => __('vehicules.pwa.onglet_immo'),
            default => __('vehicules.pwa.onglet_contrats'),
        };
    }

    /**
     * @return list<array<int, string>>
     */
    public function array(): array
    {
        // Le filtre en première ligne, puis les données : le lecteur du
        // fichier voit sur quoi il porte avant d'en tirer un total.
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
