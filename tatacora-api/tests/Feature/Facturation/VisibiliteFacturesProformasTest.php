<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Proforma;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Models\User;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Pwa\Livewire\Facturation\Proformas;
use App\Pwa\Livewire\Hebergement\Reservations;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * VISIBILITÉ des factures et des proformas au web, MECeF activé (bug du PO du 09/11/2026 : « j'ai
 * activé MECeF, testé, enregistré une RÉSERVATION, et je ne vois NI proformas NI factures »).
 *
 * Trois choses sont éprouvées, par les chemins réels :
 *  1. Une réservation ne crée NI facture NI proforma (la facture naît à la clôture du séjour, à
 *     l'encaissement du point de vente ; la proforma, par le bouton « Proforma » de la carte) :
 *     l'écran DOIT le dire, dans les deux registres vides, avec un chemin vers « Proformas ».
 *  2. Aucune facture émise ne disparaît du registre, quel que soit le mode de facturation et l'état de
 *     sa normalisation (en attente, refusée, à vérifier, normalisée, absente) — le statut s'affiche.
 *  3. Aucune proforma ne disparaît de la page Proformas, quel que soit le mode, le statut ou le nombre.
 */
final class VisibiliteFacturesProformasTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
    }

    private function administrateur(): User
    {
        return User::create([
            'login' => 'nabogou', 'mot_de_passe_hash' => Hash::make('x-mot-de-passe-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id, 'statut' => 'actif',
        ]);
    }

    private function mode(string $mode): void
    {
        ParametreSysteme::updateOrCreate(['cle' => 'facturation_mode'], ['valeur' => $mode]);
    }

    private function reservation(): Reservation
    {
        $categorie = CategorieHebergement::create(['id' => (string) Str::uuid(), 'libelle' => 'Chambre', 'capacite_max' => 2, 'tarif_base' => 18000]);
        $unite = UniteHebergement::create(['id' => (string) Str::uuid(), 'categorie_id' => $categorie->id, 'numero' => 'CH-101', 'statut' => 'libre']);
        $client = Client::create(['id' => (string) Str::uuid(), 'nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '01 97 35 59 74', 'type_client' => 'particulier']);

        Livewire::test(Reservations::class)
            ->call('ouvrirCreationReservation')
            ->set('rClientId', $client->id)->set('rUniteId', $unite->id)
            ->set('rDateArrivee', now()->addDays(10)->toDateString())->set('rDateDepart', now()->addDays(12)->toDateString())
            ->set('rAcompte', '0')
            ->call('enregistrerReservation')
            ->assertHasNoErrors();

        return Reservation::query()->firstOrFail();
    }

    /** @return array<string, array{0: string}> */
    public static function modes(): array
    {
        return ['désactivé' => ['desactive'], 'e-MECeF' => ['emecef'], 'boîtier' => ['boitier']];
    }

    #[Test]
    #[DataProvider('modes')]
    public function une_reservation_ne_cree_ni_facture_ni_proforma_et_l_ecran_le_dit(string $mode): void
    {
        $this->mode($mode);
        $this->actingAs($this->administrateur());

        $reservation = $this->reservation();

        $this->assertSame(0, Facture::query()->count(), 'Une réservation ne crée pas de facture.');
        $this->assertSame(0, Proforma::query()->count(), 'Une réservation ne crée pas de proforma.');

        // Le registre vide DIT pourquoi, et où aller.
        $registre = Livewire::test(Facturation::class)
            ->assertSee('Une réservation ne crée pas de facture')
            ->assertSee('clôturez le séjour pour facturer')
            ->assertSee('créez une proforma depuis la réservation');
        $this->assertStringContainsString(route('pwa.facturation.proformas'), $registre->html());

        // La page Proformas vide aussi.
        $proformas = Livewire::test(Proformas::class)
            ->assertSee('Une réservation ne crée pas de facture')
            ->assertSee('créez une proforma depuis la réservation');
        $this->assertStringContainsString('Nouvelle facture proforma', $proformas->html());

        // Le bouton de la carte de réservation existe (droit M2 écriture) et mène à la page prérempli.
        $carte = Livewire::test(Reservations::class)->html();
        $this->assertStringContainsString(route('pwa.facturation.proformas', ['flux' => 'hebergement', 'source' => $reservation->id]), html_entity_decode($carte));
    }

    #[Test]
    #[DataProvider('modes')]
    public function la_proforma_de_la_reservation_se_cree_et_se_liste(string $mode): void
    {
        $this->mode($mode);
        $this->actingAs($this->administrateur());
        $reservation = $this->reservation();

        Livewire::withQueryParams(['flux' => 'hebergement', 'source' => $reservation->id])->test(Proformas::class)
            ->assertSet('etatFormulaire', 'proforma')
            ->assertSet('clientNom', 'Jean KORA')
            ->call('enregistrer', true)
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame(1, Proforma::query()->count());

        // Au web, un brouillon et une émise sont listés, sous tous les modes.
        $page = Livewire::test(Proformas::class)->assertSee('KORA')->assertSee('FP-GCN/'.now()->year);
        $this->assertStringNotContainsString('Aucune proforma.', $page->html());
    }

    /**
     * Toute proforma (brouillon, émise, expirée, convertie, annulée) reste listée sous chaque mode : aucun statut,
     * aucun filtre par défaut ne masque une ligne.
     *
     * @return array<string, array{0: string, 1: string}>
     */
    public static function proformasParMode(): array
    {
        $cas = [];
        foreach (['desactive', 'emecef', 'boitier'] as $mode) {
            foreach (['brouillon', 'emise', 'expiree', 'convertie', 'annulee'] as $statut) {
                $cas["$mode / $statut"] = [$mode, $statut];
            }
        }

        return $cas;
    }

    #[Test]
    #[DataProvider('proformasParMode')]
    public function une_proforma_reste_listee_quels_que_soient_son_statut_et_le_mode(string $mode, string $statut): void
    {
        $this->mode($mode);
        $this->actingAs($this->administrateur());

        Proforma::create([
            'id' => (string) Str::uuid(),
            'statut' => $statut === 'expiree' ? 'emise' : $statut,
            'client_nom' => 'SARL '.strtoupper($statut),
            'total' => 5000,
            'source_module' => 'libre',
            'numero' => $statut === 'brouillon' ? null : 'N°0001 FP-GCN/'.now()->year,
            'annee' => $statut === 'brouillon' ? null : now()->year,
            'rang' => $statut === 'brouillon' ? null : 1,
            'date_emission' => $statut === 'brouillon' ? null : now()->subDays(60)->toDateString(),
            'valide_jusqu_au' => $statut === 'expiree' ? now()->subDays(30)->toDateString() : null,
            'motif_annulation' => $statut === 'annulee' ? 'Client désisté' : null,
        ]);

        $page = Livewire::test(Proformas::class);
        $this->assertStringContainsString('SARL '.strtoupper($statut), $page->html());
        $this->assertStringNotContainsString('Aucune proforma.', $page->html());
    }

    /**
     * Toute combinaison (mode × statut du cycle × statut de normalisation) reste au registre, avec son
     * statut affiché : une facture NON normalisée ne disparaît jamais.
     *
     * @return array<string, array{0: string, 1: string, 2: ?string, 3: string}>
     */
    public static function combinaisons(): array
    {
        $cas = [];
        foreach (['desactive', 'emecef', 'boitier'] as $mode) {
            foreach (['certifiee', 'en_attente_certification', 'echec_certification', 'brouillon'] as $statut) {
                foreach ([null, 'en_attente', 'refusee', 'a_verifier', 'normalisee'] as $norm) {
                    $cas["$mode / $statut / ".($norm ?? 'aucune')] = [$mode, $statut, $norm, ''];
                }
            }
        }

        return $cas;
    }

    #[Test]
    #[DataProvider('combinaisons')]
    public function une_facture_reste_au_registre_quel_que_soit_son_etat_de_normalisation(string $mode, string $statut, ?string $norm): void
    {
        $this->mode($mode);
        $this->actingAs($this->administrateur());
        $client = Client::create(['nom' => 'HOUNSOU', 'prenom' => 'Marceline', 'telephone' => '01 90 00 00 01', 'type_client' => 'particulier']);

        $facture = Facture::create([
            'numero_mecef' => $norm === 'normalisee' ? 'ED04000999-42' : null,
            'client_id' => $client->id, 'date_emission' => now()->toDateString(),
            'montant_ht' => '10000.00', 'montant_tva' => '1800.00', 'montant_ttc' => '11800.00',
            'statut' => $statut, 'normalisation_statut' => $norm,
            'normalisation_mode' => $norm === null ? null : ($mode === 'desactive' ? 'emecef' : $mode),
            'qr_code_fiscal' => $norm === 'normalisee' ? 'F;ED04000999;ABCD;3201910768821;20261107101500' : null,
        ]);

        $page = Livewire::test(Facturation::class);
        $html = $page->html();

        $this->assertStringContainsString('wire:key="facture-'.$facture->id.'"', $html, 'La facture a disparu du registre.');
        $this->assertStringNotContainsString('Aucune facture émise.', $html);
        $this->assertMatchesRegularExpression('/Pièces\s*<strong[^>]*>\s*1\s*</u', $html);
    }

    #[Test]
    public function une_facture_de_l_exercice_precedent_est_masquee_et_l_ecran_le_dit(): void
    {
        $this->mode('emecef');
        $this->actingAs($this->administrateur());
        $client = Client::create(['nom' => 'HOUNSOU', 'prenom' => 'M', 'telephone' => '01 90 00 00 01', 'type_client' => 'particulier']);
        Facture::create([
            'client_id' => $client->id, 'date_emission' => (now()->year - 1).'-06-01', 'montant_ht' => '1000.00', 'montant_tva' => '0.00',
            'montant_ttc' => '1000.00', 'statut' => 'certifiee',
        ]);

        // Hors exercice consulté : le registre est vide MAIS l'écran DIT qu'une facture existe ailleurs, et laquelle
        // des deux explications s'applique (exercice, ou aucune facture).
        $page = Livewire::test(Facturation::class);
        $this->assertStringContainsString('id="registre-hors-exercice"', $page->html());
        $page->assertSee('1 facture(s) émise(s) en dehors de l\'exercice consulté ('.now()->year.')');
    }

    #[Test]
    public function sans_aucune_facture_le_registre_ne_parle_pas_d_exercice(): void
    {
        $this->actingAs($this->administrateur());

        $this->assertStringNotContainsString('id="registre-hors-exercice"', Livewire::test(Facturation::class)->html());
    }

    #[Test]
    public function la_recherche_retrouve_une_facture_non_normalisee_par_son_numero(): void
    {
        $this->mode('emecef');
        $this->actingAs($this->administrateur());
        $client = Client::create(['nom' => 'HOUNSOU', 'prenom' => 'M', 'telephone' => '01 90 00 00 01', 'type_client' => 'particulier']);
        $facture = Facture::create([
            'client_id' => $client->id, 'date_emission' => now()->toDateString(), 'montant_ht' => '1000.00', 'montant_tva' => '0.00',
            'montant_ttc' => '1000.00', 'statut' => 'certifiee',
        ]);
        $this->assertNull($facture->numero_mecef);
        $this->assertNotEmpty($facture->numero);

        Livewire::test(Facturation::class)
            ->set('recherche', (string) $facture->numero)
            ->assertSeeHtml('wire:key="facture-'.$facture->id.'"');
    }

    #[Test]
    public function plus_de_cent_proformas_restent_toutes_atteignables_par_la_pagination(): void
    {
        $this->actingAs($this->administrateur());
        for ($i = 1; $i <= 103; $i++) {
            Proforma::create([
                'id' => (string) Str::uuid(), 'statut' => 'brouillon', 'client_nom' => 'CLIENT '.$i, 'total' => 1000, 'source_module' => 'libre',
            ]);
        }

        // La liste PAGINE : aucune proforma n'est hors d'atteinte, et l'écran dit combien il y en a.
        $premiere = Livewire::test(Proformas::class);
        $this->assertSame(10, substr_count($premiere->html(), 'CLIENT '));
        $premiere->assertSeeHtml('<strong>103</strong>');

        $vues = 0;
        foreach (range(1, 11) as $page) {
            $vues += substr_count(Livewire::withQueryParams(['page' => $page])->test(Proformas::class)->html(), 'CLIENT ');
        }
        $this->assertSame(103, $vues, 'Une proforma n\'est atteignable sur aucune page.');

        // Un filtre remet la liste à sa première page.
        Livewire::test(Proformas::class)->set('pageCourante', 4)->set('statut', 'brouillon')->assertSet('pageCourante', 1);
    }
}
