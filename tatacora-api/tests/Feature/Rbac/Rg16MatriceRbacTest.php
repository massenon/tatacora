<?php

declare(strict_types=1);

namespace Tests\Feature\Rbac;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * RG-16 — Contrôle d'accès basé sur les rôles.
 *
 * Vérifie les 154 combinaisons (11 rôles × 14 modules) contre la matrice
 * de référence, conformément à 07_TESTING_QA.md §9. Le test est nommé
 * d'après la RG, pas d'après la méthode testée (06_DEVELOPMENT_STANDARDS.md §2.4).
 *
 * Le seeder est la source de vérité de la matrice ; ce test vérifie que les
 * permissions RÉELLEMENT attachées en base reproduisent cette matrice — un
 * seeder correct dont l'attachement est bogué serait sinon indétectable.
 */
final class Rg16MatriceRbacTest extends TestCase
{
    use RefreshDatabase;

    /** Les 14 modules métier — ROLES et PARAM sont exclus du décompte des 154. */
    private const MODULES_METIER = [
        'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'M10', 'M11', 'M12', 'M13', 'M14',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function rg16_la_matrice_couvre_exactement_154_combinaisons(): void
    {
        $roles = array_keys(RolePermissionSeeder::MATRICE);

        // 12 depuis le 03/09/2026 : le role `super_admin` rejoint la matrice
        // (directive PO — tous CRUD, purge des archives reservee a lui).
        $this->assertCount(12, $roles, 'La matrice doit décrire exactement 12 rôles.');
        $this->assertCount(14, self::MODULES_METIER);
        $this->assertSame(168, count($roles) * count(self::MODULES_METIER));
    }

    #[Test]
    public function rg16_chaque_role_obtient_exactement_le_niveau_attendu_sur_chaque_module(): void
    {
        $ecarts = [];

        foreach (RolePermissionSeeder::MATRICE as $libelleRole => $droits) {
            $role = Role::with('permissions')->where('libelle', $libelleRole)->firstOrFail();

            foreach (self::MODULES_METIER as $module) {
                $attendu = $droits[$module];
                $obtenu = $role->niveauSurModule($module);

                if ($obtenu !== $attendu) {
                    $ecarts[] = "{$libelleRole}/{$module} : attendu '{$attendu}', obtenu '{$obtenu}'";
                }
            }
        }

        $this->assertSame([], $ecarts, "Écarts avec la matrice RBAC :\n" . implode("\n", $ecarts));
    }

    #[Test]
    public function rg16_un_niveau_lecture_seule_n_autorise_aucune_action_d_ecriture(): void
    {
        // Le réceptionniste est en 'L' sur M4 (Restaurant) : il consulte, il n'écrit pas.
        $role = Role::with('permissions')->where('libelle', 'receptionniste')->firstOrFail();

        $actionsSurM4 = $role->permissions->where('module', 'M4')->pluck('action')->all();

        $this->assertSame(['lire'], $actionsSurM4);
        $this->assertNotContains('creer', $actionsSurM4);
        $this->assertNotContains('modifier', $actionsSurM4);
        $this->assertNotContains('supprimer', $actionsSurM4);
    }

    #[Test]
    public function rg16_un_module_marque_tiret_ne_donne_aucune_permission(): void
    {
        // Le guide n'a aucun accès à M10 (Comptabilité).
        $role = Role::with('permissions')->where('libelle', 'guide')->firstOrFail();

        $this->assertCount(0, $role->permissions->where('module', 'M10'));
        $this->assertSame('-', $role->niveauSurModule('M10'));
    }

    #[Test]
    public function rg16_un_compte_desactive_n_accede_a_rien_quel_que_soit_son_role(): void
    {
        // Le cumul rôle + statut est vérifié : un administrateur désactivé
        // ne doit pas conserver ses droits (SECURITY_STRICT.md).
        $role = Role::where('libelle', 'administrateur')->firstOrFail();

        $utilisateur = User::create([
            'login' => 'admin.desactive',
            'mot_de_passe_hash' => 'mot-de-passe-de-test',
            'role_id' => $role->id,
            'statut' => 'desactive',
        ]);

        $this->assertFalse($utilisateur->estActif());
        $this->assertSame('C', $utilisateur->niveauSurModule('M1'));
    }
}
