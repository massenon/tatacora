<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Support\MenuLateral;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Masquage de la barre laterale PAR ROLE — directive PO du 03/09/2026 :
 * le gerant ne voit ni Tourisme, ni Vehicules, ni Comptabilite, ni
 * Personnel & Paie, ni le groupe Pilotage & administration, ni Clients &
 * facturation. C'est un masquage d'INTERFACE : la matrice de droits du
 * gerant reste inchangee (M10 porte aussi « Depense courante », qu'il
 * garde) — voir MenuLateral::ROUTES_MASQUEES_PAR_ROLE.
 */
final class MenuLateralParRoleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function compte(string $role): User
    {
        return User::create([
            'login' => $role.'.menu.'.bin2hex(random_bytes(3)),
            'mot_de_passe_hash' => Hash::make('MotDePasseTresLong!2026'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /** @return list<string> */
    private function routesDuMenu(User $utilisateur): array
    {
        $routes = [];

        foreach (MenuLateral::pour($utilisateur) as $section) {
            foreach ($section['items'] as $item) {
                $routes[] = $item['route'];
            }
        }

        return $routes;
    }

    #[Test]
    public function le_gerant_ne_voit_pas_les_entrees_masquees_et_garde_ses_gestes_quotidiens(): void
    {
        $routes = $this->routesDuMenu($this->compte('gerant'));

        foreach (MenuLateral::ROUTES_MASQUEES_PAR_ROLE['gerant'] as $masquee) {
            $this->assertNotContains($masquee, $routes, $masquee.' doit etre masquee au gerant (PO 03/09/2026).');
        }

        // Les gestes quotidiens RESTENT — c'est la raison du masquage par
        // route et non par module : Depense courante partage M10 avec la
        // Comptabilite masquee.
        foreach (['pwa.depenses', 'pwa.pos.comptant', 'pwa.reservations', 'pwa.stocks.liste'] as $gardee) {
            $this->assertContains($gardee, $routes, $gardee.' doit rester au menu du gerant.');
        }
    }

    #[Test]
    public function l_administrateur_et_le_super_admin_voient_tout(): void
    {
        foreach (['administrateur', 'super_admin'] as $role) {
            $routes = $this->routesDuMenu($this->compte($role));

            foreach (MenuLateral::ROUTES_MASQUEES_PAR_ROLE['gerant'] as $entree) {
                $this->assertContains($entree, $routes, $entree.' doit rester visible pour '.$role.'.');
            }
        }
    }
}
