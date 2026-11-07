<?php

declare(strict_types=1);

namespace Tests\Feature\Parametres;

use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\ReglagesMecef;
use App\Domain\Facturation\Services\TraceReglageFacturation;
use App\Models\User;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use App\Shared\Secrets\Models\SecretConfiguration;
use App\Shared\Secrets\Services\SecretsConfigurationService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Lot 1 de la facturation normalisée (MECeF) : le réglage du MODE, ses
 * validations, et le JETON JWT e-MECeF — chiffré, masqué, jamais exposé au
 * navigateur, jamais journalisé, jamais descendu au poste.
 *
 * Le jeton ci-dessous est FICTIF (une forme de JWT, aucune valeur réelle).
 */
final class ReglageFacturationNormaliseeTest extends TestCase
{
    use RefreshDatabase;

    private const JETON = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0LW5vbi1yZWVsIn0.c2lnbmF0dXJlLW5vbi1yZWVsbGU';

    private const IFU = '0202011344660';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function sans_reglage_le_mode_est_desactive_et_une_valeur_inconnue_aussi(): void
    {
        $this->assertSame(ModeFacturation::Desactive, ModeFacturation::courant());

        ParametreSysteme::create(['cle' => ModeFacturation::CLE, 'valeur' => 'n-importe-quoi']);

        $this->assertSame(ModeFacturation::Desactive, ModeFacturation::courant());
    }

    #[Test]
    public function le_registre_declare_le_groupe_mecef_sans_aucun_secret(): void
    {
        $cles = array_map(
            static fn ($d) => $d->cle,
            array_filter(RegistreParametres::definitions(), static fn ($d) => $d->groupe === RegistreParametres::GROUPE_MECEF),
        );

        $this->assertEqualsCanonicalizing(
            [ModeFacturation::CLE, ReglagesMecef::CLE_API_URL, ReglagesMecef::CLE_OPERATEUR_ID, ReglagesMecef::CLE_OPERATEUR_NOM],
            array_values($cles),
        );

        foreach (RegistreParametres::cles() as $cle) {
            foreach (RegistreParametres::MOTIFS_SECRET as $motif) {
                $this->assertStringNotContainsString($motif, $cle, "« $cle » ressemble à un secret");
            }
        }
    }

    #[Test]
    public function un_mode_reel_est_refuse_tant_que_ce_qu_il_exige_manque(): void
    {
        $this->actingAs($this->compte('administrateur'));
        $service = app(EnregistrerParametreService::class);

        // Boîtier sans IFU ni opérateur.
        try {
            $service->enregistrer([ModeFacturation::CLE => 'boitier']);
            $this->fail('Le mode boîtier sans IFU doit être refusé.');
        } catch (RuntimeException $refus) {
            $this->assertStringContainsString('13 chiffres', $refus->getMessage());
            $this->assertStringContainsString('opérateur', $refus->getMessage());
        }
        $this->assertNull(ParametreSysteme::where('cle', ModeFacturation::CLE)->value('valeur'));

        // IFU et opérateur posés : le boîtier passe (aucun jeton exigé).
        $service->enregistrer([
            'entreprise_ifu' => self::IFU,
            ReglagesMecef::CLE_OPERATEUR_ID => 'RECEPTION01',
            ReglagesMecef::CLE_OPERATEUR_NOM => 'Réception',
            ModeFacturation::CLE => 'boitier',
        ]);
        $this->assertSame(ModeFacturation::Boitier, ModeFacturation::courant());

        // e-MECeF exige en plus le jeton.
        try {
            $service->enregistrer([ModeFacturation::CLE => 'emecef']);
            $this->fail('Le mode e-MECeF sans jeton doit être refusé.');
        } catch (RuntimeException $refus) {
            $this->assertStringContainsString('jeton', $refus->getMessage());
        }
        $this->assertSame(ModeFacturation::Boitier, ModeFacturation::courant());

        app(SecretsConfigurationService::class)->enregistrer(SecretsConfigurationService::MECEF_JETON, self::JETON, $this->compte('administrateur'));
        $service->enregistrer([ModeFacturation::CLE => 'emecef']);
        $this->assertSame(ModeFacturation::Emecef, ModeFacturation::courant());

        // Une valeur hors registre n'est jamais acceptée comme mode.
        $service->enregistrer([ModeFacturation::CLE => 'N-IMPORTE-QUOI']);
        $this->assertSame(ModeFacturation::Desactive, ModeFacturation::courant(), 'une valeur illisible retombe sur Désactivé');
    }

    #[Test]
    public function l_ifu_compte_treize_chiffres_et_l_adresse_exige_https(): void
    {
        $this->actingAs($this->compte('administrateur'));

        Livewire::test(Parametres::class)
            ->call('ouvrirEditionParametre', 'entreprise_ifu')
            ->set('valeurEditee', '12345')
            ->call('enregistrerParametre')
            ->assertHasErrors('valeurEditee')
            ->set('valeurEditee', self::IFU)
            ->call('enregistrerParametre')
            ->assertHasNoErrors();
        $this->assertSame(self::IFU, ParametreSysteme::where('cle', 'entreprise_ifu')->value('valeur'));

        Livewire::test(Parametres::class)
            ->call('ouvrirEditionParametre', ReglagesMecef::CLE_API_URL)
            ->set('valeurEditee', 'http://developper.impots.bj/sygmef-emcf/api')
            ->call('enregistrerParametre')
            ->assertHasErrors('valeurEditee')
            ->set('valeurEditee', 'https://developper.impots.bj/sygmef-emcf/api')
            ->call('enregistrerParametre')
            ->assertHasNoErrors();

        // Le service refuse aussi un IFU mal formé, sans passer par l'écran (poste, API).
        $this->expectException(RuntimeException::class);
        app(EnregistrerParametreService::class)->enregistrer(['entreprise_ifu' => 'ABC']);
    }

    #[Test]
    public function seul_un_administrateur_regle_le_mode_meme_avec_param_en_ecriture(): void
    {
        $gerant = $this->compte('gerant');
        app(RolePermissionService::class)->definirNiveau(Role::where('libelle', 'gerant')->firstOrFail(), 'PARAM', 'C');
        $this->actingAs($gerant->refresh());

        Livewire::test(Parametres::class)
            ->call('ouvrirEditionParametre', ModeFacturation::CLE)
            ->set('valeurEditee', 'desactive')
            ->call('enregistrerParametre')
            ->assertHasErrors('valeurEditee');

        $this->assertNull(ParametreSysteme::where('cle', ModeFacturation::CLE)->value('valeur'));
    }

    #[Test]
    public function le_jeton_est_chiffre_masque_jamais_rendu_ni_journalise(): void
    {
        $admin = $this->compte('administrateur');
        $this->actingAs($admin);

        $page = Livewire::test(Parametres::class)
            ->assertSee(__('pwa.parametres.mecef_jeton_absent'))
            ->assertDontSeeHtml('type="password"')
            ->call('ouvrirSaisieJetonMecef')
            ->assertSeeHtml('type="password"')
            ->set('jetonMecef', self::JETON)
            ->call('enregistrerJetonMecef')
            ->assertHasNoErrors()
            ->assertSet('jetonMecef', '')
            ->assertDontSee(self::JETON)
            ->assertSee('•••')
            ->assertSee(__('pwa.parametres.mecef_jeton_effacer'));

        // Chiffré en base ; relisible seulement par le service.
        $brut = (string) DB::table('secrets_configuration')->where('cle', SecretsConfigurationService::MECEF_JETON)->value('valeur');
        $this->assertStringNotContainsString(self::JETON, $brut);
        $this->assertSame(self::JETON, app(SecretsConfigurationService::class)->lire(SecretsConfigurationService::MECEF_JETON));
        $this->assertArrayNotHasKey('valeur', SecretConfiguration::where('cle', SecretsConfigurationService::MECEF_JETON)->firstOrFail()->toArray());

        // Le HTML complet ET l'état Livewire envoyé au navigateur ne le contiennent pas.
        $this->assertStringNotContainsString(self::JETON, $page->html());
        $this->assertStringNotContainsString(self::JETON, json_encode($page->snapshot, JSON_UNESCAPED_UNICODE) ?: '');
        $this->assertStringNotContainsString(self::JETON, $this->get(route('pwa.parametres'))->getContent());

        // L'API JSON des paramètres non plus.
        $this->actingAs($admin, 'sanctum');
        $this->assertStringNotContainsString(self::JETON, $this->getJson('/api/v1/parametres')->getContent());

        // Le journal d'audit : le geste, jamais la valeur.
        $tout = json_encode(JournalAudit::all()->toArray(), JSON_UNESCAPED_UNICODE) ?: '';
        $this->assertStringNotContainsString(self::JETON, $tout);
        $this->assertTrue(JournalAudit::where('action', TraceReglageFacturation::ACTION)->exists());
        $this->assertSame(
            ['geste' => 'jeton_enregistre'],
            JournalAudit::where('action', TraceReglageFacturation::ACTION)->firstOrFail()->valeur_apres,
        );
    }

    #[Test]
    public function une_forme_illisible_est_refusee_sans_etre_citee_et_effacer_demande_une_confirmation(): void
    {
        $admin = $this->compte('administrateur');
        $this->actingAs($admin);

        Livewire::test(Parametres::class)
            ->call('ouvrirSaisieJetonMecef')
            ->set('jetonMecef', 'ceci est un secret illisible')
            ->call('enregistrerJetonMecef')
            ->assertHasErrors('jetonMecef')
            ->assertDontSee('ceci est un secret illisible')
            ->set('jetonMecef', self::JETON)
            ->call('enregistrerJetonMecef')
            ->call('demanderEffacementJetonMecef')
            ->assertSet('confirmationEffacerJetonMecef', true)
            ->assertSee(__('pwa.parametres.mecef_jeton_effacer_titre'));
        $this->assertSame(1, SecretConfiguration::count(), 'rien n\'est effacé avant la confirmation');

        Livewire::test(Parametres::class)->call('effacerJetonMecef');
        $this->assertSame(0, SecretConfiguration::count());
        $this->assertTrue(JournalAudit::where('action', TraceReglageFacturation::ACTION)->get()
            ->contains(fn ($e) => ($e->valeur_apres['geste'] ?? null) === 'jeton_efface'));
    }

    #[Test]
    public function effacer_le_jeton_est_refuse_tant_que_le_mode_emecef_est_actif(): void
    {
        $admin = $this->compte('administrateur');
        $this->actingAs($admin);
        app(SecretsConfigurationService::class)->enregistrer(SecretsConfigurationService::MECEF_JETON, self::JETON, $admin);
        app(EnregistrerParametreService::class)->enregistrer([
            'entreprise_ifu' => self::IFU,
            ReglagesMecef::CLE_OPERATEUR_ID => 'R1',
            ReglagesMecef::CLE_OPERATEUR_NOM => 'Réception',
            ModeFacturation::CLE => 'emecef',
        ]);

        Livewire::test(Parametres::class)->call('effacerJetonMecef')->assertHasErrors('jetonMecef');
        $this->assertSame(1, SecretConfiguration::count());
    }

    #[Test]
    public function un_non_administrateur_ne_saisit_ni_ne_teste_le_jeton(): void
    {
        $gerant = $this->compte('gerant');
        app(RolePermissionService::class)->definirNiveau(Role::where('libelle', 'gerant')->firstOrFail(), 'PARAM', 'C');
        $this->actingAs($gerant->refresh());

        Livewire::test(Parametres::class)
            ->assertSee(__('pwa.parametres.mecef_jeton_reserve'))
            ->assertDontSeeHtml('wire:click="ouvrirSaisieJetonMecef"')
            ->call('ouvrirSaisieJetonMecef')
            ->assertForbidden();
        Livewire::test(Parametres::class)
            ->set('jetonMecef', self::JETON)
            ->call('enregistrerJetonMecef')
            ->assertForbidden();
        Livewire::test(Parametres::class)->call('testerConnexionMecef')->assertForbidden();
        $this->assertSame(0, SecretConfiguration::count());
    }

    #[Test]
    public function tester_la_connexion_appelle_status_avec_le_jeton_et_ne_l_affiche_jamais(): void
    {
        $admin = $this->compte('administrateur');
        $this->actingAs($admin);
        app(SecretsConfigurationService::class)->enregistrer(SecretsConfigurationService::MECEF_JETON, self::JETON, $admin);

        Http::fake([
            'developper.impots.bj/*' => Http::response(['status' => true, 'ifu' => self::IFU, 'tokenValid' => true], 200),
        ]);

        Livewire::test(Parametres::class)
            ->call('testerConnexionMecef')
            ->assertSee(__('parametres.mecef_test_ok'))
            ->assertDontSee(self::JETON);

        Http::assertSent(fn ($requete) => $requete->url() === ReglagesMecef::URL_API_PAR_DEFAUT . '/info/status'
            && $requete->hasHeader('Authorization', 'Bearer ' . self::JETON));

        foreach ([
            [401, 'mecef_test_jeton_refuse'],
            [403, 'mecef_test_jeton_refuse'],
            [429, 'mecef_test_limite'],
            [500, null],
        ] as [$code, $cle]) {
            Http::swap(new \Illuminate\Http\Client\Factory());
            Http::fake(['developper.impots.bj/*' => Http::response(['message' => self::JETON], $code)]);
            Livewire::test(Parametres::class)
                ->call('testerConnexionMecef')
                ->assertDontSee(self::JETON)
                ->assertSee($cle === null ? (string) $code : __('parametres.' . $cle));
        }

        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::fake(['developper.impots.bj/*' => fn () => throw new \Illuminate\Http\Client\ConnectionException('cURL error 6')]);
        Livewire::test(Parametres::class)->call('testerConnexionMecef')->assertSee(__('parametres.mecef_test_injoignable'));

        app(EnregistrerParametreService::class)->enregistrer(['entreprise_ifu' => self::IFU]);
        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::fake(['developper.impots.bj/*' => Http::response(['status' => true, 'ifu' => '9999999999999', 'tokenValid' => true], 200)]);
        Livewire::test(Parametres::class)->call('testerConnexionMecef')->assertSee('9999999999999');
    }

    #[Test]
    public function la_descente_vers_les_postes_ne_contient_jamais_le_jeton_et_porte_le_mode(): void
    {
        $admin = $this->compte('administrateur');
        $this->actingAs($admin);
        app(SecretsConfigurationService::class)->enregistrer(SecretsConfigurationService::MECEF_JETON, self::JETON, $admin);
        app(EnregistrerParametreService::class)->enregistrer([
            'entreprise_ifu' => self::IFU,
            ReglagesMecef::CLE_OPERATEUR_ID => 'R1',
            ReglagesMecef::CLE_OPERATEUR_NOM => 'Réception',
            ModeFacturation::CLE => 'boitier',
        ]);

        // Le flux ne livre que ce qui est plus vieux que l'horizon de sécurité du curseur.
        $this->travel(10)->seconds();
        \Laravel\Sanctum\Sanctum::actingAs($admin);
        $elements = [];
        $curseur = null;
        $corps = '';

        do {
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $corps .= $reponse->getContent();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        $this->assertStringNotContainsString(self::JETON, $corps);
        $this->assertStringNotContainsString(SecretsConfigurationService::MECEF_JETON, $corps, 'même la CLÉ du secret ne descend pas');

        $parametres = collect($elements)
            ->where('table', 'parametres_systeme')
            ->mapWithKeys(fn ($e) => [$e['donnees']['cle'] => $e['donnees']['valeur']]);
        $this->assertSame('boitier', $parametres[ModeFacturation::CLE] ?? null, 'le mode descend, en lecture');
        $this->assertSame(self::IFU, $parametres['entreprise_ifu'] ?? null);
    }

    #[Test]
    public function un_poste_ne_peut_pas_ecrire_le_mode_par_la_synchronisation(): void
    {
        $this->actingAs($this->compte('administrateur'));
        app(EnregistrerParametreService::class)->enregistrer(['entreprise_ifu' => self::IFU]);

        $gestionnaire = app(\App\Shared\Sync\Gestionnaires\GestionnaireParametres::class);
        $contexte = new \App\Shared\Sync\Support\ContexteSynchronisation(
            'poste-b',
            $this->compte('administrateur'),
            \Illuminate\Support\Carbon::now()->subSeconds(5),
            \Illuminate\Support\Carbon::now(),
        );
        $resultat = $gestionnaire->creer((string) \Illuminate\Support\Str::uuid(), ['valeurs' => [ModeFacturation::CLE => 'boitier', 'tolerance_reception_pct' => '4']], $contexte);

        $this->assertContains(ModeFacturation::CLE, $resultat->complements['cles_conservees']);
        $this->assertNull(ParametreSysteme::where('cle', ModeFacturation::CLE)->value('valeur'));
        $this->assertSame('4', ParametreSysteme::where('cle', 'tolerance_reception_pct')->value('valeur'));
    }

    #[Test]
    public function le_code_de_la_descente_ne_lit_jamais_les_secrets(): void
    {
        // Une garde LUE : la descente et le catalogue ne citent ni la table des
        // secrets, ni son service, ni la clé du jeton.
        $racine = dirname(__DIR__, 3) . '/app/Shared/Sync';
        $fichiers = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS));
        $lus = 0;

        foreach ($fichiers as $fichier) {
            if ($fichier->getExtension() !== 'php') {
                continue;
            }
            $lus++;
            $source = (string) file_get_contents($fichier->getPathname());
            foreach (['secrets_configuration', 'SecretsConfigurationService', 'SecretConfiguration', 'mecef_jeton'] as $interdit) {
                $this->assertStringNotContainsString($interdit, $source, basename($fichier->getPathname()) . " cite « $interdit »");
            }
        }

        $this->assertGreaterThan(20, $lus, 'le balayage doit lire les fichiers de la synchronisation');
    }

    private function compte(string $role): User
    {
        return User::firstOrCreate(['login' => 'compte.' . $role], [
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
