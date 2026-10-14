<?php

declare(strict_types=1);

namespace App\Exports;

use App\Pwa\Livewire\Crm\ClientsCreances;
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
 * Le registre CLIENTS & CRÉANCES en tableur (M3, EF-M3-04).
 *
 * ## Pourquoi ce fichier n'existait pas — et pourquoi il existe maintenant
 *
 * `ClientsCreances` refusait ses deux boutons d'export : son en-tête de
 * classe citait `LARAVEL_PWA.md` §2, qui « réserve l'exception de lecture
 * seule au seul Hub États & Rapports », et concluait que la question était
 * hors de portée d'un agent (§9). Ce motif a cessé d'être vrai le 31/08/2026 :
 * `PwaEcritureAutoriseeTest` inscrit désormais `ouvrirExport`, `genererExport`
 * et `exporterExcel` dans `METHODES_DE_LECTURE`, PARTOUT — pas seulement au
 * Hub M14 — au motif qu'un export « ne produit rien de neuf : il rend, sur un
 * autre papier, des données que l'utilisateur a déjà sous les yeux ». Le
 * même fichier note, à propos du hub Comptabilité qui attendait le même
 * correctif : « il ne manque que leur inscription au registre relu ».
 * L'audit navigateur du 01/09/2026, validé par le Product Owner, est cette
 * décision — voir `ClientsCreances::genererExport()` (ex-`exporterExcel()`,
 * renommée le 02/09/2026 lors de l'unification du bouton « Exporter »).
 *
 * ## PA-119 — les lignes viennent de l'écran, jamais d'une seconde requête
 *
 * `$clients` est EXACTEMENT `SoldeClientService::registre()` filtré comme
 * l'écran (recherche, état) : reconstruire la requête ici ferait diverger le
 * fichier et la page au premier changement de filtre.
 *
 * ## Le solde est un MAXIMUM, et le fichier le dit
 *
 * Comme l'écran (PA-21/PA-126) : aucun `Paiement` n'existe dans ce dépôt, donc
 * aucun encaissement ne peut réduire ce chiffre. Le sous-titre du classeur le
 * répète plutôt que de laisser un nombre sans sa réserve.
 *
 * @see EF-M3-04 Suivi des soldes et créances
 * @see RG-19 Convention d'export
 */
class ClientsCreancesExport implements FromCollection, ShouldAutoSize, WithHeadings, WithMapping, WithStyles, WithTitle
{
    /**
     * `list<object{...}>` décrirait la forme exacte de
     * `SoldeClientService::registre()`, mais `Collection<TValue>` n'est PAS
     * covariante (PHPStan) : la typer ainsi ferait échouer `collection()`
     * contre le retour `Collection<int, object>` qu'exige `FromCollection`.
     * `object` seul, ici ; la forme précise reste documentée sur `map()`.
     *
     * @param  list<object>  $clients  les lignes AFFICHÉES par l'écran (voir `SoldeClientService::registre()`)
     */
    public function __construct(private readonly array $clients)
    {
    }

    public function title(): string
    {
        return __('pwa.clients.titre');
    }

    /**
     * @return Collection<int, object>
     */
    public function collection(): Collection
    {
        return collect($this->clients);
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        return [
            __('pwa.clients.col_client'),
            __('pwa.clients.col_telephone'),
            __('pwa.clients.col_type'),
            __('pwa.clients.col_solde'),
            __('pwa.clients.col_pieces'),
        ];
    }

    /**
     * @param  object{nom: string, prenom: string|null, telephone: string, type_client: string, solde: string, pieces: int}  $client
     * @return list<string|int>
     */
    public function map($client): array
    {
        $nom = trim($client->nom.' '.($client->prenom ?? ''));

        return [
            $nom !== '' ? $nom : MontantFcfa::TIRET,
            $client->telephone !== '' ? $client->telephone : MontantFcfa::TIRET,
            ClientsCreances::TYPES_CLIENT[$client->type_client] ?? $client->type_client,
            MontantFcfa::format($client->solde),
            $client->pieces,
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
