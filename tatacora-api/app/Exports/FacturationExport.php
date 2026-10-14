<?php

declare(strict_types=1);

namespace App\Exports;

use App\Domain\Facturation\Models\Facture;
use App\Pwa\Livewire\Facturation\Facturation;
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
 * Le registre FACTURATION & AVOIRS en tableur (M2, EF-M2-xx).
 *
 * ## Le motif de refus était périmé — voir `Facturation::genererExport()`
 * (ex-`exporterExcel()`, renommée le 02/09/2026, export unifié)
 *
 * `Facturation` refusait « Export Excel » (`m2-facturation.html` l.102-103)
 * en citant `LARAVEL_PWA.md` §2 : « le moteur d'états existe (RG-19) mais
 * réserve l'exception de lecture seule au seul Hub M14 ». Cette lecture a été
 * corrigée le 01/09/2026 : RG-19 gouverne le CATALOGUE d'états de M14, pas
 * les exports d'écran — `Stocks`, `Achats`, `Depenses`, `Locations`
 * appellent tous `Excel::download()` directement, sans passer par
 * `GenerateurEtatService`, et `PwaEcritureAutoriseeTest` inscrit
 * `exporterExcel`/`genererExport` comme des LECTURES depuis le 31/08/2026,
 * partout. Cette classe suit exactement le même chemin.
 *
 * ## Colonnes — identiques à l'écran, PA-119
 *
 * `Origine` et `Mode de paiement` sont rendus « — » comme l'écran : aucune
 * colonne ne les porte au schéma (voir le bloc de refus de `Facturation`).
 * Inventer une valeur ici affirmerait, dans un fichier qui part chez le
 * comptable, un fait que le serveur ne connaît pas.
 *
 * @see EF-M2 Facturation
 * @see RG-03 Immuabilité d'une facture émise — la correction passe par l'avoir
 * @see RG-19 Convention d'export
 */
class FacturationExport implements FromCollection, ShouldAutoSize, WithHeadings, WithMapping, WithStyles, WithTitle
{
    /**
     * @param  Collection<int, Facture>  $factures  les lignes AFFICHÉES par l'écran (avec `lignes`, `avoirs` chargées)
     * @param  \Illuminate\Support\Collection<string, \App\Domain\Crm\Models\Client>  $clients  indexée par `client_id`, comme l'écran
     */
    public function __construct(
        private readonly Collection $factures,
        private readonly Collection $clients,
    ) {
    }

    public function title(): string
    {
        return __('pwa.facturation.titre');
    }

    /**
     * @return Collection<int, Facture>
     */
    public function collection(): Collection
    {
        return $this->factures;
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        return [
            __('pwa.facturation.col_numero'),
            __('pwa.facturation.col_date'),
            __('pwa.facturation.col_client'),
            __('pwa.facturation.col_activites'),
            __('pwa.facturation.col_montant'),
            __('pwa.facturation.col_statut'),
        ];
    }

    /**
     * @param  Facture  $facture
     * @return list<string>
     */
    public function map($facture): array
    {
        $client = $this->clients->get($facture->client_id);
        $activites = $facture->lignes->pluck('source_module')->unique()
            ->map(static fn (string $m): string => Facturation::ACTIVITES[$m] ?? $m)
            ->implode(', ');
        $habillage = Facturation::STATUTS[$facture->statut] ?? null;

        return [
            $facture->numero_mecef ?? MontantFcfa::TIRET,
            $facture->date_emission->format('d/m/Y'),
            $client === null ? MontantFcfa::TIRET : trim(($client->prenom ?? '').' '.$client->nom),
            $activites !== '' ? $activites : MontantFcfa::TIRET,
            MontantFcfa::format((string) $facture->montant_ttc),
            $habillage['libelle'] ?? $facture->statut,
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
