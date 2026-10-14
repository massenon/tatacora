<?php

declare(strict_types=1);

namespace App\Exports;

use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\VenteService;
use Carbon\CarbonImmutable;
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
 * Le journal des ventes en tableur.
 *
 * ## PA-119 — le classeur porte CE QUI EST AFFICHE, et il DIT son filtre
 *
 * Il recevait auparavant un tableau de FILTRES et refaisait la requete
 * lui-meme. Deux consequences : la liste exportee pouvait differer de celle
 * affichee — deux chemins de lecture, donc deux verites — et rien n'ecrivait
 * le filtre sur le document. Quelqu'un qui filtre puis exporte croit avoir
 * verifie ce qu'il envoie au comptable.
 *
 * Il recoit desormais la COLLECTION deja lue par l'ecran et la phrase qui dit
 * son filtre. Il n'interroge plus la base.
 *
 * @see RG-19 Convention d'export
 */
class VentesExport implements FromCollection, ShouldAutoSize, WithColumnFormatting, WithHeadings, WithMapping, WithStyles
{
    /** La colonne des montants, formatee en nombre — jamais en texte. */
    private const COLONNE_MONTANT = 'F';

    /** Les quatre lignes d'entete inserees avant le tableau. */
    private const LIGNES_ENTETE = 4;

    /**
     * @param  Collection<int, Vente>  $ventes
     */
    public function __construct(
        private readonly Collection $ventes,
        private readonly string $filtre,
    ) {
    }

    /**
     * @return Collection<int, Vente>
     */
    public function collection(): Collection
    {
        return $this->ventes;
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        // maitre — `historique-ventes.html` l.348 : les HUIT entetes de
        // l'export, a la lettre, « Reglement » sans accent compris.
        return [
            __('pos_pwa.document.entete_numero'),
            __('pos_pwa.document.entete_date'),
            __('pos_pwa.document.entete_poste'),
            __('pos_pwa.document.entete_table'),
            __('pos_pwa.document.entete_reglement_export'),
            __('pos_pwa.document.entete_montant'),
            __('pos_pwa.document.entete_encaisse'),
            __('pos_pwa.document.entete_statut'),
        ];
    }

    /**
     * @param  Vente  $row
     * @return list<mixed>
     */
    public function map($row): array
    {
        return [
            $row->numero,
            CarbonImmutable::parse($row->created_at)->format('d/m/Y H:i'),
            $row->point_vente,
            $row->table ?? '',
            VenteService::MODES_PAIEMENT[$row->mode_paiement] ?? $row->mode_paiement,
            // Le montant part en NOMBRE : une chaine formatee ne se totalise
            // pas dans le tableur, et c'est la premiere chose qu'on y fait.
            (float) $row->montant_total,
            $row->encaisse
                ? __('pos_pwa.journal.badge_encaissee')
                : __('pos_pwa.journal.badge_note'),
            $row->estAnnulee()
                ? __('pos_pwa.journal.statut_annulees')
                : __('pos_pwa.journal.statut_validees'),
        ];
    }

    /**
     * @return array<string, string>
     */
    public function columnFormats(): array
    {
        return [
            self::COLONNE_MONTANT => NumberFormat::FORMAT_NUMBER_COMMA_SEPARATED1,
        ];
    }

    /**
     * @return array<int|string, array<string, mixed>>
     */
    public function styles(Worksheet $sheet): array
    {
        $sheet->insertNewRowBefore(1, self::LIGNES_ENTETE);

        $sheet->setCellValue('A1', __('pwa.marque').' — '.__('pwa.enseigne_courte'));
        $sheet->setCellValue('A2', __('pos_pwa.document.journal_titre'));
        $sheet->setCellValue('A3', __('pos_pwa.document.edite_le').' : '.date('d/m/Y H:i'));
        // PA-119 — le filtre est ECRIT sur le document, pas seulement applique.
        $sheet->setCellValue('A4', __('pos_pwa.document.filtre').' : '.$this->filtre);

        $sheet->getStyle('A1')->getFont()->setBold(true)->setSize(14)->setColor(new Color('14213D'));
        $sheet->getStyle('A2')->getFont()->setBold(true)->setSize(11)->setColor(new Color('B8891E'));

        $entete = self::LIGNES_ENTETE + 1;
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
            "A{$entete}:H{$derniere}" => [
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
