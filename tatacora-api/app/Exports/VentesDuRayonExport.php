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
 * Export tableur de l'onglet « Ventes du rayon » — bar (M5) ou restaurant (M4).
 *
 * Ajout du 03/09/2026 (demande du Product Owner) : l'onglet de ventes, livré le
 * matin même, n'avait aucun export ; le bouton « Exporter » de l'écran rendait
 * la CARTE quel que soit l'onglet ouvert.
 *
 * ## Une classe, pas deux — et le titre passe par le constructeur
 *
 * `CarteExport` a deux filles (`CarteBarExport`, `CarteRestaurantExport`) qui
 * ne diffèrent QUE par `title()`. Deux classes pour une chaîne : on n'en écrit
 * pas deux de plus ici. Le libellé du rayon vient d'`EcranDeCarte::
 * libelleDesVentes()`, la même clé de langue que l'onglet — la nommer ici, en
 * dur, ferait un second endroit où « Ventes du Bar » s'écrit.
 *
 * ## Il exporte CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
 *
 * Il n'interroge PAS la base : il reçoit la matrice déjà filtrée par l'écran
 * (`requeteDesVentes()`, la requête du tableau) et les deux phrases que
 * l'écran affiche — le filtre appliqué et le compteur « N ligne(s) · Total
 * validé : X ». Refaire la requête ici aurait donné deux lectures, donc deux
 * vérités, et c'est le classeur envoyé au comptable qui aurait menti.
 *
 * ## Les montants sont des CHAÎNES, délibérément
 *
 * `MontantFcfa::format()` est l'auteur unique des montants de ce dossier
 * (séparateur U+00A0), et `CarteExport` fait déjà de même. Le classeur ne les
 * totalise donc pas tout seul : le total validé de l'écran est écrit en clair
 * en tête, ligne « Résumé », plutôt que laissé à recalculer — un total refait
 * dans le tableur exclurait ou inclurait les annulations selon la main qui le
 * pose, et le nôtre exclut les annulations (RG-02 : elles restent listées).
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see PA-119 Un export porte sur ce qui est affiché, et il DIT son filtre
 * @see RG-19 Convention d'export
 */
final class VentesDuRayonExport implements FromArray, ShouldAutoSize, WithHeadings, WithStyles, WithTitle
{
    /**
     * @param  list<string>  $entetes entêtes calculées par l'écran, partagées avec
     *                                le document PDF pour que les deux formats ne divergent pas
     * @param  list<list<string>>  $lignes lignes DÉJÀ filtrées par l'écran
     * @param  string  $filtre description lisible du filtre appliqué
     * @param  string  $resume le compteur de l'écran : lignes retenues, total validé,
     *                         annulations exclues du total
     * @param  string  $titre le libellé du rayon — « Ventes du Bar »
     */
    public function __construct(
        private readonly array $entetes,
        private readonly array $lignes,
        private readonly string $filtre,
        private readonly string $resume,
        private readonly string $titre,
    ) {
    }

    /**
     * @return list<array<int, string>>
     */
    public function array(): array
    {
        // Le filtre puis le résumé, AVANT les données : le lecteur du fichier
        // voit sur quoi il porte et combien il totalise avant d'en tirer quoi
        // que ce soit.
        return array_merge([[$this->filtre], [$this->resume]], $this->lignes);
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        return $this->entetes;
    }

    public function title(): string
    {
        return $this->titre;
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
            3 => [
                'font' => ['bold' => true, 'size' => 9, 'color' => ['rgb' => 'B8891E']],
            ],
        ];
    }
}
