<?php

declare(strict_types=1);

namespace App\Exports;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Pwa\Support\MontantFcfa;
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
 * Le JOURNAL GÉNÉRAL en tableur (M10, EF-M10-06).
 *
 * ## Pourquoi « Journal » seulement, et pas les huit onglets du hub
 *
 * Le maître (`m10-syscohada.html` l.47-48) exporte « l'onglet courant » :
 * huit lectures de forme différente (journal, grand livre, balance,
 * résultat, bilan, analytique, plan comptable, clôtures), chacune portée par
 * un `ReadModel` distinct. Construire les huit tableurs dans le même lot que
 * les cinq autres écrans de ce lot aurait sacrifié la qualité de chacun à la
 * couverture du total. « Journal » est l'onglet par défaut du hub
 * (`Hub::ONGLET_DEFAUT`) : c'est ce qu'un clic sur « Excel » sans changer
 * d'onglet télécharge. `Hub::exporterExcel()` REFUSE explicitement les sept
 * autres onglets, plutôt que de produire un classeur vide ou faux sous leur
 * nom — Article 7, PA-59/60/61.
 *
 * ## Colonnes — identiques à `onglets/journal.blade.php`
 *
 * Date, compte (numéro + intitulé), libellé (et centre le cas échéant),
 * débit, crédit, statut. Zéro rendu en tiret comme l'écran (RG-19 : un
 * montant à zéro doit se voir, pas se confondre avec les vrais zéros).
 *
 * @see EF-M10-06 Édition des états réglementaires SYSCOHADA
 * @see RG-11 Les écritures restituées ici ne sont jamais modifiables
 * @see RG-19 Convention d'export
 */
class ComptabiliteJournalExport implements FromCollection, ShouldAutoSize, WithHeadings, WithMapping, WithStyles, WithTitle
{
    /**
     * @param  Collection<int, EcritureComptable>  $lignes  les lignes AFFICHÉES par l'onglet Journal
     */
    public function __construct(private readonly Collection $lignes)
    {
    }

    public function title(): string
    {
        return 'Journal';
    }

    /**
     * @return Collection<int, EcritureComptable>
     */
    public function collection(): Collection
    {
        return $this->lignes;
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        return ['Date', 'Compte', 'Intitulé', 'Libellé / centre', 'Débit', 'Crédit', 'Statut'];
    }

    /**
     * @param  EcritureComptable  $ligne
     * @return list<string>
     */
    public function map($ligne): array
    {
        $libelle = $ligne->libelle;

        if ($ligne->centre !== null) {
            $libelle .= ' · '.$ligne->centre->libelle;
        }

        return [
            $ligne->date_ecriture->format('d/m/Y'),
            (string) $ligne->compte?->numero_compte,
            (string) $ligne->compte?->libelle,
            $libelle,
            MontantFcfa::formatOuTiret($ligne->debit),
            MontantFcfa::formatOuTiret($ligne->credit),
            $ligne->statut === 'brouillon' ? 'Brouillon' : 'Validée',
        ];
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
        ];
    }
}
