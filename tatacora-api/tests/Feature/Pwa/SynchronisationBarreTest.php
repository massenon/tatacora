<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Livewire\Transverse\SynchronisationBarre;
use App\Shared\Sync\Services\SuiviPostesService;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\UtilisateurSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * L'icône de synchronisation de la barre supérieure (03/11/2026) : le voyant
 * suit UNE règle (`SuiviPostesService::voyant`), la modale montre l'état des
 * postes et la demande, et l'action est ouverte à tout compte connecté.
 */
final class SynchronisationBarreTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(UtilisateurSeeder::class);
    }

    private function compte(string $login = 'admin'): User
    {
        return User::query()->where('login', $login)->firstOrFail();
    }

    private function apparier(string $poste, ?\DateTimeInterface $dernierContact): void
    {
        $jeton = $this->compte()->createToken($poste)->accessToken;
        $jeton->forceFill(['last_used_at' => $dernierContact])->save();
    }

    #[Test]
    public function la_barre_porte_l_icone_et_son_voyant_sur_chaque_ecran(): void
    {
        $this->actingAs($this->compte());

        $this->get(route('pwa.accueil'))
            ->assertOk()
            ->assertSee('id="bouton-synchronisation"', false)
            ->assertSee('data-voyant="gris"', false)
            ->assertSee(__('pwa.synchronisation_barre.etiquette'));
    }

    #[Test]
    public function le_voyant_est_gris_vert_ou_orange_selon_le_battement(): void
    {
        $suivi = app(SuiviPostesService::class);
        $this->assertSame('gris', $suivi->voyant());

        $this->apparier('poste-a', now()->subMinutes(2));
        $this->assertSame('vert', $suivi->voyant());

        $this->apparier('poste-b', now()->subMinutes(SuiviPostesService::RETARD_MAX_MINUTES + 1));
        $this->assertSame('orange', $suivi->voyant());
    }

    #[Test]
    public function un_poste_jamais_vu_ou_revoque_est_traite_comme_la_regle_le_dit(): void
    {
        // Un jeton sans usage compte depuis sa création (COALESCE) : un poste
        // appairé à l'instant n'est pas « en retard » ; un jeton ancien jamais
        // utilisé l'est.
        $this->apparier('poste-neuf', null);
        $this->assertSame('vert', app(SuiviPostesService::class)->voyant());
        \Laravel\Sanctum\PersonalAccessToken::query()->update(['created_at' => now()->subHour()]);
        $this->assertSame('orange', app(SuiviPostesService::class)->voyant());
        $this->assertTrue(SuiviPostesService::enRetard(['jeton_utilise_le' => null]));

        // Révoqué : plus de jeton, plus attendu — retour au gris.
        $this->compte()->tokens()->delete();
        $this->assertSame('gris', app(SuiviPostesService::class)->voyant());
    }

    #[Test]
    public function la_modale_s_ouvre_liste_les_postes_et_se_ferme(): void
    {
        $this->apparier('poste-comptoir', now()->subHour());
        $this->actingAs($this->compte());

        Livewire::test(SynchronisationBarre::class)
            ->assertDontSee('poste-comptoir')
            ->call('ouvrir')
            ->assertSee('poste-comptoir')
            ->assertSee(__('pwa.synchronisation_barre.en_retard'))
            ->assertSee(__('pwa.synchronisation_postes.aucune_demande'))
            ->assertSee(__('pwa.synchronisation_postes.bouton'))
            ->call('fermer')
            ->assertDontSee('poste-comptoir');
    }

    #[Test]
    public function la_demande_est_enregistree_et_confirmee_pour_tout_compte(): void
    {
        $this->actingAs($this->compte('admin'));
        Livewire::test(SynchronisationBarre::class)
            ->call('ouvrir')
            ->call('demander')
            ->assertSee('Demande envoyée le')
            ->assertSee('id="confirmation-synchronisation-barre"', false);

        $this->assertDatabaseCount('demandes_synchronisation', 1);
    }

    #[Test]
    public function une_demande_sans_compte_connecte_est_refusee(): void
    {
        Livewire::test(SynchronisationBarre::class)->call('demander')->assertForbidden();

        $this->assertDatabaseCount('demandes_synchronisation', 0);
    }
}
