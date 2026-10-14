<?php

declare(strict_types=1);

namespace App\Exports;

use App\Domain\Stocks\Services\ConsultationStockService;
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
 * Exportation Excel (.xlsx) certifiée pour la Gestion des Stocks (M6).
 */
class StocksExport implements FromCollection, WithHeadings, WithMapping, ShouldAutoSize, WithStyles, WithTitle
{
    public function __construct(
        protected ?string $pointId = null,
        protected ?string $categorie = null,
        protected ?string $suivi = null,
    ) {
    }

    public function title(): string
    {
        return 'État des Stocks';
    }

    /**
     * ⚠ `collect(...->items())`, jamais le paginateur lui-même.
     *
     * `FromCollection` attend une `Enumerable` ; un `LengthAwarePaginator` n'en
     * est pas une. Le rendre tel quel « marchait » par accident de typage dynamique,
     * et PHPStan le refusait au niveau 6.
     *
     * Le plafond vient de `ConsultationStockService`, jamais d'un nombre écrit
     * ici : deux plafonds à deux endroits finiraient par diverger, et le tableur
     * s'arrêterait silencieusement avant la liste affichée.
     *
     * @return Collection<int, \App\Domain\Stocks\ReadModels\LigneStockArticle>
     */
    public function collection(): Collection
    {
        return collect(app(ConsultationStockService::class)->listerArticles(
            categorie: $this->categorie,
            pointId: $this->pointId,
            suivi: $this->suivi,
            parPage: ConsultationStockService::PAR_PAGE_MAX,
        )->items());
    }

    public function headings(): array
    {
        return [
            'Désignation Article',
            'Catégorie',
            'Unité de Mesure',
            // PA-161 (a) — les trois colonnes du tableau du maître, dans son
            // ordre (`m6-stocks.html` l.464). Elles manquaient au fichier
            // remis au comptable alors qu'elles s'affichaient à l'écran.
            'Point',
            'Suivi',
            'Stock Calculé',
            'Seuil d\'Alerte',
            'Valeur d\'Achat (FCFA)',
            'Coût Moyen Pondéré (FCFA)',
            'Valeur Totale du Stock (FCFA)',
        ];
    }

    /**
     * ⚠ Un article en suivi journalier n'a NI stock, NI seuil, NI valeur.
     *
     * Le maître écrit « non suivi » et « — » à leur place (l.468-472), et il a
     * raison : un « 0 » dans une colonne de tableur se somme, et le total du
     * stock passerait pour exhaustif alors qu'il ignore une partie du parc.
     * La chaîne, elle, ne s'additionne pas.
     */
    public function map($ligne): array
    {
        $journalier = ! $ligne->article->estSuiviEnStock();
        $tiret = \App\Pwa\Support\MontantFcfa::TIRET;

        // ⚠ `instanceof` et non `?->` : `articles.point_stockage_id` EST
        // nullable — un article jamais réceptionné n'a pas de point — mais
        // l'analyse statique déduit du type de la relation qu'il est toujours
        // là et signale le `?->` comme inutile. Le test explicite dit la même
        // chose sans avoir à contredire l'analyseur.
        $point = $ligne->article->pointStockage;

        return [
            $ligne->article->libelle,
            $ligne->article->categorie ?? 'Général',
            $ligne->article->unite_mesure,
            $point instanceof \App\Domain\Stocks\Models\PointStockage ? $point->libelle : $tiret,
            $journalier ? 'Journalier' : 'Permanent',
            $journalier ? 'non suivi' : (float) $ligne->stock,
            $journalier ? $tiret : (float) $ligne->article->seuil_alerte,
            // `null` et non 0 : un article jamais réceptionné n'a pas de prix
            // d'achat, et « 0 F » se lirait « acheté gratuitement ».
            $ligne->article->prix_achat === null ? $tiret : (float) $ligne->article->prix_achat,
            (float) $ligne->article->cout_moyen_pondere,
            $journalier ? $tiret : (float) $ligne->valeur,
        ];
    }

    public function styles(Worksheet $sheet): array
    {
        foreach (['F', 'G', 'H', 'I', 'J'] as $colonne) {
            $sheet->getStyle($colonne)->getAlignment()->setHorizontal(Alignment::HORIZONTAL_RIGHT);
        }

        foreach (['H', 'I', 'J'] as $colonne) {
            $sheet->getStyle($colonne)->getNumberFormat()->setFormatCode('#,##0 FCFA');
        }

        return [
            1 => [
                'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF'], 'size' => 11],
                'fill' => ['fillType' => Fill::FILL_SOLID, 'startColor' => ['rgb' => '14213D']],
                'alignment' => ['vertical' => Alignment::VERTICAL_CENTER],
            ],
        ];
    }
}
