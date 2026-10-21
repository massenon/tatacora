<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Planning;
use App\Domain\Rh\Models\Service;
use App\Domain\Rh\Services\PlanningService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Les créneaux de planning (M13, EF-M13-02) saisis sur un poste — 21/10/2026.
 *
 * Par `PlanningService::planifier`, et lui seul : RG-13 sous verrou (deux postes
 * ne planifient jamais le même employé sur le même créneau — le second est
 * REJETÉ, comme pour les contrats de location), et un employé en congé validé
 * n'est pas planifiable. Un créneau se crée, il ne se modifie pas.
 */
final class GestionnairePlannings extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly PlanningService $plannings,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'plannings';
    }

    public function module(): string
    {
        return 'M13';
    }

    public function serviceDomaine(): string
    {
        return PlanningService::class;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return Planning::query()->whereKey($entiteId)->exists() ? $this->resultat($entiteId) : null;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'employe_id' => ['required', 'string'],
            'service_id' => ['required', 'string'],
            // Le service est reconnu par son identifiant, à défaut par son
            // LIBELLÉ (le référentiel est semé des deux côtés, sous des
            // identifiants différents tant que le poste n'a rien reçu) —
            // comme pour un employé.
            'service_libelle' => ['nullable', 'string'],
            'date' => ['required', 'date_format:Y-m-d'],
            'heure_debut' => ['required', 'date_format:H:i'],
            'heure_fin' => ['required', 'date_format:H:i', 'after:heure_debut'],
        ]);

        $employe = Employe::find($this->resoudre('employes', $donnees['employe_id']));

        if ($employe === null) {
            throw new RuntimeException(__('sync.rh.employe_inconnu_planning'));
        }

        $service = Service::find($this->resoudre('services', $donnees['service_id']));

        if ($service === null && filled($donnees['service_libelle'] ?? null)) {
            $service = Service::query()->where('libelle', trim((string) $donnees['service_libelle']))->first();
        }

        if ($service === null) {
            throw new RuntimeException(__('sync.rh.service_inconnu_planning'));
        }

        $this->plannings->planifier([
            'id' => $entiteId,
            'employe_id' => $employe->id,
            'service_id' => $service->id,
            'date' => $donnees['date'],
            'heure_debut' => $donnees['heure_debut'],
            'heure_fin' => $donnees['heure_fin'],
        ]);

        return $this->resultat($entiteId);
    }
}
