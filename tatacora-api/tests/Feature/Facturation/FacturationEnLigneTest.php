<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Jobs\RejouerCertificationsMecefEnEchecJob;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use App\Shared\Secrets\Services\SecretsConfigurationService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Factory;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Décisions du PO du 07/11/2026 : l'avoir EN LIGNE (créé au serveur, identifiant serveur), la
 * demande IMMÉDIATE de normalisation e-MECeF depuis un poste, l'IFU du client, et le rejeu qui
 * ne reprend que ce qu'un bouton a demandé. Les jetons d'appairage sont RÉELS (`createToken`),
 * le serveur de la DGI est FAUX (`Http::fake`), le jeton e-MECeF est FICTIF.
 */
final class FacturationEnLigneTest extends TestCase
{
    use RefreshDatabase;

    private const JETON = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0LW5vbi1yZWVsIn0.c2lnbmF0dXJlLW5vbi1yZWVsbGU';

    private const BASE = 'https://developper.impots.bj/sygmef-emcf/api';

    private const IFU = '0202011344660';

    private const QR = 'F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;0202011344660;20261107100000';

    private User $receptionniste;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->travelTo('2026-11-07 10:00:00');
        $this->receptionniste = $this->utilisateur('receptionniste');
        $admin = $this->admin = $this->utilisateur('administrateur');
        $this->configurer('emecef');
        app(SecretsConfigurationService::class)->enregistrer(SecretsConfigurationService::MECEF_JETON, self::JETON, $admin);
        Http::preventStrayRequests();
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.'.Str::random(6), 'mot_de_passe_hash' => Hash::make('x'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id, 'statut' => 'actif',
        ]);
    }

    private function configurer(string $mode): void
    {
        foreach ([
            'entreprise_ifu' => self::IFU, 'mecef_operateur_id' => 'RECEPTION01', 'mecef_operateur_nom' => 'Réception',
            ModeFacturation::CLE => $mode, 'tva_active' => 'false',
        ] as $cle => $valeur) {
            ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
        }
    }

    private function faux(array $reponses): void
    {
        Http::swap(new Factory());
        Http::preventStrayRequests();
        Http::fake($reponses);
    }

    /** @return array<string, mixed> */
    private function confirmation(string $nim = 'ED04000999', string $compteur = '12/45 FV'): array
    {
        return [
            'codeMECeFDGI' => 'ABCD-EFGH-IJKL', 'qrCode' => "F;{$nim};ABCD-EFGH-IJKL;".self::IFU.';20261107100000',
            'dateTime' => '2026-11-07T10:00:03+01:00', 'counters' => $compteur, 'nim' => $nim,
        ];
    }

    private function facture(bool $normalisee = false, string $statut = 'certifiee'): Facture
    {
        $facture = Facture::create([
            'client_id' => Client::factory()->create()->id, 'date_emission' => '2026-11-07',
            'montant_ht' => '10000.00', 'montant_tva' => '0.00', 'montant_ttc' => '10000.00', 'statut' => $statut,
            ...($normalisee ? [
                'numero_mecef' => 'ED04000623-41', 'qr_code_fiscal' => self::QR, 'code_mecef' => 'NW34NID6ZHANFNMZ2IU7LL3H',
                'normalisation_statut' => 'normalisee', 'normalisation_mode' => 'emecef',
            ] : []),
        ]);
        LigneFacture::create([
            'facture_id' => $facture->id, 'source_module' => 'M1', 'source_id' => $facture->id, 'libelle' => 'Nuitée',
            'quantite' => 2, 'prix_unitaire' => '5000.00', 'prix_catalogue' => '5000.00', 'montant' => '10000.00',
        ]);

        return $facture->refresh();
    }

    /** @param array<string, mixed> $corps */
    private function appeler(string $chemin, array $corps, ?User $u = null, string $jetonPoste = 'poste-a', string $posteDeclare = 'poste-a')
    {
        // Le garde garde l'utilisateur d'une requête à l'autre d'un même test : on l'oublie.
        $this->app['auth']->forgetGuards();
        $jeton = ($u ?? $this->receptionniste)->createToken($jetonPoste)->plainTextToken;

        return $this->withToken($jeton)->postJson($chemin, ['poste_id' => $posteDeclare, ...$corps]);
    }

    // =====================================================================
    // L'AVOIR EN LIGNE — identifiant serveur, normalisé selon le mode
    // =====================================================================

    #[Test]
    public function l_avoir_d_une_facture_normalisee_naît_au_serveur_et_est_normalise_par_e_mecef(): void
    {
        $facture = $this->facture(true);
        $this->faux([
            self::BASE.'/invoice' => Http::response(['uid' => 'uid-av'], 200),
            self::BASE.'/invoice/uid-av/confirm' => Http::response($this->confirmation('ED04000999', '3/5 FA'), 200),
        ]);

        $reponse = $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'Erreur de saisie'], $this->admin)
            ->assertOk()
            ->assertJsonPath('data.entier', true)
            ->assertJsonPath('data.normalisation_statut', 'normalisee')
            ->assertJsonPath('data.rejeu', false);

        $avoir = Avoir::query()->where('facture_id', $facture->id)->firstOrFail();
        $this->assertSame((string) $avoir->id, $reponse->json('data.avoir_id'), 'l\'identifiant est celui du SERVEUR');
        $this->assertSame($avoir->numero, $reponse->json('data.numero_avoir'));
        $this->assertSame('ED04000999-3', $avoir->numero_mecef);

        // Type FA, référence = code MECeF de la facture d'origine ; la facture d'origine n'a pas bougé.
        $envoi = Http::recorded()[0][0]->data();
        $this->assertSame('FA', $envoi['type']);
        $this->assertSame('NW34NID6ZHANFNMZ2IU7LL3H', $envoi['reference']);
        $this->assertSame('ED04000623-41', $facture->refresh()->numero_mecef);

        // Jamais de jeton dans la réponse.
        $this->assertStringNotContainsString(self::JETON, $reponse->getContent());
    }

    #[Test]
    public function en_mode_boitier_l_avoir_est_cree_en_attente_du_poste_sans_aucune_requete_a_la_dgi(): void
    {
        $this->configurer('boitier');
        $facture = $this->facture(true);
        $this->faux([]);

        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'Erreur'], $this->admin)
            ->assertOk()
            ->assertJsonPath('data.normalisation_statut', 'en_attente')
            ->assertJsonPath('data.normalisation_mode', 'boitier');

        Http::assertNothingSent();
    }

    #[Test]
    public function la_facture_simple_donne_un_avoir_simple(): void
    {
        $this->configurer('desactive');
        $facture = $this->facture(false);
        $this->faux([]);

        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'Erreur', 'montant' => 4000])
            ->assertOk()
            ->assertJsonPath('data.entier', false)
            ->assertJsonPath('data.normalisation_statut', null);

        Http::assertNothingSent();
    }

    #[Test]
    public function le_rejeu_de_la_meme_demande_rend_le_meme_avoir_et_ne_le_double_jamais(): void
    {
        $facture = $this->facture(true);
        $this->faux([
            self::BASE.'/invoice' => Http::response(['uid' => 'u'], 200),
            self::BASE.'/invoice/u/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $demande = (string) Str::uuid();

        $premier = $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'Geste', 'montant' => 3000, 'demande_id' => $demande])->assertOk();
        $second = $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'Geste', 'montant' => 3000, 'demande_id' => $demande])
            ->assertOk()->assertJsonPath('data.rejeu', true);

        $this->assertSame($premier->json('data.avoir_id'), $second->json('data.avoir_id'));
        $this->assertSame(1, Avoir::query()->where('facture_id', $facture->id)->count());
        Http::assertSentCount(2);

        // Une annulation entière rejouée rend aussi le même avoir.
        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'Annulation'], $this->admin)->assertOk();
        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'Annulation'], $this->admin)->assertOk()->assertJsonPath('data.rejeu', true);
        $this->assertSame(2, Avoir::query()->where('facture_id', $facture->id)->count());
    }

    #[Test]
    public function un_avoir_d_un_poste_hors_liste_ou_sans_jeton_est_refuse_et_le_compte_sans_droit_m2_est_accepte(): void
    {
        $facture = $this->facture(true);
        $this->faux([]);

        // Le poste déclaré n'est PAS celui du jeton.
        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'X'], $this->admin, 'poste-a', 'poste-intrus')
            ->assertForbidden();

        // Décision du PO du 09/11/2026 : le serveur NE JUGE PLUS les droits de module du compte
        // d'appairage. Un compte sans écriture sur M2 n'est plus refusé : le droit « Annulations »
        // se juge AU POSTE, sur l'utilisateur connecté. Le poste concordant et le jeton restent exigés.
        $sansDroit = null;
        foreach (Role::all() as $role) {
            if ($role->niveauSurModule('M2') !== 'C') {
                $sansDroit = $this->utilisateur($role->libelle);
                break;
            }
        }
        $this->assertNotNull($sansDroit, 'aucun rôle sans écriture M2 : le cas ne prouverait rien');
        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'X'], $sansDroit)->assertOk();

        // Sans jeton : refusé (le jeton posé par `withToken` reste sur les requêtes suivantes).
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $this->postJson('/api/v1/sync/factures/'.$facture->id.'/avoir', ['poste_id' => 'poste-a', 'motif' => 'X'])->assertUnauthorized();

        // Seul l'avoir du compte sans droit M2 a été écrit (le poste intrus et l'appel sans jeton : rien).
        $this->assertSame(1, Avoir::count());
    }

    #[Test]
    public function les_refus_de_l_avoir_sont_en_francais_et_la_facture_inconnue_se_dit(): void
    {
        $facture = $this->facture(true);
        $this->faux([]);

        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'Trop', 'montant' => 99999])
            ->assertStatus(422)->assertJsonPath('message', __('facturation.avoir_montant_excessif'));

        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => ''])->assertStatus(422);
        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/avoir', ['motif' => 'X', 'montant' => 0])->assertStatus(422);

        $this->appeler('/api/v1/sync/factures/'.Str::uuid().'/avoir', ['motif' => 'X'])
            ->assertNotFound()->assertJsonPath('code', 'facture_inconnue');

        $this->assertSame(0, Avoir::count());
    }

    // =====================================================================
    // LA NORMALISATION IMMÉDIATE e-MECeF depuis un poste
    // =====================================================================

    #[Test]
    public function la_demande_de_normalisation_rend_le_resultat_complet_sans_jamais_le_jeton(): void
    {
        $facture = $this->facture(false);
        $this->faux([
            self::BASE.'/invoice' => Http::response(['uid' => 'uid-n'], 200),
            self::BASE.'/invoice/uid-n/confirm' => Http::response($this->confirmation(), 200),
        ]);

        $reponse = $this->appeler('/api/v1/sync/factures/'.$facture->id.'/normalisation', [])
            ->assertOk()
            ->assertJsonPath('data.normalisation_statut', 'normalisee')
            ->assertJsonPath('data.normalisation_mode', 'emecef')
            ->assertJsonPath('data.numero_mecef', 'ED04000999-12')
            ->assertJsonPath('data.code_mecef', 'ABCD-EFGH-IJKL')
            ->assertJsonPath('data.rejeu', false);

        $this->assertStringStartsWith('F;ED04000999;', (string) $reponse->json('data.qr_code'));
        $this->assertNotNull($reponse->json('data.date'));
        $this->assertStringNotContainsString(self::JETON, $reponse->getContent());
        $this->assertTrue($facture->refresh()->estNormalisee());
        Http::assertSentCount(2);
    }

    #[Test]
    public function une_facture_deja_normalisee_n_est_jamais_retransmise_le_rejeu_est_idempotent(): void
    {
        $facture = $this->facture(false);
        $this->faux([
            self::BASE.'/invoice' => Http::response(['uid' => 'uid-i'], 200),
            self::BASE.'/invoice/uid-i/confirm' => Http::response($this->confirmation(), 200),
        ]);

        $premier = $this->appeler('/api/v1/sync/factures/'.$facture->id.'/normalisation', [])->assertOk();
        Http::assertSentCount(2);

        $second = $this->appeler('/api/v1/sync/factures/'.$facture->id.'/normalisation', [])
            ->assertOk()->assertJsonPath('data.rejeu', true);

        Http::assertSentCount(2);
        $this->assertSame($premier->json('data.numero_mecef'), $second->json('data.numero_mecef'));
    }

    #[Test]
    public function un_refus_de_la_dgi_se_range_et_se_rend_en_francais_la_facture_reste_emise(): void
    {
        $facture = $this->facture(false);
        $this->faux([self::BASE.'/invoice' => Http::response(['errorCode' => '2', 'errorDesc' => 'IFU du client invalide'], 400)]);

        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/normalisation', [])
            ->assertOk()
            ->assertJsonPath('data.normalisation_statut', 'refusee')
            ->assertJsonPath('data.normalisation_motif', __('facturation.emecef.refus', ['detail' => 'IFU du client invalide']))
            ->assertJsonPath('data.numero_mecef', null)
            ->assertJsonPath('data.qr_code', null);

        $facture->refresh();
        $this->assertSame('certifiee', $facture->statut, 'la facture reste émise');
        $this->assertFalse($facture->estNormalisee());
    }

    #[Test]
    public function seul_le_mode_e_mecef_normalise_au_serveur_et_une_facture_inconnue_ou_un_poste_intrus_sont_refuses(): void
    {
        $facture = $this->facture(false);
        $this->faux([]);

        foreach (['desactive' => 'normaliser_desactive', 'boitier' => 'normaliser_poste'] as $mode => $cle) {
            $this->configurer($mode);
            $this->appeler('/api/v1/sync/factures/'.$facture->id.'/normalisation', [])
                ->assertStatus(422)->assertJsonPath('message', __('facturation.mode.'.$cle));
        }

        $this->configurer('emecef');
        $this->appeler('/api/v1/sync/factures/'.Str::uuid().'/normalisation', [])->assertNotFound()->assertJsonPath('code', 'facture_inconnue');
        $this->appeler('/api/v1/sync/factures/'.$facture->id.'/normalisation', [], null, 'poste-a', 'poste-intrus')->assertForbidden();

        Http::assertNothingSent();
        $this->assertNull($facture->refresh()->normalisation_statut);
    }

    // =====================================================================
    // IFU du client, rétention, rejeu
    // =====================================================================

    #[Test]
    public function l_ifu_du_client_est_facultatif_et_exactement_13_chiffres_s_il_est_rempli(): void
    {
        $emission = app(EmissionFactureService::class);
        $client = Client::factory()->create();

        // Vide, espaces : client sans IFU.
        foreach ([null, '', '   '] as $vide) {
            $this->assertNull($emission->emettreVide((string) $client->id, null, null, $vide)->acheteur_ifu);
        }

        // 13 chiffres (séparateurs de saisie ôtés).
        $this->assertSame('3201910768821', $emission->emettreVide((string) $client->id, null, null, '3201 9107 68821')->acheteur_ifu);

        // 12, 14, lettres : refusés avec LA phrase du web et du poste.
        foreach (['320191076882', '32019107688211', '32019107688AB', '3201910768821x'] as $mauvais) {
            try {
                $emission->emettreVide((string) $client->id, null, null, $mauvais);
                $this->fail("IFU « {$mauvais} » accepté");
            } catch (\InvalidArgumentException $refus) {
                $this->assertSame(__('facturation.ifu_client.invalide'), $refus->getMessage());
            }
        }
    }

    #[Test]
    public function retenir_pour_ce_client_range_l_ifu_sur_la_fiche_jamais_sur_le_client_de_passage_ni_sans_la_case(): void
    {
        $emission = app(EmissionFactureService::class);
        $client = Client::factory()->create();
        $facture = $emission->emettreVide((string) $client->id, null, null, '3201910768821', 'SARL Atacora');

        // Sans la case : la fiche ne bouge pas.
        $emission->retenirSurLaFiche($facture, '3201910768821', false);
        $this->assertNull($client->refresh()->ifu);

        // Avec la case : elle retient.
        $emission->retenirSurLaFiche($facture, '3201910768821', true);
        $this->assertSame('3201910768821', $client->refresh()->ifu);

        // Le client de passage (fiche partagée) ne retient jamais un IFU.
        $passage = Client::create(['nom' => 'Client de passage', 'telephone' => '-', 'type_client' => 'particulier']);
        $f2 = $emission->emettreVide((string) $passage->id, null, null, '0202011344660');
        $emission->retenirSurLaFiche($f2, '0202011344660', true);
        $this->assertNull($passage->refresh()->ifu);

        // Une facture NORMALISÉE reste figée, acheteur compris.
        $this->faux([
            self::BASE.'/invoice' => Http::response(['uid' => 'ua'], 200),
            self::BASE.'/invoice/ua/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $emission->emettreVide((string) $client->id);
        $normalisee = $emission->normaliserLaFacture($emission->figerEmission($this->facture(false)));
        $this->assertTrue($normalisee->estNormalisee());
        $this->expectException(\App\Domain\Facturation\Exceptions\FactureImmuableException::class);
        $emission->definirAcheteur($normalisee, '3201910768821', 'Autre');
    }

    #[Test]
    public function l_ifu_et_le_nom_saisis_partent_a_la_dgi_et_un_client_sans_ifu_part_sans_ifu_sous_le_nom_client_divers(): void
    {
        $emission = app(EmissionFactureService::class);

        // Avec IFU et nom saisis.
        $this->faux([
            self::BASE.'/invoice' => Http::response(['uid' => 'u1'], 200),
            self::BASE.'/invoice/u1/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $avec = $this->facture(false);
        $emission->definirAcheteur($avec, '3201910768821', 'SARL Atacora');
        $emission->normaliserLaFacture($avec->refresh());
        $client = Http::recorded()[0][0]->data()['client'];
        $this->assertSame(['name' => 'SARL Atacora', 'ifu' => '3201910768821'], $client);

        // Sans IFU et sans nom, sans fiche : « Client divers », la clé `ifu` n'est PAS envoyée.
        $this->faux([
            self::BASE.'/invoice' => Http::response(['uid' => 'u2'], 200),
            self::BASE.'/invoice/u2/confirm' => Http::response($this->confirmation('ED04000999', '13/45 FV'), 200),
        ]);
        $sans = Facture::create([
            'client_id' => Client::create(['nom' => 'Client de passage', 'telephone' => '-', 'type_client' => 'particulier'])->id,
            'date_emission' => '2026-11-07', 'montant_ht' => '10000.00', 'montant_tva' => '0.00', 'montant_ttc' => '10000.00', 'statut' => 'certifiee',
        ]);
        LigneFacture::create(['facture_id' => $sans->id, 'source_module' => 'M1', 'source_id' => $sans->id, 'libelle' => 'N', 'quantite' => 2,
            'prix_unitaire' => '5000.00', 'prix_catalogue' => '5000.00', 'montant' => '10000.00']);
        $sans->update(['acheteur_nom' => null]);
        $emission->normaliserLaFacture($sans->refresh());
        $client = Http::recorded()[0][0]->data()['client'];
        $this->assertArrayNotHasKey('ifu', $client);
        $this->assertSame('Client de passage', $client['name'], 'le nom de la fiche sert à défaut de saisie');
    }

    // =====================================================================
    // Le rejeu ne reprend que ce qu'un bouton a demandé
    // =====================================================================

    #[Test]
    public function le_rejeu_n_a_jamais_normalise_a_l_emission_il_ne_reprend_que_les_demandes_en_attente(): void
    {
        $this->faux([]);
        $neuve = $this->facture(false, 'en_attente_certification');

        $bilan = (new RejouerCertificationsMecefEnEchecJob())->handle(app(EmissionFactureService::class));
        $this->assertSame(0, $bilan['tentees'], 'aucune normalisation automatique');
        Http::assertNothingSent();
        $this->assertSame('certifiee', $neuve->refresh()->statut, 'mais la facture est émise (figée, simple)');
        $this->assertNull($neuve->normalisation_statut);

        // Une demande faite par le bouton et restée en attente est reprise.
        $demandee = $this->facture(false);
        $demandee->update(['normalisation_statut' => 'en_attente', 'normalisation_mode' => 'emecef', 'normalisation_motif' => 'DGI injoignable']);
        $this->faux([
            self::BASE.'/invoice' => Http::response(['uid' => 'ur'], 200),
            self::BASE.'/invoice/ur/confirm' => Http::response($this->confirmation(), 200),
        ]);
        $bilan = (new RejouerCertificationsMecefEnEchecJob())->handle(app(EmissionFactureService::class));
        $this->assertSame(1, $bilan['tentees']);
        $this->assertTrue($demandee->refresh()->estNormalisee());
        $this->assertNull($neuve->refresh()->normalisation_statut);
    }
}
