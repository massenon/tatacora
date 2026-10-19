<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\ReglementFournisseur;
use App\Domain\Achats\Services\ReglementFournisseurService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\DocumentsDesAutresPostes;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Les règlements fournisseur saisis sur un poste (M7) — audit de couverture
 * du 18/10/2026 : ils descendaient (F4) mais ne montaient pas, et l'argent
 * versé au fournisseur depuis un poste restait inconnu du serveur.
 *
 * Par `ReglementFournisseurService`, et lui seul : le règlement et sa pièce
 * (Dr 4011 / Cr trésorerie), sous l'UUID du poste, à SA date ; le reste dû
 * de la commande est recalculé. Les refus du service (trésorerie inconnue,
 * montant invalide ou supérieur au reste dû) sont rendus avec leur phrase.
 * Modification : l'ANNULATION seulement (contre-passation), règle Q3 pour
 * un règlement d'un autre poste.
 */
final class GestionnaireReglementsFournisseur extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly ReglementFournisseurService $reglements,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
        private readonly DocumentsDesAutresPostes $autresPostes,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'reglements_fournisseur';
    }

    public function module(): string
    {
        return 'M7';
    }

    public function serviceDomaine(): string
    {
        return ReglementFournisseurService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function champDateDocument(): ?string
    {
        return 'date_reglement';
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $reglement = ReglementFournisseur::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId, complements: ['statut_reglement' => (string) $reglement->statut]);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'commande_id' => ['required', 'string'],
            'montant' => ['required', 'integer'],
            'tresorerie' => ['required', 'string'],
            'date_reglement' => ['nullable', 'date_format:Y-m-d'],
        ]);

        $commande = CommandeAchat::find($this->resoudre('commandes_achat', $donnees['commande_id']));

        if ($commande === null) {
            throw new RuntimeException(__('sync.reglements.commande_inconnue'));
        }

        $this->reglements->regler(
            $commande,
            $this->centiemes((int) $donnees['montant']),
            (string) $donnees['tresorerie'],
            $entiteId,
            $this->dateDuDocument($donnees['date_reglement'] ?? null, $contexte),
        );

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

        $reglement = ReglementFournisseur::query()->findOrFail($entiteId);

        if ($reglement->statut !== 'annule') {
            $this->autresPostes->verifierAnnulation('reglements_fournisseur', $entiteId, $contexte);
            $this->reglements->annuler($reglement, $motif === '' ? __('sync.factures.motif_absent') : $motif);
        }

        return $this->resultat($entiteId);
    }
}
