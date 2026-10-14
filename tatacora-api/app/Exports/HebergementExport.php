<?php

declare(strict_types=1);

namespace App\Exports;

use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
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
 * Export tableur des deux écrans M1 — le parc d'hébergement et l'historique
 * des réservations.
 *
 * ## IL EXPORTE CE QUI EST AFFICHÉ, PAS LA TABLE (PA-119)
 *
 * L'export reçoit les IDENTIFIANTS déjà filtrés par l'écran, jamais des
 * critères qu'il rejouerait de son côté. Deux filtrages écrits à deux endroits
 * finiraient par diverger, et quelqu'un qui filtre puis exporte enverrait au
 * comptable un document qu'il croit avoir vérifié. Le libellé du filtre voyage
 * avec les lignes et s'imprime en tête de feuille : un fichier qui ne dit pas
 * son périmètre se lit comme le registre entier.
 *
 * ## AUCUN MONTANT DE SÉJOUR N'EST INVENTÉ (PA-55, PA-57)
 *
 * `reservations` ne porte que l'acompte. Le total d'un séjour n'existe nulle
 * part sur ce serveur, et le recalculer depuis la grille tarifaire courante
 * réécrirait le prix d'un séjour déjà vendu. La colonne rend le tiret que
 * l'écran affiche — la même valeur, pas une seconde vérité.
 *
 * @see EF-M1-07 Planning d'occupation
 * @see RG-19 Convention d'export
 *
 * @implements FromCollection<int, mixed>
 */
final class HebergementExport implements FromCollection, ShouldAutoSize, WithHeadings, WithMapping, WithStyles, WithTitle
{
    public const TIRET = '—';

    /**
     * @param  list<string>  $identifiants  les lignes AFFICHÉES, dans l'ordre où l'écran les montre
     * @param  string  $filtre  le filtre appliqué, imprimé en tête
     * @param  string  $type  `parc` (unités) ou `reservations` (historique)
     * @param  array<string, string>  $etats  l'état DÉJÀ DÉRIVÉ par l'écran, par identifiant.
     *                                        Il est reçu, jamais recalculé : une seconde
     *                                        dérivation finirait par contredire celle de
     *                                        l'écran sur le même jeu de lignes (PA-111,
     *                                        PA-121).
     */
    public function __construct(
        private readonly array $identifiants,
        private readonly string $filtre = '',
        private readonly string $type = 'parc',
        private readonly array $etats = [],
    ) {
    }

    public function title(): string
    {
        return $this->type === 'reservations'
            ? __('pwa.reservations.hist_titre')
            : __('pwa.hebergement.onglet_plan');
    }

    /**
     * @return Collection<int, mixed>
     */
    public function collection(): Collection
    {
        if ($this->identifiants === []) {
            return collect();
        }

        // `orderByRaw(FIELD(...))` conserverait l'ordre de l'écran mais
        // concaténerait des identifiants dans du SQL. Le tri se fait donc en
        // mémoire, sur la liste déjà bornée par l'écran.
        $rang = array_flip($this->identifiants);

        $lignes = $this->type === 'reservations'
            ? Reservation::with(['client', 'unite.categorie'])->findMany($this->identifiants)
            : UniteHebergement::with('categorie')->findMany($this->identifiants);

        return $lignes
            ->sortBy(static fn (object $ligne): int => $rang[$ligne->id] ?? PHP_INT_MAX)
            ->values()
            ->toBase();
    }

    /**
     * @return list<string>
     */
    public function headings(): array
    {
        if ($this->type === 'reservations') {
            // Les colonnes du maître — `historique-reservations.js` l.127.
            return [
                __('pwa.reservations.hist_col_client'),
                __('pwa.reservations.hist_col_sejour'),
                __('pwa.reservations.hist_col_nuits'),
                __('pwa.reservations.hist_col_unites'),
                __('pwa.reservations.hist_col_services'),
                __('pwa.reservations.hist_col_total'),
                __('pwa.reservations.hist_col_reste'),
                __('pwa.reservations.hist_col_etat'),
            ];
        }

        return [
            __('hebergement_pwa.hebergement.champ_code'),
            __('hebergement_pwa.hebergement.champ_categorie'),
            __('pwa.hebergement.tarif_de_base'),
            __('pwa.hebergement.col_statut'),
        ];
    }

    /**
     * @param  mixed  $row
     * @return list<string|int>
     */
    public function map($row): array
    {
        if ($row instanceof Reservation) {
            return [
                // `client_id` et `unite_id` sont NOT NULL avec une clé
                // étrangère `restrictOnDelete` : la relation ne peut pas être
                // absente, et un `?->` défensif ici ferait croire l'inverse.
                $row->client->nomComplet(),
                $row->date_arrivee->format('d/m/Y').' → '.$row->date_depart->format('d/m/Y'),
                $row->nombreNuitees(),
                $row->unite->numero,
                __('hebergement_pwa.reservations.service_hebergement'),
                // Aucun montant de séjour au schéma (PA-55/PA-57) : le tiret de
                // l'écran, jamais un chiffre reconstitué.
                self::TIRET,
                self::TIRET,
                $this->etats[$row->id] ?? self::TIRET,
            ];
        }

        /** @var UniteHebergement $row */
        return [
            $row->numero,
            $row->categorie->libelle,
            (string) $row->categorie->tarif_base,
            $row->statut,
        ];
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    public function styles(Worksheet $sheet): array
    {
        // Le filtre voyage AVEC le fichier : sans lui, le lecteur ne peut pas
        // savoir si le document couvre le registre ou une tranche (PA-119).
        if ($this->filtre !== '') {
            $sheet->insertNewRowBefore(1, 1);
            $sheet->setCellValue('A1', __(
                $this->type === 'reservations'
                    ? 'hebergement_pwa.reservations.export_filtre'
                    : 'hebergement_pwa.hebergement.export_filtre',
                ['filtre' => $this->filtre],
            ));
        }

        $entete = $this->filtre === '' ? 1 : 2;

        return [
            $entete => [
                'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF'], 'size' => 11],
                'fill' => ['fillType' => Fill::FILL_SOLID, 'startColor' => ['rgb' => '14213D']],
                'alignment' => ['vertical' => Alignment::VERTICAL_CENTER],
            ],
        ];
    }
}
