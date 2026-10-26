<?php

declare(strict_types=1);

namespace Tests\Feature\Notifications;

use App\Domain\Notifications\Contracts\DetecteurDeclencheurInterface;
use App\Domain\Notifications\Detecteurs\SejourDemainDetecteur;
use App\Domain\Notifications\Jobs\EnvoyerNotificationEmailJob;
use App\Domain\Notifications\Models\MessageNotificationCompose;
use App\Domain\Notifications\Models\ModeleNotification;
use App\Domain\Notifications\Models\NotificationEnvoyee;
use App\Domain\Notifications\Services\EnvoiEmailNotificationService;
use App\Domain\Notifications\Services\FileAttenteNotificationsService;
use App\Domain\Notifications\Services\RegistreCanaux;
use App\Models\User;
use App\Pwa\Livewire\Notifications\Hub;
use App\Shared\Mail\Support\CauseEchecEmail;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Queue;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Symfony\Component\Mailer\Exception\TransportException;
use Tests\TestCase;

/**
 * M12 — l'e-mail de notification PART (décision du PO du 26/10/2026 :
 * « l'envoi réel d'e-mails DOIT ÊTRE IMPLÉMENTÉ EN POSTE ET WEB »).
 *
 * Mis en file d'envoi (jobs) à la composition, statut envoyé / en échec /
 * relance, cause lisible, jamais deux e-mails, jamais de mot de passe dans
 * une cause d'échec, et « envoyé » seulement après l'accusé du transport.
 */
final class EnvoiEmailNotificationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        // Une messagerie « réelle » au sens de ConfigurationMailService.
        config([
            'mail.default' => 'smtp',
            'mail.mailers.smtp.host' => 'smtp.exemple.invalid',
        ]);
    }

    private function modeleEmail(): ModeleNotification
    {
        return ModeleNotification::create([
            'evenement' => 'sejour_demain',
            'canal' => RegistreCanaux::EMAIL,
            'objet' => 'Votre séjour',
            'contenu_template' => 'Bonjour {client}.',
            'actif' => true,
        ]);
    }

    private function message(?string $email = 'kora@exemple.bj', array $extra = []): MessageNotificationCompose
    {
        $modele = ModeleNotification::query()->first() ?? $this->modeleEmail();

        $cree = MessageNotificationCompose::create([
            'modele_id' => $modele->id,
            'canal' => RegistreCanaux::EMAIL,
            'reference' => 'ref-'.bin2hex(random_bytes(3)),
            'destinataire' => 'KORA',
            'email_destinataire' => $email,
            'objet' => 'Votre séjour',
            'contenu' => 'Bonjour KORA.',
            'longueur' => 13,
            'statut' => MessageNotificationCompose::STATUT_EN_ATTENTE,
        ]);

        // Le suivi d'envoi n'est écrit que par le service : jamais en masse.
        return $cree->forceFill($extra)->save() ? $cree->refresh() : $cree;
    }

    private function compte(string $role): User
    {
        return User::create([
            'login' => $role.'.m12.'.bin2hex(random_bytes(3)),
            'mot_de_passe_hash' => Hash::make('MotDePasseTresLong!2026'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /** Un détecteur qui rend UNE occurrence, avec ou sans adresse. */
    private function detecteurFictif(?string $email): void
    {
        $this->app->bind(SejourDemainDetecteur::class, fn () => new class ($email) implements DetecteurDeclencheurInterface {
            public function __construct(private readonly ?string $email)
            {
            }

            public function detecter(): array
            {
                return [[
                    'reference' => 'resa-1',
                    'destinataire' => 'KORA',
                    'email' => $this->email,
                    'variables' => ['client' => 'KORA'],
                ]];
            }
        });
    }

    #[Test]
    public function le_succes_n_ecrit_envoye_qu_apres_l_accuse_du_transport(): void
    {
        Mail::spy();
        $message = $this->message();

        $resultat = app(EnvoiEmailNotificationService::class)->envoyer($message);

        $this->assertTrue($resultat['envoye']);
        $message->refresh();
        $this->assertSame(MessageNotificationCompose::STATUT_ENVOYE, $message->statut);
        $this->assertSame(1, $message->tentatives);
        $this->assertNotNull($message->envoye_le);
        $this->assertNull($message->derniere_erreur);
        $this->assertSame(1, NotificationEnvoyee::query()->count());
        Mail::shouldHaveReceived('raw')->once();
    }

    #[Test]
    public function un_echec_garde_le_message_en_file_avec_sa_cause_lisible_et_ses_tentatives(): void
    {
        Mail::shouldReceive('raw')->andThrow(new TransportException('Connection could not be established with host "smtp.exemple.invalid:587"'));
        Mail::shouldReceive('getDefaultDriver')->andReturn('smtp');
        $message = $this->message();

        $resultat = app(EnvoiEmailNotificationService::class)->envoyer($message);

        $this->assertFalse($resultat['envoye']);
        $this->assertTrue($resultat['transitoire']);
        $this->assertStringContainsString('injoignable', (string) $resultat['motif']);

        $message->refresh();
        $this->assertSame(MessageNotificationCompose::STATUT_EN_ATTENTE, $message->statut, 'jamais « envoyé » sans accusé');
        $this->assertSame(1, $message->tentatives);
        $this->assertStringContainsString('injoignable', (string) $message->derniere_erreur);
        $this->assertNotNull($message->derniere_tentative_le);
        $this->assertNull($message->envoye_le);
        $this->assertSame(0, NotificationEnvoyee::query()->count());
    }

    #[Test]
    public function la_cause_d_un_echec_n_emporte_jamais_le_mot_de_passe(): void
    {
        config(['mail.mailers.smtp.password' => 'S3cret-Gite!']);

        $cause = CauseEchecEmail::depuis(new TransportException('Refus pour S3cret-Gite! sur l\'hôte'), 'S3cret-Gite!');

        $this->assertStringNotContainsString('S3cret-Gite!', $cause);
        $this->assertStringContainsString('***', $cause);
        $this->assertStringContainsString(
            'refusé les identifiants',
            CauseEchecEmail::depuis(new TransportException('Failed to authenticate on SMTP server with username "x"')),
        );
        $this->assertStringContainsString(
            'n’a pas répondu à temps',
            CauseEchecEmail::depuis(new TransportException('Connection timed out')),
        );
    }

    #[Test]
    public function sans_adresse_ou_sans_messagerie_rien_n_est_tente_ni_compte(): void
    {
        Mail::spy();
        $sansAdresse = $this->message(null);
        $this->assertFalse(app(EnvoiEmailNotificationService::class)->envoyer($sansAdresse)['envoye']);

        config(['mail.default' => 'log']);
        $sansMessagerie = $this->message();
        $this->assertFalse(app(EnvoiEmailNotificationService::class)->envoyer($sansMessagerie)['envoye']);

        Mail::shouldNotHaveReceived('raw');
        $this->assertSame(0, $sansAdresse->refresh()->tentatives);
        $this->assertSame(0, $sansMessagerie->refresh()->tentatives);
        $this->assertSame(MessageNotificationCompose::STATUT_EN_ATTENTE, $sansMessagerie->statut);
    }

    #[Test]
    public function jamais_deux_e_mails_le_verrou_et_la_relecture_du_statut(): void
    {
        Mail::spy();
        $message = $this->message();

        // L'autre chemin (bouton ou job) l'envoie en ce moment même.
        $verrou = Cache::lock('notification-email:'.$message->id, 60);
        $this->assertTrue($verrou->get());
        $resultat = app(EnvoiEmailNotificationService::class)->envoyer($message);
        $verrou->release();

        $this->assertFalse($resultat['envoye']);
        Mail::shouldNotHaveReceived('raw');

        // Puis un envoi réel, et un second appel sur le MÊME objet périmé.
        $perime = MessageNotificationCompose::query()->findOrFail($message->id);
        $this->assertTrue(app(EnvoiEmailNotificationService::class)->envoyer($message)['envoye']);
        try {
            app(EnvoiEmailNotificationService::class)->envoyer($perime);
            $this->fail('Un message déjà envoyé doit être refusé.');
        } catch (\RuntimeException) {
            // attendu : « déjà transmis ou abandonné »
        }

        Mail::shouldHaveReceived('raw')->once();
    }

    #[Test]
    public function la_composition_met_l_email_en_file_d_envoi_une_seule_fois(): void
    {
        Queue::fake();
        $this->modeleEmail();
        $this->detecteurFictif('kora@exemple.bj');

        $bilan = app(FileAttenteNotificationsService::class)->detecter();
        app(FileAttenteNotificationsService::class)->detecter();

        $this->assertSame(1, $bilan['composes']);
        $this->assertSame(1, MessageNotificationCompose::query()->count());
        Queue::assertPushed(EnvoyerNotificationEmailJob::class, 1);
    }

    #[Test]
    public function sans_adresse_ou_hors_canal_email_aucun_job(): void
    {
        Queue::fake();
        $this->modeleEmail();
        $this->detecteurFictif(null);
        app(FileAttenteNotificationsService::class)->detecter();

        Queue::assertNothingPushed();
        $this->assertSame(1, MessageNotificationCompose::query()->count(), 'le message est composé quand même');
    }

    #[Test]
    public function le_job_envoie_et_ne_renvoie_jamais(): void
    {
        Mail::spy();
        $message = $this->message();
        (new EnvoyerNotificationEmailJob($message->id))->handle(app(EnvoiEmailNotificationService::class));
        $this->assertSame(MessageNotificationCompose::STATUT_ENVOYE, $message->refresh()->statut);

        // Un message disparu ou déjà traité : le job ne fait rien et ne lève pas.
        (new EnvoyerNotificationEmailJob($message->id))->handle(app(EnvoiEmailNotificationService::class));
        (new EnvoyerNotificationEmailJob('inexistant'))->handle(app(EnvoiEmailNotificationService::class));
        Mail::shouldHaveReceived('raw')->once();
    }

    #[Test]
    public function une_panne_de_connexion_fait_lever_le_job_pour_la_file_et_un_refus_non(): void
    {
        Mail::shouldReceive('raw')->andThrow(new TransportException('Connection timed out'));
        Mail::shouldReceive('getDefaultDriver')->andReturn('smtp');
        $message = $this->message();

        $this->expectException(\RuntimeException::class);
        try {
            (new EnvoyerNotificationEmailJob($message->id))->handle(app(EnvoiEmailNotificationService::class));
        } finally {
            $this->assertSame(1, $message->refresh()->tentatives, 'la tentative est comptée avant la relance');
        }
    }

    #[Test]
    public function un_refus_d_identifiants_ne_fait_pas_lever_le_job(): void
    {
        Mail::shouldReceive('raw')->andThrow(new TransportException('Failed to authenticate on SMTP server'));
        Mail::shouldReceive('getDefaultDriver')->andReturn('smtp');
        $message = $this->message();

        (new EnvoyerNotificationEmailJob($message->id))->handle(app(EnvoiEmailNotificationService::class));

        $this->assertStringContainsString('refusé les identifiants', (string) $message->refresh()->derniere_erreur);
    }

    #[Test]
    public function la_relance_respecte_le_delai_et_le_plafond(): void
    {
        Queue::fake();
        $recent = $this->message(extra: ['tentatives' => 1, 'derniere_tentative_le' => now()->subMinutes(2)]);
        $du = $this->message(extra: ['tentatives' => 1, 'derniere_tentative_le' => now()->subMinutes(20)]);
        $neuf = $this->message();
        $epuise = $this->message(extra: [
            'tentatives' => MessageNotificationCompose::TENTATIVES_MAX,
            'derniere_tentative_le' => now()->subDays(2),
        ]);
        $sansAdresse = $this->message(null);
        $envoye = $this->message(extra: ['statut' => MessageNotificationCompose::STATUT_ENVOYE]);

        $relances = app(EnvoiEmailNotificationService::class)->relancer();

        $this->assertSame(2, $relances);
        Queue::assertPushed(EnvoyerNotificationEmailJob::class, 2);
        Queue::assertPushed(EnvoyerNotificationEmailJob::class, fn ($j) => $j->messageId === $du->id);
        Queue::assertPushed(EnvoyerNotificationEmailJob::class, fn ($j) => $j->messageId === $neuf->id);
        Queue::assertNotPushed(EnvoyerNotificationEmailJob::class, fn ($j) => in_array($j->messageId, [$recent->id, $epuise->id, $sansAdresse->id, $envoye->id], true));
        $this->assertTrue($epuise->refresh()->enEchec());
    }

    #[Test]
    public function la_commande_de_relance_le_dit_sans_messagerie(): void
    {
        Queue::fake();
        config(['mail.default' => 'log']);
        $this->message();

        $this->artisan('notifications:relancer-emails')->assertExitCode(1);
        Queue::assertNothingPushed();

        config(['mail.default' => 'smtp']);
        $this->artisan('notifications:relancer-emails')->assertExitCode(0);
        Queue::assertPushed(EnvoyerNotificationEmailJob::class, 1);
    }

    #[Test]
    public function le_hub_dit_l_etat_vrai_et_renvoie_apres_l_epuisement(): void
    {
        Mail::spy();
        $message = $this->message(extra: [
            'tentatives' => MessageNotificationCompose::TENTATIVES_MAX,
            'derniere_erreur' => 'Serveur SMTP injoignable (connexion absente ?) : hors ligne',
            'derniere_tentative_le' => now()->subHour(),
        ]);

        $this->actingAs($this->compte('gerant'));
        $composant = Livewire::test(Hub::class)
            ->assertSee('Tentatives d’envoi : '.MessageNotificationCompose::TENTATIVES_MAX)
            ->assertSee('Dernière erreur : Serveur SMTP injoignable')
            ->assertSee('Relances automatiques épuisées')
            ->assertSee('Renvoyer');

        $composant->call('envoyerMessage', $message->id);

        $message->refresh();
        $this->assertSame(MessageNotificationCompose::STATUT_ENVOYE, $message->statut);
        $this->assertSame(1, $message->tentatives, 'le compteur est reparti de zéro');
        Mail::shouldHaveReceived('raw')->once();
    }
}
