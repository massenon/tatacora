<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Pwa\Livewire\Transverse\Synchronisation;
use App\Pwa\Livewire\Transverse\SynchronisationPostes;
use App\Pwa\Support\MenuLateral;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use App\Shared\Sync\Models\JournalReceptionSynchronisation as Journal;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « Synchronisation », « Import & Export » et « Appairage Postes » sont au menu
 * latéral de TOUS les rôles RBAC par défaut (décision du PO du 09/11/2026), au
 * web comme au poste.
 *
 * Trois droits transverses, hors écran (`SYNCHRO`, `IMPORT_EXPORT`,
 * `APPAIRAGE`) : lecture pour tous les rôles de la matrice. Ils ne commandent
 * que la VISIBILITÉ — chaque action sensible garde sa garde. Ce fichier prouve
 * les deux moitiés : (1) chaque rôle voit et ouvre les trois pages, et retirer
 * le droit d'un rôle les lui retire (mutation) ; (2) voir ne donne aucune
 * action interdite.
 */
final class EntreesMenuOuvertesATousTest extends TestCase
{
    use RefreshDatabase;

    private const ENTREES = [
        'SYNCHRO' => ['nom' => 'Synchronisation', 'route' => 'pwa.synchronisation'],
        'IMPORT_EXPORT' => ['nom' => 'Import & Export', 'route' => 'pwa.import-export'],
        'APPAIRAGE' => ['nom' => 'Appairage Postes', 'route' => 'pwa.synchronisation-postes'],
    ];

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
    private function routes(User $utilisateur): array
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
    public function la_matrice_donne_la_lecture_a_tous_les_roles_et_l_ecriture_aux_administrateurs(): void
    {
        $this->assertSame(['SYNCHRO', 'APPAIRAGE', 'IMPORT_EXPORT'], RolePermissionSeeder::DROITS_OUVERTS_A_TOUS);
        $this->assertCount(12, RolePermissionSeeder::MATRICE);

        foreach (RolePermissionSeeder::MATRICE as $role => $droits) {
            foreach (RolePermissionSeeder::DROITS_OUVERTS_A_TOUS as $code) {
                $attendu = in_array($role, ['administrateur', 'super_admin'], true) ? 'C' : 'L';
                $this->assertSame($attendu, $droits[$code], "$role / $code");
                $this->assertSame($attendu, $this->compte($role)->niveauSurModule($code), "$role / $code en base");
            }
        }
    }

    #[Test]
    public function chaque_role_voit_les_trois_entrees_au_menu_et_ouvre_les_trois_pages(): void
    {
        foreach (array_keys(RolePermissionSeeder::MATRICE) as $role) {
            $compte = $this->compte($role);
            $routes = $this->routes($compte);

            foreach (self::ENTREES as $entree) {
                $this->assertContains($entree['route'], $routes, "{$entree['nom']} manque au menu de $role.");
                $this->actingAs($compte)->get(route($entree['route']))->assertOk();
            }

            $this->actingAs($compte)->get('/pwa')->assertOk()->assertSee('Synchronisation')
                ->assertSee('Import &amp; Export', false)->assertSee('Appairage Postes');
        }
    }

    #[Test]
    public function le_gerant_n_est_plus_prive_de_ces_trois_entrees(): void
    {
        foreach (['pwa.import-export', 'pwa.synchronisation-postes', 'pwa.synchronisation'] as $route) {
            $this->assertNotContains($route, MenuLateral::ROUTES_MASQUEES_PAR_ROLE['gerant']);
        }
        // Les masquages du 03/09/2026 qui restent valables : Paramètres, Rôles…
        $this->assertContains('pwa.parametres', MenuLateral::ROUTES_MASQUEES_PAR_ROLE['gerant']);
    }

    #[Test]
    public function retirer_le_droit_par_defaut_d_un_role_lui_retire_l_entree_et_la_page(): void
    {
        // MUTATION : le droit par défaut d'un rôle retiré (comme le ferait une
        // matrice sans la colonne) — l'entrée disparaît et la route refuse.
        foreach (self::ENTREES as $code => $entree) {
            $role = Role::where('libelle', 'barman')->firstOrFail();
            $compte = $this->compte('barman');
            $this->assertContains($entree['route'], $this->routes($compte));

            app(RolePermissionService::class)->definirNiveau($role, $code, '-');
            $compte = User::findOrFail($compte->id)->refresh();
            $compte->unsetRelation('role');

            $this->assertNotContains($entree['route'], $this->routes($compte->fresh()), "$code retiré : l'entrée reste.");
            $this->actingAs($compte->fresh())->get(route($entree['route']))->assertForbidden();

            // …et les deux autres entrées du même rôle restent (retrait ciblé).
            app(RolePermissionService::class)->definirNiveau($role->fresh(), $code, 'L');
        }
    }

    #[Test]
    public function un_role_cree_a_l_ecran_recoit_aussi_la_lecture_des_trois_pages(): void
    {
        $role = app(RolePermissionService::class)->creerRole('Stagiaire', null);
        $compte = User::create([
            'login' => 'stagiaire.menu', 'mot_de_passe_hash' => Hash::make('MotDePasseTresLong!2026'),
            'role_id' => $role->id, 'statut' => 'actif',
        ]);

        foreach (self::ENTREES as $code => $entree) {
            $this->assertSame('L', $compte->fresh()->niveauSurModule($code), $code);
            $this->assertContains($entree['route'], $this->routes($compte->fresh()));
        }
    }

    #[Test]
    public function un_non_admin_voit_les_postes_sans_bouton_de_revocation_et_ne_peut_pas_revoquer(): void
    {
        $this->actingAs($this->compte('guide'));

        Livewire::test(SynchronisationPostes::class)
            ->assertViewHas('peutRevoquer', false)
            ->assertDontSee('Révoquer')
            ->call('demanderRevocation', 'poste-a')
            ->assertForbidden();

        $this->app['auth']->forgetGuards();
        $this->actingAs($this->compte('administrateur'));
        Livewire::test(SynchronisationPostes::class)->assertViewHas('peutRevoquer', true);
    }

    #[Test]
    public function un_non_admin_voit_la_synchronisation_complete_et_peut_rejouer(): void
    {
        $guide = $this->compte('guide');
        $autre = $this->compte('barman');

        foreach ([[$guide, 'poste-guide', 'clients'], [$autre, 'poste-autre', 'clients']] as [$auteur, $poste, $table]) {
            Journal::create([
                'id' => (string) Str::uuid(), 'uuid_operation' => (string) Str::uuid(), 'session_id' => 'session-1',
                'poste_id' => $poste, 'utilisateur_id' => $auteur->id, 'table_concernee' => $table,
                'entite_id' => (string) Str::uuid(), 'type_operation' => 'creation',
                'horodatage_poste' => now(), 'recu_le' => now(), 'issue' => Journal::REJETEE,
                'cause' => 'Cause de test '.$poste, 'tentatives' => 1, 'derniere_tentative_le' => now(), 'traitement' => Journal::A_TRAITER,
            ]);
        }

        $this->actingAs($guide);
        Livewire::test(Synchronisation::class)
            // 10/11/2026 (PO : « le REJOUER et voir la synchronisation doivent être accessibles à tous
            // les rôles ») : tout compte voit la page complète, journaux de réception compris.
            ->assertSee('onglets-synchronisation', false)
            ->assertSeeLivewire(\App\Pwa\Livewire\Transverse\ReceptionSynchronisation::class);
    }

    #[Test]
    public function un_non_admin_n_a_ni_sauvegarde_ni_reinitialisation_dans_import_export(): void
    {
        foreach (['receptionniste', 'guide', 'barman', 'cuisine'] as $role) {
            $this->app['auth']->forgetGuards();
            $this->actingAs($this->compte($role));

            $html = (string) $this->get('/pwa/import-export?onglet=sauvegardes')->assertOk()->getContent();
            $this->assertStringNotContainsString(e((string) __('pwa.import_export.onglet_sauvegardes')), $html, $role);
            $this->assertStringNotContainsString(e((string) __('pwa.import_export.onglet_restaurer')), $html, $role);
            $this->assertStringNotContainsString(e((string) __('pwa.import_export.onglet_seeders')), $html, $role);
            $this->assertStringNotContainsString('data-panneau-ie="sauvegardes"', $html, $role);

            // Les actions refusent même appelées à la main.
            Livewire::test(ImportExport::class)->call('genererSauvegarde')->assertForbidden();
            Livewire::test(ImportExport::class)->call('telechargerSauvegarde', 'x.sql')->assertForbidden();
            Livewire::test(ImportExport::class)->call('ouvrirExport')->assertForbidden();
            Livewire::test(ImportExport::class)->call('restaurerArchive', 'hors_service', 'x')->assertForbidden();
            Livewire::test(ImportExport::class)->call('controlerFichierImport')->assertForbidden();
            Livewire::test(ImportExport::class)->call('telechargerModele')->assertForbidden();
            // Et la réinitialisation n'est plus de cette page : elle est aux Paramètres,
            // réservée aux administrateurs (403).
            Livewire::test(Parametres::class)->call('ouvrirReinitialisation')->assertForbidden();
        }
    }

    #[Test]
    public function l_administrateur_garde_les_onglets_d_administration_et_le_bouton_de_reinitialisation_aux_parametres(): void
    {
        $this->actingAs($this->compte('administrateur'));

        $html = (string) $this->get('/pwa/import-export')->assertOk()->getContent();
        $this->assertStringContainsString(e((string) __('pwa.import_export.onglet_sauvegardes')), $html);
        $this->assertStringContainsString(e((string) __('pwa.import_export.onglet_restaurer')), $html);
        $this->assertStringNotContainsString('data-panneau-ie="seeders"', $html);

        $html = (string) $this->get('/pwa/parametres?onglet=activation')->assertOk()->getContent();
        $this->assertStringContainsString('Réinitialiser les données de test', $html);
    }
}
