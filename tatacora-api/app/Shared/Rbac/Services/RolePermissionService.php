<?php

declare(strict_types=1);

namespace App\Shared\Rbac\Services;

use App\Shared\Rbac\Models\Permission;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Écriture RÉELLE de la matrice RBAC — `roles-permissions.html`, maître dont
 * l'écran de la PWA lisait jusqu'au 01/09/2026 la matrice `permission_role`
 * SANS jamais l'écrire (voir le docblock, désormais périmé, de
 * `App\Pwa\Livewire\Transverse\RolesPermissions`).
 *
 * ## `permission_role` reste l'UNIQUE table de vérité — jamais recopiée
 *
 * `Role::niveauSurModule()` DÉRIVE le niveau du nombre d'actions attachées
 * (1 = L, plusieurs = C, aucune = -). Ce Service n'invente donc jamais de
 * colonne `niveau` : `definirNiveau()` synchronise les LIGNES de
 * `permission_role` pour le couple (rôle, module), et la lecture reste,
 * comme avant, `Role::niveauSurModule()` — jamais une seconde formule.
 *
 * ## Le verrou de soi-même — la SEULE règle métier de cet écran
 *
 * Le maître l'écrit lui-même (`roles-permissions.html` l.83-90) : un
 * administrateur ne peut pas se retirer l'accès à `ROLES`. `definirNiveau()`
 * refuse toute tentative de faire passer `administrateur`/`ROLES` sous `C` —
 * refusée avec un message NOMMÉ, jamais silencieuse.
 *
 * ## « Rétablir le socle » ne touche JAMAIS un rôle ajouté
 *
 * `retablirSocle()` ne parcourt QUE les onze rôles de
 * `RolePermissionSeeder::MATRICE` : un rôle créé depuis cet écran n'y figure
 * pas, et rester intact est le comportement voulu — « rétablir le socle du
 * CdCF » n'a aucun sens sur un rôle qui n'appartient pas au CdCF.
 */
class RolePermissionService
{
    /**
     * Les actions attachées pour chaque niveau — LA même correspondance que
     * `RolePermissionSeeder::run()`, jamais une seconde inventée ici : deux
     * listes finiraient par diverger (Article 10).
     *
     * @var array<string, list<string>>
     */
    private const ACTIONS_PAR_NIVEAU = [
        'C' => ['lire', 'creer', 'modifier', 'supprimer', 'valider'],
        'L' => ['lire'],
        '-' => [],
    ];

    /**
     * Crée un rôle NEUF, sans aucune permission (registre fermé « - » sur
     * tous les modules) — un rôle nouvellement créé n'obtient un droit que
     * si quelqu'un le lui donne explicitement (même principe que
     * l'administrateur du client Flutter, PA-103 : jamais un droit par
     * effet de bord).
     *
     * @throws RuntimeException libellé vide ou déjà pris
     */
    public function creerRole(string $libelle, ?string $description): Role
    {
        $libellePropre = trim($libelle);

        if ($libellePropre === '') {
            throw new RuntimeException(__('pwa.roles.libelle_requis'));
        }

        return DB::transaction(function () use ($libellePropre, $description): Role {
            $existe = Role::query()
                ->where('libelle', $libellePropre)
                ->lockForUpdate()
                ->exists();

            if ($existe) {
                throw new RuntimeException(__('pwa.roles.role_deja_existant', ['libelle' => $libellePropre]));
            }

            return Role::create([
                'libelle' => $libellePropre,
                'description' => filled($description) ? trim($description) : null,
            ]);
        });
    }

    /**
     * Synchronise les permissions d'un rôle sur UN module pour égaler
     * exactement le niveau demandé.
     *
     * @throws RuntimeException niveau hors registre, ou verrouillage de soi-même
     */
    public function definirNiveau(Role $role, string $module, string $niveau): Role
    {
        if (! array_key_exists($niveau, self::ACTIONS_PAR_NIVEAU)) {
            throw new RuntimeException(__('pwa.roles.niveau_invalide', ['niveau' => $niveau]));
        }

        if ($role->libelle === 'administrateur' && $module === 'ROLES' && $niveau !== 'C') {
            throw new RuntimeException(__('pwa.roles.verrouillage_administrateur'));
        }

        return DB::transaction(function () use ($role, $module, $niveau): Role {
            $actions = self::ACTIONS_PAR_NIVEAU[$niveau];

            $idsAGarder = [];
            foreach ($actions as $action) {
                $permission = Permission::firstOrCreate(['module' => $module, 'action' => $action]);
                $idsAGarder[] = $permission->id;
            }

            $idsDuModule = Permission::query()->where('module', $module)->pluck('id')->all();

            $role->permissions()->detach($idsDuModule);
            if ($idsAGarder !== []) {
                $role->permissions()->attach($idsAGarder);
            }

            return $role->refresh();
        });
    }

    /**
     * Rétablit la matrice du CdCF sur les rôles du SOCLE — jamais ceux
     * ajoutés depuis cet écran (voir l'en-tête).
     *
     * @return int le nombre de rôles réellement rétablis
     */
    public function retablirSocle(): int
    {
        return DB::transaction(function (): int {
            $restaures = 0;

            foreach (RolePermissionSeeder::MATRICE as $libelle => $droits) {
                $role = Role::query()->where('libelle', $libelle)->lockForUpdate()->first();

                if ($role === null) {
                    // Le socle décrit onze rôles ; si l'un d'eux a disparu
                    // (jamais semé sur cette base), il n'y a rien à rétablir.
                    continue;
                }

                foreach ($droits as $module => $niveau) {
                    $this->synchroniserSansGarde($role, $module, $niveau);
                }

                $restaures++;
            }

            return $restaures;
        });
    }

    /**
     * Le rôle est-il EXACTEMENT celui du socle du CdCF ? `null` s'il n'existe
     * aucun socle pour ce rôle — un rôle ajouté depuis cet écran, pour lequel
     * « conforme » ou « amendée » n'a pas de sens.
     */
    public function estConformeAuSocle(Role $role): ?bool
    {
        $matrice = RolePermissionSeeder::MATRICE[$role->libelle] ?? null;

        if ($matrice === null) {
            return null;
        }

        foreach ($matrice as $module => $niveau) {
            if ($role->niveauSurModule($module) !== $niveau) {
                return false;
            }
        }

        return true;
    }

    /**
     * Même synchronisation que `definirNiveau()`, sans la garde de
     * verrouillage : `retablirSocle()` pose justement `ROLES = C` sur
     * `administrateur`, ce que la garde autorise déjà — mais l'appeler ICI
     * évite toute dépendance d'ordre dans la boucle du dessus.
     */
    private function synchroniserSansGarde(Role $role, string $module, string $niveau): void
    {
        $actions = self::ACTIONS_PAR_NIVEAU[$niveau] ?? [];

        $idsAGarder = [];
        foreach ($actions as $action) {
            $permission = Permission::firstOrCreate(['module' => $module, 'action' => $action]);
            $idsAGarder[] = $permission->id;
        }

        $idsDuModule = Permission::query()->where('module', $module)->pluck('id')->all();

        $role->permissions()->detach($idsDuModule);
        if ($idsAGarder !== []) {
            $role->permissions()->attach($idsAGarder);
        }
    }
}
