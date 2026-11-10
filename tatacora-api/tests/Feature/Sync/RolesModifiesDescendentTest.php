<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use App\Shared\Sync\Services\EpoqueSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * 10/11/2026 (PO : « si l'admin modifie le RBAC, l'application doit prendre en compte le rôle modifié
 * et le synchroniser ») : toute écriture d'un rôle au WEB fait avancer l'ÉPOQUE (les postes redescendent
 * dans la minute, sans attendre le passage complet de 5 minutes) et la matrice modifiée est celle que la
 * descente livre.
 */
class RolesModifiesDescendentTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function modifier_un_niveau_fait_avancer_l_epoque_et_le_role_porte_le_droit(): void
    {
        $epoque = app(EpoqueSynchronisation::class);
        $avant = $epoque->courante();
        $barman = Role::query()->where('libelle', 'barman')->firstOrFail();

        app(RolePermissionService::class)->definirNiveau($barman, 'M1', 'C');

        $this->assertNotSame($avant, $epoque->courante());
        // La matrice modifiée est celle que la descente des rôles livre (couverte table par table par
        // `ParametresRolesSynchronisationTest`) : ici, le rôle est daté et porte le droit.
        $this->assertTrue($barman->refresh()->permissions()->where('module', 'M1')->where('action', 'creer')->exists());
    }

    #[Test]
    public function creer_un_role_et_retablir_le_socle_font_aussi_avancer_l_epoque(): void
    {
        $epoque = app(EpoqueSynchronisation::class);
        $service = app(RolePermissionService::class);

        $avant = $epoque->courante();
        $service->creerRole('Superviseur', null);
        $apresCreation = $epoque->courante();
        $this->assertNotSame($avant, $apresCreation);

        $service->retablirSocle(['barman']);
        $this->assertNotSame($apresCreation, $epoque->courante());
    }
}
