<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Models\User;
use App\Pwa\Livewire\Transverse\SynchronisationPostes;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Sync\Services\SuiviPostesService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\PersonalAccessToken;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Révoquer l'appairage d'un poste — décision du Product Owner du 19/10/2026
 * (gérer l'appairage « dans le poste et le web »). Le jeton du poste porte
 * son NOM ; révoquer supprime les jetons de ce nom, tous comptes confondus :
 * le poste reçoit 401 au passage suivant (sa file reste intacte, côté poste),
 * les autres postes continuent. Réservé aux Administrateurs, tracé.
 */
final class RevocationAppairageTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-19 09:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->admin = $this->creerUtilisateur('administrateur');
    }

    private function appairer(string $poste, User $compte): string
    {
        return $compte->createToken($poste)->plainTextToken;
    }

    private function appel(string $methode, string $url, string $jeton): \Illuminate\Testing\TestResponse
    {
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer ' . $jeton)->json($methode, $url);
    }

    #[Test]
    public function un_administrateur_revoque_un_poste_depuis_la_pwa_les_autres_continuent(): void
    {
        $reception = $this->creerUtilisateur('receptionniste');
        $jetonA = $this->appairer('PC-COMPTOIR', $this->creerUtilisateur('barman'));
        $jetonB = $this->appairer('PC-RECEPTION', $reception);
        // Réappairé par un autre compte : DEUX jetons du même nom.
        $this->appairer('PC-RECEPTION', $this->admin);

        $this->appel('GET', '/api/v1/sync/demande?poste_id=PC-RECEPTION', $jetonB)->assertOk();

        $this->actingAs($this->admin);
        Livewire::test(SynchronisationPostes::class)
            ->assertSee('Appairage')
            ->assertSee('PC-RECEPTION')
            ->assertSee('Appairé — dernier usage 19/10/2026 09:00')
            ->call('demanderRevocation', 'PC-RECEPTION')
            ->assertSet('posteARevoquer', 'PC-RECEPTION')
            ->assertSee('Révoquer l\'appairage du poste « PC-RECEPTION » ?')
            ->call('annulerRevocation')
            ->assertSet('posteARevoquer', null);
        $this->assertSame(2, PersonalAccessToken::where('name', 'PC-RECEPTION')->count());

        Livewire::test(SynchronisationPostes::class)
            ->call('demanderRevocation', 'PC-RECEPTION')
            ->call('revoquer')
            ->assertSee('Appairage du poste « PC-RECEPTION » révoqué.')
            ->assertSee('Non appairé');

        $this->assertSame(0, PersonalAccessToken::where('name', 'PC-RECEPTION')->count());
        $trace = JournalAudit::where('action', 'appairage_revoque')->firstOrFail();
        $this->assertSame(['poste' => 'PC-RECEPTION', 'jetons' => 2], $trace->valeur_apres);
        $this->assertSame($this->admin->id, $trace->utilisateur_id);

        $this->appel('GET', '/api/v1/sync/demande?poste_id=PC-RECEPTION', $jetonB)->assertUnauthorized();
        $this->appel('GET', '/api/v1/sync/demande?poste_id=PC-COMPTOIR', $jetonA)->assertOk();
    }

    #[Test]
    public function hors_administration_personne_ne_revoque(): void
    {
        $this->appairer('PC-RECEPTION', $this->admin);
        $gerant = $this->creerUtilisateur('gerant');

        $this->actingAs($gerant);
        Livewire::test(SynchronisationPostes::class)
            ->assertDontSeeHtml('wire:click="demanderRevocation')
            ->call('demanderRevocation', 'PC-RECEPTION')
            ->assertForbidden();
        Livewire::test(SynchronisationPostes::class)
            ->set('posteARevoquer', 'PC-RECEPTION')
            ->call('revoquer')
            ->assertForbidden();

        $this->appel('POST', '/api/v1/sync/postes/PC-RECEPTION/revocation', $this->appairer('PC-GERANT', $gerant))
            ->assertForbidden();
        $this->assertSame(1, PersonalAccessToken::where('name', 'PC-RECEPTION')->count());

        $this->expectException(RuntimeException::class);
        app(SuiviPostesService::class)->revoquer('PC-RECEPTION', $gerant);
    }

    #[Test]
    public function depuis_un_poste_l_administrateur_revoque_un_autre_poste_jamais_le_sien(): void
    {
        $jetonAdmin = $this->appairer('PC-BUREAU', $this->admin);
        $this->appairer('PC RÉCEPTION', $this->creerUtilisateur('receptionniste'));

        $this->appel('GET', '/api/v1/sync/postes', $jetonAdmin)->assertOk()
            ->assertJsonPath('data.postes.0.poste_id', 'PC RÉCEPTION')
            ->assertJsonPath('data.postes.0.appaire', true);

        $this->appel('POST', '/api/v1/sync/postes/' . rawurlencode('PC RÉCEPTION') . '/revocation', $jetonAdmin)
            ->assertOk()
            ->assertJsonPath('data.jetons_revoques', 1);
        $this->assertSame(0, PersonalAccessToken::where('name', 'PC RÉCEPTION')->count());

        // Déjà révoqué : dit, rien d'autre ne bouge.
        $this->appel('POST', '/api/v1/sync/postes/' . rawurlencode('PC RÉCEPTION') . '/revocation', $jetonAdmin)
            ->assertStatus(422)
            ->assertJsonPath('message', __('sync.postes.poste_non_appaire', ['poste' => 'PC RÉCEPTION']));

        // Son propre appairage : refusé (il se « Dissocie »).
        $this->appel('POST', '/api/v1/sync/postes/PC-BUREAU/revocation', $jetonAdmin)
            ->assertStatus(422)
            ->assertJsonPath('message', __('sync.postes.revocation_soi_meme'));
        $this->assertSame(1, PersonalAccessToken::where('name', 'PC-BUREAU')->count());
    }
}
