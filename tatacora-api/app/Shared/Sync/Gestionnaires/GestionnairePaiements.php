<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Paiement;
use App\Domain\Facturation\Services\EncaissementFactureService;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\DocumentsDesAutresPostes;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Encaissements de facture saisis sur un poste (M2) — lot F5d, 17/10/2026.
 *
 * ## Par `EncaissementFactureService`, et lui seul
 *
 * Le paiement et sa pièce (Dr trésorerie du mode / Cr 4111) naissent dans la
 * même transaction du service, sous l'UUID du poste et à SA date. Les refus
 * du service sont ceux du poste (mode inconnu, montant nul, montant supérieur
 * au reste dû) : rendus avec leur phrase.
 *
 * ## Deux écarts admis, et SIGNALÉS
 *
 * - La facture n'est pas certifiée au serveur : la certification MECeF n'est
 *   pas lancée (PA-17), une facture d'un poste arrive « en attente ». Le
 *   poste a déjà reçu l'argent : le refuser perdrait un encaissement réel.
 *   Le paiement est écrit, l'anomalie `paiement_facture_non_certifiee` le dit.
 * - La caisse du poste n'est pas connue du serveur : le paiement entre dans
 *   la caisse ouverte du serveur (`paiement_session_inconnue`). Sans aucune
 *   caisse ouverte, le service refuse — l'opération reste au poste.
 *
 * ## Modification : l'ANNULATION seulement
 *
 * `statut: annule` + `motif` → `annuler` (contre-passation de la pièce
 * entière). Tout autre champ : refusé.
 */
final class GestionnairePaiements extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly EncaissementFactureService $encaissement,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
        private readonly DocumentsDesAutresPostes $autresPostes,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'paiements';
    }

    public function module(): string
    {
        return 'M2';
    }

    public function serviceDomaine(): string
    {
        return EncaissementFactureService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function champDateDocument(): ?string
    {
        return 'date_paiement';
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $paiement = Paiement::query()->findOrFail($entiteId);
        $anomalies = array_values(array_unique(array_column($this->anomalies->duDocument($this->table(), $entiteId), 'type')));

        return new EcritureSynchronisee($entiteId, complements: [
            'statut_paiement' => (string) $paiement->statut,
            ...($anomalies !== [] ? ['anomalies' => $anomalies] : []),
        ]);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'facture_id' => ['required', 'string'],
            'session_id' => ['nullable', 'string'],
            'mode_paiement' => ['required', 'string'],
            'montant' => ['required', 'integer'],
            'date_paiement' => ['nullable', 'date'],
        ]);

        $facture = Facture::find($this->resoudre('factures', $donnees['facture_id']));

        if ($facture === null) {
            throw new RuntimeException(__('sync.paiements.facture_inconnue'));
        }

        $sessionCitee = empty($donnees['session_id']) ? null : (string) $this->resoudre('sessions_caisse', $donnees['session_id']);
        $sessionConnue = $sessionCitee !== null && SessionCaisse::query()->whereKey($sessionCitee)->exists();

        $this->encaissement->encaisser(
            facture: $facture,
            montant: $this->centiemes((int) $donnees['montant']),
            modePaiement: (string) $donnees['mode_paiement'],
            id: $entiteId,
            sessionId: $sessionConnue ? $sessionCitee : null,
            quand: $this->dateDuDocument($donnees['date_paiement'] ?? null, $contexte),
            nonFigeeAdmise: true,
        );

        if (! $facture->estFigee()) {
            $this->anomalies->signaler($contexte, $this->table(), $entiteId, AnomalieSynchronisation::PAIEMENT_FACTURE_NON_CERTIFIEE, details: [
                'facture_id' => $facture->id,
                'statut_facture' => (string) $facture->statut,
            ]);
        }

        if (! $sessionConnue) {
            $this->anomalies->signaler($contexte, $this->table(), $entiteId, AnomalieSynchronisation::PAIEMENT_SESSION_INCONNUE, details: [
                'session_citee' => $donnees['session_id'] ?? null,
            ]);
        }

        return $this->resultat($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $statut = $payload['statut'] ?? null;
        $motif = trim((string) ($payload['motif'] ?? ''));
        unset($payload['statut'], $payload['motif']);

        if ($statut !== 'annule' || $payload !== []) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        $paiement = Paiement::query()->findOrFail($entiteId);

        // Rejeu : déjà annulé — rendu, jamais contre-passé deux fois.
        if ($paiement->statut !== 'annule') {
            // Q3 (lot F6) : l'encaissement d'un autre poste, par
            // l'administration ou le comptable seulement.
            $this->autresPostes->verifierAnnulation('paiements', $entiteId, $contexte);
            $this->encaissement->annuler($paiement, $motif === '' ? __('sync.factures.motif_absent') : $motif);
        }

        return $this->resultat($entiteId);
    }
}
