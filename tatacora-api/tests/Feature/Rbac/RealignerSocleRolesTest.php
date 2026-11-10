<?php

declare(strict_types=1);

namespace Tests\Feature\Rbac;

use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Décision du PO du 10/11/2026 : le Barman est CONFORME au socle du CdCF, le
 * Comptable a les MÊMES droits que le Gérant, et une base déjà semée se
 * ramène au socle par `roles:realigner-socle`, rôle par rôle, sans toucher
 * un rôle créé à l'écran.
 */
final class RealignerSocleRolesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function niveaux(string $libelle): array
    {
        $role = Role::query()->where('libelle', $libelle)->firstOrFail();
        $niveaux = [];
        foreach (array_keys(RolePermissionSeeder::MATRICE['administrateur']) as $module) {
            $niveaux[$module] = $role->refresh()->niveauSurModule($module);
        }

        return $niveaux;
    }

    #[Test]
    public function le_comptable_a_la_matrice_exacte_du_gerant_et_le_barman_celle_du_socle(): void
    {
        $this->assertSame(RolePermissionSeeder::MATRICE['gerant'], RolePermissionSeeder::MATRICE['comptable']);
        $this->assertSame($this->niveaux('gerant'), $this->niveaux('comptable'));

        $barman = $this->niveaux('barman');
        $this->assertSame(
            ['M1' => '-', 'M2' => '-', 'M3' => 'L', 'M4' => '-', 'M5' => 'C', 'M6' => 'C', 'M7' => '-', 'M8' => '-',
                'M9' => '-', 'M10' => '-', 'M11' => 'L', 'M12' => '-', 'M13' => '-', 'M14' => 'L', 'ROLES' => '-', 'PARAM' => '-'],
            array_intersect_key($barman, array_flip(['M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'M10', 'M11', 'M12', 'M13', 'M14', 'ROLES', 'PARAM'])),
        );
        $this->assertSame('C', $barman['PROFIL_NOM']);
        $this->assertSame('C', $barman['PROFIL_TELEPHONE']);
        $this->assertSame('-', $barman['PROFIL_INTITULE']);
    }

    #[Test]
    public function la_simulation_montre_l_ecart_et_n_ecrit_rien(): void
    {
        $service = app(RolePermissionService::class);
        $barman = Role::query()->where('libelle', 'barman')->firstOrFail();
        $service->definirNiveau($barman, 'M1', 'C');
        $service->definirNiveau($barman, 'M10', 'L');

        $this->artisan('roles:realigner-socle', ['--role' => ['barman'], '--dry-run' => true])
            ->expectsOutputToContain('barman : 2 écart(s) au socle')
            ->assertSuccessful();

        $this->assertSame('C', $this->niveaux('barman')['M1']);
        $this->assertSame(0, JournalAudit::query()->where('action', 'roles:realigner-socle')->count());
    }

    #[Test]
    public function le_realignement_ramene_le_role_nomme_est_idempotent_et_laisse_les_autres(): void
    {
        $service = app(RolePermissionService::class);
        $barman = Role::query()->where('libelle', 'barman')->firstOrFail();
        $service->definirNiveau($barman, 'M1', 'C');
        $magasinier = Role::query()->where('libelle', 'magasinier')->firstOrFail();
        $service->definirNiveau($magasinier, 'M1', 'L');
        $maison = $service->creerRole('Chef de salle', null);
        $service->definirNiveau($maison, 'M1', 'C');

        $this->artisan('roles:realigner-socle', ['--role' => ['barman']])->assertSuccessful();

        $this->assertSame('-', $this->niveaux('barman')['M1']);
        $this->assertSame('L', $this->niveaux('magasinier')['M1'], 'un rôle non nommé n\'est pas touché');
        $this->assertSame('C', $maison->refresh()->niveauSurModule('M1'), 'un rôle créé à l\'écran n\'est jamais touché');
        $this->assertSame(1, JournalAudit::query()->where('action', 'roles:realigner-socle')->count());

        // Idempotent : un second passage ne réécrit ni ne trace rien.
        $this->artisan('roles:realigner-socle', ['--role' => ['barman']])
            ->expectsOutputToContain('barman : conforme au socle.')
            ->assertSuccessful();
        $this->assertSame(1, JournalAudit::query()->where('action', 'roles:realigner-socle')->count());
    }

    #[Test]
    public function un_role_hors_socle_est_refuse(): void
    {
        app(RolePermissionService::class)->creerRole('Chef de salle', null);

        $this->artisan('roles:realigner-socle', ['--role' => ['Chef de salle']])->assertFailed();
    }
}
