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
 * `C` (gérant, comptable, administrateurs) agit ; `L` (barman…) voit la page en lecture seule ;
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
            $this->assertSame($attendu, $this->compte($role)->niveauSurModule('IMPORT_EXPORT'), "$role en base");
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
    public function le_barman_voit_la_page_en_lecture_seule_et_tous_les_gestes_sont_refuses(): void
    {
        $this->actingAs($this->compte('barman'));

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
    public function le_droit_du_gerant_passe_de_c_a_l_met_la_page_en_lecture_seule_sans_reconnexion(): void
    {
        $service = app(RolePermissionService::class);
        $role = Role::where('libelle', 'gerant')->firstOrFail();
        $compte = $this->compte('gerant');
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

        $page()->assertOk()->assertSee('Sauvegardes de la base');
        $composant()->assertViewHas('peutEcrire', true);

        $service->definirNiveau($role->fresh(), 'IMPORT_EXPORT', 'L');

        $reponse = $page()->assertOk();
        $reponse->assertDontSee('Sauvegardes de la base');
        $composant()->assertViewHas('peutEcrire', false)->call('genererSauvegarde')->assertForbidden();

        $service->definirNiveau($role->fresh(), 'IMPORT_EXPORT', '-');
        $page()->assertForbidden();

        // « Mettre à jour les rôles » (socle) rend l'accès total sans reconnexion.
        $service->retablirSocle(['gerant']);
        $page()->assertOk()->assertSee('Sauvegardes de la base');
        $composant()->assertViewHas('peutEcrire', true);
    }
}
