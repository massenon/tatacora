<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Rh\Models\Employe;
use App\Domain\Vehicules\Models\EntretienVehicule;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ParcVehiculeService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Les entretiens et carburations d'un véhicule (M8, EF-M8-05) saisis sur un
 * poste — « Immobiliser » de la PWA, porté au poste le 21/10/2026.
 *
 * Par `ParcVehiculeService::enregistrerEntretien`, comme l'écran. Une ligne
 * d'entretien est un FAIT daté : elle se crée, ne se modifie jamais (la PWA n'a
 * aucun geste de correction), et le statut du véhicule n'est PAS touché — c'est
 * la distinction statut / disponibilité de la PWA (RG-02).
 *
 * Le rejeu d'un même identifiant ne double rien (`reprendreExistant`).
 */
final class GestionnaireEntretiensVehicule extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly ParcVehiculeService $parc,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'entretiens_vehicule';
    }

    public function module(): string
    {
        return 'M8';
    }

    public function serviceDomaine(): string
    {
        return ParcVehiculeService::class;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return EntretienVehicule::query()->whereKey($entiteId)->exists() ? $this->resultat($entiteId) : null;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'vehicule_id' => ['required', 'string'],
            'type' => ['required', 'in:' . EntretienVehicule::TYPE_ENTRETIEN . ',' . EntretienVehicule::TYPE_CARBURATION],
            'date' => ['required', 'date_format:Y-m-d'],
            'cout' => ['required', 'integer', 'min:0'],
            'chauffeur_id' => ['nullable', 'string'],
        ]);

        $vehicule = Vehicule::find($this->resoudre('vehicules', $donnees['vehicule_id']));

        if ($vehicule === null) {
            throw new RuntimeException(__('sync.vehicules.inconnu_entretien'));
        }

        $chauffeur = null;

        if (! empty($donnees['chauffeur_id'])) {
            $chauffeur = Employe::find($this->resoudre('employes', $donnees['chauffeur_id']));

            if ($chauffeur === null) {
                throw new RuntimeException(__('sync.vehicules.chauffeur_inconnu'));
            }
        }

        $this->parc->enregistrerEntretien([
            'id' => $entiteId,
            'vehicule_id' => $vehicule->id,
            'type' => $donnees['type'],
            'date' => $donnees['date'],
            'cout' => bcadd((string) $donnees['cout'], '0', 2),
            'chauffeur_id' => $chauffeur?->id,
        ]);

        return $this->resultat($entiteId);
    }
}
