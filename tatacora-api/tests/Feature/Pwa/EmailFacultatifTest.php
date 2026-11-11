<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Notifications\Detecteurs\BulletinDisponibleDetecteur;
use App\Domain\Notifications\Detecteurs\EcheanceVpsDetecteur;
use App\Domain\Notifications\Models\MessageNotificationCompose;
use App\Domain\Notifications\Models\ModeleNotification;
use App\Domain\Notifications\Services\FileAttenteNotificationsService;
use App\Domain\Notifications\Services\RegistreCanaux;
use App\Domain\Rh\Models\BulletinPaie;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Service as ServiceRh;
use App\Models\User;
use App\Pwa\Livewire\Rh\Paie;
use App\Pwa\Livewire\Transverse\MonProfil;
use App\Shared\Mail\Support\AdresseEmailFacultative;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Queue;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * L'e-mail FACULTATIF d'un employé (fiche RH) et d'un compte (Mon profil) —
 * décision du PO du 28/10/2026.
 *
 * Tient : facultatif, normalisé (trim + minuscules), format refusé en clair,
 * sans unicité, écrit par la synchronisation du poste, et destinataire des
 * notifications `bulletin_disponible` (le salarié) et `echeance_vps` (le compte
 * comptable) — sans adresse, le message est composé et ne part pas, sans erreur.
 */
final class EmailFacultatifTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function compte(string $role, ?string $email = null, string $statut = 'actif'): User
    {
        return User::create([
            'login' => $role.'.mail.'.bin2hex(random_bytes(3)),
            'email' => $email,
            'mot_de_passe_hash' => Hash::make('MotDePasseTresLong!2026'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => $statut,
        ]);
    }

    private function bulletinValide(Employe $employe, string $numero): void
    {
        (new BulletinPaie())->forceFill([
            'employe_id' => $employe->id, 'periode' => '2026-10', 'statut' => BulletinPaie::STATUT_VALIDEE,
            'numero' => $numero, 'salaire_base' => '100000.00', 'total_primes' => '0.00', 'total_retenues' => '0.00',
            'cnss_salarie' => '0.00', 'its' => '0.00', 'net_a_payer' => '90000.00',
        ])->save();
    }

    private function saisirEmploye(string $email): \Livewire\Features\SupportTesting\Testable
    {
        $service = ServiceRh::firstOrCreate(['libelle' => 'Réception']);

        return Livewire::test(Paie::class)
            ->call('ouvrirFormulaireEmploye')
            ->set('nomSaisi', 'DOSSOU'.bin2hex(random_bytes(2)))
            ->set('prenomSaisi', 'Paul')
            ->set('emailSaisi', $email)
            ->set('posteSaisi', 'Chef cuisinier')
            ->set('serviceSaisi', $service->id)
            ->set('embaucheSaisie', '2026-01-15')
            ->set('salaireBaseSaisi', '110000')
            ->call('enregistrerEmploye');
    }

    #[Test]
    public function la_fiche_employe_normalise_l_email_et_l_accepte_vide(): void
    {
        $this->actingAs($this->compte('rh'));

        $this->saisirEmploye('  Paul.DOSSOU@Exemple.BJ ')->assertHasNoErrors();
        $this->saisirEmploye('')->assertHasNoErrors();
        // Aucune unicité : la même boîte sur un second dossier est acceptée.
        $this->saisirEmploye('paul.dossou@exemple.bj')->assertHasNoErrors();

        $emails = Employe::query()->orderBy('created_at')->pluck('email')->all();
        $this->assertCount(3, $emails);
        $this->assertEqualsCanonicalizing(['paul.dossou@exemple.bj', null, 'paul.dossou@exemple.bj'], $emails);
    }

    #[Test]
    public function la_fiche_employe_refuse_une_adresse_mal_formee_avec_la_phrase_du_poste(): void
    {
        $this->actingAs($this->compte('rh'));

        $this->saisirEmploye('pas-une-adresse')
            ->assertHasErrors(['emailSaisi' => 'email'])
            ->assertSee(__('rh_pwa.email_invalide'));
        $this->saisirEmploye('a@b')->assertHasErrors('emailSaisi');
        // Au-delà de 255 caractères : refusée, avec la même phrase (aucune phrase de plus à rejouer).
        $this->saisirEmploye(str_repeat('a', 250).'@exemple.bj')->assertHasErrors('emailSaisi');
        $this->assertSame(0, Employe::query()->count());
    }

    #[Test]
    public function la_modification_relit_l_email_et_peut_l_effacer(): void
    {
        $this->actingAs($this->compte('rh'));
        $this->saisirEmploye('kora@exemple.bj')->assertHasNoErrors();
        $employe = Employe::query()->firstOrFail();

        Livewire::test(Paie::class)
            ->call('ouvrirFormulaireEmploye', $employe->id)
            ->assertSet('emailSaisi', 'kora@exemple.bj')
            ->set('emailSaisi', '')
            ->call('enregistrerEmploye')
            ->assertHasNoErrors();

        $this->assertNull($employe->refresh()->email);
    }

    #[Test]
    public function mon_profil_ecrit_l_email_du_compte_courant_seul(): void
    {
        $moi = $this->compte('barman', 'ancien@exemple.bj');
        $autre = $this->compte('rh', 'rh@exemple.bj');
        $this->actingAs($moi);

        Livewire::test(MonProfil::class)
            ->assertSet('emailSaisi', 'ancien@exemple.bj')
            ->set('emailSaisi', ' Nouveau@Exemple.BJ ')
            ->call('enregistrerInformations')
            ->assertHasNoErrors();
        $this->assertSame('nouveau@exemple.bj', $moi->refresh()->email);
        $this->assertSame('rh@exemple.bj', $autre->refresh()->email);

        Livewire::test(MonProfil::class)
            ->set('emailSaisi', 'faux')
            ->call('enregistrerInformations')
            ->assertHasErrors(['emailSaisi' => 'email']);
        $this->assertSame('nouveau@exemple.bj', $moi->refresh()->email);

        // Facultatif : vider efface ; même adresse qu'un autre compte : acceptée.
        Livewire::test(MonProfil::class)->set('emailSaisi', '')->call('enregistrerInformations')->assertHasNoErrors();
        $this->assertNull($moi->refresh()->email);
        Livewire::test(MonProfil::class)->set('emailSaisi', 'rh@exemple.bj')->call('enregistrerInformations')->assertHasNoErrors();
        $this->assertSame('rh@exemple.bj', $moi->refresh()->email);
    }

    #[Test]
    public function la_synchronisation_du_poste_ecrit_l_email_normalise_le_refuse_mal_forme_et_le_conserve_si_absent(): void
    {
        $this->travelTo('2026-10-18 10:00:00');
        $rh = $this->creerUtilisateur('rh');
        ServiceRh::firstOrCreate(['libelle' => 'Hébergement']);
        $id = $this->uuid();
        $base = [
            'nom' => 'HOUNSOU', 'prenom' => 'Marceline', 'poste' => 'Réceptionniste',
            'service_id' => $this->uuid(), 'service_libelle' => 'Hébergement',
            'date_embauche' => '2023-02-01', 'salaire_base' => 150000, 'type_contrat' => 'CDI',
        ];

        $this->pousser([$this->creation('employes', $id, [...$base, 'email' => 'marceline@exemple.bj'])], $rh, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('marceline@exemple.bj', Employe::findOrFail($id)->email);

        // Une charge SANS la clé (poste d'avant la v45) ne touche pas l'adresse.
        $this->pousser([$this->operation('employes', 'modification', $id, ['poste' => 'Cheffe'])], $rh)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('marceline@exemple.bj', Employe::findOrFail($id)->email);

        // Une adresse mal formée est refusée, l'ancienne reste.
        $reponse = $this->pousser([$this->operation('employes', 'modification', $id, [...$base, 'email' => 'pas-un-mail'])], $rh);
        $this->assertNotSame('synchronise', $reponse->json('resultats.0.statut'));
        $this->assertSame('marceline@exemple.bj', Employe::findOrFail($id)->email);

        // Vide, explicite : effacée.
        $this->pousser([$this->operation('employes', 'modification', $id, [...$base, 'email' => null])], $rh)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertNull(Employe::findOrFail($id)->email);
    }

    #[Test]
    public function la_descente_porte_l_email_de_l_employe(): void
    {
        $this->assertContains('email', \App\Shared\Sync\Services\CatalogueDescendantService::COLONNES['employes']);
    }

    #[Test]
    public function la_regle_est_partagee_et_stable(): void
    {
        $this->assertNull(AdresseEmailFacultative::normaliser(null));
        $this->assertNull(AdresseEmailFacultative::normaliser("  \t "));
        $this->assertSame('a@b.bj', AdresseEmailFacultative::normaliser(' A@B.BJ '));
    }

    #[Test]
    public function bulletin_disponible_vise_l_email_du_salarie_ou_rien_sans_erreur(): void
    {
        $this->travelTo('2026-10-18 10:00:00');
        $service = ServiceRh::firstOrCreate(['libelle' => 'Réception']);
        $avec = Employe::create([
            'matricule' => 'EMP-2026-00001', 'nom' => 'AVEC', 'prenom' => 'Mail', 'email' => 'avec@exemple.bj', 'poste' => 'x',
            'service_id' => $service->id, 'date_embauche' => '2023-02-01', 'salaire_base' => '100000.00', 'statut' => 'actif',
        ]);
        $sans = Employe::create([
            'matricule' => 'EMP-2026-00002', 'nom' => 'SANS', 'prenom' => 'Mail', 'poste' => 'x',
            'service_id' => $service->id, 'date_embauche' => '2023-02-01', 'salaire_base' => '100000.00', 'statut' => 'actif',
        ]);
        foreach ([$avec, $sans] as $employe) {
            $this->bulletinValide($employe, 'BUL-'.$employe->matricule);
        }

        $parNom = collect((new BulletinDisponibleDetecteur())->detecter())->keyBy('destinataire');

        $this->assertSame('avec@exemple.bj', $parNom['Mail AVEC']['email']);
        $this->assertNull($parNom['Mail SANS']['email']);
    }

    #[Test]
    public function echeance_vps_vise_le_premier_comptable_actif_avec_une_adresse(): void
    {
        $this->compte('comptable', null);
        $this->compte('comptable', 'suspendu@exemple.bj', 'suspendu');
        $this->compte('rh', 'rh@exemple.bj');
        $this->assertNull($this->emailDuComptable());

        $this->compte('comptable', 'compta@exemple.bj');
        $this->assertSame('compta@exemple.bj', $this->emailDuComptable());
    }

    private function emailDuComptable(): ?string
    {
        $methode = new \ReflectionMethod(EcheanceVpsDetecteur::class, 'emailDuComptable');

        return $methode->invoke(app(EcheanceVpsDetecteur::class));
    }

    #[Test]
    public function le_message_compose_pour_un_salarie_porte_son_adresse_et_part_en_file(): void
    {
        $this->travelTo('2026-10-18 10:00:00');
        Queue::fake();
        config(['mail.default' => 'smtp', 'mail.mailers.smtp.host' => 'smtp.exemple.invalid']);
        ModeleNotification::create([
            'evenement' => 'bulletin_disponible', 'canal' => RegistreCanaux::EMAIL, 'objet' => 'Bulletin {periode}',
            'contenu_template' => 'Bonjour {employe}, net {net}.', 'actif' => true,
        ]);
        $service = ServiceRh::firstOrCreate(['libelle' => 'Réception']);
        foreach ([['AVEC', 'avec@exemple.bj'], ['SANS', null]] as [$nom, $email]) {
            $employe = Employe::create([
                'matricule' => 'EMP-2026-'.$nom, 'nom' => $nom, 'prenom' => 'Mail', 'email' => $email, 'poste' => 'x',
                'service_id' => $service->id, 'date_embauche' => '2023-02-01', 'salaire_base' => '100000.00', 'statut' => 'actif',
            ]);
            $this->bulletinValide($employe, 'BUL-'.$nom);
        }

        $bilan = app(FileAttenteNotificationsService::class)->detecter();

        $this->assertSame(2, $bilan['composes']);
        $this->assertSame([], $bilan['echecs']);
        $messages = MessageNotificationCompose::query()->get()->keyBy('destinataire');
        $this->assertSame('avec@exemple.bj', $messages['Mail AVEC']->email_destinataire);
        $this->assertNull($messages['Mail SANS']->email_destinataire);
        Queue::assertPushed(\App\Domain\Notifications\Jobs\EnvoyerNotificationEmailJob::class, 1);
    }
}
