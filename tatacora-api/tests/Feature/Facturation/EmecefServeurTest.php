<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Jobs\RejouerCertificationsMecefEnEchecJob;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Domain\Facturation\Models\Paiement;
use App\Domain\Facturation\Providers\MecefServiceProvider;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Facturation\Services\MecefClientEmecef;
use App\Domain\Facturation\Services\MecefClientFake;
use App\Domain\Facturation\Services\MecefClientInterface;
use App\Domain\Facturation\Services\MecefClientRefus;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\ReglagesMecef;
use App\Domain\Facturation\Services\StatutNormalisation;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use App\Shared\Secrets\Services\SecretsConfigurationService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Factory;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Lot 3 : le client e-MECeF contre un FAUX serveur de la DGI (`Http::fake`) —
 * création puis confirmation, expiration, 401, 429, erreurs classées, idempotence,
 * avoir, choix de l'implémentation par le MODE, jeton jamais divulgué.
 *
 * Le jeton ci-dessous est FICTIF.
 */
final class EmecefServeurTest extends TestCase
{
    use RefreshDatabase;

    private const JETON = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0LW5vbi1yZWVsIn0.c2lnbmF0dXJlLW5vbi1yZWVsbGU';

    private const BASE = 'https://developper.impots.bj/sygmef-emcf/api';

    private const IFU = '0202011344660';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->travelTo('2026-11-07 10:00:00');
        $admin = User::create([
            'login' => 'admin.essai', 'mot_de_passe_hash' => Hash::make('x'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id, 'statut' => 'actif',
        ]);
        $this->actingAs($admin);
        $this->configurer('emecef');
        app(SecretsConfigurationService::class)->enregistrer(SecretsConfigurationService::MECEF_JETON, self::JETON, $admin);
        Http::preventStrayRequests();
    }

    private function configurer(string $mode, bool $tva = false): void
    {
        foreach ([
            'entreprise_ifu' => self::IFU,
            ReglagesMecef::CLE_OPERATEUR_ID => 'RECEPTION01',
            ReglagesMecef::CLE_OPERATEUR_NOM => 'Réception',
            ModeFacturation::CLE => $mode,
            'tva_active' => $tva ? 'true' : 'false',
            'taux_tva' => '18',
            'convention_prix' => 'ttc',
        ] as $cle => $valeur) {
            ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
        }
    }

    /** Une facture de 10 000 FCFA (2 × 5 000), sans TVA. */
    private function facture(int $unitaire = 5000, int $quantite = 2, string $libelle = 'Nuitée chambre 3'): Facture
    {
        $facture = Facture::create([
            'client_id' => Client::factory()->create()->id,
            'date_emission' => '2026-11-07',
            'montant_ht' => (string) ($unitaire * $quantite) . '.00', 'montant_tva' => '0.00', 'montant_ttc' => (string) ($unitaire * $quantite) . '.00',
            'statut' => 'en_attente_certification',
        ]);
        LigneFacture::create([
            'facture_id' => $facture->id, 'source_module' => 'M1', 'source_id' => $facture->id,
            'libelle' => $libelle, 'quantite' => $quantite, 'prix_unitaire' => $unitaire . '.00',
            'prix_catalogue' => $unitaire . '.00', 'montant' => ($unitaire * $quantite) . '.00',
        ]);

        return $facture->refresh();
    }

    /** @return array<string, mixed> */
    private function confirmation(string $nim = 'ED04000999', string $compteur = '12/45 FV', string $code = 'ABCD-EFGH-IJKL-MNOP-QRST-UVWX'): array
    {
        return [
            'codeMECeFDGI' => $code,
            'qrCode' => "F;{$nim};{$code};" . self::IFU . ';20261107100000',
            'dateTime' => '2026-11-07T10:00:03+01:00',
            'counters' => $compteur,
            'nim' => $nim,
        ];
    }

    /**
     * Pose les réponses du FAUX serveur de la DGI. `Http::fake` EMPILE les stubs (le premier qui
     * correspond gagne) : chaque jeu de réponses repart donc d'une fabrique NEUVE.
     *
     * @param  array<string, mixed>  $reponses
     */
    private function faux(array $reponses): void
    {
        Http::swap(new Factory());
        Http::preventStrayRequests();
        Http::fake($reponses);
    }

    private function emission(): EmissionFactureService
    {
        // Un conteneur NEUF : le client est choisi par le MODE à chaque résolution.
        return app()->make(EmissionFactureService::class);
    }

    #[Test]
    public function creation_puis_confirmation_dans_la_foulee_et_la_facture_est_normalisee(): void
    {
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-1', 'total' => 10000], 200),
            self::BASE . '/invoice/uid-1/confirm' => Http::response($this->confirmation(), 200),
        ]);

        $facture = $this->emission()->certifier($this->facture());

        $this->assertTrue($facture->estNormalisee());
        $this->assertSame('ED04000999-12', $facture->numero_mecef);
        $this->assertSame('ABCD-EFGH-IJKL-MNOP-QRST-UVWX', $facture->code_mecef);
        $this->assertStringStartsWith('F;ED04000999;', (string) $facture->qr_code_fiscal);
        $this->assertSame('12', $facture->normalisation_compteur);
        $this->assertSame('emecef', $facture->normalisation_mode);
        $this->assertSame('certifiee', $facture->statut);
        $this->assertNull($facture->emecef_uid);
        $this->assertNull($facture->normalisation_motif);

        // Deux appels, dans cet ordre, avec le jeton en Bearer — et nulle part ailleurs.
        Http::assertSentCount(2);
        $envois = Http::recorded();
        /** @var Request $creation */
        $creation = $envois[0][0];
        $this->assertSame('POST', $creation->method());
        $this->assertSame(self::BASE . '/invoice', $creation->url());
        $this->assertSame('Bearer ' . self::JETON, $creation->header('Authorization')[0]);
        $corps = $creation->data();
        $this->assertSame(self::IFU, $corps['ifu']);
        $this->assertSame('FV', $corps['type']);
        $this->assertSame(['id' => 'RECEPTION01', 'name' => 'Réception'], $corps['operator']);
        $this->assertSame([['name' => 'Nuitée chambre 3', 'price' => 5000, 'quantity' => 2, 'taxGroup' => 'A']], $corps['items']);
        $this->assertSame([['name' => 'CREDIT', 'amount' => 10000]], $corps['payment'], 'rien d\'encaissé : le tout en crédit');
        $this->assertArrayNotHasKey('reference', $corps);
        $this->assertStringNotContainsString(self::JETON, json_encode($corps, JSON_UNESCAPED_UNICODE) ?: '');
        $this->assertSame('PUT', $envois[1][0]->method());
        $this->assertSame(self::BASE . '/invoice/uid-1/confirm', $envois[1][0]->url());
    }

    #[Test]
    public function les_reglements_actifs_partent_par_mode_et_le_reste_du_en_credit(): void
    {
        $facture = $this->facture(5000, 2);
        $session = \App\Domain\Caisse\Models\SessionCaisse::create([
            'point_vente' => 'bar', 'montant_fond' => '10000.00', 'date_ouverture' => now(), 'utilisateur_ouverture_id' => auth()->id(),
        ]);
        foreach ([['especes', '4000.00', 'actif'], ['mobile_money', '3000.00', 'actif'], ['carte', '1000.00', 'annule']] as [$mode, $montant, $statut]) {
            Paiement::create([
                'facture_id' => $facture->id, 'session_id' => $session->id, 'mode_paiement' => $mode, 'montant' => $montant,
                'date_paiement' => now(), 'statut' => $statut,
                ...($statut === 'annule' ? ['motif_annulation' => 'Erreur', 'annule_par_id' => auth()->id(), 'date_annulation' => now()] : []),
            ]);
        }
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-p'], 200),
            self::BASE . '/invoice/uid-p/confirm' => Http::response($this->confirmation(), 200),
        ]);

        $this->emission()->certifier($facture);

        $envois = Http::recorded();
        $this->assertSame([
            ['name' => 'ESPECES', 'amount' => 4000],
            ['name' => 'MOBILEMONEY', 'amount' => 3000],
            ['name' => 'CREDIT', 'amount' => 3000],
        ], $envois[0][0]->data()['payment']);
    }

    #[Test]
    public function avec_la_tva_les_articles_partent_en_ttc_et_la_taxe_de_sejour_en_groupe_f(): void
    {
        $this->configurer('emecef', tva: true);
        // HT 5 000 → TTC 5 900 à 18 %.
        $facture = Facture::create([
            'client_id' => Client::factory()->create()->id, 'date_emission' => '2026-11-07',
            'montant_ht' => '10000.00', 'montant_tva' => '1800.00', 'montant_ttc' => '11800.00', 'statut' => 'en_attente_certification',
        ]);
        foreach ([['Nuitée chambre 3', '5000.00'], ['Taxe de séjour (2 nuits)', '5000.00']] as [$libelle, $prix]) {
            LigneFacture::create([
                'facture_id' => $facture->id, 'source_module' => 'M1', 'source_id' => $facture->id, 'libelle' => $libelle,
                'quantite' => 1, 'prix_unitaire' => $prix, 'prix_catalogue' => $prix, 'montant' => $prix,
            ]);
        }
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-t'], 200),
            self::BASE . '/invoice/uid-t/confirm' => Http::response($this->confirmation(), 200),
        ]);

        $this->emission()->certifier($facture->refresh());

        $articles = Http::recorded()[0][0]->data()['items'];
        $this->assertSame(5900, $articles[0]['price']);
        $this->assertSame('B', $articles[0]['taxGroup']);
        $this->assertSame('TAXE DE SEJOUR', $articles[1]['name']);
        $this->assertSame('F', $articles[1]['taxGroup']);
    }

    #[Test]
    public function une_facture_deja_normalisee_n_est_jamais_retransmise(): void
    {
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-1'], 200),
            self::BASE . '/invoice/uid-1/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $facture = $this->emission()->certifier($this->facture());
        Http::assertSentCount(2);

        $this->emission()->certifier($facture);
        $this->emission()->certifier($facture->refresh());
        (new RejouerCertificationsMecefEnEchecJob())->handle($this->emission());

        Http::assertSentCount(2);
        $this->assertSame('ED04000999-12', $facture->refresh()->numero_mecef);
    }

    #[Test]
    public function le_uid_non_confirme_est_conserve_et_confirme_seul_au_rejeu(): void
    {
        // Création réussie, confirmation refusée par la limite de débit : le uid reste.
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-2'], 200),
            self::BASE . '/invoice/uid-2/confirm' => Http::response([], 429, ['Retry-After' => '5']),
        ]);
        $facture = $this->emission()->certifier($this->facture());
        $this->assertSame('uid-2', $facture->emecef_uid);
        $this->assertSame('en_attente', $facture->normalisation_statut);

        $this->travel(10)->seconds();
        $this->faux([self::BASE . '/invoice/uid-2/confirm' => Http::response($this->confirmation(), 200)]);
        $facture = $this->emission()->certifier($facture->refresh());

        $this->assertTrue($facture->estNormalisee());
        Http::assertNotSent(fn (Request $r) => $r->method() === 'POST', 'le rejeu CONFIRME le uid conservé, il ne recrée rien');
        Http::assertSent(fn (Request $r) => $r->url() === self::BASE . '/invoice/uid-2/confirm');
    }

    #[Test]
    public function un_uid_expire_est_recree_une_fois(): void
    {
        $facture = $this->facture();
        $facture->update(['emecef_uid' => 'uid-vieux', 'emecef_uid_le' => now()->subSeconds(60)]);
        $this->faux([
            self::BASE . '/invoice/uid-vieux/confirm' => Http::response([], 404),
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-neuf'], 200),
            self::BASE . '/invoice/uid-neuf/confirm' => Http::response($this->confirmation(), 200),
        ]);

        $facture = $this->emission()->certifier($facture->refresh());

        $this->assertTrue($facture->estNormalisee());
        $urls = collect(Http::recorded())->map(fn ($e) => $e[0]->method() . ' ' . $e[0]->url())->all();
        $this->assertSame([
            'PUT ' . self::BASE . '/invoice/uid-vieux/confirm',
            'POST ' . self::BASE . '/invoice',
            'PUT ' . self::BASE . '/invoice/uid-neuf/confirm',
        ], $urls);

        // Un uid plus vieux que 100 s n'est même pas tenté.
        $autre = $this->facture();
        $autre->update(['emecef_uid' => 'uid-perime', 'emecef_uid_le' => now()->subSeconds(200)]);
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-n2'], 200),
            self::BASE . '/invoice/uid-n2/confirm' => Http::response($this->confirmation('ED04000999', '13/46 FV', 'ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ'), 200),
        ]);
        $this->emission()->certifier($autre->refresh());
        Http::assertNotSent(fn (Request $r) => str_contains($r->url(), 'uid-perime'));
    }

    #[Test]
    public function jeton_refuse_401_403_en_attente_avec_motif_sans_secret_et_delai_de_quinze_minutes(): void
    {
        foreach ([401, 403] as $code) {
            $this->faux([self::BASE . '/invoice' => Http::response(['message' => self::JETON], $code)]);
            $facture = $this->emission()->certifier($this->facture());

            $this->assertSame('en_attente', $facture->normalisation_statut);
            $this->assertSame('echec_certification', $facture->statut);
            $this->assertSame(__('facturation.emecef.jeton_refuse'), $facture->normalisation_motif);
            $this->assertStringNotContainsString(self::JETON, (string) $facture->normalisation_motif);
            $this->assertEqualsWithDelta(now()->addSeconds(900)->timestamp, $facture->emecef_prochain_essai_le?->timestamp, 5);
            $this->assertNull($facture->numero_mecef);
            $this->assertFalse($facture->estNormalisee());
        }
    }

    #[Test]
    public function limite_429_respecte_retry_after_et_le_job_n_insiste_pas_avant_l_heure(): void
    {
        $this->faux([self::BASE . '/invoice' => Http::response([], 429, ['Retry-After' => '90'])]);
        $facture = $this->emission()->certifier($this->facture());

        $this->assertSame('en_attente', $facture->normalisation_statut);
        $this->assertSame(__('facturation.emecef.limite', ['secondes' => 90]), $facture->normalisation_motif);
        $this->assertEqualsWithDelta(now()->addSeconds(90)->timestamp, $facture->emecef_prochain_essai_le?->timestamp, 3);

        // Avant l'heure : le job ne fait AUCUNE requête.
        Http::assertSentCount(1);
        $bilan = (new RejouerCertificationsMecefEnEchecJob())->handle($this->emission());
        $this->assertSame(0, $bilan['tentees']);
        Http::assertSentCount(1);

        // Après l'heure : il rejoue.
        $this->travel(95)->seconds();
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-r'], 200),
            self::BASE . '/invoice/uid-r/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $bilan = (new RejouerCertificationsMecefEnEchecJob())->handle($this->emission());
        $this->assertSame(1, $bilan['certifiees']);
        $this->assertTrue($facture->refresh()->estNormalisee());
    }

    #[Test]
    public function reseau_et_erreur_serveur_a_la_creation_laissent_en_attente_et_rejouable(): void
    {
        $this->faux([self::BASE . '/invoice' => fn () => throw new ConnectionException('cURL error 28: timeout')]);
        $facture = $this->emission()->certifier($this->facture());
        $this->assertSame('en_attente', $facture->normalisation_statut);
        $this->assertSame(__('facturation.emecef.injoignable'), $facture->normalisation_motif);
        $this->assertTrue(StatutNormalisation::EnAttente->rejouable());

        $autre = $this->facture();
        $this->faux([self::BASE . '/invoice' => Http::response('boum', 503)]);
        $autre = $this->emission()->certifier($autre);
        $this->assertSame(__('facturation.emecef.erreur_serveur', ['code' => 503]), $autre->normalisation_motif);
        $this->assertSame('en_attente', $autre->normalisation_statut);
    }

    #[Test]
    public function un_refus_de_la_dgi_est_une_facture_refusee_avec_sa_description(): void
    {
        $this->faux([self::BASE . '/invoice' => Http::response(['errorCode' => '2', 'errorDesc' => 'IFU du client invalide'], 400)]);
        $facture = $this->emission()->certifier($this->facture());

        $this->assertSame('refusee', $facture->normalisation_statut);
        $this->assertSame(__('facturation.emecef.refus', ['detail' => 'IFU du client invalide']), $facture->normalisation_motif);

        // Une erreur renvoyée en 200 avec errorCode : même chose.
        $this->faux([self::BASE . '/invoice' => Http::response(['errorCode' => '9', 'errorDesc' => 'Taxe inconnue'], 200)]);
        $autre = $this->emission()->certifier($this->facture());
        $this->assertSame('refusee', $autre->normalisation_statut);
    }

    #[Test]
    public function une_confirmation_sans_reponse_exploitable_est_a_verifier_et_jamais_rejouee(): void
    {
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-x'], 200),
            self::BASE . '/invoice/uid-x/confirm' => fn () => throw new ConnectionException('reset'),
        ]);
        $facture = $this->emission()->certifier($this->facture());
        $this->assertSame('a_verifier', $facture->normalisation_statut);
        $this->assertSame(__('facturation.emecef.reponse_invalide_apres_confirmation'), $facture->normalisation_motif);

        // Réponse 200 sans code ni QR : même issue.
        $autre = $this->facture();
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-y'], 200),
            self::BASE . '/invoice/uid-y/confirm' => Http::response(['nim' => 'ED04000999'], 200),
        ]);
        $this->assertSame('a_verifier', $this->emission()->certifier($autre)->normalisation_statut);

        // Le job ne les reprend JAMAIS.
        $avant = collect(Http::recorded())->count();
        $bilan = (new RejouerCertificationsMecefEnEchecJob())->handle($this->emission());
        $this->assertSame(0, $bilan['tentees']);
        $this->assertCount($avant, Http::recorded());
    }

    #[Test]
    public function le_jeton_n_est_ni_journalise_ni_cite_dans_aucune_phrase_d_erreur(): void
    {
        Log::spy();
        $messages = [];

        foreach ([401, 429, 500, 400] as $code) {
            $this->faux([self::BASE . '/invoice' => Http::response(['message' => self::JETON, 'errorDesc' => 'refus'], $code, ['Retry-After' => '30'])]);
            $messages[] = (string) $this->emission()->certifier($this->facture())->normalisation_motif;
        }

        foreach ($messages as $message) {
            $this->assertStringNotContainsString(self::JETON, $message);
            $this->assertStringNotContainsString('Bearer', $message);
        }

        Log::shouldNotHaveReceived('error');
        Log::shouldNotHaveReceived('warning', fn ($m, $contexte = []) => str_contains($m . json_encode($contexte), self::JETON));
        $this->assertStringNotContainsString(self::JETON, json_encode(\App\Shared\Audit\Models\JournalAudit::all()->toArray(), JSON_UNESCAPED_UNICODE) ?: '');
    }

    #[Test]
    public function le_mode_choisit_l_implementation_et_une_configuration_incomplete_refuse_en_clair(): void
    {
        $this->configurer('desactive');
        $this->assertInstanceOf(MecefClientFake::class, app()->make(MecefClientInterface::class));

        $this->configurer('boitier');
        $this->assertInstanceOf(MecefClientFake::class, app()->make(MecefClientInterface::class), 'le serveur ne certifie pas : jamais le client réel');

        $this->configurer('emecef');
        $client = app()->make(MecefClientInterface::class);
        $this->assertInstanceOf(MecefClientEmecef::class, $client);
        $this->assertTrue($client->estModeReel());
        $this->assertSame('emecef_actif', MecefServiceProvider::etatConfiguration());

    }

    #[Test]
    public function sans_jeton_en_mode_e_mecef_refus_clair_sans_requete_et_sans_repli_sur_la_demo(): void
    {
        // Le jeton ne s'efface pas sous le mode e-MECeF : on le retire en base (panne, `APP_KEY` changée).
        \Illuminate\Support\Facades\DB::table('secrets_configuration')->delete();

        $this->assertInstanceOf(MecefClientRefus::class, app()->make(MecefClientInterface::class));
        $this->assertSame('emecef_incomplet', MecefServiceProvider::etatConfiguration());

        $facture = $this->emission()->certifier($this->facture());

        $this->assertSame('en_attente', $facture->normalisation_statut);
        $this->assertStringContainsString(__('parametres.mecef_manque_jeton'), (string) $facture->normalisation_motif);
        $this->assertStringContainsString('Facturation e-MECeF incomplète', (string) $facture->normalisation_motif);
        $this->assertNull($facture->numero_mecef, 'jamais un numéro de démonstration');
        Http::assertNothingSent();
    }

    #[Test]
    public function en_mode_boitier_le_serveur_ne_certifie_pas_et_ne_fait_aucune_requete(): void
    {
        $this->configurer('boitier');
        $facture = $this->emission()->certifier($this->facture());

        $this->assertSame('en_attente', $facture->normalisation_statut);
        $this->assertSame('boitier', $facture->normalisation_mode);
        $this->assertSame(__('facturation.emecef.attente_poste'), $facture->normalisation_motif);
        $this->assertNull($facture->numero_mecef);
        $this->assertSame('en_attente_certification', $facture->statut, 'jamais figée tant que le poste n\'a pas normalisé');
        Http::assertNothingSent();

        $bilan = (new RejouerCertificationsMecefEnEchecJob())->handle($this->emission());
        $this->assertSame(0, $bilan['tentees'], 'le job ne certifie pas non plus : le poste reprend à son passage');
        Http::assertNothingSent();

        // Un poste qui a dit « refusée » n'est pas écrasé par « en attente du poste ».
        $facture->update(['normalisation_statut' => 'refusee', 'normalisation_motif' => 'Refusée par le boîtier']);
        $this->emission()->certifier($facture->refresh());
        $this->assertSame('refusee', $facture->refresh()->normalisation_statut);
    }

    #[Test]
    public function en_mode_desactive_la_demonstration_reste_et_aucune_requete_ne_part(): void
    {
        $this->configurer('desactive');
        $facture = $this->emission()->certifier($this->facture());

        $this->assertStringStartsWith('MECEF-DEMO-', (string) $facture->numero_mecef);
        $this->assertNull($facture->normalisation_statut);
        $this->assertFalse($facture->estNormalisee());
        Http::assertNothingSent();
    }

    #[Test]
    public function une_demonstration_est_remplacee_par_la_vraie_normalisation_quand_un_mode_reel_est_choisi(): void
    {
        $this->configurer('desactive');
        $facture = $this->emission()->certifier($this->facture());
        $this->assertStringStartsWith('MECEF-DEMO-', (string) $facture->numero_mecef);

        $this->configurer('emecef');
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-d'], 200),
            self::BASE . '/invoice/uid-d/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $facture = $this->emission()->certifier($facture->refresh());

        $this->assertTrue($facture->estNormalisee());
        $this->assertSame('ED04000999-12', $facture->numero_mecef);
    }

    #[Test]
    public function l_avoir_d_une_facture_normalisee_passe_par_la_dgi_avec_le_code_de_l_origine(): void
    {
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-f'], 200),
            self::BASE . '/invoice/uid-f/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $facture = $this->emission()->certifier($this->facture());
        $this->assertTrue($facture->estNormalisee());

        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-a'], 200),
            self::BASE . '/invoice/uid-a/confirm' => Http::response($this->confirmation('ED04000999', '2/3 FA', 'AVOIR-CODE-AVOIR-CODE-AVOIR-1'), 200),
        ]);
        $avoir = $this->emission()->emettreAvoir($facture, '10000.00', 'Erreur de saisie');

        $this->assertSame('normalisee', $avoir->normalisation_statut);
        $this->assertSame('ED04000999-2', $avoir->numero_mecef);
        $this->assertSame('AVOIR-CODE-AVOIR-CODE-AVOIR-1', $avoir->code_mecef);

        $creationAvoir = collect(Http::recorded())->map(fn ($e) => $e[0])->first(fn (Request $r) => $r->method() === 'POST' && ($r->data()['type'] ?? '') === 'FA');
        $this->assertNotNull($creationAvoir);
        $this->assertSame('ABCD-EFGH-IJKL-MNOP-QRST-UVWX', $creationAvoir->data()['reference'], 'référence = code MECeF de la facture d\'origine');
        $this->assertSame([['name' => 'Nuitée chambre 3', 'price' => 5000, 'quantity' => 2, 'taxGroup' => 'A']], $creationAvoir->data()['items']);

        // La facture d'origine n'a pas bougé (RG-03).
        $this->assertSame('ED04000999-12', $facture->refresh()->numero_mecef);
    }

    #[Test]
    public function un_avoir_partiel_part_en_une_ligne_et_celui_d_une_facture_non_normalisee_n_a_rien_a_normaliser(): void
    {
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-f'], 200),
            self::BASE . '/invoice/uid-f/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $facture = $this->emission()->certifier($this->facture());
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-p'], 200),
            self::BASE . '/invoice/uid-p/confirm' => Http::response($this->confirmation('ED04000999', '5/6 FA', 'PART-CODE-PART-CODE-PART-CODE'), 200),
        ]);
        $this->emission()->emettreAvoir($facture, '3000.00', 'Geste commercial');
        $creation = collect(Http::recorded())->map(fn ($e) => $e[0])->last(fn (Request $r) => $r->method() === 'POST');
        $this->assertSame(3000, $creation->data()['items'][0]['price']);
        $this->assertSame(1, $creation->data()['items'][0]['quantity']);

        // Une facture NON normalisée : son avoir n'est pas normalisé, aucune requête.
        $this->faux([]);
        $this->configurer('desactive');
        $simple = $this->emission()->certifier($this->facture());
        $this->configurer('emecef');
        $avoir = $this->emission()->emettreAvoir($simple->refresh(), '1000.00', 'Test');
        $this->assertNull($avoir->normalisation_statut);
        Http::assertNothingSent();
    }

    #[Test]
    public function en_mode_boitier_l_avoir_d_une_facture_normalisee_attend_le_poste(): void
    {
        $facture = $this->facture();
        $facture->update([
            'numero_mecef' => 'ED04000623-41', 'qr_code_fiscal' => 'F;ED04000623;ABC;' . self::IFU . ';20261107100000',
            'normalisation_statut' => 'normalisee', 'normalisation_mode' => 'boitier', 'statut' => 'certifiee',
        ]);
        $this->configurer('boitier');

        $avoir = $this->emission()->emettreAvoir($facture->refresh(), '2000.00', 'Erreur');

        $this->assertSame('en_attente', $avoir->normalisation_statut);
        $this->assertSame('boitier', $avoir->normalisation_mode);
        $this->assertInstanceOf(Avoir::class, $avoir);
        Http::assertNothingSent();
    }

    #[Test]
    public function totaux_incoherents_refus_avant_tout_envoi(): void
    {
        $facture = $this->facture();
        $facture->update(['montant_ttc' => '12000.00']);

        $resultat = $this->emission()->certifier($facture->refresh());

        $this->assertSame('en_attente', $resultat->normalisation_statut, 'corrigible : la DGI n\'a rien vu');
        $this->assertStringContainsString('ne concordent pas', (string) $resultat->normalisation_motif);
        $this->assertStringNotContainsString('La DGI a refusé', (string) $resultat->normalisation_motif);
        Http::assertNothingSent();
    }

    private function documentDe(Facture $facture): string
    {
        $facture->loadMissing(['lignes', 'avoirs', 'paiements']);

        return view('pdf.facture-mecef', [
            'facture' => $facture,
            'client' => Client::query()->find($facture->client_id),
            'activites' => \App\Pwa\Livewire\Facturation\Facturation::ACTIVITES,
            'modesPaiement' => \App\Domain\Ventes\Services\VenteService::MODES_PAIEMENT,
            'totalAvoirs' => '0.00',
            'net' => (string) $facture->montant_ttc,
            'resteDu' => $facture->resteDu(),
            'auteur' => 'compte.test',
            'entete' => app(\App\Shared\ReportEngine\Services\ReportHeaderService::class)->genererEnTete(
                typeRapport: (string) __('facturation_pwa.document_titre'),
                periode: '',
                auteur: null,
            ),
        ])->render();
    }

    #[Test]
    public function le_document_a4_ne_porte_les_mentions_fiscales_que_pour_une_facture_reellement_normalisee(): void
    {
        $this->faux([
            self::BASE . '/invoice' => Http::response(['uid' => 'uid-1'], 200),
            self::BASE . '/invoice/uid-1/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $normalisee = $this->emission()->certifier($this->facture());
        $html = $this->documentDe($normalisee);

        $this->assertStringContainsString('Facture normalisée MECeF', $html);
        $this->assertStringContainsString('ED04000999-12', $html);
        $this->assertStringContainsString('ABCD-EFGH-IJKL-MNOP-QRST-UVWX', $html);
        $this->assertStringContainsString('F;ED04000999;', $html);
        $this->assertStringNotContainsString('en attente d\'inscription', $html);

        // En attente (jeton refusé) : l'état et le motif, aucune mention fiscale.
        $this->faux([self::BASE . '/invoice' => Http::response([], 401)]);
        $attente = $this->emission()->certifier($this->facture());
        $htmlAttente = $this->documentDe($attente);
        $this->assertStringNotContainsString('Facture normalisée MECeF', $htmlAttente);
        $this->assertStringContainsString('Normalisation : En attente de normalisation', $htmlAttente);
        $this->assertStringContainsString('a refusé le jeton', $htmlAttente);
        $this->assertStringNotContainsString(self::JETON, $htmlAttente);

        // Une démonstration : aucune mention fiscale non plus.
        $this->configurer('desactive');
        $demo = $this->emission()->certifier($this->facture());
        $htmlDemo = $this->documentDe($demo);
        $this->assertStringNotContainsString('Facture normalisée MECeF', $htmlDemo);
        $this->assertStringNotContainsString('MECEF-DEMO-', $htmlDemo, 'un numéro de démonstration n\'apparaît jamais');
    }

    #[Test]
    public function le_serveur_utilise_les_fabriques_http_du_conteneur_sans_requete_reelle(): void
    {
        // Garde du faux serveur : `preventStrayRequests` est actif, donc une requête non
        // simulée ferait échouer ce test — la preuve que rien ne sort vers la vraie DGI.
        $this->assertInstanceOf(Factory::class, Http::getFacadeRoot());
    }
}
