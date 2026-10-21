<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Pwa\Livewire\Transverse\SynchronisationPostes;
use App\Shared\Sync\Models\DemandeSynchronisation;
use App\Shared\Sync\Services\SuiviPostesService;
use App\Shared\Sync\Models\EtatPosteSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le bouton « Synchroniser » du serveur (décision PO du 18/10/2026) : la PWA
 * enregistre une demande, le poste la lit (`/sync/demande`) puis descend ;
 * l'écran dit, poste par poste, ce que le serveur en sait.
 */
final class BoutonSynchroniserServeurTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-18 10:00:00');
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function la_demande_du_serveur_est_lue_par_le_poste_puis_suivie_par_sa_descente(): void
    {
        $poste = $this->creerUtilisateur('receptionniste');
        $pwa = $this->creerUtilisateur('barman');

        Sanctum::actingAs($poste);
        $this->getJson('/api/v1/sync/demande?poste_id=poste-a')->assertOk()->assertJsonPath('data.demandee_le', null);

        // Un compte quelconque de la PWA demande ; un second clic dans la
        // minute ne double pas la demande.
        $this->actingAs($pwa);
        Livewire::test(SynchronisationPostes::class)
            ->call('synchroniser')
            ->assertSee('Demande envoyée le 18/10/2026 10:00:00')
            ->call('synchroniser');
        $this->assertSame(1, DemandeSynchronisation::count());

        Sanctum::actingAs($poste);
        $this->getJson('/api/v1/sync/demande?poste_id=poste-a')->assertOk()
            ->assertJsonPath('data.demandee_le', now()->toIso8601String());

        Livewire::actingAs($pwa)->test(SynchronisationPostes::class)->assertSee('poste-a')->assertSee('Pas encore reçue');

        $this->travel(20)->seconds();
        Sanctum::actingAs($poste);
        $this->getJson('/api/v1/referentiels?poste_id=poste-a&en_attente=3')->assertOk();

        Livewire::actingAs($pwa)->test(SynchronisationPostes::class)
            ->assertSee('Reçue')
            ->assertDontSee('Pas encore reçue')
            ->assertSee($poste->login);
    }

    #[Test]
    public function postes_et_appairage_dit_les_neuf_colonnes_et_l_etat_de_chaque_poste(): void
    {
        $compte = $this->creerUtilisateur('receptionniste');
        $admin = $this->creerUtilisateur('administrateur');
        $compte->createToken('poste-actif');
        $compte->createToken('poste-expire', ['*'], now()->subDay());
        $compte->createToken('poste-valide', ['*'], now()->addDays(30))->accessToken->forceFill(['last_used_at' => now()->subDays(3)])->save();
        // Un poste connu seulement par son état : plus de jeton (révoqué).
        $this->actingAs($compte);
        EtatPosteSynchronisation::create(['poste_id' => 'poste-revoque', 'utilisateur_id' => $compte->id]);

        $etats = collect(app(SuiviPostesService::class)->etats())->keyBy('poste_id');

        $this->assertSame('actif', $etats['poste-actif']['etat']);
        $this->assertNull($etats['poste-actif']['expire_le'], 'sans expiration');
        $this->assertSame('expire', $etats['poste-expire']['etat']);
        $this->assertSame('silencieux', $etats['poste-valide']['etat']);
        $this->assertNotNull($etats['poste-valide']['expire_le']);
        $this->assertSame('non_appaire', $etats['poste-revoque']['etat']);
        $this->assertNull($etats['poste-revoque']['appaire_le']);
        $this->assertNotNull($etats['poste-actif']['appaire_le']);

        $page = Livewire::actingAs($admin)->test(SynchronisationPostes::class);
        foreach (['Poste', 'Utilisateur', 'Appairé le', 'Dernier contact', 'Expiration', 'Dernier envoi', 'Dernier contrôle', 'État', 'Actions'] as $colonne) {
            $page->assertSee($colonne);
        }
        $page->assertSee('Sans expiration')->assertSee('Expiré')->assertSee('Sans nouvelles')->assertSee('Non appairé')
            ->call('actualiser')->assertSee('poste-actif');
    }

    #[Test]
    public function le_dernier_controle_est_note_au_passage_du_poste_sur_la_coherence(): void
    {
        $compte = $this->creerUtilisateur('receptionniste');
        $jeton = $compte->createToken('poste-a')->plainTextToken;

        $this->assertNull(EtatPosteSynchronisation::query()->where('poste_id', 'poste-a')->value('dernier_controle_le'));

        $this->withToken($jeton)->getJson('/api/v1/sync/coherence?du=2026-10-01&au=2026-10-18')->assertOk();

        $this->assertNotNull(EtatPosteSynchronisation::query()->where('poste_id', 'poste-a')->value('dernier_controle_le'));
        $this->withToken($jeton)->getJson('/api/v1/sync/postes')->assertOk()
            ->assertJsonPath('data.postes.0.poste_id', 'poste-a')
            ->assertJsonPath('data.postes.0.dernier_controle', now()->toIso8601String())
            ->assertJsonPath('data.postes.0.etat', 'actif');
    }

    #[Test]
    public function l_entree_de_menu_synchronisation_suit_le_droit_sur_parametres_et_le_menu_de_compte_reste(): void
    {
        $admin = $this->creerUtilisateur('administrateur');

        $this->actingAs($admin)->get('/pwa')->assertOk()
            ->assertSee('Synchronisation')
            ->assertSee('href="'.route('pwa.synchronisation-postes').'"', false);
        $this->actingAs($this->creerUtilisateur('gerant'))->get('/pwa')->assertOk()
            ->assertDontSee('>Synchronisation<', false);
    }

    #[Test]
    public function la_demande_refuse_un_poste_qui_n_est_pas_celui_du_jeton(): void
    {
        $compte = $this->creerUtilisateur('receptionniste');
        $jeton = $compte->createToken('poste-a')->plainTextToken;

        $this->withToken($jeton)->getJson('/api/v1/sync/demande?poste_id=poste-b')->assertForbidden();
        $this->withToken($jeton)->getJson('/api/v1/sync/demande')->assertUnprocessable();
    }

    #[Test]
    public function la_page_est_ouverte_a_tout_compte_et_au_menu_de_compte(): void
    {
        $guide = $this->creerUtilisateur('guide');

        $this->actingAs($guide)->get(route('pwa.synchronisation-postes'))->assertOk()
            ->assertSee('Demander la synchronisation des postes')
            ->assertSee('Postes &amp; Appairage', false)
            ->assertSee('Actualiser')
            ->assertSee('Aucun poste ne s');
        $this->actingAs($guide)->get('/pwa')->assertOk()
            ->assertSee('href="'.route('pwa.synchronisation-postes').'"', false);
    }

    #[Test]
    public function l_ecran_du_poste_demande_et_lit_l_etat_des_postes_par_l_api(): void
    {
        $compte = $this->creerUtilisateur('guide');
        Sanctum::actingAs($compte);

        $this->postJson('/api/v1/sync/demande')->assertCreated()
            ->assertJsonPath('data.demandee_le', now()->toIso8601String());
        $this->getJson('/api/v1/referentiels?poste_id=poste-a&en_attente=2')->assertOk();

        $this->getJson('/api/v1/sync/postes')->assertOk()
            ->assertJsonPath('data.demandee_le', now()->toIso8601String())
            ->assertJsonPath('data.postes.0.poste_id', 'poste-a')
            ->assertJsonPath('data.postes.0.en_attente', 2)
            ->assertJsonPath('data.postes.0.demande_suivie', true)
            ->assertJsonPath('data.postes.0.utilisateur', $compte->login);
    }
}
