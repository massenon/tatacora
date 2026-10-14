<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Paiement;
use App\Domain\Hebergement\Models\CanalReservation;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Models\User;
use App\Pwa\Livewire\Accueil;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use Carbon\CarbonImmutable;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * LE BOUTON « PAYER » DU TABLEAU DE BORD — PA-165, 02/09/2026.
 *
 * `maitre-refuse:tableau-de-bord.html#bouton-payer` est retiré depuis cette
 * vague : `EncaissementFactureService` lève la prémisse (PA-21) qui motivait
 * le refus. Ce fichier prouve que le bouton ne se rend QUE quand une facture
 * FIGÉE et NON SOLDÉE couvre réellement la réservation (lignes de source M1),
 * et que le geste encaisse par le MÊME service que `ClientsCreances`.
 *
 * @see EF-M2-03 Encaissement des factures
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-165
 */
final class AccueilPayerTest extends TestCase
{
    use RefreshDatabase;

    private CategorieHebergement $categorie;

    private UniteHebergement $unite;

    private Client $client;

    private CanalReservation $canal;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        $this->categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow',
            'capacite_max' => 2,
            'tarif_base' => '28000.00',
        ]);

        $this->unite = UniteHebergement::create([
            'categorie_id' => $this->categorie->id,
            'numero' => 'BNG-01',
            'statut' => 'libre',
        ]);

        $this->client = Client::create([
            'nom' => 'KPETONI',
            'prenom' => 'Julien',
            'telephone' => '01 90 00 00 02',
            'type_client' => 'particulier',
        ]);

        $this->canal = CanalReservation::create(['nom' => 'Physique', 'actif' => true]);
    }

    #[Test]
    public function le_bouton_payer_ne_se_rend_que_si_une_facture_figee_non_soldee_couvre_la_reservation(): void
    {
        $reservation = $this->reservationDuJour();
        $this->actingAs($this->utilisateurQuiEcrit());

        // Sans facture : le bouton n'apparaît pas.
        $html = (string) $this->get('/pwa')->assertOk()->getContent();
        $this->assertStringNotContainsString('ouvrirRecouvrementDuJour', $html);

        $this->factureCertifiee($reservation, '20000.00');

        // Avec une facture figée non soldée : le bouton apparaît.
        $html = (string) $this->get('/pwa')->assertOk()->getContent();
        $this->assertStringContainsString("ouvrirRecouvrementDuJour('".$reservation->id."')", $html);
    }

    #[Test]
    public function un_reglement_reel_depuis_le_tableau_de_bord_reduit_le_reste_du(): void
    {
        $this->actingAs($this->utilisateurQuiEcrit());
        $reservation = $this->reservationDuJour();
        $facture = $this->factureCertifiee($reservation, '20000.00');

        $this->assertSame('20000.00', $facture->resteDu());

        Livewire::test(Accueil::class)
            ->call('ouvrirRecouvrementDuJour', $reservation->id)
            ->assertSet('etatFormulaire', 'payer')
            ->assertSet('payerFactureId', $facture->id)
            ->set('payerMontant', '20000')
            ->set('payerMode', 'especes')
            ->call('confirmerRecouvrementDuJour')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame(1, Paiement::query()->count());
        $this->assertSame('0.00', $facture->fresh()->resteDu());

        $compteClient = CompteComptable::where('numero_compte', '4111')->firstOrFail();
        $this->assertDatabaseHas('ecritures_comptables', [
            'compte_id' => $compteClient->id,
            'credit' => '20000.00',
            'statut' => 'validee',
        ]);
    }

    #[Test]
    public function un_role_en_lecture_ne_peut_pas_ouvrir_le_paiement(): void
    {
        $this->actingAs($this->utilisateurQuiEcrit());
        $reservation = $this->reservationDuJour();
        $this->factureCertifiee($reservation, '20000.00');

        // `comptable` porte M11 = 'L' ET M2 = 'L' : la lecture, jamais
        // l'écriture — les deux droits exigés par cette action (PA-65).
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M11'));
        $this->assertSame('L', $comptable->niveauSurModule('M2'));

        $refusAvant = JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->count();
        $this->actingAs($comptable);

        Livewire::test(Accueil::class)
            ->call('ouvrirRecouvrementDuJour', $reservation->id)
            ->assertSet('etatFormulaire', null)
            ->assertForbidden();

        $this->assertSame(0, Paiement::query()->count());
        $this->assertSame(
            $refusAvant + 1,
            JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->count(),
        );
    }

    // ----------------------------------------------------------- auxiliaires

    private function reservationDuJour(): Reservation
    {
        return Reservation::create([
            'client_id' => $this->client->id,
            'unite_id' => $this->unite->id,
            'canal_id' => $this->canal->id,
            'date_arrivee' => CarbonImmutable::today()->toDateString(),
            'date_depart' => CarbonImmutable::today()->addDays(2)->toDateString(),
            'statut' => 'confirmee',
        ]);
    }

    /**
     * Une facture CERTIFIÉE (figée) couvrant la réservation — écrite
     * directement (comme `CrmPwaTest::jeuDeDonnees()`) : ce fichier teste le
     * geste de PAIEMENT, pas l'émission, et `EmissionFactureService` ne
     * produit qu'une facture `en_attente_certification`.
     */
    private function factureCertifiee(Reservation $reservation, string $montantTtc): \App\Domain\Facturation\Models\Facture
    {
        $factureId = (string) Str::uuid();

        \Illuminate\Support\Facades\DB::table('factures')->insert([
            'id' => $factureId,
            'client_id' => $this->client->id,
            'date_emission' => now()->toDateString(),
            'montant_ht' => $montantTtc,
            'montant_tva' => '0.00',
            'montant_ttc' => $montantTtc,
            'statut' => 'certifiee',
            'numero_mecef' => 'MECEF-TEST-'.Str::random(6),
            'utilisateur_creation_id' => auth()->id(),
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        \Illuminate\Support\Facades\DB::table('lignes_facture')->insert([
            'id' => (string) Str::uuid(),
            'facture_id' => $factureId,
            'source_module' => 'M1',
            'source_id' => $reservation->id,
            'libelle' => 'Hébergement',
            'quantite' => '2.00',
            'prix_unitaire' => $montantTtc,
            'montant' => $montantTtc,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $sessionId = (string) Str::uuid();
        SessionCaisse::create([
            'id' => $sessionId,
            'point_vente' => 'reception',
            'utilisateur_ouverture_id' => auth()->id(),
            'date_ouverture' => now()->subHours(2),
            'montant_fond' => '10000.00',
        ]);

        return \App\Domain\Facturation\Models\Facture::findOrFail($factureId);
    }

    /** Le rôle qui porte `M11 = C` ET `M2 = C`, lu du référentiel plutôt que supposé. */
    private function utilisateurQuiEcrit(): User
    {
        foreach (['gerant', 'administrateur'] as $role) {
            $modele = Role::where('libelle', $role)->first();
            if ($modele !== null && $modele->niveauSurModule('M11') === 'C' && $modele->niveauSurModule('M2') === 'C') {
                return $this->utilisateur($role);
            }
        }

        $this->fail('Aucun rôle du référentiel ne porte M11 = C et M2 = C.');
    }

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
