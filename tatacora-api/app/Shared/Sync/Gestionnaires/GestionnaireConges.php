<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Rh\Models\Conge;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Services\CongeService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Les demandes de congé (M13, EF-M13-04) saisies et décidées sur un poste —
 * 21/10/2026.
 *
 * Par `CongeService` : la DEMANDE est toujours acceptée (RG-14 ne porte pas sur
 * le dépôt) ; la décision est la seule modification admise — `valide` passe par
 * `valider` (préavis et couverture de service, paramétrés au serveur, jamais
 * devinés : un refus du serveur rend la décision du poste « à traiter ») et
 * `refuse` par `refuser`. Le validateur est le compte du poste qui décide.
 * Une décision déjà prise au même sens est un rejeu : acceptée, rien n'est
 * réécrit.
 */
final class GestionnaireConges extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly CongeService $conges,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'conges';
    }

    public function module(): string
    {
        return 'M13';
    }

    public function serviceDomaine(): string
    {
        return CongeService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return Conge::query()->whereKey($entiteId)->exists() ? $this->resultat($entiteId) : null;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'employe_id' => ['required', 'string'],
            'type' => ['required', 'in:' . implode(',', Conge::TYPES)],
            'date_debut' => ['required', 'date_format:Y-m-d'],
            'date_fin' => ['required', 'date_format:Y-m-d', 'after_or_equal:date_debut'],
        ]);

        $employe = Employe::find($this->resoudre('employes', $donnees['employe_id']));

        if ($employe === null) {
            throw new RuntimeException(__('sync.rh.employe_inconnu_conge'));
        }

        $this->conges->demander([
            'id' => $entiteId,
            'employe_id' => $employe->id,
            'type' => $donnees['type'],
            'date_debut' => $donnees['date_debut'],
            'date_fin' => $donnees['date_fin'],
        ]);

        return $this->resultat($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $refuses = array_diff(array_keys($payload), ['statut_validation']);

        if ($refuses !== []) {
            throw new RuntimeException(__('sync.rh.conge_champ_non_modifiable', ['champs' => implode(', ', $refuses)]));
        }

        $donnees = $this->validerForme($payload, [
            'statut_validation' => ['required', 'in:' . Conge::STATUT_VALIDE . ',' . Conge::STATUT_REFUSE],
        ]);
        $conge = Conge::query()->findOrFail($entiteId);

        // Rejeu : la décision est déjà celle-là.
        if ($conge->statut_validation === $donnees['statut_validation']) {
            return $this->resultat($entiteId);
        }

        $donnees['statut_validation'] === Conge::STATUT_VALIDE
            ? $this->conges->valider($conge, $contexte->utilisateur)
            : $this->conges->refuser($conge, $contexte->utilisateur);

        return $this->resultat($entiteId);
    }
}
