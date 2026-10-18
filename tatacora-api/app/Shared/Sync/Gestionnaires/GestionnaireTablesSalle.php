<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Ventes\Models\TableSalle;
use App\Domain\Ventes\Services\TableSalleService;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

/**
 * Le plan de salle (`tables_salle`) créé ou retouché sur un poste — lot F6,
 * décision du Product Owner du 18/10/2026 (« il faut le créer » : l'arbitrage
 * des tables entre postes).
 *
 * Par `TableSalleService`, et lui seul : la clé naturelle (espace, numéro)
 * est unique ; une table du même espace et du même numéro saisie sur deux
 * postes FUSIONNE (`fusionne_avec`) au lieu de se doubler. Modification :
 * numéro (`renumeroter`), places (`changerPlaces`), activation (`basculer`,
 * qui refuse une table au panier ouvert). Module M5 (RG-16, la lecture du
 * plan) ; l'écriture exige EN PLUS `PARAM`, le droit de l'écran Paramètres.
 */
final class GestionnaireTablesSalle extends GestionnaireAbstrait
{
    public function __construct(private readonly TableSalleService $tables)
    {
    }

    public function table(): string
    {
        return 'tables_salle';
    }

    /** Le module du point de vente (RG-16) — celui qui LIT le plan. */
    public function module(): string
    {
        return PosComptant::MODULE;
    }

    /** L'ÉCRITURE exige en plus le droit de l'écran Paramètres, comme à la PWA. */
    public function modulesRequis(array $payload): array
    {
        return [PosComptant::MODULE, Parametres::MODULE];
    }

    public function serviceDomaine(): string
    {
        return TableSalleService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerGeste($payload, [
            'espace' => ['required', 'string'],
            'numero' => ['required', 'integer', 'min:1'],
            'places' => ['nullable', 'integer', 'min:1'],
        ]);
        $espace = TableSalleService::espace((string) $donnees['espace']);

        if ($espace === null || ! $espace['avecTables']) {
            throw new RuntimeException(__('sync.tables.espace_invalide', ['espace' => $donnees['espace']]));
        }

        $existante = TableSalle::query()
            ->where('espace', $donnees['espace'])
            ->where('numero', (int) $donnees['numero'])
            ->first();

        if ($existante !== null) {
            return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existante->id);
        }

        $this->tables->creer(
            (string) $donnees['espace'],
            (int) $donnees['numero'],
            isset($donnees['places']) ? (int) $donnees['places'] : null,
            $entiteId,
        );

        return new EcritureSynchronisee($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $refuses = array_diff(array_keys($payload), ['numero', 'places', 'actif']);

        if ($refuses !== []) {
            throw new RuntimeException(__('sync.tables.champ_non_modifiable', ['champs' => implode(', ', $refuses)]));
        }

        $donnees = $this->validerGeste($payload, [
            'numero' => ['sometimes', 'integer', 'min:1'],
            'places' => ['sometimes', 'integer', 'min:1'],
            'actif' => ['sometimes', 'boolean'],
        ]);
        $table = TableSalle::query()->findOrFail($entiteId);

        if (isset($donnees['numero']) && (int) $donnees['numero'] !== (int) $table->numero) {
            $this->tables->renumeroter($entiteId, (int) $donnees['numero']);
        }

        if (isset($donnees['places'])) {
            $this->tables->changerPlaces($entiteId, (int) $donnees['places']);
        }

        if (array_key_exists('actif', $donnees) && (bool) $donnees['actif'] !== (bool) $table->refresh()->actif) {
            $this->tables->basculer($entiteId);
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
        $validateur = Validator::make($payload, $regles);

        if ($validateur->fails()) {
            throw new RuntimeException((string) $validateur->errors()->first());
        }

        return $validateur->validated();
    }
}
