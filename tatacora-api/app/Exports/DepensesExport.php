<?php

declare(strict_types=1);

namespace App\Exports;

use App\Domain\Depenses\Models\Depense;
use App\Pwa\Livewire\Depenses\Depenses as EcranDepenses;
use Illuminate\Support\Collection;
use Maatwebsite\Excel\Concerns\FromCollection;
use Maatwebsite\Excel\Concerns\ShouldAutoSize;
use Maatwebsite\Excel\Concerns\WithColumnFormatting;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithMapping;
use Maatwebsite\Excel\Concerns\WithStyles;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Border;
use PhpOffice\PhpSpreadsheet\Style\Color;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use PhpOffice\PhpSpreadsheet\Style\NumberFormat;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

/**
 * Classeur « État des dépenses courantes » (M10, RG-19).
 *
 * ## Deux défauts corrigés au lot PA-159, et le second est celui qui comptait
 *
 * 1. **Il REFAISAIT la requête.** Le constructeur recevait des *filtres* et
 *    rappelait `DepenseService::filtrer()` lui-même. Deux lectures pour un
 *    seul document : celle de l'écran et celle du fichier. Entre les deux, une
 *    dépense saisie par quelqu'un d'autre entrait dans le classeur sans
 *    apparaître à l'écran — et PA-119 dit exactement l'inverse : un export
 *    porte sur CE QUI EST AFFICHÉ. Il reçoit désormais la collection déjà lue.
 * 2. **La colonne « Statut Comptable » lisait `ecriture_refus`.** Une dépense
 *    antérieure à ce lot n'a ni écriture ni refus : elle sortait
 *    « Comptabilisée » sur le document remis au Comptable, alors qu'aucune
 *    pièce n'existait. `estComptabilisee()` lit la clé étrangère, seule preuve
 *    qu'une écriture existe réellement.
 *
 * ## Les entêtes sont ceux du MAÎTRE
 *
 * `prototype_v2/pages/depenses.js` l.316 : `['Date', 'Libellé', 'Nature',
 * 'Charge (SYSCOHADA)', 'Trésorerie', 'Montant', 'Comptabilisation']`. Ils
 * étaient huit et différents (« Numéro », « Libellé Général », « Compte
 * Trésorerie »…). Aucune règle CSS ne s'applique dans un tableur : ce qui est
 * écrit ici est ce que le comptable lit.
 *
 * ## Le PÉRIMÈTRE est écrit dans le classeur (PA-119)
 *
 * Un fichier qui ne dit pas son filtre se lit comme s'il portait tout le
 * registre.
 *
 * @see RG-19 Convention d'export
 */
class DepensesExport implements FromCollection, ShouldAutoSize, WithColumnFormatting, WithHeadings, WithMapping, WithStyles
{
    /**
     * @param  Collection<int, Depense>  $depenses  la liste DÉJÀ filtrée et affichée
     * @param  string  $filtre  le périmètre en toutes lettres
     */
    public function __construct(
        private readonly Collection $depenses,
        private readonly string $filtre = '',
    ) {
    }

    /**
     * @return Collection<int, Depense>
     */
    public function collection(): Collection
    {
        return $this->depenses;
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        return [
            __('depenses_pwa.col_date'),
            __('depenses_pwa.col_libelle'),
            __('depenses_pwa.col_nature'),
            __('depenses_pwa.col_charge'),
            __('depenses_pwa.col_tresorerie'),
            __('depenses_pwa.col_montant'),
            __('depenses_pwa.export_col_comptabilisation'),
        ];
    }

    /**
     * @param  Depense  $row
     * @return list<string|float>
     */
    public function map($row): array
    {
        $comptes = $row->lignes
            ->pluck('compte_charge')
            ->filter()
            ->unique()
            ->implode(', ');

        return [
            $row->date_transaction->format('d/m/Y'),
            (string) $row->libelle,
            EcranDepenses::valeursDistinctes($row->lignes, 'nature'),
            $comptes,
            EcranDepenses::TRESORERIES[$row->tresorerie] ?? (string) $row->tresorerie,
            // Le montant part en NOMBRE, pas en chaîne formatée : un tableur
            // qui reçoit « 12 500 F » ne peut plus l'additionner.
            (float) $row->montant_total,
            $row->estComptabilisee()
                ? __('depenses_pwa.export_comptabilisee')
                : __('depenses_pwa.export_non_comptabilisee'),
        ];
    }

    /**
     * @return array<string, string>
     */
    public function columnFormats(): array
    {
        return [
            'F' => NumberFormat::FORMAT_NUMBER_COMMA_SEPARATED1,
        ];
    }

    /**
     * @return array<int|string, array<string, mixed>>
     */
    public function styles(Worksheet $sheet): array
    {
        $sheet->insertNewRowBefore(1, 4);

        $sheet->setCellValue('A1', __('pwa.marque'));
        $sheet->setCellValue('A2', __('depenses_pwa.export_document'));
        $sheet->setCellValue('A3', __('depenses_pwa.export_titre').' — '.$this->filtre.' — '.date('d/m/Y H:i'));

        $sheet->getStyle('A1')->getFont()->setBold(true)->setSize(14)->setColor(new Color('14213D'));
        $sheet->getStyle('A2')->getFont()->setBold(true)->setSize(11)->setColor(new Color('B8891E'));

        $entete = 5;
        $derniere = $sheet->getHighestRow();

        return [
            $entete => [
                'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF']],
                'fill' => [
                    'fillType' => Fill::FILL_SOLID,
                    'startColor' => ['rgb' => '14213D'],
                ],
                'alignment' => [
                    'horizontal' => Alignment::HORIZONTAL_CENTER,
                    'vertical' => Alignment::VERTICAL_CENTER,
                ],
            ],
            "A{$entete}:G{$derniere}" => [
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
