<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Pwa\Livewire\Transverse\Parametres;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * PO 10/11/2026 : l'import de la signature et du cachet est JUSTE SOUS l'interrupteur « Afficher la
 * signature et le cachet sur les factures » (Identité & Légal) ; on peut remplacer ET retirer.
 */
final class SignatureCachetSousInterrupteurTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        Storage::fake(ApparenceEtablissementService::DISQUE);
    }

    private function connecterAdministrateur(): void
    {
        $this->actingAs(User::create([
            'login' => 'compte.administrateur',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]));
    }

    #[Test]
    public function le_bloc_d_import_suit_l_interrupteur_dans_identite_et_legal(): void
    {
        $this->connecterAdministrateur();

        $html = (string) Livewire::test(Parametres::class)->set('onglet', 'identite')->html();

        $interrupteur = strpos($html, 'Afficher la signature et le cachet');
        $bloc = strpos($html, 'data-bloc="signature-cachet"');

        $this->assertNotFalse($bloc, 'Le bloc « Signature et cachet » est rendu dans Identité & Légal.');
        $this->assertNotFalse($interrupteur);
        $this->assertGreaterThan($interrupteur, $bloc, 'Le bloc vient APRÈS l\'interrupteur.');
        $this->assertStringContainsString(__('pwa.parametres.signature_cachet_bloc_titre'), $html);
        $this->assertStringContainsString(__('pwa.parametres.apparence_signature_bouton'), $html);
        $this->assertStringContainsString(__('pwa.parametres.apparence_cachet_bouton'), $html);
    }

    #[Test]
    public function une_image_deposee_s_affiche_puis_se_retire(): void
    {
        $this->connecterAdministrateur();
        $apparence = app(ApparenceEtablissementService::class);
        $png = base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
        $apparence->enregistrerImageDocument('signature', $png);

        $this->assertNotNull($apparence->octetsImageDocument('signature'));
        $rendu = Livewire::test(Parametres::class)->set('onglet', 'identite');
        $this->assertStringContainsString(__('pwa.parametres.apparence_retirer'), (string) $rendu->html());

        $rendu->call('retirerSignature');

        $this->assertNull($apparence->octetsImageDocument('signature'));
    }

    #[Test]
    public function un_fichier_qui_n_est_pas_une_image_est_refuse_sur_ses_octets(): void
    {
        $this->expectException(\App\Domain\Depenses\Exceptions\RefusRecuDepense::class);

        app(ApparenceEtablissementService::class)->enregistrerImageDocument('cachet', '<?php echo 1; ?> pas une image');
    }
}
