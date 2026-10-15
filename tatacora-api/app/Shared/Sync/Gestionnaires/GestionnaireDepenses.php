<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Depenses\Models\Depense;
use App\Domain\Depenses\Services\DepenseService;
use App\Shared\Sync\Services\ResolveurCentresCout;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * Dépenses courantes saisies hors connexion (M10, niveau C — celui de l'écran
 * `Depenses::enregistrerDepense`) — lot S3, décision du Product Owner du
 * 15/10/2026.
 *
 * ## Le payload : `depenses_local` + `lignes_depense_local` du poste
 *
 * `date_transaction`, `tresorerie` (`caisse` | `momo` | `banque` — les CLÉS
 * de `DepenseService::TRESORERIES`), `libelle`, et `lignes[]` : `libelle`,
 * `compte_charge` (numéro SYSCOHADA), `nature`, `famille`, `montant` en
 * FRANCS ENTIERS. Le poste ne stocke pas de centre de coût : il le joint au
 * payload, `centre_id` + `centre_libelle`.
 *
 * ## La pièce : produite par le SERVEUR (D246)
 *
 * Par `DepenseService::enregistrer()` — pièce CAI/BQ validée dans la même
 * transaction, datée de `date_transaction`, numéro `DEP-AAAA-…` de l'année de
 * CETTE date (une dépense du 31/12 synchronisée en janvier reste dans son
 * exercice). L'écriture que le poste a passée dans son moteur local n'est
 * JAMAIS reçue : le serveur seul tient la comptabilité.
 *
 * ## Le centre de coût (RG-12) : résolu, jamais deviné
 *
 * `ResolveurCentresCout` : l'UUID s'il existe au serveur, sinon le libellé
 * normalisé. Un centre CITÉ mais introuvable refuse la dépense (imputer un
 * autre axe fausserait l'analytique en silence). Aucun centre cité : comme à
 * l'écran en ligne, le centre par défaut du compte s'applique, et à défaut
 * `PasserEcritureService` refuse la pièce (RG-12).
 *
 * ## Idempotence : l'UUID du poste, vérifié dans la transaction du service.
 *
 * ## Modification : refusée — une pièce comptable se contre-passe (RG-11).
 */
final class GestionnaireDepenses extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly DepenseService $depenses,
        private readonly ResolveurCentresCout $centres,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'depenses';
    }

    public function module(): string
    {
        return 'M10';
    }

    public function serviceDomaine(): string
    {
        return DepenseService::class;
    }

    public function champDateDocument(): ?string
    {
        return 'date_transaction';
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        // Les règles de l'écran en ligne (`Depenses::enregistrerDepense`),
        // dans les unités du poste : montants en francs ENTIERS.
        $donnees = $this->validerForme($payload, [
            'date_transaction' => ['required', 'date'],
            'libelle' => ['required', 'string', 'max:255'],
            'tresorerie' => ['required', 'string', Rule::in(array_keys(DepenseService::TRESORERIES))],
            'centre_id' => ['nullable', 'string'],
            'centre_libelle' => ['nullable', 'string', 'max:255'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.libelle' => ['required', 'string', 'max:255'],
            'lignes.*.compte_charge' => ['required', 'string', 'exists:plan_comptable,numero_compte'],
            'lignes.*.nature' => ['nullable', 'string', 'max:255'],
            'lignes.*.famille' => ['nullable', 'string', 'max:255'],
            'lignes.*.montant' => ['required', 'integer', 'min:1'],
        ], [
            'lignes.required' => __('depenses.sans_ligne'),
            'lignes.min' => __('depenses.sans_ligne'),
            'tresorerie.in' => __('depenses.tresorerie_inconnue', ['code' => (string) ($payload['tresorerie'] ?? '')]),
        ]);

        $centreId = null;
        $centreCite = filled($donnees['centre_id'] ?? null) || filled($donnees['centre_libelle'] ?? null);

        if ($centreCite) {
            $centreId = $this->centres->resoudre($donnees['centre_id'] ?? null, $donnees['centre_libelle'] ?? null);

            if ($centreId === null) {
                throw new RuntimeException(__('sync.depenses.centre_introuvable', [
                    'centre' => (string) ($donnees['centre_libelle'] ?? $donnees['centre_id']),
                ]));
            }
        }

        $date = $this->dateDuDocument($donnees['date_transaction'], $contexte);

        $lignes = [];

        foreach (array_values($donnees['lignes']) as $ligne) {
            $lignes[] = [
                'compte_charge' => (string) $ligne['compte_charge'],
                'montant' => $this->francs((int) $ligne['montant']),
                'libelle' => trim((string) $ligne['libelle']),
                ...(filled($ligne['nature'] ?? null) ? ['nature' => (string) $ligne['nature']] : []),
                ...(filled($ligne['famille'] ?? null) ? ['famille' => (string) $ligne['famille']] : []),
            ];
        }

        $this->depenses->enregistrer([
            'id' => $entiteId,
            'date_transaction' => $date->toDateString(),
            'tresorerie' => (string) $donnees['tresorerie'],
            'centre_id' => $centreId,
            'libelle' => trim((string) $donnees['libelle']),
            'lignes' => $lignes,
        ], $contexte->utilisateur, $date->year);

        return $this->resultat($entiteId);
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $depense = Depense::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId, complements: [
            'numero' => $depense->numero,
            'montant_total' => (string) $depense->montant_total,
        ]);
    }
}
