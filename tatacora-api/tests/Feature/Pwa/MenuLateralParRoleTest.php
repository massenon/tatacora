<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Support\MenuLateral;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * La barre latérale est pilotée UNIQUEMENT par le RBAC (décision du PO du
 * 11/11/2026, qui rend caduc le masquage du gérant du 03/09/2026) : un module
 * à « - » est masqué, « L » ou « C » est visible. Aucun masquage par nom de
 * rôle ; seule l'exigence d'un RÔLE précis (`roles_exiges`) subsiste, pour
 * « Comptes utilisateurs » (administrateurs).
 *
 * Source EXTÉRIEURE à `MenuLateral::NAVIGATION` : la matrice du seeder
 * (`RolePermissionSeeder::MATRICE`) et la table route → module ci-dessous,
 * recopiée à la main. Une entrée de menu dont le module change, ou un
 * masquage remis par rôle, fait rougir ce fichier.
 */
final class MenuLateralParRoleTest extends TestCase
{
    use RefreshDatabase;

    /** Les 28 entrées de la barre, dans l'ordre : route => module qui la commande. */
    private const ROUTE_MODULE = [
        'pwa.accueil' => 'M11',
        'pwa.pos.comptant' => 'M5',
        'pwa.pos.heberges' => 'M1',
        'pwa.historique-ventes' => 'M5',
        'pwa.depenses' => 'M10',
        'pwa.reservations' => 'M1',
        'pwa.hebergement' => 'M1',
        'pwa.clients' => 'M3',
        'pwa.facturation' => 'M2',
        'pwa.stocks.liste' => 'M6',
        'pwa.stocks.inventaires' => 'M6',
        'pwa.achats.approvisionnement' => 'M7',
        'pwa.achats.liste' => 'M7',
        'pwa.restaurant.carte' => 'M4',
        'pwa.bar.carte' => 'M5',
        'pwa.tourisme' => 'M9',
        'pwa.vehicules' => 'M8',
        'pwa.comptabilite.hub' => 'M10',
        'pwa.paie' => 'M13',
        'pwa.conges-plannings' => 'M13',
        'pwa.etats.studio' => 'M14',
        'pwa.notifications' => 'M12',
        'pwa.import-export' => 'IMPORT_EXPORT',
        'pwa.roles-permissions' => 'ROLES',
        'pwa.comptes-utilisateurs' => 'ROLES',
        'pwa.parametres' => 'PARAM',
        'pwa.synchronisation' => 'SYNCHRO',
        'pwa.synchronisation-postes' => 'APPAIRAGE',
    ];

    /** Les entrées qui exigent en plus un rôle d'administration. */
    private const ROUTES_ADMINISTRATION = ['pwa.comptes-utilisateurs'];

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

    /**
     * Ce que la MATRICE du seeder promet à ce rôle, sans passer par MenuLateral.
     *
     * @return list<string>
     */
    private function attendu(string $role, array $matrice): array
    {
        $routes = [];

        foreach (self::ROUTE_MODULE as $route => $module) {
            if ($matrice[$module] === '-') {
                continue;
            }
            if (in_array($route, self::ROUTES_ADMINISTRATION, true) && ! in_array($role, User::ROLES_ADMINISTRATION, true)) {
                continue;
            }
            $routes[] = $route;
        }

        return $routes;
    }

    #[Test]
    public function la_table_de_reference_couvre_exactement_les_entrees_de_la_barre(): void
    {
        $this->assertSame(array_keys(self::ROUTE_MODULE), MenuLateral::routesDuMenu());
        foreach (self::ROUTE_MODULE as $route => $module) {
            $this->assertSame($module, MenuLateral::moduleDeRoute($route), $route);
        }
    }

    #[Test]
    public function l_exigence_de_role_du_registre_est_celle_des_roles_d_administration(): void
    {
        $exigences = [];
        foreach (MenuLateral::NAVIGATION as $entree) {
            foreach ($entree['items'] ?? [$entree] as $item) {
                if (isset($item['roles_exiges'])) {
                    $exigences[$item['route']] = $item['roles_exiges'];
                }
            }
        }

        $this->assertSame(['pwa.comptes-utilisateurs' => User::ROLES_ADMINISTRATION], $exigences);
    }

    #[Test]
    public function la_barre_de_chaque_role_du_socle_est_exactement_celle_de_la_matrice(): void
    {
        foreach (RolePermissionSeeder::MATRICE as $role => $matrice) {
            $this->assertSame(
                $this->attendu($role, $matrice),
                $this->routesDuMenu($this->compte($role)),
                "La barre de « $role » diverge de la matrice du seeder.",
            );
        }
    }

    #[Test]
    public function le_gerant_voit_finance_rh_tourisme_vehicules_et_le_pilotage(): void
    {
        $routes = $this->routesDuMenu($this->compte('gerant'));

        // M1..M14 = C, ROLES = L, PARAM = L : tout ce qui suit est visible.
        foreach ([
            'pwa.comptabilite.hub', 'pwa.paie', 'pwa.conges-plannings', 'pwa.tourisme', 'pwa.vehicules',
            'pwa.etats.studio', 'pwa.notifications', 'pwa.clients', 'pwa.facturation',
            'pwa.roles-permissions', 'pwa.parametres', 'pwa.import-export', 'pwa.synchronisation', 'pwa.synchronisation-postes',
            'pwa.depenses', 'pwa.pos.comptant', 'pwa.reservations', 'pwa.stocks.liste',
        ] as $route) {
            $this->assertContains($route, $routes, "$route doit être au menu du gérant.");
        }

        // PO 11/11/2026 (décision finale) : Rôles & Permissions et Paramètres sont AFFICHÉS au gérant
        // et au comptable, en lecture seule (ROLES = L, PARAM = L).
        $this->assertSame('L', RolePermissionSeeder::MATRICE['gerant']['ROLES']);
        $this->assertSame('L', RolePermissionSeeder::MATRICE['gerant']['PARAM']);
        $this->assertSame(RolePermissionSeeder::MATRICE['gerant'], RolePermissionSeeder::MATRICE['comptable']);

        // Seule exception : « Comptes utilisateurs » exige un rôle d'administration.
        $this->assertNotContains('pwa.comptes-utilisateurs', $routes);

        $sections = array_map(static fn (array $s): ?string => $s['groupe'], MenuLateral::pour($this->compte('gerant')));
        foreach (['Finance', 'Ressources humaines', 'Tourisme & véhicules', 'Pilotage & administration'] as $groupe) {
            $this->assertContains($groupe, $sections);
        }
    }

    #[Test]
    public function l_administrateur_et_le_super_admin_voient_tout_y_compris_les_comptes_utilisateurs(): void
    {
        foreach (['administrateur', 'super_admin'] as $role) {
            $this->assertSame(array_keys(self::ROUTE_MODULE), $this->routesDuMenu($this->compte($role)), $role);
        }
    }

    #[Test]
    public function le_masquage_par_nom_de_role_n_existe_plus(): void
    {
        $this->assertFalse(defined(MenuLateral::class.'::ROUTES_MASQUEES_PAR_ROLE'));
        $this->assertFalse(
            (new \ReflectionClass(MenuLateral::class))->hasMethod('routeMasqueePourRole'),
        );
    }

    #[Test]
    public function un_role_modifie_change_le_menu_a_la_requete_suivante_sans_deconnexion(): void
    {
        $service = app(RolePermissionService::class);
        $role = Role::where('libelle', 'gerant')->firstOrFail();
        $compte = $this->compte('gerant');

        // Chaque « requête » relit l'utilisateur en base, comme le fait la session
        // (aucun cache de droits n'existe : `Role::niveauSurModule` lit `permissions`).
        $page = function () use ($compte): string {
            // Même SESSION, aucune nouvelle authentification : seul l'identifiant est en session,
            // l'utilisateur et son rôle sont relus en base à chaque requête.
            $this->app['auth']->forgetGuards();

            return (string) $this->withSession([$this->app['auth']->guard('web')->getName() => $compte->id])
                ->get('/pwa')->assertOk()->getContent();
        };

        $this->assertStringContainsString('Comptabilité', $page());
        $this->assertStringContainsString('Personnel &amp; Paie', $page());

        // L'administrateur retire M10 et M13 au gérant : la barre se met à jour.
        $service->definirNiveau($role->fresh(), 'M10', '-');
        $service->definirNiveau($role->fresh(), 'M13', '-');
        $html = $page();
        $this->assertStringNotContainsString('SYSCOHADA', $html);
        $this->assertStringNotContainsString('Personnel &amp; Paie', $html);
        $this->assertStringNotContainsString('Congés &amp; Plannings', $html);
        $this->assertStringNotContainsString('RESSOURCES HUMAINES', $html);

        // « Mettre à jour les rôles » = rétablir le socle : les entrées reviennent.
        $service->retablirSocle(['gerant']);
        $html = $page();
        $this->assertStringContainsString('SYSCOHADA', $html);
        $this->assertStringContainsString('Personnel &amp; Paie', $html);
        $this->assertStringContainsString('Congés &amp; Plannings', $html);
        $this->assertStringContainsString('RESSOURCES HUMAINES', $html);

        // Un niveau « L » suffit pour voir : la lecture garde l'entrée.
        $service->definirNiveau($role->fresh(), 'M9', 'L');
        $this->assertStringContainsString('href="'.route('pwa.tourisme').'"', $page());
        $service->definirNiveau($role->fresh(), 'M9', '-');
        $this->assertStringNotContainsString('href="'.route('pwa.tourisme').'"', $page());
    }

    #[Test]
    public function roles_et_parametres_s_ouvrent_au_gerant_et_au_comptable_en_lecture_seule(): void
    {
        foreach (['gerant', 'comptable'] as $role) {
            $this->app['auth']->forgetGuards();
            $this->actingAs($this->compte($role));

            $roles = $this->get(route('pwa.roles-permissions'))->assertOk();
            $roles->assertSee('Rôles');
            // Aucun geste d'écriture n'est offert : ni création de rôle, ni rétablissement du socle.
            $roles->assertDontSee('wire:click="ouvrirFormulaireRole"', false);
            $roles->assertDontSee('wire:click="ouvrirRetablirSocle"', false);
            $this->get(route('pwa.parametres'))->assertOk();

            // Le serveur relit le droit à chaque geste : un appel falsifié est refusé.
            \Livewire\Livewire::test(\App\Pwa\Livewire\Transverse\RolesPermissions::class)
                ->call('retablirSocle')->assertForbidden();
            \Livewire\Livewire::test(\App\Pwa\Livewire\Transverse\Parametres::class)
                ->call('basculerCanal', 'inexistant')->assertForbidden();
        }

        // Contre-épreuve : l'administrateur, lui, a les boutons.
        $this->app['auth']->forgetGuards();
        $this->actingAs($this->compte('administrateur'));
        $this->get(route('pwa.roles-permissions'))->assertOk()
            ->assertSee('wire:click="ouvrirFormulaireRole"', false);
    }
}
