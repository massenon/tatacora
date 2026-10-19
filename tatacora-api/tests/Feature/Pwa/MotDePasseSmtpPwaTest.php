<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Backup\Services\ExportTableService;
use App\Shared\Backup\Services\ReinitialisationDonneesTestService;
use App\Shared\Mail\Services\ConfigurationMailService;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use App\Shared\Secrets\Models\SecretConfiguration;
use App\Shared\Secrets\Services\SecretsConfigurationService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le mot de passe SMTP du serveur, saisi dans Paramètres → Email (SMTP) —
 * décision du Product Owner du 19/10/2026 (« chiffré en base »).
 *
 * Ce que chaque cas tient : la valeur est CHIFFRÉE en base (une copie de la
 * base sans `APP_KEY` ne la révèle pas), jamais réaffichée, jamais tracée,
 * jamais exportée ; elle prévaut sur `MAIL_PASSWORD` à l'envoi, et `.env`
 * reprend quand elle est effacée ou indéchiffrable ; la saisie est réservée
 * aux deux rôles d'administration, même pour un rôle qui aurait `PARAM = C`.
 */
final class MotDePasseSmtpPwaTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'Ex3mple-SMTP-n0n-reel';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        config(['mail.mailers.smtp.password' => 'depuis-le-env']);
    }

    #[Test]
    public function un_administrateur_le_saisit_il_est_chiffre_jamais_reaffiche_ni_trace(): void
    {
        $admin = $this->compte('administrateur');
        $this->actingAs($admin);

        Livewire::test(Parametres::class, ['onglet' => 'email'])
            ->assertSee(__('pwa.parametres.email_motdepasse_absent'))
            ->set('motDePasseSmtp', self::SECRET)
            ->call('enregistrerMotDePasseSmtp')
            ->assertHasNoErrors()
            ->assertSet('motDePasseSmtp', '')
            ->assertDontSee(self::SECRET)
            ->assertSee(__('pwa.parametres.email_motdepasse_effacer'));

        // Chiffré : la colonne brute ne contient pas la valeur.
        $brut = (string) DB::table('secrets_configuration')->value('valeur');
        $this->assertNotSame('', $brut);
        $this->assertStringNotContainsString(self::SECRET, $brut);
        $this->assertSame(self::SECRET, app(SecretsConfigurationService::class)->lire(SecretsConfigurationService::SMTP_MOT_DE_PASSE));
        $this->assertArrayNotHasKey('valeur', SecretConfiguration::firstOrFail()->toArray());

        // Le geste est tracé, la valeur jamais.
        $trace = JournalAudit::where('action', 'secret_enregistre')->firstOrFail();
        $this->assertSame($admin->id, $trace->utilisateur_id);
        $this->assertStringNotContainsString(self::SECRET, json_encode($trace->toArray(), JSON_UNESCAPED_UNICODE) ?: '');

        // Et l'état, jamais la valeur, sur un nouveau rendu.
        Livewire::test(Parametres::class, ['onglet' => 'email'])
            ->assertSee(__('pwa.parametres.email_motdepasse_renseigne', ['date' => now()->format('d/m/Y H:i'), 'par' => $admin->login]))
            ->assertDontSee(self::SECRET);
    }

    #[Test]
    public function il_prevaut_sur_le_env_a_l_envoi_et_le_env_reprend_quand_il_est_efface(): void
    {
        $admin = $this->compte('administrateur');
        $this->actingAs($admin);
        $mail = app(ConfigurationMailService::class);

        $mail->appliquer();
        $this->assertSame('depuis-le-env', config('mail.mailers.smtp.password'));

        Livewire::test(Parametres::class, ['onglet' => 'email'])
            ->set('motDePasseSmtp', self::SECRET)
            ->call('enregistrerMotDePasseSmtp');
        $mail->appliquer();
        $this->assertSame(self::SECRET, config('mail.mailers.smtp.password'));

        Livewire::test(Parametres::class, ['onglet' => 'email'])->call('effacerMotDePasseSmtp');
        $this->assertSame(0, SecretConfiguration::count());
        $this->assertTrue(JournalAudit::where('action', 'secret_efface')->exists());

        // Effacé : une nouvelle configuration (redémarrage) relit `.env`.
        config(['mail.mailers.smtp.password' => 'depuis-le-env']);
        $mail->appliquer();
        $this->assertSame('depuis-le-env', config('mail.mailers.smtp.password'));
    }

    #[Test]
    public function une_valeur_indechiffrable_est_traitee_comme_absente(): void
    {
        DB::table('secrets_configuration')->insert([
            'id' => (string) str()->uuid(),
            'cle' => SecretsConfigurationService::SMTP_MOT_DE_PASSE,
            'valeur' => 'chiffre-par-une-autre-cle',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->assertNull(app(SecretsConfigurationService::class)->lire(SecretsConfigurationService::SMTP_MOT_DE_PASSE));
        app(ConfigurationMailService::class)->appliquer();
        $this->assertSame('depuis-le-env', config('mail.mailers.smtp.password'));
    }

    #[Test]
    public function un_role_non_administrateur_ne_le_saisit_pas_meme_avec_param_en_ecriture(): void
    {
        $gerant = $this->compte('gerant');
        app(RolePermissionService::class)->definirNiveau(Role::where('libelle', 'gerant')->firstOrFail(), 'PARAM', 'C');
        $this->actingAs($gerant->refresh());

        Livewire::test(Parametres::class, ['onglet' => 'email'])
            ->assertSee(__('pwa.parametres.email_motdepasse_reserve'))
            ->assertDontSeeHtml('wire:click="enregistrerMotDePasseSmtp"')
            ->set('motDePasseSmtp', self::SECRET)
            ->call('enregistrerMotDePasseSmtp')
            ->assertForbidden();

        $this->assertSame(0, SecretConfiguration::count());

        // Le service refuse aussi, sans passer par l'écran.
        $this->expectException(\RuntimeException::class);
        app(SecretsConfigurationService::class)->enregistrer(SecretsConfigurationService::SMTP_MOT_DE_PASSE, self::SECRET, $gerant);
    }

    #[Test]
    public function une_valeur_vide_ou_une_cle_hors_registre_est_refusee(): void
    {
        $this->actingAs($this->compte('administrateur'));

        Livewire::test(Parametres::class, ['onglet' => 'email'])
            ->set('motDePasseSmtp', '')
            ->call('enregistrerMotDePasseSmtp')
            ->assertHasErrors('motDePasseSmtp');
        $this->assertSame(0, SecretConfiguration::count());

        $this->expectException(\RuntimeException::class);
        app(SecretsConfigurationService::class)->enregistrer('cle_inventee', 'x', $this->compte('administrateur'));
    }

    #[Test]
    public function la_table_n_est_ni_exportable_ni_videe_par_la_reinitialisation(): void
    {
        $this->assertContains('secrets_configuration', ExportTableService::TABLES_EXCLUES);
        $this->assertNotContains('secrets_configuration', app(ExportTableService::class)->tablesExportables());
        $this->assertContains('secrets_configuration', ReinitialisationDonneesTestService::TABLES_PRESERVEES);
    }

    private function compte(string $role): User
    {
        return User::firstOrCreate(['login' => 'compte.'.$role], [
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
