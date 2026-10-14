<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Models\RelanceClient;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Paiement;
use App\Models\User;
use App\Pwa\Livewire\Crm\ClientsCreances;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * LES ÉCRITURES M3/M2 DEPUIS L'ÉCRAN CLIENTS & CRÉANCES — PA-165, 02/09/2026.
 *
 * ## Ce que ce fichier prouve, et qui n'était prouvé nulle part
 *
 * `CrmPwaTest` tenait l'écran quand il était en lecture seule. Ce fichier
 * tient les TROIS écritures que la vague PA-165 lui apporte : le
 * recouvrement d'une facture (`EncaissementFactureService`, premier writer
 * de `paiements`), la relance d'un client (`RelanceClientService`) et la
 * création d'un client (`EnregistrementClientService`). Chaque cas emprunte
 * le chemin RÉEL — appeler le Service, pas relire son code (PA-59/60/61).
 *
 * @see EF-M2-03 Encaissement des factures
 * @see EF-M3-03 Relances clients
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-165
 */
final class ClientsCreancesEcritureTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
    }

    // =====================================================================
    // Recouvrement — EF-M2-03 depuis M3
    // =====================================================================

    #[Test]
    public function un_recouvrement_reel_reduit_le_reste_du_de_la_facture(): void
    {
        [$client, $facture] = $this->clientAvecFactureImpayee('10000.00');
        $this->actingAs($this->utilisateurQuiEcrit());

        $this->assertSame('10000.00', $facture->resteDu());

        Livewire::test(ClientsCreances::class)
            ->call('ouvrirRecouvrement', $client->id)
            ->assertSet('etatFormulaire', 'recouvrement')
            ->assertSet('recouvrementFactureId', $facture->id)
            ->set('recouvrementMontant', '4000')
            ->set('recouvrementMode', 'especes')
            ->call('enregistrerRecouvrement')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame(1, Paiement::query()->count());
        $paiement = Paiement::query()->firstOrFail();
        $this->assertSame($facture->id, $paiement->facture_id);
        $this->assertSame('4000.00', (string) $paiement->montant);
        $this->assertSame('especes', $paiement->mode_paiement);

        $this->assertSame('6000.00', $facture->fresh()->resteDu());

        // La pièce comptable RÉELLE est passée — même transaction (règle du
        // Product Owner) : un DÉBIT trésorerie (5711, caisse) et un CRÉDIT
        // client (4111), portant le libellé « Encaissement <n° facture> —
        // <id paiement> » (PA-52 : c'est le seul lien entre les deux lignes).
        $compteClient = CompteComptable::where('numero_compte', '4111')->firstOrFail();
        $libelle = sprintf('Encaissement %s — %s', (string) $facture->numero_mecef, $paiement->id);

        $this->assertDatabaseHas('ecritures_comptables', [
            'compte_id' => $compteClient->id,
            'credit' => '4000.00',
            'libelle' => $libelle,
            'statut' => 'validee',
        ]);

        $compteCaisse = CompteComptable::where('numero_compte', '5711')->firstOrFail();
        $this->assertDatabaseHas('ecritures_comptables', [
            'compte_id' => $compteCaisse->id,
            'debit' => '4000.00',
            'libelle' => $libelle,
            'statut' => 'validee',
        ]);
    }

    /**
     * Un sur-encaissement est REFUSÉ, et le refus reste LISIBLE — la modale
     * NE SE FERME PAS : la fermer laisserait croire à un encaissement qui
     * n'a pas eu lieu (PA-59/60/61).
     */
    #[Test]
    public function un_sur_encaissement_est_refuse_et_la_modale_reste_ouverte(): void
    {
        [$client, $facture] = $this->clientAvecFactureImpayee('5000.00');
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(ClientsCreances::class)
            ->call('ouvrirRecouvrement', $client->id)
            ->set('recouvrementMontant', '9000')
            ->call('enregistrerRecouvrement')
            ->assertHasErrors('recouvrementMontant')
            ->assertSet('etatFormulaire', 'recouvrement');

        $this->assertSame(0, Paiement::query()->count());
        $this->assertSame('5000.00', $facture->fresh()->resteDu());
    }

    #[Test]
    public function un_role_en_lecture_ne_peut_pas_ouvrir_le_recouvrement(): void
    {
        [$client] = $this->clientAvecFactureImpayee('5000.00');

        // `comptable` porte M3 = 'L' ET M2 = 'L' : la lecture, jamais
        // l'écriture — les deux droits exigés par cette action (PA-65).
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M3'));
        $this->assertSame('L', $comptable->niveauSurModule('M2'));

        $refusAvant = JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->count();

        $this->actingAs($comptable);

        Livewire::test(ClientsCreances::class)
            ->call('ouvrirRecouvrement', $client->id)
            ->assertSet('etatFormulaire', null)
            ->assertForbidden();

        $this->assertSame(0, Paiement::query()->count());
        $this->assertSame(
            $refusAvant + 1,
            JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->count(),
        );
    }

    // =====================================================================
    // Relance — EF-M3-03
    // =====================================================================

    #[Test]
    public function une_relance_est_reellement_enregistree(): void
    {
        [$client] = $this->clientAvecFactureImpayee('6000.00');
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(ClientsCreances::class)
            ->call('ouvrirRelance', $client->id)
            ->assertSet('etatFormulaire', 'relance')
            ->assertSet('relanceMontant', '6000.00')
            ->set('relanceCanal', 'whatsapp')
            ->set('relanceCommentaire', 'Rappel envoyé, promesse de règlement sous une semaine.')
            ->call('enregistrerRelance')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $relance = RelanceClient::query()->firstOrFail();
        $this->assertSame($client->id, $relance->client_id);
        $this->assertSame('whatsapp', $relance->canal);
        $this->assertSame('6000.00', (string) $relance->montant_reclame);
    }

    #[Test]
    public function un_canal_hors_registre_est_refuse(): void
    {
        [$client] = $this->clientAvecFactureImpayee('6000.00');
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(ClientsCreances::class)
            ->call('ouvrirRelance', $client->id)
            ->set('relanceCanal', 'sms')
            ->call('enregistrerRelance')
            ->assertHasErrors('relanceCanal');

        $this->assertSame(0, RelanceClient::query()->count());
    }

    // =====================================================================
    // Nouveau client — EF-M3-01
    // =====================================================================

    #[Test]
    public function un_nouveau_client_est_reellement_cree(): void
    {
        $this->actingAs($this->utilisateurQuiEcrit());

        Livewire::test(ClientsCreances::class)
            ->call('ouvrirFormulaireClient')
            ->assertSet('etatFormulaire', 'client')
            ->set('clientNom', 'DOSSOU Firmin')
            ->set('clientTelephone', '01 90 55 66 77')
            ->set('clientType', 'particulier')
            ->call('enregistrerClient')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame(1, Client::query()->where('nom', 'DOSSOU Firmin')->count());
    }

    // ----------------------------------------------------------- auxiliaires

    /**
     * @return array{0: Client, 1: Facture}
     */
    private function clientAvecFactureImpayee(string $montantTtc): array
    {
        $auteur = $this->utilisateurQuiEcrit();
        $this->actingAs($auteur);

        $client = Client::create([
            'nom' => 'KORA',
            'prenom' => 'Jean',
            'telephone' => '01 90 00 00 03',
            'type_client' => 'particulier',
        ]);

        $facture = Facture::create([
            'client_id' => $client->id,
            'date_emission' => now()->subDays(5)->toDateString(),
            'montant_ht' => $montantTtc,
            'montant_tva' => '0.00',
            'montant_ttc' => $montantTtc,
            'statut' => 'certifiee',
            'numero_mecef' => 'MECEF-TEST-' . Str::random(6),
        ]);

        SessionCaisse::create([
            'point_vente' => 'reception',
            'utilisateur_ouverture_id' => $auteur->id,
            'date_ouverture' => now()->subDays(1),
            'montant_fond' => '10000.00',
        ]);

        return [$client, $facture];
    }

    /** Le rôle qui porte `M3 = C` ET `M2 = C`, lu du référentiel plutôt que supposé. */
    private function utilisateurQuiEcrit(): User
    {
        foreach (['receptionniste', 'gerant', 'administrateur'] as $role) {
            $modele = Role::where('libelle', $role)->first();
            if ($modele !== null && $modele->niveauSurModule('M3') === 'C' && $modele->niveauSurModule('M2') === 'C') {
                return $this->utilisateur($role);
            }
        }

        $this->fail('Aucun rôle du référentiel ne porte M3 = C et M2 = C.');
    }

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.' . $role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.' . $role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
