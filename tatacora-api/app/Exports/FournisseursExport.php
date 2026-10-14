<?php

declare(strict_types=1);

namespace App\Exports;

use App\Domain\Achats\Models\Fournisseur;
use App\Pwa\Livewire\Achats\Achats;
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
 * Le RÉFÉRENTIEL FOURNISSEURS en tableur (M7, EF-M7-01).
 *
 * ## Deux valeurs par défaut ont été RETIRÉES, et c'est le correctif
 *
 * Cette classe écrivait « Comptant » sur toute condition de paiement absente et
 * « Moyen » sur toute évaluation absente. Le tableur affirmait donc des faits
 * que personne n'avait saisis : un fournisseur neuf y arrivait noté « Moyen »,
 * et un fournisseur payé à 30 jours mais non renseigné y devenait « Comptant ».
 * Article 7 : « — » quand la donnée n'existe pas, jamais une valeur plausible.
 *
 * ## Les lignes viennent de l'écran, pas d'une seconde requête
 *
 * PA-119 — l'export porte sur CE QUI EST AFFICHÉ. Le filtre par évaluation que
 * cette classe rejouait était une DEUXIÈME définition du même filtre, et elle
 * ignorait la recherche et la sélection.
 *
 * @see EF-M7-01 Référentiel fournisseurs
 * @see RG-19 Convention d'export
 */
class FournisseursExport implements FromCollection, ShouldAutoSize, WithHeadings, WithMapping, WithStyles, WithTitle
{
    /**
     * @param  Collection<int, Fournisseur>  $fournisseurs  les lignes AFFICHÉES par l'écran
     */
    public function __construct(private readonly Collection $fournisseurs)
    {
    }

    public function title(): string
    {
        return __('pwa.achats.onglet_fournisseurs');
    }

    /**
     * @return Collection<int, Fournisseur>
     */
    public function collection(): Collection
    {
        return $this->fournisseurs;
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        return [
            __('pwa.achats.col_fournisseur'),
            __('pwa.achats.col_contact'),
            __('pwa.achats.col_categorie'),
            __('pwa.achats.col_conditions'),
            __('pwa.achats.col_evaluation'),
        ];
    }

    /**
     * @param  Fournisseur  $fournisseur
     * @return list<string>
     */
    public function map($fournisseur): array
    {
        return [
            (string) $fournisseur->raison_sociale,
            $fournisseur->contact ?? MontantFcfa::TIRET,
            $fournisseur->categorie ?? MontantFcfa::TIRET,
            $fournisseur->conditions_paiement ?? MontantFcfa::TIRET,
            // Le libellé du maître pour l'`enum` du schéma — la même table de
            // correspondance que l'écran, jamais une seconde.
            Achats::EVALUATIONS[$fournisseur->evaluation]['libelle'] ?? MontantFcfa::TIRET,
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
