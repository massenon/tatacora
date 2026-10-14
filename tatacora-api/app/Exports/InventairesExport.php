<?php

declare(strict_types=1);

namespace App\Exports;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Services\FicheStockService;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Maatwebsite\Excel\Concerns\FromCollection;
use Maatwebsite\Excel\Concerns\ShouldAutoSize;
use Maatwebsite\Excel\Concerns\WithHeadings;
use Maatwebsite\Excel\Concerns\WithMapping;
use Maatwebsite\Excel\Concerns\WithStyles;
use Maatwebsite\Excel\Concerns\WithTitle;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;

/**
 * Exportation Excel (.xlsx) pour la Fiche de Stock (M6).
 *
 * ⚠ Corrigé le 31/08/2026 : `collection()` appelait
 * `pourArticle(article:, dateDebut:, dateFin:)`. AUCUN de ces trois noms
 * n'existe — la signature réelle est `pourArticle($article, $debut, $fin,
 * $pointId)`. Tout export « Excel » de la fiche de stock levait donc une
 * `ArgumentCountError` au premier clic. Personne ne l'avait vu : la classe
 * n'était atteinte que derrière un `class_exists()`, et l'écran qui l'appelait
 * répondait 500 avant d'arriver jusqu'ici.
 *
 * Le point de stockage est désormais transmis : sans lui, l'export d'une fiche
 * filtrée sur le bar aurait rendu les mouvements de TOUS les points, sous le
 * même titre (PA-119).
 */
class InventairesExport implements FromCollection, WithHeadings, WithMapping, ShouldAutoSize, WithStyles, WithTitle
{
    public function __construct(
        protected string $articleId = '',
        protected string $debut = '',
        protected string $fin = '',
        protected ?string $pointId = null,
    ) {
    }

    public function title(): string
    {
        return 'Fiche de Stock';
    }

    /**
     * @return Collection<int, array{date: string, type: string, motif: string, entree: string, sortie: string, solde: string}>
     */
    public function collection(): Collection
    {
        $article = Article::find($this->articleId) ?? Article::first();

        if (! $article instanceof Article) {
            return collect([]);
        }

        $fiche = app(FicheStockService::class)->pourArticle(
            $article,
            $this->debut !== '' ? $this->debut : now()->subDays(29)->toDateString(),
            $this->fin !== '' ? $this->fin : now()->toDateString(),
            $this->pointId,
        );

        return collect($fiche['lignes']);
    }

    public function headings(): array
    {
        return [
            'Date & Heure',
            'Motif / Origine',
            'Entrée',
            'Sortie',
            'Solde Progressif',
        ];
    }

    public function map($l): array
    {
        return [
            CarbonImmutable::parse($l['date'])->format('d/m/Y H:i'),
            $l['motif'],
            $l['entree'] > 0 ? (float)$l['entree'] : 0,
            $l['sortie'] > 0 ? (float)$l['sortie'] : 0,
            (float)$l['solde'],
        ];
    }

    public function styles(Worksheet $sheet): array
    {
        $sheet->getStyle('C')->getAlignment()->setHorizontal(Alignment::HORIZONTAL_RIGHT);
        $sheet->getStyle('D')->getAlignment()->setHorizontal(Alignment::HORIZONTAL_RIGHT);
        $sheet->getStyle('E')->getAlignment()->setHorizontal(Alignment::HORIZONTAL_RIGHT);

        return [
            1 => [
                'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF'], 'size' => 11],
                'fill' => ['fillType' => Fill::FILL_SOLID, 'startColor' => ['rgb' => '14213D']],
                'alignment' => ['vertical' => Alignment::VERTICAL_CENTER],
            ],
        ];
    }
}
