<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Models\User;
use App\Pwa\Livewire\Transverse\ClocheNotifications;
use App\Pwa\Support\AlertesOuverture;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\UtilisateurSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * La cloche de la barre superieure — alertes d'ouverture DERIVEES (audit PO
 * du 01/09/2026).
 *
 * Trois proprietes eprouvees, chacune contre sa raison d'etre :
 *
 * 1. Une alerte est DERIVEE d'une condition reelle et DISPARAIT avec elle —
 *    jamais une ligne stockee qui vieillirait (PA-59/60/61).
 * 2. « Marquer lu » n'ecrit que l'etat « vu » du compte qui fait le geste :
 *    l'alerte reste derivee, l'autre compte la voit toujours non lue.
 * 3. Le RBAC filtre par module, via LA MEME source que le menu
 *    (`MenuLateral::moduleAccessible`) — un compte sans M5 ne voit pas les
 *    alertes de caisse.
 */
final class ClocheNotificationsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(UtilisateurSeeder::class);
    }

    private function ouvrirCaisseHier(): SessionCaisse
    {
        $admin = User::query()->where('login', 'admin')->firstOrFail();

        return SessionCaisse::query()->create([
            'id' => (string) Str::uuid(),
            'point_vente' => 'bar',
            'utilisateur_ouverture_id' => $admin->id,
            'date_ouverture' => now()->subDay(),
            'montant_fond' => '10000.00',
        ]);
    }

    #[Test]
    public function une_caisse_ouverte_hier_produit_une_alerte_derivee(): void
    {
        $session = $this->ouvrirCaisseHier();
        $admin = User::query()->where('login', 'admin')->firstOrFail();

        $alertes = AlertesOuverture::pour($admin);
        $cles = array_column($alertes, 'cle');

        $this->assertContains('caisse:' . $session->id, $cles);

        // La condition cesse — la cloture est posee — et l'alerte disparait
        // D'ELLE-MEME : rien n'a ete stocke qui puisse survivre a sa cause.
        $session->update(['date_cloture' => now()]);

        $this->assertNotContains(
            'caisse:' . $session->id,
            array_column(AlertesOuverture::pour($admin->refresh()), 'cle'),
        );
    }

    #[Test]
    public function marquer_tout_lu_n_ecrit_que_pour_le_compte_qui_fait_le_geste(): void
    {
        $session = $this->ouvrirCaisseHier();
        $admin = User::query()->where('login', 'admin')->firstOrFail();
        $gerant = User::query()->where('login', 'n.nabogou')->firstOrFail();

        $this->actingAs($admin);

        Livewire::test(ClocheNotifications::class)
            ->call('marquerToutLu');

        $cle = 'caisse:' . $session->id;

        $vueAdmin = collect(AlertesOuverture::pour($admin))->firstWhere('cle', $cle);
        $vueGerant = collect(AlertesOuverture::pour($gerant))->firstWhere('cle', $cle);

        $this->assertNotNull($vueAdmin);
        $this->assertTrue($vueAdmin['vue'], 'L alerte doit etre vue pour le compte qui a fait le geste.');
        $this->assertNotNull($vueGerant);
        $this->assertFalse($vueGerant['vue'], 'Le geste d un compte ne marque jamais les alertes d un autre.');
    }

    #[Test]
    public function marquer_lu_refuse_une_cle_qui_ne_designe_aucune_alerte(): void
    {
        $this->ouvrirCaisseHier();
        $admin = User::query()->where('login', 'admin')->firstOrFail();

        $this->actingAs($admin);

        Livewire::test(ClocheNotifications::class)
            ->call('marquerLu', 'fabriquee:inexistante');

        $this->assertSame(0, DB::table('alertes_vues')->where('cle_alerte', 'fabriquee:inexistante')->count());
    }

    #[Test]
    public function un_compte_sans_acces_au_module_ne_voit_pas_l_alerte(): void
    {
        $session = $this->ouvrirCaisseHier();

        // La cuisine n'a pas M5 : l'alerte de caisse ne lui parvient pas.
        $cuisine = User::query()->where('login', 'cuisine')->firstOrFail();

        $this->assertNotContains(
            'caisse:' . $session->id,
            array_column(AlertesOuverture::pour($cuisine), 'cle'),
        );
    }
}
