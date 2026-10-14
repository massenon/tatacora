<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Livewire\Transverse\VerrouSession;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le verrou de session (demande du Product Owner, 01/09/2026).
 *
 * ## Ce qui compte, et que la relecture seule ne prouve pas
 *
 * 1. Le bon mot de passe DÉVERROUILLE réellement (`Auth::validate` doit
 *    parler au provider : `login` + `password` → `mot_de_passe_hash` via
 *    `getAuthPassword()`). Un provider mal câblé rendrait le verrou
 *    indéverrouillable pour toujours — la page fonctionnerait parfaitement
 *    jusqu'au premier voile, puis enfermerait tout le monde dehors.
 * 2. Il ne touche JAMAIS à la session : après un déverrouillage comme après
 *    un échec, l'utilisateur est toujours authentifié — le panier ouvert au
 *    POS n'a pas bougé.
 * 3. Un compte inconnu du serveur (session morte) est renvoyé à la
 *    connexion, jamais laissé devant un voile qui ne peut plus rien.
 * 4. Cinq échecs limitent la cadence, comme à la connexion.
 *
 * ## Mutation vérifiée (01/09/2026)
 *
 * `Auth::validate` remplacé par `false` (verrou qui refuse tout) → rouge sur
 * le cas 1 ; `RateLimiter::hit` retiré → rouge sur le cas 4.
 */
final class VerrouSessionTest extends TestCase
{
    use RefreshDatabase;

    private User $utilisateur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->utilisateur = User::create([
            'login' => 'reception.verrou',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-correct'),
            'role_id' => Role::where('libelle', 'receptionniste')->firstOrFail()->id,
            'statut' => 'actif',
        ]);

        RateLimiter::clear('verrou-session|'.$this->utilisateur->id);
    }

    #[Test]
    public function le_bon_mot_de_passe_deverrouille_sans_toucher_a_la_session(): void
    {
        $this->actingAs($this->utilisateur);

        Livewire::test(VerrouSession::class)
            ->set('motDePasse', 'mot-de-passe-correct')
            ->call('deverrouiller')
            ->assertHasNoErrors()
            ->assertDispatched('session-deverrouillee')
            // Le champ est purgé après CHAQUE tentative, succès compris.
            ->assertSet('motDePasse', '');

        $this->assertTrue(Auth::check(), 'Le déverrouillage ne ré-authentifie pas : la session n\'a pas bougé.');
    }

    #[Test]
    public function un_mauvais_mot_de_passe_refuse_sans_deconnecter(): void
    {
        $this->actingAs($this->utilisateur);

        Livewire::test(VerrouSession::class)
            ->set('motDePasse', 'faux')
            ->call('deverrouiller')
            ->assertHasErrors('motDePasse')
            ->assertNotDispatched('session-deverrouillee')
            ->assertSet('motDePasse', '');

        $this->assertTrue(Auth::check(), 'Un échec de verrou ne ferme jamais la session : le panier du POS est dessous.');
    }

    #[Test]
    public function cinq_echecs_limitent_la_cadence(): void
    {
        $this->actingAs($this->utilisateur);

        $composant = Livewire::test(VerrouSession::class);

        for ($i = 0; $i < 5; $i++) {
            $composant->set('motDePasse', 'faux')->call('deverrouiller');
        }

        // La sixième tentative est bloquée MÊME avec le bon mot de passe :
        // c'est la limitation qui parle, pas la vérification.
        $composant->set('motDePasse', 'mot-de-passe-correct')
            ->call('deverrouiller')
            ->assertHasErrors('motDePasse')
            ->assertNotDispatched('session-deverrouillee');
    }

    #[Test]
    public function une_session_morte_est_renvoyee_a_la_connexion(): void
    {
        Livewire::test(VerrouSession::class)
            ->set('motDePasse', 'peu-importe')
            ->call('deverrouiller')
            ->assertRedirect(route('pwa.connexion'));
    }
}
