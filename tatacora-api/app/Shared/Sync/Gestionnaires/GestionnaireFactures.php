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
use App\Shared\Sync\Support\DocumentsDesAutresPostes;
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
 * ## Modification : l'ANNULATION ou l'AVOIR PARTIEL, par avoir (RG-03)
 *
 * `statut: annulee` + `motif` → `emettreAvoir` du TTC entier ; le numéro
 * `AV-` de l'avoir est rendu (`numero_avoir`). Tout autre champ : refusé.
 *
 * `montant` + `motif` (sans `statut`, 21/10/2026) → `emettreAvoir` du montant
 * saisi, en francs entiers, comme « Émettre un avoir » de la PWA : la règle est
 * celle du SERVICE — un avoir n'excède jamais le TTC de sa facture, il peut
 * s'ajouter à d'autres (le service ne les cumule pas). `avoir_id` (facultatif)
 * est l'identifiant de l'avoir sur le poste : l'avoir naît sous cet UUID, un
 * rejeu ne le double pas, et le numéro rendu (`numero_avoir`, `avoir_id`) est
 * celui de CET avoir. La garde Q3 (facture d'un autre poste) ne vaut que pour
 * l'ANNULATION : un avoir partiel n'annule rien, et la PWA l'ouvre à tout compte
 * en écriture sur M2.
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
        private readonly DocumentsDesAutresPostes $autresPostes,
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
        $montant = $payload['montant'] ?? null;
        $avoirId = $payload['avoir_id'] ?? null;
        unset($payload['statut'], $payload['motif'], $payload['montant'], $payload['avoir_id']);

        if ($payload !== []) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        if ($statut === 'annulee' && $montant === null && $avoirId === null) {
            return $this->annuler($entiteId, $motif, $contexte);
        }

        if ($statut === null && $montant !== null) {
            return $this->avoirPartiel($entiteId, $montant, $motif, $avoirId, $contexte);
        }

        throw new RuntimeException(__('sync.modification_non_synchronisable'));
    }

    private function annuler(string $entiteId, string $motif, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $facture = Facture::query()->findOrFail($entiteId);

        // Rejeu : un avoir du TTC entier existe déjà — il est rendu, jamais
        // doublé. (Un avoir PARTIEL antérieur n'annule pas la facture.)
        $entier = Avoir::query()->where('facture_id', $entiteId)->where('montant', '>=', (string) $facture->montant_ttc)->exists();

        if (! $entier) {
            // Q3 (lot F6) : la facture d'un autre poste, par l'administration
            // ou le comptable seulement.
            $this->autresPostes->verifierAnnulation('factures', $entiteId, $contexte);
            $avoir = $this->emission->emettreAvoir($facture, (string) $facture->montant_ttc, $motif === '' ? __('sync.factures.motif_absent') : $motif);

            return $this->resultatAvoir($entiteId, $avoir);
        }

        return $this->resultat($entiteId);
    }

    private function avoirPartiel(string $entiteId, mixed $montant, string $motif, mixed $avoirId, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme(
            ['montant' => $montant, 'avoir_id' => $avoirId],
            ['montant' => ['required', 'integer', 'gt:0'], 'avoir_id' => ['nullable', 'uuid']],
            ['montant.integer' => __('sync.factures.avoir_montant_invalide'), 'montant.gt' => __('sync.factures.avoir_montant_invalide')],
        );

        $facture = Facture::query()->findOrFail($entiteId);

        // Rejeu : l'avoir de ce poste existe déjà sous son identifiant.
        if ($donnees['avoir_id'] !== null) {
            $existant = Avoir::query()->find($donnees['avoir_id']);

            if ($existant !== null) {
                return $this->resultatAvoir($entiteId, $existant);
            }
        }

        try {
            $avoir = $this->emission->emettreAvoir(
                $facture,
                $this->francs((int) $donnees['montant']),
                $motif === '' ? __('sync.factures.avoir_motif_absent') : $motif,
                $donnees['avoir_id'],
            );
        } catch (\InvalidArgumentException $refus) {
            // Le plafond du service (TTC) : un refus du serveur, avec SA phrase.
            throw new RuntimeException($refus->getMessage(), 0, $refus);
        }

        return $this->resultatAvoir($entiteId, $avoir);
    }

    private function resultatAvoir(string $entiteId, Avoir $avoir): EcritureSynchronisee
    {
        $facture = Facture::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId, complements: [
            'numero' => $facture->numero,
            'montant_ttc' => (string) $facture->montant_ttc,
            'numero_avoir' => $avoir->numero,
            'avoir_id' => (string) $avoir->id,
        ]);
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
