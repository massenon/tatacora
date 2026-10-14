<?php

declare(strict_types=1);

namespace App\Exports;

use Illuminate\Support\Collection;
use Maatwebsite\Excel\Concerns\FromCollection;
use Maatwebsite\Excel\Concerns\ShouldAutoSize;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithStyles;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Border;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

/**
 * Le classeur des six rapports du tableau de bord (M11).
 *
 * Rendu par `App\Pwa\Livewire\Accueil::exporterExcel()`.
 *
 * ## LES EN-TÊTES VIENNENT DE L'APPELANT, ILS NE SONT PLUS ÉCRITS ICI
 *
 * La version précédente figeait « Indicateur Clé / Valeur / Remarque » et
 * mappait `$row['label']`, `$row['valeur']`, `$row['note']` : elle ne savait
 * exporter QUE la bande d'indicateurs, et un rapport de série mensuelle en
 * serait sorti avec trois colonnes vides sous les mauvais intitulés. Elle
 * portait aussi ses propres textes français en dur, hors de `lang/` — le
 * document remis au comptable ne pouvait donc pas dire la même chose que
 * l'écran dont il sort.
 *
 * ## AUCUN FORMAT NUMÉRIQUE IMPOSÉ SUR LES MONTANTS
 *
 * Les montants arrivent en CHAÎNE, tels que `bcadd()` les a produits. Les
 * déclarer numériques ferait convertir en flottant par PhpSpreadsheet, ce que
 * la règle projet interdit sur un montant : « 1 234 567,89 » n'a pas de
 * représentation binaire exacte, et l'écart se voit sur les totaux.
 *
 * @see RG-19 Convention d'export
 */
class DashboardExport implements FromCollection, ShouldAutoSize, WithHeadings, WithStyles
{
    /**
     * @param  list<list<string>>  $lignes
     * @param  list<string>  $entetes
     */
    public function __construct(
        private readonly array $lignes,
        private readonly array $entetes,
        private readonly string $titre,
        private readonly string $periodeLibelle,
    ) {
    }

    /**
     * @return Collection<int, list<string>>
     */
    public function collection(): Collection
    {
        return new Collection($this->lignes);
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        return $this->entetes;
    }

    /**
     * Trois lignes de cartouche, puis l'en-tête de colonnes.
     *
     * `insertNewRowBefore` décale la feuille : la ligne d'en-tête se retrouve
     * en 4, jamais en 5 — la version précédente en insérait quatre et stylait
     * la 5, c'est-à-dire la première ligne de DONNÉES.
     *
     * @return array<int|string, array<string, mixed>>
     */
    public function styles(Worksheet $feuille): array
    {
        $feuille->insertNewRowBefore(1, 3);

        $feuille->setCellValue('A1', 'TATACORA AFRIQUE — GÎTE CHEZ NOËL');
        $feuille->setCellValue('A2', $this->titre);
        $feuille->setCellValue('A3', $this->periodeLibelle);

        $feuille->getStyle('A1')->getFont()->setBold(true)->setSize(13);
        $feuille->getStyle('A2')->getFont()->setBold(true);

        $ligneEntete = 4;
        $derniere = max($ligneEntete, $feuille->getHighestRow());
        $derniereColonne = $feuille->getHighestColumn();

        return [
            $ligneEntete => [
                'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF']],
                'fill' => [
                    'fillType' => Fill::FILL_SOLID,
                    'startColor' => ['rgb' => '14213D'],
                ],
                'alignment' => [
                    'horizontal' => Alignment::HORIZONTAL_LEFT,
                    'vertical' => Alignment::VERTICAL_CENTER,
                ],
            ],
            "A{$ligneEntete}:{$derniereColonne}{$derniere}" => [
                'borders' => [
                    'allBorders' => [
                        'borderStyle' => Border::BORDER_THIN,
                        'color' => ['rgb' => 'CBD5E1'],
                    ],
                ],
            ],
        ];
    }
}
