<?php

declare(strict_types=1);

namespace Tests\Feature\ContactEditeur;

use App\Models\User;
use App\Pwa\Livewire\Transverse\ContactEditeur;
use App\Shared\ContactEditeur\Jobs\EnvoyerMessageEditeurJob;
use App\Shared\ContactEditeur\Mail\MessageEditeurMail;
use App\Shared\ContactEditeur\Models\MessageEditeur;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Symfony\Component\Mailer\Exception\TransportException;
use Tests\TestCase;

/**
 * « Contactez l'éditeur » — envoi SMTP réel (directive PO du 14/10/2026) :
 * envoi par Mailable au support, échec → « en attente d'envoi » sans bloquer,
 * rejeu par `contact-editeur:rejouer`.
 */
final class EnvoiMessageEditeurTest extends TestCase
{
    use RefreshDatabase;

    private User $auteur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->auteur = User::create([
            'id' => (string) Str::uuid(),
            'login' => 'auteur-contact',
            'mot_de_passe_hash' => Hash::make(Str::random(24)),
            'role_id' => Role::where('libelle', 'receptionniste')->firstOrFail()->id,
            'statut' => 'actif',
        ]);

        // Une messagerie « réelle » au sens de ConfigurationMailService.
        config([
            'mail.default' => 'smtp',
            'mail.mailers.smtp.host' => 'smtp.exemple.invalid',
            'contact_editeur.destinataires' => ['rarhodes06@gmail.com'],
        ]);
    }

    #[Test]
    public function le_message_part_au_support_par_le_mailable_et_passe_transmis(): void
    {
        Mail::fake();

        Livewire::actingAs($this->auteur)->test(ContactEditeur::class)
            ->call('ouvrirFormulaireMessage')
            ->set('objetMessage', 'Question')
            ->set('corpsMessage', 'Bonjour <b>éditeur</b>')
            ->call('envoyerMessage')
            ->assertSee(__('pwa.contact.message_envoye'));

        $message = MessageEditeur::query()->sole();
        $this->assertSame(MessageEditeur::STATUT_TRANSMIS, $message->statut);

        Mail::assertSent(MessageEditeurMail::class, function (MessageEditeurMail $courriel): bool {
            return $courriel->hasTo('rarhodes06@gmail.com')
                && str_contains($courriel->render(), '&lt;b&gt;');
        });
    }

    #[Test]
    public function un_echec_smtp_garde_le_message_en_attente_puis_le_rejeu_le_transmet(): void
    {
        Mail::shouldReceive('to')->andThrow(new TransportException('Connexion refusee'));
        // Lu par `Mail::fake()` plus bas, quand le serveur « revient ».
        Mail::shouldReceive('getDefaultDriver')->andReturn('smtp');

        Livewire::actingAs($this->auteur)->test(ContactEditeur::class)
            ->call('ouvrirFormulaireBug')
            ->set('moduleBug', ContactEditeur::MODULES[0])
            ->set('descriptionBug', 'Le calcul est faux')
            ->call('signalerBug')
            ->assertHasNoErrors()
            ->assertSee(__('pwa.contact.envoi_en_attente'))
            ->assertSee(__('pwa.contact.envois_statut_a_transmettre'));

        $message = MessageEditeur::query()->sole();
        $this->assertSame(MessageEditeur::STATUT_A_TRANSMETTRE, $message->statut);

        // Le serveur revient : la commande planifiée rejoue.
        Mail::fake();
        $this->artisan('contact-editeur:rejouer')->assertExitCode(0);

        $this->assertSame(MessageEditeur::STATUT_TRANSMIS, $message->fresh()?->statut);
        Mail::assertSent(MessageEditeurMail::class, 1);
    }

    #[Test]
    public function sans_messagerie_configuree_le_rejeu_le_dit_et_ne_tente_rien(): void
    {
        config(['mail.default' => 'log']);
        Mail::fake();

        MessageEditeur::create([
            'type' => MessageEditeur::TYPE_MESSAGE,
            'objet' => 'En attente',
            'corps' => 'Corps',
            'statut' => MessageEditeur::STATUT_A_TRANSMETTRE,
        ]);

        $this->artisan('contact-editeur:rejouer')->assertExitCode(1);

        Mail::assertNothingSent();
        $this->assertSame(MessageEditeur::STATUT_A_TRANSMETTRE, MessageEditeur::query()->sole()->statut);
    }

    #[Test]
    public function un_echec_note_les_tentatives_et_la_cause_lisible_et_la_page_la_dit(): void
    {
        Mail::shouldReceive('to')->andThrow(new TransportException('Connection could not be established with host "smtp.exemple.invalid:587"'));
        Mail::shouldReceive('getDefaultDriver')->andReturn('smtp');

        Livewire::actingAs($this->auteur)->test(ContactEditeur::class)
            ->call('ouvrirFormulaireMessage')
            ->set('objetMessage', 'Question')
            ->set('corpsMessage', 'Bonjour')
            ->call('envoyerMessage')
            ->assertSee('Dernière erreur : Serveur SMTP injoignable');

        $message = MessageEditeur::query()->sole();
        $this->assertSame(MessageEditeur::STATUT_A_TRANSMETTRE, $message->statut);
        $this->assertSame(1, $message->tentatives);
        $this->assertStringContainsString('injoignable', (string) $message->derniere_erreur);
        $this->assertNotNull($message->derniere_tentative_le);
        $this->assertNull($message->envoye_le);
    }

    #[Test]
    public function le_succes_pose_envoye_le_et_efface_la_derniere_erreur(): void
    {
        Mail::fake();
        MessageEditeur::create([
            'type' => MessageEditeur::TYPE_MESSAGE,
            'objet' => 'Reprise',
            'corps' => 'Corps',
            'statut' => MessageEditeur::STATUT_A_TRANSMETTRE,
        ]);
        MessageEditeur::query()->update(['tentatives' => 2, 'derniere_erreur' => 'ancienne cause']);

        $this->artisan('contact-editeur:rejouer')->assertExitCode(0);

        $message = MessageEditeur::query()->sole();
        $this->assertSame(MessageEditeur::STATUT_TRANSMIS, $message->statut);
        $this->assertSame(3, $message->tentatives);
        $this->assertNull($message->derniere_erreur);
        $this->assertNotNull($message->envoye_le);
    }

    #[Test]
    public function le_message_est_mis_en_file_d_envoi_et_jamais_envoye_deux_fois(): void
    {
        Queue::fake();

        Livewire::actingAs($this->auteur)->test(ContactEditeur::class)
            ->call('ouvrirFormulaireMessage')
            ->set('objetMessage', 'Question')
            ->set('corpsMessage', 'Bonjour')
            ->call('envoyerMessage')
            ->assertSee(__('pwa.contact.envoi_en_attente'));

        Queue::assertPushed(EnvoyerMessageEditeurJob::class, 1);

        // Le job : envoie, puis un second passage ne renvoie RIEN.
        Mail::fake();
        $message = MessageEditeur::query()->sole();
        (new EnvoyerMessageEditeurJob($message->id))->handle(
            app(\App\Shared\ContactEditeur\Services\MessageEditeurService::class),
            app(\App\Shared\Mail\Services\ConfigurationMailService::class),
        );
        (new EnvoyerMessageEditeurJob($message->id))->handle(
            app(\App\Shared\ContactEditeur\Services\MessageEditeurService::class),
            app(\App\Shared\Mail\Services\ConfigurationMailService::class),
        );

        $this->assertSame(MessageEditeur::STATUT_TRANSMIS, $message->fresh()?->statut);
        Mail::assertSent(MessageEditeurMail::class, 1);
    }

    #[Test]
    public function le_rejeu_s_arrete_au_plafond_de_tentatives(): void
    {
        Mail::fake();
        MessageEditeur::create([
            'type' => MessageEditeur::TYPE_MESSAGE,
            'objet' => 'Epuise',
            'corps' => 'Corps',
            'statut' => MessageEditeur::STATUT_A_TRANSMETTRE,
        ]);
        MessageEditeur::query()->update(['tentatives' => MessageEditeur::TENTATIVES_MAX]);

        $this->artisan('contact-editeur:rejouer')->assertExitCode(0);

        Mail::assertNothingSent();
        $this->assertSame(MessageEditeur::STATUT_A_TRANSMETTRE, MessageEditeur::query()->sole()->statut, 'jamais supprimé ni affirmé transmis');
    }
}
