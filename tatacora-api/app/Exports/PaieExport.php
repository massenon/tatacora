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
 * Export tableur de l'écran M13 — Personnel & Paie.
 *
 * Même contrat que `TourismeExport` : les lignes viennent de l'écran, donc du
 * filtre affiché (PA-119), et les entêtes portent la casse du maître.
 *
 * ⚠ **Aucune colonne « Coût employeur » à valeur unique.** L'onglet Bulletins
 * exporte la part patronale CONFIRMÉE (19,4 %), et l'onglet Livre rend le
 * coût total sur une ligne « min — max ». Un chiffre unique dans un classeur
 * serait repris tel quel dans une déclaration : c'est précisément le refus de
 * PA-53, et un export est le dernier endroit où il pourrait se perdre.
 *
 * @see PA-119 Un export porte sur ce qui est affiché, et il DIT son filtre
 * @see PA-53 Le refus de calculer le total de charge patronale est le livrable
 */
class PaieExport implements FromArray, ShouldAutoSize, WithHeadings, WithStyles, WithTitle
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
            'bulletins' => [
                __('rh_pwa.col_matricule'),
                __('rh_pwa.col_employe'),
                __('rh_pwa.col_brut'),
                __('rh_pwa.col_cnss_salarie'),
                __('rh_pwa.col_its'),
                __('rh_pwa.col_autres_retenues'),
                __('rh_pwa.col_net'),
                __('rh_pwa.col_charges_patronales'),
            ],
            'livre' => [
                __('rh_pwa.col_rubrique'),
                __('rh_pwa.col_montant'),
            ],
            'declarations' => [
                __('rh_pwa.col_declaration'),
                __('rh_pwa.col_objet'),
                __('rh_pwa.col_montant'),
                __('rh_pwa.col_echeance'),
                __('rh_pwa.col_etat'),
            ],
            'bareme' => [
                __('rh_pwa.col_tranche'),
                __('rh_pwa.col_taux'),
                __('rh_pwa.col_impot_max'),
                __('rh_pwa.col_cumul'),
            ],
            default => [
                __('rh_pwa.col_matricule'),
                __('rh_pwa.col_employe'),
                __('rh_pwa.champ_poste'),
                __('rh_pwa.champ_service'),
                __('rh_pwa.col_contrat'),
                __('rh_pwa.col_embauche'),
                __('rh_pwa.col_cnss'),
                __('rh_pwa.col_salaire_base'),
            ],
        };
    }

    public function title(): string
    {
        return match ($this->onglet) {
            'bulletins' => __('rh_pwa.onglet_bulletins'),
            'livre' => __('rh_pwa.onglet_livre'),
            'declarations' => __('rh_pwa.onglet_declarations'),
            'bareme' => __('rh_pwa.onglet_bareme'),
            default => __('rh_pwa.onglet_personnel'),
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
