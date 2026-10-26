<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Models\User;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « Créer un compte » depuis le hub : la saisie ABOUTIT. Une seule règle de
 * numéro (deux à quatre chiffres, `PlanComptableService::NUMERO_COMPTE_FORMAT`),
 * jugée par le service, dite par la phrase du service.
 */
final class CreationCompteHubTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs(User::create([
            'login' => 'comptable.test',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'comptable')->firstOrFail()->id,
            'statut' => 'actif',
        ]));
    }

    #[Test]
    public function creer_le_compte_6056_depuis_le_hub_aboutit_et_le_compte_existe_au_plan(): void
    {
        Livewire::test(Hub::class)
            ->call('ouvrirNouveauCompte')
            ->set('numeroCompte', PlanComptableService::NUMERO_COMPTE_EXEMPLE)
            ->set('libelleCompte', "Produits d'entretien")
            ->set('natureCompte', 'charge')
            ->call('enregistrerCompte')
            ->assertHasNoErrors();

        $compte = CompteComptable::where('numero_compte', '6056')->first();
        $this->assertNotNull($compte, 'Le compte 6056 doit exister au plan.');
        $this->assertSame('6', (string) $compte->classe);
        $this->assertSame('charge', $compte->nature);
    }

    #[Test]
    public function un_numero_invalide_est_refuse_avec_la_phrase_du_service(): void
    {
        foreach (['605600', '6', 'abcd', '0123'] as $numero) {
            $attendue = __('comptabilite.compte_numero_invalide', ['numero' => $numero]);

            Livewire::test(Hub::class)
                ->call('ouvrirNouveauCompte')
                ->set('numeroCompte', $numero)
                ->set('libelleCompte', 'Test')
                ->set('natureCompte', 'charge')
                ->call('enregistrerCompte')
                ->assertHasErrors(['compte'])
                ->assertSee($attendue === '' ? 'x' : e($attendue), false);

            $this->assertSame(0, CompteComptable::where('numero_compte', $numero)->count());
        }
    }

    #[Test]
    public function la_regle_est_unique_hub_vue_service_et_phrase(): void
    {
        $racine = dirname(__DIR__, 3);
        $hub = (string) file_get_contents($racine.'/app/Pwa/Livewire/Comptabilite/Hub.php');
        $vue = (string) file_get_contents($racine.'/resources/views/pwa/comptabilite/hub.blade.php');
        $service = (string) file_get_contents($racine.'/app/Domain/Comptabilite/Services/PlanComptableService.php');

        // Le hub ne porte aucune regex de numéro à lui.
        $this->assertStringNotContainsString('[1-9][0-9]', $hub);
        // La vue prend sa longueur et son exemple de la constante, jamais en dur.
        $this->assertStringContainsString('PlanComptableService::NUMERO_COMPTE_CHIFFRES_MAX', $vue);
        $this->assertStringContainsString('PlanComptableService::NUMERO_COMPTE_EXEMPLE', $vue);
        $this->assertStringNotContainsString('605600', $vue);
        // Le service juge par la constante, et une seule regex de ce genre y existe.
        $this->assertStringContainsString('preg_match(self::NUMERO_COMPTE_FORMAT', $service);
        $this->assertSame(1, preg_match_all('#\'/\^\[1-9\]#', $service));

        // La constante, le maximum, l'exemple et la phrase disent la même chose.
        $this->assertSame(1, preg_match('/^\/\^\[1-9\]\[0-9\]\{1,(\d)\}\$\/$/', PlanComptableService::NUMERO_COMPTE_FORMAT, $m));
        $this->assertSame(PlanComptableService::NUMERO_COMPTE_CHIFFRES_MAX, (int) $m[1] + 1);
        $this->assertSame(1, preg_match(PlanComptableService::NUMERO_COMPTE_FORMAT, PlanComptableService::NUMERO_COMPTE_EXEMPLE));
        $this->assertStringContainsString('de deux à quatre chiffres', __('comptabilite.compte_numero_invalide', ['numero' => 'x']));

        // Le plan du PO : aucun numéro au-delà du maximum.
        $max = 0;
        foreach (array_slice(file($racine.'/database/data/plan-comptable-syscohada-revise.csv', FILE_IGNORE_NEW_LINES), 1) as $ligne) {
            $max = max($max, strlen(explode(';', $ligne)[0]));
        }
        $this->assertSame(PlanComptableService::NUMERO_COMPTE_CHIFFRES_MAX, $max);
    }
}
