<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Rh\Models\BulletinPaie;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Services\BulletinPaieService;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Les bulletins de paie établis sur un poste (M13) — audit de couverture du
 * 18/10/2026.
 *
 * Le serveur RECALCULE : `BulletinPaieService::etablirBulletin`, avec SON
 * barème et SES paramètres, sous l'UUID du poste ; le numéro est le sien,
 * rendu au poste. Un bulletin existe déjà pour cet employé et ce mois (un
 * autre poste, la PWA) : FUSION, jamais un second. Le net du poste diffère
 * du serveur : le serveur fait foi, l'écart est SIGNALÉ. Modification :
 * l'annulation seulement (`statut: annulee` + motif).
 */
final class GestionnaireBulletinsPaie extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly BulletinPaieService $bulletins,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'bulletins_paie';
    }

    public function module(): string
    {
        return 'M13';
    }

    public function serviceDomaine(): string
    {
        return BulletinPaieService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $bulletin = BulletinPaie::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId, complements: [
            'numero' => (string) $bulletin->numero,
            'net_a_payer' => (string) $bulletin->net_a_payer,
            'statut_bulletin' => (string) $bulletin->statut,
        ]);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'employe_id' => ['required', 'string'],
            'periode' => ['required', 'regex:/^\d{4}-\d{2}$/'],
            'net_a_payer' => ['nullable', 'integer'],
        ]);

        $employe = Employe::find($this->resoudre('employes', $donnees['employe_id']));

        if ($employe === null) {
            throw new RuntimeException(__('sync.rh.employe_inconnu'));
        }

        $bulletin = $this->bulletins->etablirBulletin($employe, (string) $donnees['periode'], $entiteId);

        if ((string) $bulletin->id !== $entiteId) {
            return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $bulletin->id);
        }

        if (isset($donnees['net_a_payer'])
            && bccomp($this->francs((int) $donnees['net_a_payer']), (string) $bulletin->net_a_payer, 2) !== 0) {
            $this->anomalies->signaler(
                $contexte,
                $this->table(),
                $entiteId,
                AnomalieSynchronisation::BULLETIN_ECART_NET,
                valeurPoste: $this->francs((int) $donnees['net_a_payer']),
                valeurServeur: (string) $bulletin->net_a_payer,
            );
        }

        return $this->resultat($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $statut = $payload['statut'] ?? null;
        $motif = trim((string) ($payload['motif'] ?? ''));
        unset($payload['statut'], $payload['motif']);

        if ($statut !== BulletinPaie::STATUT_ANNULEE || $payload !== []) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        $bulletin = BulletinPaie::query()->findOrFail($entiteId);

        if (! $bulletin->estAnnule()) {
            $this->bulletins->annulerBulletin($bulletin, $motif === '' ? __('sync.factures.motif_absent') : $motif);
        }

        return $this->resultat($entiteId);
    }
}
