<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\TableSalle;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\PanierService;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

/**
 * L'OCCUPATION d'une table de salle par un poste — lot F6, décision du
 * Product Owner du 18/10/2026 (« il faut le créer »).
 *
 * L'occupation se DÉDUIT des paniers ouverts (`TableSalleService::estOccupee`,
 * jamais un drapeau). Un poste qui ouvre une addition sur une table envoie
 * l'ouverture de SON panier (`creation`, son UUID) ; le serveur l'inscrit
 * sous verrou de plage `(table_id, statut)` — la même discipline que
 * `PanierService::ouvrirPourPoste` — et REFUSE si la table porte déjà un
 * panier ouvert d'un autre poste ou de la PWA. Le refus revient au poste
 * (« À traiter ») : deux postes hors connexion qui ouvrent la même table, le
 * second l'apprend à la reconnexion.
 *
 * La `modification` ferme l'addition (`statut: cloture`) : sur la vente du
 * même UUID si le serveur la détient (`cloturerSurVente`), sinon sans vente
 * (`abandonner`). Fermer un panier que le serveur n'a jamais inscrit (ouverture
 * refusée) est accepté sans rien écrire : une libération n'est jamais bloquée.
 *
 * Seuls les paniers DE TABLE partent : un comptoir n'occupe rien.
 */
final class GestionnairePaniersTable extends GestionnaireAbstrait
{
    public function __construct(
        private readonly PanierService $paniers,
        private readonly ResolveurCorrespondances $correspondances,
    ) {
    }

    public function table(): string
    {
        return 'paniers';
    }

    public function module(): string
    {
        return PosComptant::MODULE;
    }

    public function serviceDomaine(): string
    {
        return PanierService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return new EcritureSynchronisee($entiteId);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $validateur = Validator::make($payload, [
            'point_vente' => ['required', 'string', 'max:50'],
            'table_id' => ['required', 'string'],
        ]);

        if ($validateur->fails()) {
            throw new RuntimeException((string) $validateur->errors()->first());
        }

        $tableId = (string) $this->correspondances->resoudre('tables_salle', (string) $payload['table_id']);
        $table = TableSalle::find($tableId);

        if ($table === null) {
            throw new RuntimeException(__('sync.tables.inconnue'));
        }

        DB::transaction(function () use ($entiteId, $payload, $table): void {
            $occupant = Panier::query()
                ->where('table_id', $table->id)
                ->where('statut', Panier::STATUT_OUVERT)
                ->lockForUpdate()
                ->first();

            if ($occupant !== null && $occupant->id !== $entiteId) {
                throw new RuntimeException(__('sync.tables.occupee', ['libelle' => $table->libelle]));
            }

            if ($occupant === null) {
                Panier::create([
                    'id' => $entiteId,
                    'reservation_id' => null,
                    'type_vente' => Panier::TYPE_COMPTANT,
                    'point_vente' => (string) $payload['point_vente'],
                    'table_id' => $table->id,
                    'statut' => Panier::STATUT_OUVERT,
                ]);
            }
        });

        return new EcritureSynchronisee($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        if (($payload['statut'] ?? null) !== Panier::STATUT_CLOTURE || array_diff(array_keys($payload), ['statut']) !== []) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        $panier = Panier::query()->findOrFail($entiteId);

        if ($panier->statut !== Panier::STATUT_CLOTURE) {
            $vente = Vente::find($entiteId);
            $vente !== null
                ? $this->paniers->cloturerSurVente($panier, $vente)
                : $this->paniers->abandonner($panier);
        }

        return new EcritureSynchronisee($entiteId);
    }

    /** Une addition dont l'ouverture a été refusée se ferme sans rien écrire. */
    public function modificationSurInconnu(string $entiteId, array $payload, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return ($payload['statut'] ?? null) === Panier::STATUT_CLOTURE ? new EcritureSynchronisee($entiteId) : null;
    }
}
