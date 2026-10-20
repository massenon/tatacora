<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Models\User;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Shared\Backup\Services\ReinitialisationDonneesTestService;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Sync\Http\Middleware\GenerationDesDonnees;
use App\Shared\Sync\Models\GenerationDonnees;
use App\Shared\Sync\Services\GenerationDonneesService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Symfony\Component\Process\Process;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les essais en production, puis la réinitialisation sur le web ET les
 * postes — décision du Product Owner du 19/10/2026.
 *
 *  1. En Production, la réinitialisation n'est possible que pendant la
 *     phase d'essais (`TATACORA_PHASE_ESSAIS=true`), et l'écran le dit.
 *  2. Elle ouvre une GÉNÉRATION nouvelle : un poste qui rappelle l'ancienne
 *     est refusé (409) à l'envoi comme à la descente — rien n'est écrit ;
 *     un poste réinitialisé (qui n'en rappelle aucune) adopte la nouvelle.
 */
final class ReinitialisationPhaseEssaisTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->admin = $this->creerUtilisateur('administrateur');
        ParametreSysteme::updateOrCreate(['cle' => ReinitialisationDonneesTestService::CLE_BASCULE], ['valeur' => 'true']);
    }

    private function enProduction(bool $phaseEssais): void
    {
        $this->app->detectEnvironment(static fn (): string => 'production');
        config(['tatacora.phase_essais' => $phaseEssais]);
    }

    /** @param  array<string, mixed>  $corps */
    private function envoyer(array $corps): \Illuminate\Testing\TestResponse
    {
        Sanctum::actingAs($this->admin);

        return $this->postJson('/api/v1/sync', ['poste_id' => 'poste-a', ...$corps]);
    }

    #[Test]
    public function en_production_hors_phase_d_essais_la_reinitialisation_reste_refusee(): void
    {
        $this->enProduction(false);
        $service = app(ReinitialisationDonneesTestService::class);

        $this->assertFalse($service->estAutorisee());
        $this->actingAs($this->admin);
        Livewire::test(ImportExport::class, ['onglet' => 'seeders'])
            ->assertSee(__('pwa.import_export.reset_environnement_production'))
            ->assertDontSee(__('pwa.import_export.reset_phase_essais'));
    }

    #[Test]
    public function pendant_la_phase_d_essais_elle_vide_la_production_et_ouvre_une_generation(): void
    {
        if ((new Process([config('backup.mysqldump', 'mysqldump'), '--version']))->run() !== 0) {
            $this->markTestSkipped('mysqldump introuvable.');
        }

        // La sauvegarde préalable est RÉELLE : celle de ce test est retirée
        // après lui (elle polluerait les relevés de la vue Import & Export).
        $deja = glob(storage_path('app/sauvegardes/tatacora-*.sql')) ?: [];
        $this->beforeApplicationDestroyed(static function () use ($deja): void {
            foreach (array_diff(glob(storage_path('app/sauvegardes/tatacora-*.sql')) ?: [], $deja) as $f) {
                @unlink($f);
            }
        });

        $avant = app(GenerationDonneesService::class)->courante()->generation;
        $client = Client::create(['nom' => 'Client d\'essai', 'telephone' => '+229 01 00 00 00 77', 'type_client' => 'particulier']);
        $this->enProduction(true);

        $this->actingAs($this->admin);
        Livewire::test(ImportExport::class, ['onglet' => 'seeders'])
            ->assertSee(__('pwa.import_export.reset_phase_essais'))
            ->call('ouvrirReinitialisation')
            ->set('phraseConfirmationReset', 'VIDER')
            ->call('reinitialiserDonneesTest')
            ->assertHasNoErrors();

        $this->assertNull($client->fresh());
        $apres = app(GenerationDonneesService::class)->courante();
        $this->assertNotSame($avant, $apres->generation);
        $this->assertSame(GenerationDonneesService::MOTIF_REINITIALISATION, $apres->motif);
        $this->assertSame(2, GenerationDonnees::count());
    }

    #[Test]
    public function un_poste_d_avant_la_reinitialisation_est_refuse_un_poste_reinitialise_adopte_la_nouvelle(): void
    {
        $g0 = app(GenerationDonneesService::class)->courante()->generation;

        // Avant : le poste n'en connaît aucune, il apprend la courante.
        $this->envoyer(['operations' => [$this->creation('clients', $this->uuid(), ['nom' => 'Essai', 'telephone' => '96000001', 'type_client' => 'particulier'])]])
            ->assertOk()
            ->assertHeader(GenerationDesDonnees::ENTETE, $g0)
            ->assertHeader(GenerationDesDonnees::ENTETE_PHASE_ESSAIS, '0');
        $this->envoyer(['generation' => $g0, 'operations' => [$this->creation('clients', $this->uuid(), ['nom' => 'Essai 2', 'telephone' => '96000002', 'type_client' => 'particulier'])]])
            ->assertOk();
        $this->assertSame(2, Client::count());

        // Le serveur est réinitialisé (ouverture de la génération seule ici :
        // le vidage complet est éprouvé ci-dessus).
        $g1 = app(GenerationDonneesService::class)->ouvrir($this->admin)->generation;
        Client::query()->delete();

        // Le poste d'avant : 409, RIEN n'est écrit, ni à l'envoi ni servi.
        $refus = $this->envoyer(['generation' => $g0, 'operations' => [$this->creation('clients', $this->uuid(), ['nom' => 'Essai 3', 'telephone' => '96000003', 'type_client' => 'particulier'])]])
            ->assertStatus(409)
            ->assertJsonPath('code', GenerationDesDonnees::CODE_PERIMEE)
            ->assertJsonPath('generation', $g1)
            ->assertHeader(GenerationDesDonnees::ENTETE, $g1);
        $this->assertStringContainsString('réinitialisé', (string) $refus->json('message'));
        $this->assertSame(0, Client::count());

        $this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-a', 'generation' => $g0]))
            ->assertStatus(409)
            ->assertJsonPath('code', GenerationDesDonnees::CODE_PERIMEE);
        $this->getJson('/api/v1/sync/demande?' . http_build_query(['poste_id' => 'poste-a', 'generation' => $g0]))
            ->assertStatus(409);

        // Le poste réinitialisé n'en rappelle aucune : il adopte la nouvelle.
        $this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-a']))
            ->assertOk()
            ->assertHeader(GenerationDesDonnees::ENTETE, $g1);
        $this->envoyer(['generation' => $g1, 'operations' => [$this->creation('clients', $this->uuid(), ['nom' => 'Réel', 'telephone' => '96000004', 'type_client' => 'particulier'])]])
            ->assertOk();
        $this->assertSame(['Réel'], Client::pluck('nom')->all());
    }

    #[Test]
    public function les_postes_apprennent_la_phase_d_essais(): void
    {
        $this->enProduction(true);
        Sanctum::actingAs($this->admin);
        $this->getJson('/api/v1/sync/demande?poste_id=poste-a')
            ->assertOk()
            ->assertHeader(GenerationDesDonnees::ENTETE_PHASE_ESSAIS, '1');
    }

    #[Test]
    public function la_generation_survit_a_la_reinitialisation_et_n_est_pas_dans_le_flux(): void
    {
        $this->assertContains('generations_donnees', ReinitialisationDonneesTestService::TABLES_PRESERVEES);

        Sanctum::actingAs($this->admin);
        $tables = collect($this->getJson('/api/v1/referentiels?poste_id=poste-a&limite=500')->assertOk()->json('data.elements'))
            ->pluck('table')->unique()->all();
        $this->assertNotContains('generations_donnees', $tables);
    }
}
