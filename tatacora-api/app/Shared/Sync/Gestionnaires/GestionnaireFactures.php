<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Ventes\Models\Vente;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Factures émises sur un poste (M2) — lot F5c, décisions du Product Owner du
 * 17/10/2026 (Q2 : le poste émet une facture PROVISOIRE, le serveur attribue
 * le numéro continu, la synchronisation régularise ; « F-AAAA-NNNNN au
 * serveur »).
 *
 * ## Par `EmissionFactureService`, et lui seul
 *
 * La facture naît vide (`emettreVide`, sous l'UUID du poste, à SA date
 * d'émission, numéro `F-` alloué sous verrou), puis chaque ligne entre par
 * `ajouterLigne` au PRIX VENDU par le poste : le service ventile le hors-taxe
 * et recalcule les totaux — jamais une seconde arithmétique ici. Le résultat
 * rend le NUMÉRO (et le TTC du serveur) : le poste remplace son numéro
 * provisoire par celui-ci.
 *
 * ## L'origine de chaque ligne (`source_id`, NOT NULL)
 *
 * Hébergement (M1) → la réservation ; restaurant et bar (M4, M5) → la VENTE
 * du poste quand le serveur la détient (le panier clôturé est poussé avant
 * sa facture), sinon la facture elle-même ; location et tourisme → la
 * facture. Jamais un identifiant inventé.
 *
 * ## Le client
 *
 * Celui de la réservation, sinon celui du payload s'il est connu du serveur,
 * sinon le client « Client de passage » (une seule fiche au serveur) : une
 * facture du serveur exige un client, un client de passage n'en a pas.
 *
 * ## Modification : l'ANNULATION seulement, par avoir (RG-03)
 *
 * `statut: annulee` + `motif` → `emettreAvoir` du TTC entier ; le numéro
 * `AV-` de l'avoir est rendu (`numero_avoir`). Tout autre champ : refusé.
 */
final class GestionnaireFactures extends GestionnaireDocumentAbstrait
{
    /** Les origines du poste (`OrigineFacture`). */
    public const ORIGINES = ['pos_comptant', 'pos_sejour', 'facture_directe'];

    /** La fiche du client de passage, au serveur. */
    public const CLIENT_DE_PASSAGE = ['nom' => 'Client de passage', 'telephone' => '-', 'type_client' => 'particulier'];

    public function __construct(
        private readonly EmissionFactureService $emission,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'factures';
    }

    public function module(): string
    {
        return 'M2';
    }

    public function serviceDomaine(): string
    {
        return EmissionFactureService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function champDateDocument(): ?string
    {
        return 'date_emission';
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $facture = Facture::query()->findOrFail($entiteId);
        $avoir = Avoir::query()->where('facture_id', $entiteId)->orderBy('created_at')->first();

        return new EcritureSynchronisee($entiteId, complements: array_filter([
            'numero' => $facture->numero,
            'montant_ttc' => (string) $facture->montant_ttc,
            'numero_avoir' => $avoir?->numero,
        ], static fn (?string $v): bool => $v !== null));
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'origine' => ['required', 'in:' . implode(',', self::ORIGINES)],
            'date_emission' => ['required', 'date_format:Y-m-d'],
            'client_id' => ['nullable', 'string'],
            'reservation_id' => ['nullable', 'string'],
            'panier_id' => ['nullable', 'string'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.module' => ['required', 'in:M1,M4,M5,M8,M9'],
            'lignes.*.libelle' => ['required', 'string', 'max:255'],
            'lignes.*.prix_unitaire' => ['required', 'integer'],
            'lignes.*.quantite' => ['required', 'integer', 'min:1'],
        ]);

        $reservation = null;

        if (! empty($donnees['reservation_id'])) {
            $reservation = Reservation::find($this->resoudre('reservations', $donnees['reservation_id']));

            if ($reservation === null) {
                throw new RuntimeException(__('sync.factures.reservation_inconnue'));
            }
        }

        $vente = empty($donnees['panier_id']) ? null : Vente::find($this->resoudre('ventes', $donnees['panier_id']));

        DB::transaction(function () use ($entiteId, $donnees, $reservation, $vente): void {
            $facture = $this->emission->emettreVide($this->client($donnees, $reservation), $entiteId, (string) $donnees['date_emission']);
            $facture->update(['origine' => $donnees['origine']]);

            foreach (array_values($donnees['lignes']) as $ligne) {
                $module = (string) $ligne['module'];
                $source = match (true) {
                    $module === 'M1' && $reservation !== null => $reservation->id,
                    in_array($module, ['M4', 'M5'], true) && $vente !== null => $vente->id,
                    default => $facture->id,
                };

                $this->emission->ajouterLigne(
                    facture: $facture,
                    moduleSource: $module,
                    sourceId: (string) $source,
                    libelle: (string) $ligne['libelle'],
                    quantite: (string) $ligne['quantite'],
                    prixUnitaire: $this->francs((int) $ligne['prix_unitaire']),
                );
            }
        });

        return $this->resultat($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $statut = $payload['statut'] ?? null;
        $motif = trim((string) ($payload['motif'] ?? ''));
        unset($payload['statut'], $payload['motif']);

        if ($statut !== 'annulee' || $payload !== []) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        $facture = Facture::query()->findOrFail($entiteId);

        // Rejeu : un avoir existe déjà — il est rendu, jamais doublé.
        if (! Avoir::query()->where('facture_id', $entiteId)->exists()) {
            $this->emission->emettreAvoir($facture, (string) $facture->montant_ttc, $motif === '' ? __('sync.factures.motif_absent') : $motif);
        }

        return $this->resultat($entiteId);
    }

    /**
     * @param  array<string, mixed>  $donnees
     */
    private function client(array $donnees, ?Reservation $reservation): string
    {
        if ($reservation !== null) {
            return (string) $reservation->client_id;
        }

        if (! empty($donnees['client_id'])) {
            $client = Client::find($this->resoudre('clients', $donnees['client_id']));

            if ($client !== null) {
                return (string) $client->id;
            }
        }

        return (string) Client::query()->firstOrCreate(
            ['nom' => self::CLIENT_DE_PASSAGE['nom'], 'telephone' => self::CLIENT_DE_PASSAGE['telephone']],
            ['type_client' => self::CLIENT_DE_PASSAGE['type_client']],
        )->id;
    }
}
