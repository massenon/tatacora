<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ParcVehiculeService;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

/**
 * Le parc de véhicules (M8) saisi sur un poste — audit de couverture du
 * 18/10/2026 (« tout ce que la PWA enregistre, tous les modules »).
 *
 * Par `ParcVehiculeService` : création (DISPONIBLE), retouche, et le statut
 * par ses gestes — `hors_service` = archivage (refusé si un contrat engage
 * le véhicule), `disponible` = remise en service, `entretien` (même verrou).
 * « Loué » se déduit des contrats : refusé. L'immatriculation est la clé
 * naturelle : une plaque déjà au parc FUSIONNE.
 *
 * ## Places, année, transmission (lot L3-S, 27/10/2026)
 *
 * Le poste les saisit désormais (décision du PO : « même logique que le web »)
 * et les retouche : mêmes bornes que `Locations::enregistrerVehicule` (année
 * de 1950 à l'an prochain, places de 1 à 99, transmission en texte libre).
 * Un poste d'avant la v41 n'en envoie pas : année 0 et le manque est SIGNALÉ,
 * comme avant (« ne bride pas les postes »). Dès qu'ils sont envoyés, ils sont
 * validés comme au web, jamais ignorés en silence.
 */
final class GestionnaireVehicules extends GestionnaireAbstrait
{
    public const CATEGORIES = ['voiture', '4x4', 'pickup', 'moto', 'scooter', 'velo', 'bus'];

    public function __construct(
        private readonly ParcVehiculeService $parc,
        private readonly SignalementAnomalies $anomalies,
    ) {
    }

    public function table(): string
    {
        return 'vehicules';
    }

    public function module(): string
    {
        return 'M8';
    }

    public function serviceDomaine(): string
    {
        return ParcVehiculeService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerGeste($payload, [
            'immatriculation' => ['required', 'string', 'max:255'],
            'categorie' => ['required', 'in:' . implode(',', self::CATEGORIES)],
            'tarif_jour' => ['required', 'integer', 'min:0'],
            'annee' => ['nullable', 'integer', 'min:1950', 'max:' . ((int) date('Y') + 1)],
            'capacite' => ['nullable', 'integer', 'min:1', 'max:99'],
            'transmission' => ['nullable', 'string', 'max:255'],
        ]);
        $plaque = trim((string) $donnees['immatriculation']);
        $existant = Vehicule::query()->where('immatriculation', $plaque)->first();

        if ($existant !== null) {
            return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existant->id);
        }

        $this->parc->creer([
            'immatriculation' => $plaque,
            'categorie' => $donnees['categorie'],
            'tarif_jour' => bcadd((string) $donnees['tarif_jour'], '0', 2),
            'annee' => (int) ($donnees['annee'] ?? 0),
            'capacite' => $donnees['capacite'] ?? null,
            'transmission' => $donnees['transmission'] ?? null,
        ], $entiteId);

        if (empty($donnees['annee'])) {
            $this->anomalies->signaler($contexte, 'vehicules', $entiteId, AnomalieSynchronisation::VEHICULE_SANS_ANNEE);
        }

        return new EcritureSynchronisee($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $refuses = array_diff(array_keys($payload), ['immatriculation', 'categorie', 'tarif_jour', 'statut', 'annee', 'capacite', 'transmission']);

        if ($refuses !== []) {
            throw new RuntimeException(__('sync.vehicules.champ_non_modifiable', ['champs' => implode(', ', $refuses)]));
        }

        $donnees = $this->validerGeste($payload, [
            'immatriculation' => ['sometimes', 'string', 'max:255'],
            'categorie' => ['sometimes', 'in:' . implode(',', self::CATEGORIES)],
            'tarif_jour' => ['sometimes', 'integer', 'min:0'],
            // Comme `Locations::enregistrerVehicule` : année et places sont
            // obligatoires quand elles sont soumises (jamais effacées par un
            // `null`), la transmission peut être vidée.
            'annee' => ['sometimes', 'required', 'integer', 'min:1950', 'max:' . ((int) date('Y') + 1)],
            'capacite' => ['sometimes', 'required', 'integer', 'min:1', 'max:99'],
            'transmission' => ['sometimes', 'nullable', 'string', 'max:255'],
            'statut' => ['sometimes', 'string'],
        ]);
        $vehicule = Vehicule::query()->findOrFail($entiteId);
        $statut = $donnees['statut'] ?? null;
        unset($donnees['statut']);

        if (isset($donnees['tarif_jour'])) {
            $donnees['tarif_jour'] = bcadd((string) $donnees['tarif_jour'], '0', 2);
        }

        if ($donnees !== []) {
            $this->parc->modifier($vehicule, $donnees);
        }

        if ($statut !== null && $statut !== $vehicule->refresh()->statut) {
            match ($statut) {
                'hors_service' => $this->parc->archiver($vehicule),
                'disponible' => $this->parc->remettreEnService($vehicule),
                'entretien' => $this->parc->mettreEnEntretien($vehicule),
                default => throw new RuntimeException(__('sync.vehicules.statut_non_synchronisable', ['statut' => $statut])),
            };
        }

        return new EcritureSynchronisee($entiteId);
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  array<string, mixed>  $regles
     * @return array<string, mixed>
     */
    private function validerGeste(array $payload, array $regles): array
    {
        $validateur = Validator::make($payload, $regles, [], [
            'annee' => __('vehicules.pwa.champ_annee'),
            'capacite' => __('vehicules.pwa.champ_capacite'),
            'transmission' => __('vehicules.pwa.champ_transmission'),
        ]);

        if ($validateur->fails()) {
            throw new RuntimeException((string) $validateur->errors()->first());
        }

        return $validateur->validated();
    }
}
