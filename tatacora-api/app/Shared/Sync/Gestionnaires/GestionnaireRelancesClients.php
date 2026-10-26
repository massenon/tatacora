<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Models\RelanceClient;
use App\Domain\Crm\Services\RelanceClientService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Les relances de clients débiteurs (M3, EF-M3-03) tracées sur un poste —
 * 21/10/2026, « tout au complet » (le poste fait ce que la PWA fait).
 *
 * Par `RelanceClientService::enregistrer`, et lui seul : le canal doit être au
 * registre fermé (`RelanceClient::CANAUX`), le client connu, le montant un
 * nombre positif ou nul. Une relance est un FAIT daté — « on a réclamé tant,
 * le client a promis pour telle date » : elle se crée, ne se modifie jamais
 * (aucun geste de correction à la PWA), et n'écrit aucune pièce comptable.
 *
 * Le montant réclamé voyage en chaîne décimale (`"15000.00"`) : c'est ce qui a
 * été DIT au client ce jour-là, figé, que le solde vivant ne remplace pas.
 *
 * Le rejeu d'un même identifiant ne double rien (`reprendreExistant`).
 */
final class GestionnaireRelancesClients extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly RelanceClientService $relances,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'relances_clients';
    }

    public function module(): string
    {
        return 'M3';
    }

    public function serviceDomaine(): string
    {
        return RelanceClientService::class;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return RelanceClient::query()->whereKey($entiteId)->exists() ? $this->resultat($entiteId) : null;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'client_id' => ['required', 'string'],
            'date_relance' => ['required', 'date_format:Y-m-d'],
            'canal' => ['required', 'in:' . implode(',', RelanceClient::CANAUX)],
            'montant_reclame' => ['required', 'numeric', 'min:0'],
            'promesse' => ['nullable', 'date_format:Y-m-d'],
            'commentaire' => ['nullable', 'string', 'max:500'],
        ]);

        $client = Client::find($this->resoudre('clients', $donnees['client_id']));

        if ($client === null) {
            throw new RuntimeException(__('sync.crm.client_inconnu_relance'));
        }

        $this->relances->enregistrer([
            'id' => $entiteId,
            'client_id' => $client->id,
            'date_relance' => $donnees['date_relance'],
            'canal' => $donnees['canal'],
            'montant_reclame' => (string) $donnees['montant_reclame'],
            'promesse' => $donnees['promesse'] ?? null,
            'commentaire' => $donnees['commentaire'] ?? null,
        ]);

        return $this->resultat($entiteId);
    }
}
