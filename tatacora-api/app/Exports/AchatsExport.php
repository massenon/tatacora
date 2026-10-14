<?php

declare(strict_types=1);

namespace App\Exports;

use App\Domain\Achats\Models\CommandeAchat;
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
 * Les COMMANDES D'ACHAT en tableur (M7).
 *
 * ## Le classeur reçoit les lignes, il ne les rejoue pas
 *
 * PA-119 : « un export porte sur CE QUI EST AFFICHÉ ». Cette classe interrogeait
 * la base elle-même et rendait le registre ENTIER : quelqu'un qui filtrait puis
 * exportait envoyait au comptable un document qu'il croyait avoir vérifié. Les
 * lignes sont désormais celles que l'écran a construites, avec ses filtres et
 * sa sélection — une seule requête, un seul périmètre.
 *
 * ## Trois colonnes du prototype ne sont PAS écrites
 *
 * Ni numéro de bon (`commandes_achat` n'en porte aucun au schéma : en fabriquer
 * un créerait une référence introuvable partout ailleurs), ni « Réglé », ni
 * « Reste dû » — rien ne rattache un règlement à une commande d'achat dans ce
 * dépôt. Un tableur est relu hors de l'écran qui l'a produit : une colonne
 * plausible y devient un fait.
 *
 * @see EF-M7-02 Émission de commandes d'achat
 * @see RG-19 Convention d'export
 */
class AchatsExport implements FromCollection, ShouldAutoSize, WithHeadings, WithMapping, WithStyles, WithTitle
{
    /**
     * @param  Collection<int, CommandeAchat>  $commandes  les lignes AFFICHÉES par l'écran
     */
    public function __construct(private readonly Collection $commandes)
    {
    }

    public function title(): string
    {
        return __('pwa.achats.onglet_commandes');
    }

    /**
     * @return Collection<int, CommandeAchat>
     */
    public function collection(): Collection
    {
        return $this->commandes;
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        return [
            __('pwa.appro.col_numero'),
            __('pwa.achats.col_fournisseur'),
            __('pwa.achats.col_date_commande'),
            __('pwa.appro.col_lignes'),
            __('pwa.achats.col_montant_estime'),
            __('pwa.achats.col_statut'),
        ];
    }

    /**
     * @param  CommandeAchat  $commande
     * @return list<string|int|float>
     */
    public function map($commande): array
    {
        // `fournisseur_id` est NOT NULL au schema, mais la relation peut ne pas
        // etre chargee : Article 7 impose alors « — », pas une chaine vide que
        // le lecteur du tableur prendrait pour un fournisseur sans nom.
        $fournisseur = $commande->fournisseur;

        return [
            (string) $commande->id,
            $fournisseur === null ? MontantFcfa::TIRET : (string) $fournisseur->raison_sociale,
            $commande->date_commande->format('d/m/Y'),
            $commande->lignes->count(),
            // Le montant part en NOMBRE : un tableur doit pouvoir le sommer.
            // Il est calculé par `bcadd` sur les lignes, jamais lu dans une
            // colonne que rien n'écrit.
            (float) $commande->montantTotal(),
            Achats::STATUTS[$commande->statut]['libelle'] ?? (string) $commande->statut,
        ];
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function styles(Worksheet $sheet): array
    {
        $sheet->getStyle('D')->getAlignment()->setHorizontal(Alignment::HORIZONTAL_RIGHT);
        $sheet->getStyle('E')->getAlignment()->setHorizontal(Alignment::HORIZONTAL_RIGHT);
        $sheet->getStyle('E')->getNumberFormat()->setFormatCode('#,##0 "FCFA"'); // PA-186 : « FCFA » partout.

        return [
            1 => [
                'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF'], 'size' => 11],
                'fill' => ['fillType' => Fill::FILL_SOLID, 'startColor' => ['rgb' => '14213D']],
                'alignment' => ['vertical' => Alignment::VERTICAL_CENTER],
            ],
        ];
    }
}
