<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Comptabilite\Models\Immobilisation;
use App\Domain\Comptabilite\Services\ImmobilisationService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;

/**
 * Les immobilisations (M10) saisies sur un poste — onglet « Immobilisations »
 * du hub comptable, porté au poste le 21/10/2026 (« tout au complet »).
 *
 * Par `ImmobilisationService::creer`, et lui seul : mêmes règles, mêmes
 * PHRASES (libellé, valeur d'origine strictement positive, durée d'utilité
 * obligatoire, date de mise en service valide, compte connu du plan). Le CODE
 * `IMMO-AAAA-NNNNN` est celui de la séquence du serveur : il est rendu au poste,
 * qui remplace le sien (comme le matricule d'un employé).
 *
 * Création seule : la PWA n'a aucun geste de correction ni de sortie d'une
 * immobilisation, et le plan d'amortissement est CALCULÉ, jamais stocké. Aucune
 * écriture de dotation n'est passée (voir `ImmobilisationService`) : la table
 * n'est donc pas « financière » au sens de RG-17.
 *
 * Le payload reste VOLONTAIREMENT laxiste sur la forme : un libellé vide, une
 * valeur nulle ou une durée absente doivent atteindre le service, qui les
 * refuse avec SA phrase — une validation de forme ici les remplacerait par la
 * phrase générique de `validation.php`.
 */
final class GestionnaireImmobilisations extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly ImmobilisationService $immobilisations,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'immobilisations';
    }

    public function module(): string
    {
        return 'M10';
    }

    public function serviceDomaine(): string
    {
        return ImmobilisationService::class;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return Immobilisation::query()->whereKey($entiteId)->exists() ? $this->resultat($entiteId) : null;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId, complements: [
            'code' => (string) Immobilisation::query()->findOrFail($entiteId)->code,
        ]);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'libelle' => ['nullable', 'string'],
            // Centimes entiers du poste ; le service juge le signe.
            'valeur_origine' => ['required', 'integer'],
            'duree_annees' => ['nullable', 'integer'],
            'date_mise_service' => ['nullable', 'string'],
            'compte_immobilisation' => ['nullable', 'string'],
        ]);

        $this->immobilisations->creer([
            'id' => $entiteId,
            'libelle' => $donnees['libelle'] ?? '',
            'valeur_origine' => $this->centiemes((int) $donnees['valeur_origine']),
            'duree_annees' => $donnees['duree_annees'] ?? 0,
            'date_mise_service' => $donnees['date_mise_service'] ?? '',
            'compte_immobilisation' => $donnees['compte_immobilisation'] ?? null,
        ]);

        return $this->resultat($entiteId);
    }
}
