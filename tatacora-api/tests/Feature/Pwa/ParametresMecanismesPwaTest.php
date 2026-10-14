<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Ventes\Models\TableSalle;
use App\Domain\Ventes\Services\PanierService;
use App\Domain\Ventes\Services\TableSalleService;
use App\Models\User;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Pwa\Support\AlertesOuverture;
use App\Shared\Backup\Services\ReinitialisationDonneesTestService;
use App\Shared\Mail\Services\ConfigurationMailService;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\Parametres\Services\OptionsSystemeService;
use App\Shared\Rbac\Models\Role;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\TablesSalleSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les MÉCANISMES rendus réels par la vague « sept onglets » du 02/09/2026
 * (directive Product Owner) : bascules d'activation appliquées au clic ET
 * réellement LUES, envoi d'email de test honnête, téléversement de logo
 * remplacé jamais accumulé, CRUD des tables de salle avec le refus du maître.
 *
 * ## Ce que chaque cas éprouve, et pourquoi il existe
 *
 * La famille de défauts visée est PA-59/60/61 — l'indicateur qui affirme un
 * état qu'il n'a pas vérifié : une bascule que rien ne lit, un « email envoyé
 * avec succès » sans envoi, une table désactivable pendant que son panier
 * porte des consommations servies. Chaque garde nouvelle a été tranchée par
 * mutation (casser → rouge → restaurer), notée sur le cas concerné.
 *
 * @see App\Pwa\Livewire\Transverse\Parametres
 * @see App\Domain\Ventes\Services\TableSalleService
 * @see App\Shared\Parametres\Services\OptionsSystemeService
 */
final class ParametresMecanismesPwaTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    // =====================================================================
    // Activation & Sécurité — la bascule est LUE, pas seulement stockée
    // =====================================================================

    /**
     * La bascule s'applique AU CLIC (jamais au bouton Enregistrer) et son
     * consommateur la lit : `ReinitialisationDonneesTestService` refuse tant
     * qu'elle est fermée — l'état par défaut du maître — et accepte dès
     * qu'elle est ouverte (hors Production, l'autre garde ne bouge pas).
     */
    #[Test]
    public function la_bascule_reinitialisation_ouvre_reellement_l_onglet_seeders(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $service = app(ReinitialisationDonneesTestService::class);

        // FERMÉE par défaut, comme au maître (`options-systeme.js`, DEFAUTS).
        // `estOuverte()` est la lecture du CONSOMMATEUR (refonte Import &
        // Export du 02/09/2026), pas une seconde formule de cet écran.
        $this->assertFalse($service->estOuverte());

        Livewire::test(Parametres::class)
            ->call('basculerOption', OptionsSystemeService::CLE_REINITIALISATION_SEEDERS)
            ->assertHasNoErrors();

        // Appliquée immédiatement : aucune étape « Enregistrer » entre le
        // clic et l'effet.
        $this->assertTrue($service->estOuverte());
        $this->assertDatabaseHas('parametres_systeme', [
            'cle' => OptionsSystemeService::CLE_REINITIALISATION_SEEDERS,
            'valeur' => 'true',
        ]);

        // Un second clic referme — et le service le voit aussi.
        Livewire::test(Parametres::class)
            ->call('basculerOption', OptionsSystemeService::CLE_REINITIALISATION_SEEDERS);

        $this->assertFalse($service->estOuverte());
    }

    /**
     * `alertes_ouverture` — OUVERTE par défaut (le seul défaut à `true` du
     * maître), et fermée, la cloche ne dérive PLUS RIEN : le cas construit
     * une condition d'alerte réelle (caisse non clôturée d'hier), sans quoi
     * « fermée → aucune alerte » serait vert à vide.
     */
    #[Test]
    public function la_bascule_alertes_ouverture_eteint_reellement_la_cloche(): void
    {
        $admin = $this->utilisateur('administrateur');
        $this->actingAs($admin);

        // Une clôture en retard — la condition la plus simple à poser.
        DB::table('sessions_caisse')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'point_vente' => 'bar',
            'date_ouverture' => now()->subDay(),
            'montant_fond' => '10000.00',
            'utilisateur_ouverture_id' => $admin->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Défaut du maître : ouverte — l'alerte est dérivée.
        $this->assertNotSame([], AlertesOuverture::pour($admin));

        Livewire::test(Parametres::class)
            ->call('basculerOption', OptionsSystemeService::CLE_ALERTES_OUVERTURE);

        // Fermée : plus rien, pour tous les profils.
        $this->assertSame([], AlertesOuverture::pour($admin));
    }

    /** Une clé hors du groupe des bascules est un bouton falsifié : 404. */
    #[Test]
    public function une_cle_hors_du_groupe_activation_est_refusee_par_la_bascule(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Parametres::class)
            ->call('basculerOption', ReportHeaderService::CLE_RAISON_SOCIALE)
            ->assertNotFound();

        $this->assertDatabaseMissing('parametres_systeme', [
            'cle' => ReportHeaderService::CLE_RAISON_SOCIALE,
        ]);
    }

    /** Le RBAC de l'écran : un rôle en lecture ne bascule rien. */
    #[Test]
    public function un_role_en_lecture_ne_bascule_aucune_option(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        Livewire::test(Parametres::class)
            ->call('basculerOption', OptionsSystemeService::CLE_REINITIALISATION_SEEDERS)
            ->assertForbidden();

        $this->assertFalse(app(ReinitialisationDonneesTestService::class)->estOuverte());
    }

    // =====================================================================
    // Email (SMTP) — le test d'envoi ne SIMULE jamais
    // =====================================================================

    /**
     * Les trois issues honnêtes : sans adresse de contact, le dire ; sans
     * transport réel (mailer `array`/`log`), le dire — jamais « envoyé avec
     * succès » sur un envoi qui n'a pas eu lieu (le maître, lui, simule :
     * `parametres.html` l.524-527) ; et quand le transport accepte, dire à
     * qui c'est parti.
     */
    #[Test]
    public function le_test_email_dit_l_etat_reel_du_transport(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        // 1. Aucune adresse de contact paramétrée.
        $composant = Livewire::test(Parametres::class)->call('envoyerEmailTest');
        $resultat = $composant->get('resultatTestEmail');
        $this->assertFalse($resultat['succes']);
        $this->assertSame(__('pwa.parametres.email_test_sans_adresse'), $resultat['detail']);

        // 2. Une adresse, mais aucun transport réel (l'environnement de test
        // roule sur le mailer `array`).
        ParametreSysteme::create(['cle' => ReportHeaderService::CLE_EMAIL, 'valeur' => 'contact@tatacora.test']);
        config(['mail.default' => 'array']);

        $composant = Livewire::test(Parametres::class)->call('envoyerEmailTest');
        $resultat = $composant->get('resultatTestEmail');
        $this->assertFalse($resultat['succes']);
        $this->assertSame(__('pwa.parametres.email_test_sans_configuration'), $resultat['detail']);

        // 3. Le serveur SMTP paramétré prend la main sur le `.env` — la
        // configuration effective est bien celle de l'écran — et le transport
        // (substitué ici) accepte : le résultat le dit, avec l'adresse.
        ParametreSysteme::create(['cle' => ConfigurationMailService::CLE_SMTP_HOTE, 'valeur' => 'smtp.tatacora.test']);
        ParametreSysteme::create(['cle' => ConfigurationMailService::CLE_SMTP_PORT, 'valeur' => '2525']);
        Mail::fake();

        $composant = Livewire::test(Parametres::class)->call('envoyerEmailTest');
        $resultat = $composant->get('resultatTestEmail');

        $this->assertTrue($resultat['succes']);
        $this->assertSame(__('pwa.parametres.email_test_envoye', ['adresse' => 'contact@tatacora.test']), $resultat['detail']);
        $this->assertSame('smtp.tatacora.test', config('mail.mailers.smtp.host'));
        $this->assertSame(2525, config('mail.mailers.smtp.port'));
        $this->assertSame('smtp', config('mail.default'));
    }

    // =====================================================================
    // Logo & Apparence — remplacé, jamais accumulé
    // =====================================================================

    /**
     * Le téléversement écrit un fichier RÉEL sur le disque `public`, et un
     * second téléversement d'une autre extension SUPPRIME le premier : un
     * répertoire qui accumule rendrait `fichierDe()` ambigu, et l'ancien logo
     * pourrait ressortir.
     */
    #[Test]
    public function le_logo_televerse_remplace_l_ancien_sans_accumulation(): void
    {
        Storage::fake(ApparenceEtablissementService::DISQUE);
        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Parametres::class)
            ->call('ouvrirChangementLogo')
            ->assertSet('etatFormulaire', 'logo')
            ->set('logoTeleverse', UploadedFile::fake()->image('logo.png', 200, 200))
            ->call('enregistrerLogo')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $disque = Storage::disk(ApparenceEtablissementService::DISQUE);
        $disque->assertExists('apparence/logo.png');

        // Second envoi, autre extension : l'ancien fichier PART.
        Livewire::test(Parametres::class)
            ->call('ouvrirChangementLogo')
            ->set('logoTeleverse', UploadedFile::fake()->image('nouveau.jpg', 200, 200))
            ->call('enregistrerLogo')
            ->assertHasNoErrors();

        $disque->assertMissing('apparence/logo.png');
        $disque->assertExists('apparence/logo.jpg');

        // Et la coquille le sert désormais par la route dédiée (pas de
        // `storage:link` sur cPanel mutualisé), plus l'actif livré.
        $this->assertStringContainsString('/pwa/apparence/logo', app(ApparenceEtablissementService::class)->urlLogo());
    }

    /** Un fichier qui n'est pas une image PNG/JPG est refusé avant toute écriture. */
    #[Test]
    public function un_fichier_hors_format_est_refuse_au_televersement(): void
    {
        Storage::fake(ApparenceEtablissementService::DISQUE);
        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Parametres::class)
            ->call('ouvrirChangementLogo')
            ->set('logoTeleverse', UploadedFile::fake()->create('script.pdf', 10, 'application/pdf'))
            ->call('enregistrerLogo')
            ->assertHasErrors('logoTeleverse');

        $this->assertSame([], Storage::disk(ApparenceEtablissementService::DISQUE)->files('apparence'));
    }

    // =====================================================================
    // Espaces & tables — le CRUD réel, avec le refus du maître
    // =====================================================================

    /**
     * LE REFUS DU MAÎTRE : une table au panier OUVERT ne se désactive pas —
     * les consommations servies n'auraient plus de table pour les porter
     * jusqu'à l'addition. Le refus vit dans `TableSalleService::basculer()`,
     * jamais recopié à l'écran.
     *
     * Éprouvé par mutation le 02/09/2026 : retirer le contrôle d'occupation
     * du service fait rougir ce cas (la table passe `actif = false` pendant
     * que son panier est ouvert) — restauré ensuite.
     */
    #[Test]
    public function une_table_au_panier_ouvert_ne_se_desactive_pas(): void
    {
        $this->seed(TablesSalleSeeder::class);
        $this->actingAs($this->utilisateur('administrateur'));

        $table = TableSalle::where('libelle', 'R1')->firstOrFail();
        app(PanierService::class)->ouvrirPourPoste('Restaurant', $table->id);

        Livewire::test(Parametres::class)
            ->call('basculerTable', $table->id);

        // Refusée : RIEN n'a bougé. (Le bandeau `pwa-erreur` est flashé par
        // l'action — la boutique de session des requêtes Livewire de test ne
        // l'expose pas au test, le MESSAGE est donc éprouvé sur le service,
        // l'auteur unique du refus.)
        $this->assertTrue($table->refresh()->actif);

        try {
            app(TableSalleService::class)->basculer($table->id);
            $this->fail('La desactivation d une table au panier ouvert aurait du etre refusee.');
        } catch (\RuntimeException $refus) {
            $this->assertStringContainsString('R1', $refus->getMessage());
            $this->assertSame(__('ventes.table_panier_ouvert', ['libelle' => 'R1']), $refus->getMessage());
        }

        // Une table SANS panier ouvert, elle, se désactive — puis se réactive.
        $libre = TableSalle::where('libelle', 'J1')->firstOrFail();

        Livewire::test(Parametres::class)->call('basculerTable', $libre->id);
        $this->assertFalse($libre->refresh()->actif);

        Livewire::test(Parametres::class)->call('basculerTable', $libre->id);
        $this->assertTrue($libre->refresh()->actif);
    }

    /**
     * Créer et renuméroter : le libellé SUIT le numéro (tables-engine.js), et
     * un numéro déjà pris est refusé avec le message du maître — la table
     * n'est jamais créée en double (l'unicité `(espace, numero)` du schéma
     * tient ce que le service vérifie).
     */
    #[Test]
    public function creer_et_renumeroter_une_table_suivent_les_regles_du_maitre(): void
    {
        $this->seed(TablesSalleSeeder::class);
        $this->actingAs($this->utilisateur('administrateur'));

        // Création réelle : R7 n'existe pas au jeu initial (6 au restaurant).
        Livewire::test(Parametres::class)
            ->call('ouvrirAjoutTable')
            ->assertSet('etatFormulaire', 'table')
            ->set('tableEspace', 'restaurant')
            ->set('tableNumero', '7')
            ->set('tablePlaces', '6')
            ->call('enregistrerTable')
            ->assertHasNoErrors();

        $creee = TableSalle::where('espace', 'restaurant')->where('numero', 7)->firstOrFail();
        $this->assertSame('R7', $creee->libelle);
        $this->assertSame(6, $creee->places);

        // Un numéro déjà pris est refusé — « La table R1 existe déjà. »
        Livewire::test(Parametres::class)
            ->call('ouvrirAjoutTable')
            ->set('tableEspace', 'restaurant')
            ->set('tableNumero', '1')
            ->call('enregistrerTable')
            ->assertHasErrors('tableNumero');

        // Renumérotation : le libellé suit.
        Livewire::test(Parametres::class)
            ->call('ouvrirRenumerotationTable', $creee->id)
            ->assertSet('tableNumero', '7')
            ->set('tableNumero', '9')
            ->call('enregistrerTable')
            ->assertHasNoErrors();

        $creee->refresh();
        $this->assertSame(9, $creee->numero);
        $this->assertSame('R9', $creee->libelle);
    }

    /**
     * « Rétablir le jeu initial » : les treize tables du seeder reviennent
     * ACTIVES par LE MÊME `retablirJeuInitial()` que lui (un seul auteur), la
     * table hors jeu est DÉSACTIVÉE — jamais supprimée : ses ventes passées
     * doivent continuer de la citer (RG-02).
     */
    #[Test]
    public function retablir_le_jeu_initial_reactive_les_treize_tables_sans_rien_supprimer(): void
    {
        $this->seed(TablesSalleSeeder::class);
        $this->actingAs($this->utilisateur('administrateur'));

        // L'exploitant a remanié : R1 désactivée, une table hors jeu créée.
        app(TableSalleService::class)->basculer(TableSalle::where('libelle', 'R1')->firstOrFail()->id);
        $horsJeu = app(TableSalleService::class)->creer('plage', 9);

        Livewire::test(Parametres::class)
            ->call('ouvrirRetablirTables')
            ->assertSet('confirmationRetablirTables', true)
            ->call('retablirTables')
            ->assertSet('confirmationRetablirTables', false);

        $this->assertSame(13, TableSalle::where('actif', true)->count());
        $this->assertTrue(TableSalle::where('libelle', 'R1')->firstOrFail()->actif);
        // Hors jeu : désactivée, PAS supprimée.
        $this->assertFalse($horsJeu->refresh()->actif);
        $this->assertSame(14, TableSalle::count());
    }

    /** Le seeder est idempotent ET s'efface devant une base déjà dotée. */
    #[Test]
    public function le_seeder_des_tables_ne_double_rien_et_respecte_une_base_remaniee(): void
    {
        $this->seed(TablesSalleSeeder::class);
        $this->assertSame(13, TableSalle::count());

        // Re-semer ne double rien.
        $this->seed(TablesSalleSeeder::class);
        $this->assertSame(13, TableSalle::count());

        // Une base remaniée n'est PAS écrasée : le seeder se retire, le
        // rétablissement reste un CHOIX de l'écran Paramètres.
        $this->actingAs($this->utilisateur('administrateur'));
        $desactivee = TableSalle::where('libelle', 'P1')->firstOrFail();
        app(TableSalleService::class)->basculer($desactivee->id);

        $this->seed(TablesSalleSeeder::class);
        $this->assertFalse($desactivee->refresh()->actif);
    }

    // =====================================================================

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.'.$role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
