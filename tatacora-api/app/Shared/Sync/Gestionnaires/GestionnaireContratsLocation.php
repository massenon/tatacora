<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Crm\Models\Client;
use App\Domain\Numerotation\Services\SequenceDocumentService;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ContratLocationService;
use App\Pwa\Livewire\Vehicules\Locations;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Les contrats de location (M8) saisis sur un poste — audit de couverture du
 * 18/10/2026.
 *
 * Par `ContratLocationService::creer`, et lui seul : RG-08 (aucun
 * chevauchement sur le même véhicule, sous verrou — deux postes ne louent
 * jamais le même véhicule sur la même période) et RG-09 (pièces). Puis, comme
 * la PWA : le numéro `LOC-` de la séquence, statut `actif`, montant = tarif
 * du jour × jours (le poste ne saisit ni remise ni acompte : 0), reste dû =
 * montant. Les numéros de pièce et de permis viennent de la saisie du poste
 * (la charge de la file), jamais d'un fichier.
 */
final class GestionnaireContratsLocation extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly ContratLocationService $contrats,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'contrats_location';
    }

    public function module(): string
    {
        return 'M8';
    }

    public function serviceDomaine(): string
    {
        return ContratLocationService::class;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $contrat = ContratLocation::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId, complements: array_filter([
            'numero' => $contrat->getAttribute('numero'),
            'montant' => (string) $contrat->getAttribute('montant'),
        ], static fn (?string $v): bool => $v !== null));
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'vehicule_id' => ['required', 'string'],
            'client_id' => ['required', 'string'],
            'guide_id' => ['nullable', 'string'],
            'date_debut' => ['required', 'date_format:Y-m-d'],
            'date_fin' => ['required', 'date_format:Y-m-d', 'after:date_debut'],
            'piece_identite' => ['required', 'string', 'max:255'],
            'permis_conduire' => ['nullable', 'string', 'max:255'],
        ]);

        $vehicule = Vehicule::find($this->resoudre('vehicules', $donnees['vehicule_id']));

        if ($vehicule === null) {
            throw new RuntimeException(__('sync.vehicules.inconnu'));
        }

        $client = Client::find($this->resoudre('clients', $donnees['client_id']));

        if ($client === null) {
            throw new RuntimeException(__('sync.vehicules.client_inconnu'));
        }

        DB::transaction(function () use ($entiteId, $donnees, $vehicule, $client): void {
            $contrat = $this->contrats->creer([
                'id' => $entiteId,
                'vehicule_id' => $vehicule->id,
                'client_id' => $client->id,
                'guide_id' => empty($donnees['guide_id']) ? null : $this->resoudre('guides', $donnees['guide_id']),
                'date_debut' => $donnees['date_debut'],
                'date_fin' => $donnees['date_fin'],
                'piece_identite' => $donnees['piece_identite'],
                'permis_conduire' => $donnees['permis_conduire'] ?? null,
            ]);
            $jours = (int) $contrat->date_debut->diffInDays($contrat->date_fin);
            $montant = bcmul((string) $vehicule->tarif_jour, (string) $jours, 2);

            $contrat->forceFill([
                'numero' => app(SequenceDocumentService::class)->suivant('contrats_location', Locations::PREFIXE_CONTRAT),
                'statut' => 'actif',
                'montant' => $montant,
                'acompte' => '0.00',
                'reste_a_payer' => $montant,
            ])->save();
        });

        return $this->resultat($entiteId);
    }
}
