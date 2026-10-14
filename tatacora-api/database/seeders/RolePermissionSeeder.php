<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Shared\Rbac\Models\{Permission, Role};
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class RolePermissionSeeder extends Seeder
{
    /**
     * Matrice RBAC 14×11 — IDENTIQUE à celle déjà validée dans le prototype
     * (roles-permissions.html / assets/js/rbac.js MATRICE_RBAC). Toute divergence
     * avec cette source doit être corrigée ICI, jamais acceptée comme "presque pareil".
     *
     * ## `ANNULATIONS` — transverse, comme `ROLES` et `PARAM` (01/09/2026)
     *
     * Droit d'exécuter une annulation de réservation AVEC commission et
     * remboursement (EF-M1-06) — distinct du droit `M1` qui couvre déjà
     * créer/modifier une réservation. Avant cette colonne, N'IMPORTE QUEL
     * rôle avec `M1 = C` pouvait annuler ET décider seul du remboursement en
     * numéraire sorti de caisse : un trou RBAC réel, révélé en auditant ce
     * dépôt pour cette tâche. Suivant le seul précédent du dépôt pour un
     * droit qui n'est pas un module métier — `ROLES`/`PARAM` —, ce n'est ni
     * un M15 ni une sous-action de M1 (le schéma de permissions ne porte
     * qu'un niveau C/L/- par module, pas une granularité par geste).
     *
     * Choix retenu, à réviser par le Product Owner si besoin :
     * `administrateur`/`gerant` en `C` (le geste engage réellement la
     * caisse) ; `receptionniste` — qui garde `M1 = C` — et `comptable` en
     * `L` : ils VOIENT l'onglet Annulations et son historique, mais
     * n'exécutent pas eux-mêmes un remboursement, qui reste un arbitrage de
     * direction. Tous les autres rôles restent à `-`, comme sur `M1`.
     */
    public const MATRICE = [
        // SUPER_ADMIN — directive PO du 03/09/2026 : tous les CRUD, la
        // suppression en bloc de tous les modules ET la purge des archives
        // (que lui seul peut executer — la garde vit dans les composants qui
        // purgent, sur `User::estSuperAdmin()`). Les tables FINANCIERES
        // restent hors de portee de toute suppression physique (RG-03/RG-11,
        // MECeF) : meme le super_admin passe par le geste metier.
        'super_admin'    => ['M1'=>'C','M2'=>'C','M3'=>'C','M4'=>'C','M5'=>'C','M6'=>'C','M7'=>'C','M8'=>'C','M9'=>'C','M10'=>'C','M11'=>'C','M12'=>'C','M13'=>'C','M14'=>'C','ROLES'=>'C','PARAM'=>'C','ANNULATIONS'=>'C'],
        'administrateur' => ['M1'=>'C','M2'=>'C','M3'=>'C','M4'=>'C','M5'=>'C','M6'=>'C','M7'=>'C','M8'=>'C','M9'=>'C','M10'=>'C','M11'=>'C','M12'=>'C','M13'=>'C','M14'=>'C','ROLES'=>'C','PARAM'=>'C','ANNULATIONS'=>'C'],
        'gerant'         => ['M1'=>'C','M2'=>'C','M3'=>'C','M4'=>'C','M5'=>'C','M6'=>'C','M7'=>'C','M8'=>'C','M9'=>'C','M10'=>'C','M11'=>'C','M12'=>'C','M13'=>'C','M14'=>'C','ROLES'=>'L','PARAM'=>'L','ANNULATIONS'=>'C'],
        'receptionniste' => ['M1'=>'C','M2'=>'C','M3'=>'C','M4'=>'L','M5'=>'L','M6'=>'L','M7'=>'-','M8'=>'L','M9'=>'L','M10'=>'-','M11'=>'L','M12'=>'L','M13'=>'-','M14'=>'L','ROLES'=>'-','PARAM'=>'-','ANNULATIONS'=>'L'],
        'cuisine'        => ['M1'=>'-','M2'=>'-','M3'=>'L','M4'=>'C','M5'=>'-','M6'=>'C','M7'=>'-','M8'=>'-','M9'=>'-','M10'=>'-','M11'=>'L','M12'=>'-','M13'=>'-','M14'=>'L','ROLES'=>'-','PARAM'=>'-','ANNULATIONS'=>'-'],
        'barman'         => ['M1'=>'-','M2'=>'-','M3'=>'L','M4'=>'-','M5'=>'C','M6'=>'C','M7'=>'-','M8'=>'-','M9'=>'-','M10'=>'-','M11'=>'L','M12'=>'-','M13'=>'-','M14'=>'L','ROLES'=>'-','PARAM'=>'-','ANNULATIONS'=>'-'],
        'magasinier'     => ['M1'=>'-','M2'=>'-','M3'=>'-','M4'=>'L','M5'=>'L','M6'=>'C','M7'=>'C','M8'=>'-','M9'=>'-','M10'=>'-','M11'=>'L','M12'=>'-','M13'=>'-','M14'=>'L','ROLES'=>'-','PARAM'=>'-','ANNULATIONS'=>'-'],
        'achats'         => ['M1'=>'-','M2'=>'-','M3'=>'-','M4'=>'-','M5'=>'-','M6'=>'L','M7'=>'C','M8'=>'-','M9'=>'-','M10'=>'-','M11'=>'L','M12'=>'-','M13'=>'-','M14'=>'L','ROLES'=>'-','PARAM'=>'-','ANNULATIONS'=>'-'],
        'vehicules'      => ['M1'=>'-','M2'=>'-','M3'=>'L','M4'=>'-','M5'=>'-','M6'=>'-','M7'=>'-','M8'=>'C','M9'=>'L','M10'=>'-','M11'=>'L','M12'=>'-','M13'=>'-','M14'=>'L','ROLES'=>'-','PARAM'=>'-','ANNULATIONS'=>'-'],
        'guide'          => ['M1'=>'-','M2'=>'-','M3'=>'L','M4'=>'-','M5'=>'-','M6'=>'-','M7'=>'-','M8'=>'L','M9'=>'C','M10'=>'-','M11'=>'-','M12'=>'-','M13'=>'-','M14'=>'-','ROLES'=>'-','PARAM'=>'-','ANNULATIONS'=>'-'],
        'rh'             => ['M1'=>'-','M2'=>'-','M3'=>'-','M4'=>'-','M5'=>'-','M6'=>'-','M7'=>'-','M8'=>'-','M9'=>'-','M10'=>'L','M11'=>'L','M12'=>'-','M13'=>'C','M14'=>'L','ROLES'=>'-','PARAM'=>'-','ANNULATIONS'=>'-'],
        'comptable'      => ['M1'=>'L','M2'=>'L','M3'=>'L','M4'=>'L','M5'=>'L','M6'=>'L','M7'=>'L','M8'=>'L','M9'=>'L','M10'=>'C','M11'=>'L','M12'=>'-','M13'=>'L','M14'=>'C','ROLES'=>'-','PARAM'=>'-','ANNULATIONS'=>'L'],
    ];

    public function run(): void
    {
        // Idempotent depuis le 28/08/2026 ; COMPLÉMENTAIRE depuis le
        // 02/09/2026. La garde « des rôles existent → tout sauter » avait un
        // angle mort trouvé au passage navigateur : un module AJOUTÉ à la
        // matrice (ANNULATIONS) n'atteignait jamais une base déjà semée —
        // l'administrateur de dev n'avait aucun droit d'annulation, et le
        // bouton d'annulation des réservations n'existait pour personne.
        //
        // Le complément ne porte QUE sur les modules entièrement absents du
        // référentiel `permissions` : un module déjà connu a pu être ajusté
        // à l'écran Rôles & Permissions, et le seeder ne réécrit JAMAIS un
        // arbitrage d'écran (même règle que ComptesReelsSeeder pour les
        // mots de passe : posé une fois, plus jamais touché).
        if (Role::query()->exists()) {
            $this->completerModulesNouveaux();
            $this->completerRolesNouveaux();

            return;
        }

        $modules = array_keys(self::MATRICE['administrateur']);
        $permissions = [];
        foreach ($modules as $module) {
            foreach (['lire', 'creer', 'modifier', 'supprimer', 'valider'] as $action) {
                $permissions[$module][$action] = Permission::create([
                    'id' => (string) Str::uuid(), 'module' => $module, 'action' => $action,
                ]);
            }
        }

        foreach (self::MATRICE as $roleKey => $droits) {
            $role = Role::create(['id' => (string) Str::uuid(), 'libelle' => $roleKey]);
            foreach ($droits as $module => $niveau) {
                if ($niveau === '-') {
                    continue;
                }
                $actions = $niveau === 'C' ? ['lire', 'creer', 'modifier', 'supprimer', 'valider'] : ['lire'];
                foreach ($actions as $action) {
                    $role->permissions()->attach($permissions[$module][$action]->id);
                }
            }
        }
    }

    /**
     * Pose les permissions d'un module que la matrice connaît mais que la
     * base ne connaît pas encore — et SEULEMENT celles-là.
     */
    private function completerModulesNouveaux(): void
    {
        $connus = Permission::query()->distinct()->pluck('module')->all();
        $nouveaux = array_diff(array_keys(self::MATRICE['administrateur']), $connus);

        foreach ($nouveaux as $module) {
            $permissions = [];
            foreach (['lire', 'creer', 'modifier', 'supprimer', 'valider'] as $action) {
                $permissions[$action] = Permission::create([
                    'id' => (string) Str::uuid(), 'module' => $module, 'action' => $action,
                ]);
            }

            foreach (self::MATRICE as $roleKey => $droits) {
                // Chaque role de la MATRICE porte toutes les colonnes : la
                // lecture est directe, sans repli.
                $niveau = $droits[$module];
                if ($niveau === '-') {
                    continue;
                }

                $role = Role::query()->where('libelle', $roleKey)->first();
                if ($role === null) {
                    continue;
                }

                $actions = $niveau === 'C' ? ['lire', 'creer', 'modifier', 'supprimer', 'valider'] : ['lire'];
                foreach ($actions as $action) {
                    $role->permissions()->syncWithoutDetaching([$permissions[$action]->id]);
                }
            }
        }
    }

    /**
     * Cree les ROLES que la matrice connait mais que la base n'a pas —
     * meme logique complementaire que les modules (03/09/2026, ne du role
     * `super_admin`) : un role deja present n'est JAMAIS reecrit, ses
     * ajustements d'ecran priment.
     */
    private function completerRolesNouveaux(): void
    {
        foreach (self::MATRICE as $roleKey => $droits) {
            if (Role::query()->where('libelle', $roleKey)->exists()) {
                continue;
            }

            $role = Role::create(['id' => (string) Str::uuid(), 'libelle' => $roleKey]);

            foreach ($droits as $module => $niveau) {
                if ($niveau === '-') {
                    continue;
                }

                $actions = $niveau === 'C' ? ['lire', 'creer', 'modifier', 'supprimer', 'valider'] : ['lire'];

                foreach ($actions as $action) {
                    $permission = Permission::query()
                        ->where('module', $module)
                        ->where('action', $action)
                        ->first();

                    if ($permission !== null) {
                        $role->permissions()->syncWithoutDetaching([$permission->id]);
                    }
                }
            }
        }
    }
}
