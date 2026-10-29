<?php

declare(strict_types=1);

namespace Tests\Feature\Auth;

use App\Models\User;
use App\Pwa\Livewire\ChangementMotDePasseObligatoire;
use App\Pwa\Livewire\CodeSecours;
use App\Pwa\Livewire\Connexion;
use App\Pwa\Livewire\Transverse\ComptesUtilisateurs;
use App\Pwa\Livewire\Transverse\MonProfil;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Auth\Services\MotDePassePerduService;
use App\Shared\Auth\Support\GenerateurDeSecret;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « Mot de passe perdu » SANS e-mail (décision du PO du 29/10/2026, option A).
 *
 * Trois familles, une seule exigence : la règle est PROUVÉE par le chemin que
 * l'utilisateur emprunte (composants Livewire, middleware, commande), jamais
 * par le seul service.
 *
 *  1. réinitialisation par un administrateur + changement forcé + expiration ;
 *  2. garde-fous (soi-même, super_admin, droit, audit sans secret) ;
 *  3. code de secours (usage unique, rotation, essais limités, non-admin refusé).
 *
 * ## Mutations vérifiées (29/10/2026)
 *
 * Voir `docs/JOURNAL_DES_LOTS.md` : chaque garde ci-dessous a été retirée tour à
 * tour du code et a fait rougir au moins un cas.
 */
final class MotDePassePerduTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->admin = $this->compte('admin.un', 'administrateur', 'Admin-Initial-1');
        RateLimiter::clear('secours|admin.un');
        RateLimiter::clear('secours-adresse|127.0.0.1');
        foreach (['1', '2', '3', '4', '5', '6'] as $n) {
            RateLimiter::clear('secours-adresse|10.0.0.'.$n);
        }
    }

    private function compte(string $login, string $role, string $motDePasse = 'ancien-mot-de-passe'): User
    {
        return User::create([
            'login' => $login,
            'mot_de_passe_hash' => Hash::make($motDePasse),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * @return array{motDePasse: string, expireLe: \Illuminate\Support\Carbon, login: string}
     */
    private function reinitialiser(User $cible, ?User $auteur = null): array
    {
        return app(MotDePassePerduService::class)
            ->reinitialiserParAdministrateur($auteur ?? $this->admin, $cible->id, '10.0.0.5');
    }

    // ====================================================== le générateur

    #[Test]
    public function le_mot_de_passe_temporaire_est_fort_et_sans_caractere_ambigu(): void
    {
        $vus = [];

        for ($i = 0; $i < 200; $i++) {
            $mdp = GenerateurDeSecret::motDePasseTemporaire();
            $vus[$mdp] = true;

            $this->assertGreaterThanOrEqual(12, strlen($mdp));
            $this->assertDoesNotMatchRegularExpression('/[0O1lI]/', $mdp, 'Aucun caractere ambigu.');
            $this->assertMatchesRegularExpression('/[A-Z]/', $mdp);
            $this->assertMatchesRegularExpression('/[a-z]/', $mdp);
            $this->assertMatchesRegularExpression('/[0-9]/', $mdp);
        }

        $this->assertGreaterThan(195, count($vus), 'Les mots de passe ne se repetent pas.');
    }

    #[Test]
    public function le_code_de_secours_a_au_moins_vingt_caracteres_en_groupes_lisibles(): void
    {
        $code = GenerateurDeSecret::codeDeSecours();

        $this->assertMatchesRegularExpression('/^([A-Z2-9]{5}-){4}[A-Z2-9]{5}$/', $code);
        $this->assertGreaterThanOrEqual(20, strlen(str_replace('-', '', $code)));
        $this->assertDoesNotMatchRegularExpression('/[0O1lI]/', $code);
        $this->assertSame(str_replace('-', '', $code), GenerateurDeSecret::normaliserCode(strtolower($code)));
    }

    // ============================================ réinitialisation par admin

    #[Test]
    public function un_administrateur_reinitialise_un_autre_compte_et_voit_le_temporaire_une_fois(): void
    {
        $cible = $this->compte('marie', 'receptionniste');
        $cible->createToken('poste-1');
        $ancienRemember = $cible->remember_token;

        $this->actingAs($this->admin);

        $page = Livewire::test(ComptesUtilisateurs::class)
            ->call('ouvrirReinitialisation', $cible->id)
            ->assertSee(__('pwa.comptes.reinitialiser_confirmer'))
            ->call('reinitialiserMotDePasse');

        $temporaire = $page->get('resultat')['motDePasse'];
        $page->assertSee($temporaire)->assertSee(__('pwa.secret_unique.copier'));

        $cible->refresh();
        $this->assertTrue(Hash::check($temporaire, $cible->mot_de_passe_hash), 'Le hash du temporaire est pose.');
        $this->assertTrue($cible->must_change_password);
        $this->assertEqualsWithDelta(
            now()->addHours(24)->timestamp,
            $cible->temp_expires_at->timestamp,
            10,
            'Le temporaire expire dans 24 h.',
        );
        $this->assertSame(0, $cible->tokens()->count(), 'Les jetons du compte sont coupes.');
        $this->assertNotSame($ancienRemember, $cible->remember_token);

        // Une fois fermée, la fenêtre ne montre plus rien.
        $page->call('fermerModales')->assertSet('resultat', null)->assertDontSee($temporaire);
    }

    #[Test]
    public function un_administrateur_ne_peut_pas_reinitialiser_son_propre_compte(): void
    {
        $this->actingAs($this->admin);
        $avant = $this->admin->mot_de_passe_hash;

        Livewire::test(ComptesUtilisateurs::class)
            ->call('ouvrirReinitialisation', $this->admin->id)
            ->assertSet('compteACibler', null)
            ->assertSee(__('pwa.comptes.refus_soi_meme'));

        // Et si l'appel est force par le service (page manipulee) :
        try {
            app(MotDePassePerduService::class)->reinitialiserParAdministrateur($this->admin, $this->admin->id, null);
            $this->fail('Le service doit refuser la reinitialisation de soi-meme.');
        } catch (\RuntimeException $refus) {
            $this->assertSame(__('pwa.comptes.refus_soi_meme'), $refus->getMessage());
        }

        $this->admin->refresh();
        $this->assertSame($avant, $this->admin->mot_de_passe_hash);
        $this->assertFalse($this->admin->must_change_password);
    }

    #[Test]
    public function seul_un_administrateur_reinitialise_et_un_admin_ne_prend_pas_la_main_sur_un_super_admin(): void
    {
        $cible = $this->compte('marie', 'receptionniste');
        $gerant = $this->compte('gerard', 'gerant');
        $super = $this->compte('chef', 'super_admin');

        // Un gerant (ROLES en lecture) : 403 par `exigerEcriture`.
        $this->actingAs($gerant);
        Livewire::test(ComptesUtilisateurs::class)
            ->set('compteACibler', $cible->id)
            ->call('reinitialiserMotDePasse')
            ->assertForbidden();
        $this->assertFalse($cible->refresh()->must_change_password);

        // Le service refuse aussi un auteur non administrateur, droit RBAC ou non.
        try {
            app(MotDePassePerduService::class)->reinitialiserParAdministrateur($gerant, $cible->id, null);
            $this->fail('Un non-administrateur ne reinitialise rien.');
        } catch (\RuntimeException $refus) {
            $this->assertSame(__('pwa.comptes.refus_droit'), $refus->getMessage());
        }

        // Un administrateur ne reinitialise pas un super_admin ; l'inverse est permis.
        try {
            app(MotDePassePerduService::class)->reinitialiserParAdministrateur($this->admin, $super->id, null);
            $this->fail('Un administrateur ne prend pas la main sur un super_admin.');
        } catch (\RuntimeException $refus) {
            $this->assertSame(__('pwa.comptes.refus_super_admin'), $refus->getMessage());
        }
        $this->assertFalse($super->refresh()->must_change_password);

        $this->reinitialiser($this->admin, $super);
        $this->assertTrue($this->admin->refresh()->must_change_password);
    }

    #[Test]
    public function l_audit_porte_qui_quel_compte_quand_et_jamais_le_secret(): void
    {
        $cible = $this->compte('marie', 'receptionniste');
        $fait = $this->reinitialiser($cible);
        $cible->refresh();

        $entree = JournalAudit::where('action', 'reinitialisation_mot_de_passe')->sole();
        $this->assertSame($this->admin->id, $entree->utilisateur_id, 'Qui.');
        $this->assertSame($cible->id, $entree->entite_id, 'Quel compte.');
        $this->assertSame('utilisateurs', $entree->entite_concernee);
        $this->assertNotNull($entree->date_heure, 'Quand.');
        $this->assertSame('10.0.0.5', $entree->adresse_poste);

        $this->assertNoSecretInAudit([$fait['motDePasse'], $cible->mot_de_passe_hash, $cible->previous_password_hash]);
    }

    /**
     * @param  list<string|null>  $secrets
     */
    private function assertNoSecretInAudit(array $secrets): void
    {
        $tout = JournalAudit::all()->map(fn ($e) => json_encode($e->getAttributes()))->implode("\n");

        $this->assertNotSame('', $tout, 'Le journal doit contenir quelque chose, sinon le controle est vide.');

        foreach ($secrets as $secret) {
            if ($secret === null || $secret === '') {
                continue;
            }
            $this->assertStringNotContainsString($secret, $tout, 'Un secret ou une empreinte figure au journal d audit.');
        }
    }

    #[Test]
    public function le_journal_d_audit_affiche_les_actions_sous_leur_libelle_et_le_login_du_compte(): void
    {
        $cible = $this->compte('marie', 'receptionniste');
        $this->reinitialiser($cible);
        $code = $this->codeDeSecours();
        $this->actingAs($this->admin);

        $html = (string) $this->get('/pwa/journal-audit')->assertOk()->getContent();

        $this->assertStringContainsString('Réinitialisation du mot de passe', $html);
        $this->assertStringContainsString('Code de secours généré', $html);
        $texte = (string) preg_replace('/\s+/', ' ', strip_tags($html));
        $this->assertStringContainsString('Compte utilisateur : marie', $texte);
        // Le journal rendu à l'écran ne porte lui non plus aucun secret.
        $this->assertStringNotContainsString($code, $html);
        $this->assertStringNotContainsString(GenerateurDeSecret::normaliserCode($code), $html);
    }

    // ================================================= changement obligatoire

    #[Test]
    public function le_temporaire_n_ouvre_que_l_ecran_de_choix_d_un_nouveau_mot_de_passe(): void
    {
        $cible = $this->compte('marie', 'gerant');
        $temporaire = $this->reinitialiser($cible)['motDePasse'];

        Livewire::test(Connexion::class)
            ->set('login', 'marie')
            ->set('motDePasse', $temporaire)
            ->call('seConnecter')
            ->assertRedirect(route('pwa.changement-mot-de-passe'));

        $this->assertAuthenticatedAs($cible);

        // Aucun module : tout renvoie vers l'ecran de changement.
        $this->get(route('pwa.accueil'))->assertRedirect(route('pwa.changement-mot-de-passe'));
        $this->get(route('pwa.stocks.liste'))->assertRedirect(route('pwa.changement-mot-de-passe'));
        $this->get(route('pwa.mon-profil'))->assertRedirect(route('pwa.changement-mot-de-passe'));
        $this->get(route('pwa.changement-mot-de-passe'))->assertOk()
            ->assertSee(__('pwa.changement_mdp.titre_h1'));
    }

    #[Test]
    public function le_changement_exige_un_mot_de_passe_different_du_temporaire_et_de_l_ancien(): void
    {
        $cible = $this->compte('marie', 'gerant', 'Ancien-Secret-9');
        $temporaire = $this->reinitialiser($cible)['motDePasse'];
        $this->actingAs($cible->refresh());

        $page = Livewire::test(ChangementMotDePasseObligatoire::class);

        $page->set('nouveauMotDePasse', 'court')->set('confirmationMotDePasse', 'court')
            ->call('definirNouveauMotDePasse')
            ->assertHasErrors('nouveauMotDePasse');

        $page->set('nouveauMotDePasse', 'Nouveau-Secret-7')->set('confirmationMotDePasse', 'autre-chose-1')
            ->call('definirNouveauMotDePasse')
            ->assertHasErrors('confirmationMotDePasse');

        $page->set('nouveauMotDePasse', $temporaire)->set('confirmationMotDePasse', $temporaire)
            ->call('definirNouveauMotDePasse')
            ->assertHasErrors(['nouveauMotDePasse' => __('pwa.changement_mdp.identique_temporaire')]);

        $page->set('nouveauMotDePasse', 'Ancien-Secret-9')->set('confirmationMotDePasse', 'Ancien-Secret-9')
            ->call('definirNouveauMotDePasse')
            ->assertHasErrors(['nouveauMotDePasse' => __('pwa.changement_mdp.identique_ancien')]);

        $this->assertTrue($cible->refresh()->must_change_password, 'Rien n a ete change par les refus.');
    }

    #[Test]
    public function apres_le_changement_la_session_est_fermee_et_le_nouveau_mot_de_passe_ouvre_les_modules(): void
    {
        $cible = $this->compte('marie', 'gerant');
        $cible->createToken('poste-1');
        $this->reinitialiser($cible);
        $this->actingAs($cible->refresh());
        $remember = $cible->remember_token;

        Livewire::test(ChangementMotDePasseObligatoire::class)
            ->set('nouveauMotDePasse', 'Nouveau-Secret-7')
            ->set('confirmationMotDePasse', 'Nouveau-Secret-7')
            ->call('definirNouveauMotDePasse')
            ->assertRedirect(route('pwa.connexion'));

        $this->assertGuest();
        $cible->refresh();
        $this->assertFalse($cible->must_change_password);
        $this->assertNull($cible->temp_expires_at);
        $this->assertNull($cible->previous_password_hash);
        $this->assertNotSame($remember, $cible->remember_token, 'Le jeton « se souvenir de moi » est regenere.');
        $this->assertSame(0, $cible->tokens()->count());

        Livewire::test(Connexion::class)
            ->set('login', 'marie')
            ->set('motDePasse', 'Nouveau-Secret-7')
            ->call('seConnecter')
            ->assertRedirect(route('pwa.accueil'));
    }

    #[Test]
    public function le_temporaire_expire_apres_vingt_quatre_heures(): void
    {
        $cible = $this->compte('marie', 'gerant');
        $temporaire = $this->reinitialiser($cible)['motDePasse'];

        // 23 h 59 : encore valable.
        $this->travel(23)->hours();
        $this->travel(59)->minutes();
        Livewire::test(Connexion::class)
            ->set('login', 'marie')->set('motDePasse', $temporaire)
            ->call('seConnecter')
            ->assertRedirect(route('pwa.changement-mot-de-passe'));
        auth()->logout();

        // 24 h 01 : refuse, il faut en regenerer un.
        $this->travel(2)->minutes();
        Livewire::test(Connexion::class)
            ->set('login', 'marie')->set('motDePasse', $temporaire)
            ->call('seConnecter')
            ->assertHasErrors(['identifiants' => __('pwa.changement_mdp.expire')]);
        $this->assertGuest();

        // Une session deja ouverte avec le temporaire est fermee par le middleware.
        $this->actingAs($cible->refresh());
        $this->get(route('pwa.changement-mot-de-passe'))
            ->assertRedirect(route('pwa.connexion'));
        $this->assertGuest();

        // Et un nouveau temporaire remet tout en etat.
        $this->travelBack();
        $fait = $this->reinitialiser($cible);
        $this->assertTrue(Hash::check($fait['motDePasse'], $cible->refresh()->mot_de_passe_hash));
    }

    #[Test]
    public function une_session_ouverte_avant_la_reinitialisation_est_fermee(): void
    {
        $cible = $this->compte('marie', 'gerant', 'Ancien-Secret-9');

        // La connexion range ELLE-MEME l'empreinte du mot de passe dans la session :
        // sans cela, elle ne serait rangee qu'a la requete suivante, apres une
        // reinitialisation eventuelle.
        Livewire::test(Connexion::class)
            ->set('login', 'marie')->set('motDePasse', 'Ancien-Secret-9')
            ->call('seConnecter')->assertRedirect(route('pwa.accueil'));
        $this->assertNotEmpty(session('empreintes_mots_de_passe'));

        $this->reinitialiser($cible);

        // Le meme navigateur, sans se reconnecter, sur une NOUVELLE requete (le
        // garde relit alors le compte en base) : AuthenticateSession le renvoie.
        auth()->forgetGuards();
        $this->get(route('pwa.accueil'))->assertRedirect(route('pwa.connexion'));
    }

    #[Test]
    public function le_titulaire_qui_change_son_propre_mot_de_passe_reste_connecte(): void
    {
        $this->compte('marie', 'gerant', 'Ancien-Secret-9');

        Livewire::test(Connexion::class)
            ->set('login', 'marie')->set('motDePasse', 'Ancien-Secret-9')
            ->call('seConnecter')->assertRedirect(route('pwa.accueil'));

        Livewire::test(MonProfil::class)
            ->set('ancienMotDePasse', 'Ancien-Secret-9')
            ->set('nouveauMotDePasse', 'Nouveau-Secret-7')
            ->set('confirmationMotDePasse', 'Nouveau-Secret-7')
            ->call('changerMotDePasse')
            ->assertHasNoErrors();

        // Une NOUVELLE requete (le garde relit le compte en base) : toujours ouvert.
        auth()->forgetGuards();
        $this->get(route('pwa.accueil'))->assertOk();
    }

    #[Test]
    public function l_api_n_emet_aucun_jeton_tant_que_le_mot_de_passe_temporaire_n_est_pas_remplace(): void
    {
        $cible = $this->compte('marie', 'gerant');
        $temporaire = $this->reinitialiser($cible)['motDePasse'];

        $this->postJson('/api/v1/login', ['identifiant' => 'marie', 'mot_de_passe' => $temporaire, 'poste' => 'poste-1'])
            ->assertStatus(403);

        $this->assertSame(0, $cible->tokens()->count());
    }

    // ================================================== code de secours

    #[Test]
    public function mon_profil_pose_un_code_apres_confirmation_du_mot_de_passe_et_ne_stocke_que_son_hash(): void
    {
        $this->actingAs($this->admin);

        $page = Livewire::test(MonProfil::class)
            ->call('ouvrirFormulaireCodeSecours')
            ->set('motDePasseCodeSecours', 'mauvais')
            ->call('genererCodeSecours')
            ->assertHasErrors('motDePasseCodeSecours')
            ->assertSet('codeSecoursAffiche', null);

        $this->assertNull($this->admin->refresh()->recovery_code_hash);

        $page->set('motDePasseCodeSecours', 'Admin-Initial-1')->call('genererCodeSecours');
        $code = $page->get('codeSecoursAffiche');

        $this->assertMatchesRegularExpression('/^([A-Z2-9]{5}-){4}[A-Z2-9]{5}$/', $code);
        $page->assertSee($code)->assertSee(__('pwa.secret_unique.copier'))->assertSee(__('pwa.secret_unique.imprimer'));

        $this->admin->refresh();
        $this->assertNotNull($this->admin->recovery_code_generated_at);
        $this->assertNotSame($code, $this->admin->recovery_code_hash);
        $this->assertTrue(Hash::check(GenerateurDeSecret::normaliserCode($code), $this->admin->recovery_code_hash));

        $page->call('fermerModales')->assertSet('codeSecoursAffiche', null)->assertDontSee($code);
        $this->assertNoSecretInAudit([$code, GenerateurDeSecret::normaliserCode($code), $this->admin->recovery_code_hash]);
        $this->assertSame(1, JournalAudit::where('action', 'code_secours_genere')->count());
    }

    #[Test]
    public function un_non_administrateur_n_a_ni_section_ni_geste_de_code_de_secours(): void
    {
        $this->actingAs($this->compte('marie', 'gerant'));

        Livewire::test(MonProfil::class)
            ->assertDontSee(__('pwa.profil.code_secours_titre'))
            ->call('ouvrirFormulaireCodeSecours')
            ->assertForbidden();
    }

    #[Test]
    public function la_commande_artisan_affiche_le_code_une_fois_et_refuse_un_non_administrateur(): void
    {
        $this->compte('marie', 'gerant');

        // Un seul administrateur actif : la commande le choisit sans argument.
        $this->artisan('tatacora:code-secours')
            ->expectsOutputToContain('Code de secours de « admin.un »')
            ->assertSuccessful();

        $this->assertNotNull($this->admin->refresh()->recovery_code_hash);

        $this->artisan('tatacora:code-secours', ['login' => 'marie'])->assertFailed();
        $this->assertNull(User::where('login', 'marie')->sole()->recovery_code_hash);

        // Deux administrateurs : la commande refuse de choisir.
        $this->compte('admin.deux', 'administrateur');
        $this->artisan('tatacora:code-secours')->assertFailed();
        $this->assertSame(0, Artisan::call('tatacora:code-secours', ['login' => 'admin.deux']));
    }

    /** Pose un code a `admin.un` et le rend. */
    private function codeDeSecours(?User $admin = null): string
    {
        return app(MotDePassePerduService::class)->poserCodeDeSecours($admin ?? $this->admin, '10.0.0.5');
    }

    private function perdu(string $login, string $code, string $nouveau = 'Tout-Neuf-Mdp-4'): \Livewire\Features\SupportTesting\Testable
    {
        return Livewire::test(CodeSecours::class)
            ->set('login', $login)
            ->set('code', $code)
            ->set('nouveauMotDePasse', $nouveau)
            ->set('confirmationMotDePasse', $nouveau)
            ->call('reinitialiserParCodeDeSecours');
    }

    #[Test]
    public function le_code_reinitialise_l_administrateur_est_consomme_et_un_nouveau_est_remis_une_fois(): void
    {
        $code = $this->codeDeSecours();
        $this->admin->createToken('poste-1');

        $page = $this->perdu('admin.un', strtolower($code));
        $nouveauCode = $page->get('nouveauCode');

        $page->assertHasNoErrors()->assertSee($nouveauCode)->assertSee(__('pwa.secret_unique.imprimer'));
        $this->assertNotSame($code, $nouveauCode, 'Rotation : un NOUVEAU code.');

        $this->admin->refresh();
        $this->assertTrue(Hash::check('Tout-Neuf-Mdp-4', $this->admin->mot_de_passe_hash));
        $this->assertFalse($this->admin->must_change_password);
        $this->assertSame(0, $this->admin->tokens()->count(), 'Les jetons sont coupes.');
        $this->assertTrue(Hash::check(GenerateurDeSecret::normaliserCode($nouveauCode), $this->admin->recovery_code_hash));

        // Usage unique : l'ancien code ne sert plus, le nouveau si.
        $this->perdu('admin.un', $code, 'Autre-Mdp-Sur-5')->assertHasErrors('identifiants');
        $this->assertTrue(Hash::check('Tout-Neuf-Mdp-4', $this->admin->refresh()->mot_de_passe_hash), 'L ancien code n a rien change.');
        $this->perdu('admin.un', $nouveauCode, 'Autre-Mdp-Sur-5')->assertHasNoErrors();

        // Rien de secret au journal ; la reussite et le refus y sont traces.
        $this->assertSame(2, JournalAudit::where('action', 'code_secours_utilise')->count());
        $this->assertSame(1, JournalAudit::where('action', 'code_secours_refuse')->count());
        $this->assertNoSecretInAudit([
            $code, $nouveauCode, 'Tout-Neuf-Mdp-4', 'Autre-Mdp-Sur-5',
            GenerateurDeSecret::normaliserCode($code), $this->admin->refresh()->recovery_code_hash,
        ]);
    }

    #[Test]
    public function le_refus_est_identique_que_le_compte_existe_ou_non_ou_ne_soit_pas_administrateur(): void
    {
        $code = $this->codeDeSecours();
        $gerant = $this->compte('marie', 'gerant');
        // Un gerant dont on a force un hash de code : il ne doit pas pouvoir l'emprunter.
        $gerant->forceFill(['recovery_code_hash' => Hash::make(GenerateurDeSecret::normaliserCode($code))])->save();

        $messages = [];

        foreach ([['inconnu', $code], ['admin.un', 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE'], ['marie', $code]] as [$login, $saisie]) {
            $page = $this->perdu($login, $saisie);
            $messages[] = $page->errors()->get('identifiants')[0] ?? null;
        }

        $this->assertSame([__('pwa.code_secours.refus')], array_values(array_unique($messages)), 'Meme message dans les trois cas.');
        $this->assertFalse(Hash::check('Tout-Neuf-Mdp-4', $gerant->refresh()->mot_de_passe_hash), 'Un non-administrateur n entre pas par ce chemin.');
        $this->assertTrue(Hash::check('Admin-Initial-1', $this->admin->refresh()->mot_de_passe_hash));
    }

    #[Test]
    public function cinq_echecs_bloquent_quinze_minutes_meme_avec_le_bon_code(): void
    {
        $code = $this->codeDeSecours();

        for ($i = 0; $i < 5; $i++) {
            $this->perdu('admin.un', 'ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ')->assertHasErrors('identifiants');
        }

        // Le bon code, maintenant : bloque, sans dire pourquoi autrement que par la duree.
        $page = $this->perdu('admin.un', $code);
        $page->assertHasErrors(['identifiants' => __('pwa.code_secours.bloque', ['minutes' => '15'])]);
        $this->assertTrue(Hash::check('Admin-Initial-1', $this->admin->refresh()->mot_de_passe_hash));

        // Le blocage tombe apres quinze minutes.
        $this->travel(16)->minutes();
        $this->perdu('admin.un', $code)->assertHasNoErrors();
        $this->travelBack();
    }

    #[Test]
    public function le_blocage_vaut_aussi_par_compte_quelle_que_soit_l_adresse(): void
    {
        $code = $this->codeDeSecours();
        $service = app(MotDePassePerduService::class);

        // Cinq echecs depuis cinq adresses differentes : chaque adresse n'en a qu'un.
        foreach (['10.0.0.1', '10.0.0.2', '10.0.0.3', '10.0.0.4', '10.0.0.5'] as $adresse) {
            try {
                $service->reinitialiserParCodeDeSecours('admin.un', 'ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ', 'Tout-Neuf-Mdp-4', $adresse);
            } catch (\RuntimeException) {
            }
        }

        // Le bon code, depuis une sixieme adresse : le COMPTE est bloque.
        try {
            $service->reinitialiserParCodeDeSecours('admin.un', $code, 'Tout-Neuf-Mdp-4', '10.0.0.6');
            $this->fail('Le compte doit etre bloque, quelle que soit l adresse.');
        } catch (\RuntimeException $refus) {
            $this->assertSame(__('pwa.code_secours.bloque', ['minutes' => '15']), $refus->getMessage());
        }

        $this->assertSame(1, JournalAudit::where('action', 'code_secours_bloque')->count());
        $this->assertTrue(Hash::check('Admin-Initial-1', $this->admin->refresh()->mot_de_passe_hash));
    }

    #[Test]
    public function le_blocage_vaut_aussi_par_adresse_pour_des_comptes_differents(): void
    {
        $code = $this->codeDeSecours();

        foreach (['a', 'b', 'c', 'd', 'e'] as $login) {
            $this->perdu($login, 'ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ');
        }

        // Un login jamais essaye, la meme adresse : bloque aussi.
        $this->perdu('admin.un', $code)->assertHasErrors(['identifiants' => __('pwa.code_secours.bloque', ['minutes' => '15'])]);
    }

    #[Test]
    public function une_saisie_incomplete_ne_consomme_aucun_essai(): void
    {
        $this->codeDeSecours();

        for ($i = 0; $i < 8; $i++) {
            Livewire::test(CodeSecours::class)
                ->set('login', 'admin.un')->set('code', '')
                ->set('nouveauMotDePasse', 'court')->set('confirmationMotDePasse', 'court')
                ->call('reinitialiserParCodeDeSecours')
                ->assertHasErrors(['code', 'nouveauMotDePasse']);
        }

        $this->assertFalse(RateLimiter::tooManyAttempts('secours|admin.un', 5));
    }

    #[Test]
    public function un_ancien_administrateur_sans_code_est_refuse_comme_les_autres(): void
    {
        // Compte d'avant ce lot : pas de code. Aucune porte derobee.
        $this->perdu('admin.un', 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE')
            ->assertHasErrors(['identifiants' => __('pwa.code_secours.refus')]);
    }

    #[Test]
    public function la_page_de_connexion_mene_au_recours_et_la_page_s_affiche_sans_session(): void
    {
        $this->get(route('pwa.connexion'))
            ->assertOk()
            ->assertSee(route('pwa.code-secours'), false)
            ->assertSee(__('pwa.connexion.mot_de_passe_administrateur_perdu'));

        $this->get(route('pwa.code-secours'))
            ->assertOk()
            ->assertSee(__('pwa.code_secours.titre'));
    }
}
