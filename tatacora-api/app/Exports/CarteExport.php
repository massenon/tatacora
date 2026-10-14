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
 * Export tableur d'un écran de carte — bar (M5) ou restaurant (M4).
 *
 * Maître : `prototype_v2/pages/carte-module.js` l.393-406 (`etatCourant()`).
 * Le maître n'a qu'UN état pour les deux rayons ; seul le nom de la feuille
 * change, et c'est la seule chose que les deux classes filles portent.
 *
 * ## Il exporte CE QUI EST AFFICHÉ, jamais la table entière (PA-119)
 *
 * Les versions précédentes relisaient `CarteBoisson::with('article')->get()` et
 * `Plat::with(...)->get()` en ne reprenant QU'UN filtre de l'écran (la
 * catégorie), et jamais la recherche ni l'état. Quelqu'un qui filtrait sur
 * « sans lien de stock » puis exportait recevait la carte entière, et
 * l'envoyait au comptable en croyant l'avoir vérifiée. Les lignes sont
 * désormais CALCULÉES PAR L'ÉCRAN et passées telles quelles ; le filtre est
 * écrit en première ligne du fichier.
 *
 * ## Les entêtes sont la casse du maître
 *
 * `Article`, pas `ARTICLE`. La classe `uppercase` du maître est une règle CSS :
 * elle ne s'applique pas au tableur, et une majuscule écrite en dur ressort
 * telle quelle sur le document remis.
 *
 * @see PA-119 Un export porte sur ce qui est affiché, et il DIT son filtre
 * @see RG-19 Convention d'export
 */
abstract class CarteExport implements FromArray, ShouldAutoSize, WithHeadings, WithStyles, WithTitle
{
    /**
     * @param  list<string>  $entetes entêtes calculées par l'écran, partagées
     *                                avec le document PDF pour que les deux formats ne divergent pas
     * @param  list<list<string>>  $lignes lignes DÉJÀ filtrées par l'écran
     * @param  string  $filtre description lisible du filtre appliqué
     */
    public function __construct(
        private readonly array $entetes,
        private readonly array $lignes,
        private readonly string $filtre,
    ) {
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
        return $this->entetes;
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
