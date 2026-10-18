<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Pwa\Livewire\Transverse\RolesPermissions;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

/**
 * Les rôles et leur matrice saisis sur un poste — audit de couverture du
 * 18/10/2026 (lot 10e).
 *
 * Par `RolePermissionService`, et lui seul : le libellé est unique (un rôle
 * du même libellé FUSIONNE, la matrice du serveur restant la sienne) ; un
 * niveau passe par `definirNiveau`, qui garde le verrou de l'administrateur.
 * La modification porte TOUJOURS le libellé et la matrice entière : un rôle
 * du socle né sous un autre UUID sur le poste se retrouve par son libellé.
 *
 * Les COMPTES et les mots de passe ne se synchronisent jamais
 * (authentification locale, PA-103) : seul le référentiel rôle → droits.
 */
final class GestionnaireRoles extends GestionnaireAbstrait
{
    public function __construct(private readonly RolePermissionService $roles)
    {
    }

    public function table(): string
    {
        return 'roles';
    }

    public function module(): string
    {
        return RolesPermissions::MODULE;
    }

    public function serviceDomaine(): string
    {
        return RolePermissionService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    /** Les modules d'une matrice : ceux du socle, administrateur en tête. */
    public static function modules(): array
    {
        return array_keys(RolePermissionSeeder::MATRICE['administrateur']);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerRole($payload);
        $existant = Role::query()->where('libelle', trim((string) $donnees['libelle']))->first();

        if ($existant !== null) {
            return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existant->id);
        }

        $role = $this->roles->creerRole((string) $donnees['libelle'], $donnees['description'] ?? null, $entiteId);
        $this->appliquerDroits($role, $donnees['droits'] ?? []);

        return new EcritureSynchronisee($entiteId);
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerRole($payload);
        $this->appliquerDroits(Role::query()->findOrFail($entiteId), $donnees['droits'] ?? []);

        return new EcritureSynchronisee($entiteId);
    }

    /**
     * Un rôle du socle connu du poste sous son propre UUID : retrouvé par son
     * libellé (fusion), ou créé s'il manque au serveur.
     */
    public function modificationSurInconnu(string $entiteId, array $payload, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        $donnees = $this->validerRole($payload);
        $existant = Role::query()->where('libelle', trim((string) $donnees['libelle']))->first();

        if ($existant === null) {
            return $this->creer($entiteId, $payload, $contexte);
        }

        $this->appliquerDroits($existant, $donnees['droits'] ?? []);

        return new EcritureSynchronisee($entiteId, fusionneAvec: (string) $existant->id);
    }

    /**
     * @param  array<string, string>  $droits
     */
    private function appliquerDroits(Role $role, array $droits): void
    {
        foreach ($droits as $module => $niveau) {
            if ($role->refresh()->niveauSurModule((string) $module) !== $niveau) {
                $this->roles->definirNiveau($role, (string) $module, (string) $niveau);
            }
        }
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function validerRole(array $payload): array
    {
        $validateur = Validator::make($payload, [
            'libelle' => ['required', 'string', 'max:100'],
            'description' => ['nullable', 'string', 'max:255'],
            'droits' => ['sometimes', 'array'],
            'droits.*' => ['in:C,L,-'],
        ]);

        if ($validateur->fails()) {
            throw new RuntimeException((string) $validateur->errors()->first());
        }

        $inconnus = array_diff(array_keys($payload['droits'] ?? []), self::modules());

        if ($inconnus !== []) {
            throw new RuntimeException(__('sync.roles.module_inconnu', ['modules' => implode(', ', $inconnus)]));
        }

        return $validateur->validated();
    }
}
