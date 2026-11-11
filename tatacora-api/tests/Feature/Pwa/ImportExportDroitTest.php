<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Models\User;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le CRUD de « Import & Export » est piloté par le droit `IMPORT_EXPORT` (PO, 11/11/2026) :
 * `C` (rôles système : administrateurs, gérant, comptable, barman) agit ; `L` (réceptionniste…) voit la page en lecture seule ;
 * un droit passé de `C` à `L` change la page à la requête suivante, sans reconnexion.
 */
final class ImportExportDroitTest extends TestCase
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
            'login' => $role.'.ie.'.bin2hex(random_bytes(3)),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    #[Test]
    public function la_matrice_du_socle_donne_c_au_gerant_et_au_comptable_l_aux_autres(): void
    {
        foreach (RolePermissionSeeder::MATRICE as $role => $droits) {
            $attendu = in_array($role, ['super_admin', 'administrateur', 'gerant', 'comptable'], true) ? 'C' : 'L';
            $this->assertSame($attendu, $droits['IMPORT_EXPORT'], $role);
            // Niveau EFFECTIF : les rôles système (dont le barman, L au socle) ont toujours C.
            $effectif = in_array($role, User::ROLES_SYSTEME_IMPORT_EXPORT, true) ? 'C' : $attendu;
            $this->assertSame($effectif, $this->compte($role)->niveauSurModule('IMPORT_EXPORT'), "$role en base");
        }
    }

    #[Test]
    public function le_gerant_et_le_comptable_importent_sauvegardent_et_exportent(): void
    {
        foreach (['gerant', 'comptable'] as $role) {
            $this->app['auth']->forgetGuards();
            $this->actingAs($this->compte($role));
            Client::create(['nom' => 'Client '.$role, 'telephone' => '+229 01 00 00 00 13', 'type_client' => 'particulier']);

            Livewire::test(ImportExport::class)
                ->assertViewHas('peutEcrire', true)
                ->assertViewHas('accesAdministration', true)
                ->assertSee('Sauvegardes de la base')
                ->call('ouvrirExport')
                ->set('tableExport', 'clients')
                ->call('exporterTable')
                ->assertHasNoErrors()
                ->assertFileDownloaded('clients.json');

            $csv = "Nom / Raison sociale;Type de client;Téléphone;Email\nImport {$role};particulier;+229 01 97 00 00 0".strlen($role).";\n";
            $rapport = Livewire::test(ImportExport::class)
                ->set('moduleImport', 'm3-clients')
                ->set('fichierImport', UploadedFile::fake()->createWithContent('clients.csv', $csv))
                ->call('controlerFichierImport')
                ->assertHasNoErrors()
                ->get('rapportControle');
            $this->assertTrue($rapport['ok'], $role);

            // Sauvegarde et restauration : plus refusées (elles exigeaient PARAM en écriture).
            Livewire::test(ImportExport::class)->call('retirerSauvegarde', 'inexistante.sql.gz')->assertOk();
            Livewire::test(ImportExport::class)->call('restaurerArchive', 'hors_service', 'inconnu')->assertOk();
        }
    }

    #[Test]
    public function le_receptionniste_voit_la_page_en_lecture_seule_et_tous_les_gestes_sont_refuses(): void
    {
        // Preuve que la règle des rôles système est BORNÉE : un autre rôle du socle suit son droit L.
        $this->actingAs($this->compte('receptionniste'));

        $this->get(route('pwa.import-export'))->assertOk();

        Livewire::test(ImportExport::class)
            ->assertViewHas('peutEcrire', false)
            ->assertViewHas('accesAdministration', false)
            ->assertDontSee('Sauvegardes de la base')
            ->call('ouvrirExport')->assertForbidden();

        Livewire::test(ImportExport::class)->call('genererSauvegarde')->assertForbidden();
        Livewire::test(ImportExport::class)->call('retirerSauvegarde', 'x.sql.gz')->assertForbidden();
        Livewire::test(ImportExport::class)->call('restaurerArchive', 'hors_service', 'x')->assertForbidden();
        Livewire::test(ImportExport::class)
            ->set('moduleImport', 'm3-clients')
            ->set('fichierImport', UploadedFile::fake()->createWithContent('c.csv', "a;b\n"))
            ->call('controlerFichierImport')->assertForbidden();
        Livewire::test(ImportExport::class)->set('tableExport', 'clients')->call('exporterTable')->assertForbidden();
    }

    #[Test]
    public function le_droit_du_receptionniste_passe_de_c_a_l_met_la_page_en_lecture_seule_sans_reconnexion(): void
    {
        $service = app(RolePermissionService::class);
        $role = Role::where('libelle', 'receptionniste')->firstOrFail();
        $compte = $this->compte('receptionniste');
        $cle = $this->app['auth']->guard('web')->getName();

        // Même session, aucune nouvelle authentification : l'utilisateur est relu en base.
        $page = function () use ($compte, $cle) {
            $this->app['auth']->forgetGuards();

            return $this->withSession([$cle => $compte->id])->get(route('pwa.import-export'));
        };
        $composant = function () use ($compte) {
            $this->app['auth']->forgetGuards();
            $this->actingAs(User::findOrFail($compte->id));

            return Livewire::test(ImportExport::class);
        };

        $service->definirNiveau($role->fresh(), 'IMPORT_EXPORT', 'C');
        $page()->assertOk()->assertSee('Sauvegardes de la base');
        $composant()->assertViewHas('peutEcrire', true);

        $service->definirNiveau($role->fresh(), 'IMPORT_EXPORT', 'L');

        $reponse = $page()->assertOk();
        $reponse->assertDontSee('Sauvegardes de la base');
        $composant()->assertViewHas('peutEcrire', false)->call('genererSauvegarde')->assertForbidden();

        $service->definirNiveau($role->fresh(), 'IMPORT_EXPORT', '-');
        $page()->assertForbidden();

        // « Mettre à jour les rôles » (socle) rend l'accès total sans reconnexion.
        $service->definirNiveau($role->fresh(), 'IMPORT_EXPORT', 'C');
        $page()->assertOk()->assertSee('Sauvegardes de la base');
        $composant()->assertViewHas('peutEcrire', true);
    }
    /**
     * Directive PO du 11/11/2026 : les utilisateurs SYSTÈME ont TOUJOURS l'accès complet à Import &
     * Export (trois onglets, tous les gestes), même sans RBAC — ligne absente, `-` ou `L`.
     *
     * @return array<string, array{0: string, 1: string}>
     */
    public static function systemeEtNiveaux(): array
    {
        $cas = [];
        foreach (User::ROLES_SYSTEME_IMPORT_EXPORT as $role) {
            foreach (['-', 'L'] as $niveau) {
                $cas["$role en $niveau"] = [$role, $niveau];
            }
        }

        return $cas;
    }

    #[Test]
    #[\PHPUnit\Framework\Attributes\DataProvider('systemeEtNiveaux')]
    public function les_utilisateurs_systeme_gardent_l_acces_complet_quelle_que_soit_la_ligne_en_base(string $role, string $niveau): void
    {
        $service = app(RolePermissionService::class);
        $service->definirNiveau(Role::where('libelle', $role)->firstOrFail(), 'IMPORT_EXPORT', $niveau);
        $compte = $this->compte($role);

        // La ligne stockée est bien celle de la matrice modifiée (le droit est implicite, pas réécrit).
        $this->assertSame($niveau, Role::where('libelle', $role)->firstOrFail()->niveauSurModule('IMPORT_EXPORT'));
        $this->assertSame('C', $compte->niveauSurModule('IMPORT_EXPORT'));

        $this->actingAs($compte);
        Client::create(['nom' => 'Client '.$role, 'telephone' => '+229 01 00 00 00 14', 'type_client' => 'particulier']);

        foreach (['importer', 'sauvegardes', 'restaurer'] as $onglet) {
            $this->get(route('pwa.import-export', ['onglet' => $onglet]))->assertOk()
                ->assertSee('Sauvegardes de la base')->assertSee('Restaurer');
            Livewire::test(ImportExport::class, ['onglet' => $onglet])
                ->assertViewHas('onglet', $onglet)
                ->assertViewHas('peutEcrire', true)
                ->assertViewHas('accesAdministration', true);
        }

        Livewire::test(ImportExport::class)
            ->call('ouvrirExport')->assertOk()
            ->set('tableExport', 'clients')->call('exporterTable')
            ->assertHasNoErrors()->assertFileDownloaded('clients.json');
        Livewire::test(ImportExport::class)->call('genererSauvegarde')->assertOk();
        Livewire::test(ImportExport::class)->call('retirerSauvegarde', 'inexistante.sql.gz')->assertOk();
        Livewire::test(ImportExport::class)->call('restaurerArchive', 'hors_service', 'inconnu')->assertOk();
        // L'import d'un module exige en plus l'écriture du module importé (M3 : le barman n'a pas).
        if ($compte->niveauSurModule('M3') === 'C') {
            $rapport = Livewire::test(ImportExport::class)
                ->set('moduleImport', 'm3-clients')
                ->set('fichierImport', UploadedFile::fake()->createWithContent('clients.csv', "Nom / Raison sociale;Type de client;Téléphone;Email\nImport {$role};particulier;+229 01 97 00 00 07;\n"))
                ->call('controlerFichierImport')->assertHasNoErrors()->get('rapportControle');
            $this->assertTrue($rapport['ok']);
        }

        // La purge reste au super_admin seul ; aucun autre rôle système n'y gagne rien.
        $page = Livewire::test(ImportExport::class);
        $page->assertViewHas('estSuperAdmin', $role === 'super_admin');
        if ($role !== 'super_admin') {
            Livewire::test(ImportExport::class)->call('purgerArchive')->assertForbidden();
        }
    }

    #[Test]
    public function la_ligne_import_export_supprimee_ne_limite_pas_l_administrateur_mais_limite_les_roles_hors_liste(): void
    {
        $role = Role::where('libelle', 'administrateur')->firstOrFail();
        $role->permissions()->detach($role->permissions()->where('module', 'IMPORT_EXPORT')->pluck('permissions.id'));
        $this->assertSame('-', $role->fresh()->niveauSurModule('IMPORT_EXPORT'));
        $this->assertSame('C', $this->compte('administrateur')->niveauSurModule('IMPORT_EXPORT'));

        // Un rôle hors liste (réceptionniste) suit son droit : `L` = lecture seule, jamais plus.
        $this->actingAs($this->compte('receptionniste'));
        Livewire::test(ImportExport::class)->assertViewHas('peutEcrire', false)->call('genererSauvegarde')->assertForbidden();
    }

    #[Test]
    public function la_regle_implicite_est_portee_par_user_et_par_la_reponse_de_connexion(): void
    {
        $this->assertSame(['IMPORT_EXPORT'], User::MODULES_IMPLICITES_SYSTEME);
        $this->assertSame(['super_admin', 'administrateur', 'comptable', 'gerant', 'barman'], User::ROLES_SYSTEME_IMPORT_EXPORT);
        foreach (User::ROLES_SYSTEME_IMPORT_EXPORT as $role) {
            $this->assertTrue($this->compte($role)->estRoleSystemeImportExport(), $role);
        }
        foreach (['receptionniste', 'cuisine', 'magasinier', 'achats', 'vehicules', 'guide', 'rh'] as $role) {
            if (Role::where('libelle', $role)->exists()) {
                $this->assertFalse($this->compte($role)->estRoleSystemeImportExport(), $role);
            }
        }
        // Les autres modules d'un administrateur ne sont PAS relevés : le reste suit le RBAC.
        $role = Role::where('libelle', 'administrateur')->firstOrFail();
        app(RolePermissionService::class)->definirNiveau($role, 'M3', 'L');
        $this->assertSame('L', $this->compte('administrateur')->niveauSurModule('M3'));
    }
}
