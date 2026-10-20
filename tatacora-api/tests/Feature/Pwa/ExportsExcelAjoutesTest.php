<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Domain\Crm\Models\Client;
use App\Models\User;
use App\Pwa\Livewire\Comptabilite\Hub;
use App\Pwa\Livewire\Crm\ClientsCreances;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Pwa\Livewire\Stocks\Inventaires;
use App\Pwa\Livewire\Stocks\Stocks;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les TROIS boutons « Excel » ajoutés le 01/09/2026 (audit navigateur du
 * chrome transverse, Product Owner) — `ClientsCreances`, `Facturation`,
 * `Comptabilite\Hub`. Deux écrans (Stocks, Inventaires, Approvisionnement)
 * avaient déjà leur infrastructure d'export ; ceux-ci n'en avaient AUCUNE, et
 * le motif qui les refusait était périmé (voir les docblocks des trois
 * classes).
 *
 * ## Export UNIFIÉ (02/09/2026) — le contrat que ces cas éprouvent désormais
 *
 * Dérogation PO du 01/09/2026, rappelée le 02/09/2026 : UN bouton
 * « Exporter » par écran, la modale partagée, le format PDF/Excel choisi
 * dedans. `ClientsCreances::exporterExcel()` et `Facturation::
 * exporterExcel()` sont devenues `ouvrirExport()`/`genererExport()`, et le
 * PDF ajouté est un état RÉEL (dompdf, mêmes lignes que l'écran, en-tête
 * `ReportHeaderService`) — les cas `*_produit_le_pdf_du_registre` exécutent
 * réellement cette branche. Voir `DerogationsMaquette`
 * (export_bouton_unique).
 *
 * ## Ce que ces cas vérifient, et pourquoi `assertStatus(200)` est la seule
 * assertion qui compte
 *
 * `AchatsCyclePwaTest::les_quatre_exports_sont_reellement_produits()` l'a
 * déjà trouvé : Livewire rend un refus RBAC comme un STATUT de réponse, pas
 * comme une exception, et `assertHasNoErrors()` ne le voit pas. Chaque cas
 * d'exécution réelle ici se termine donc par `assertStatus(200)`, jamais par
 * une simple absence d'erreur de validation.
 *
 * ## Le défaut réel que ce lot a trouvé, à l'essai dans un vrai navigateur
 *
 * `Stocks::ouvrirExport()` et `Inventaires::ouvrirExport()` posaient
 * `$this->formatExport = $format` AVANT `$this->ouvrirFormulaire('export')`
 * — qui appelle `$this->reset(['formatExport'])` et écrasait donc la valeur
 * tout juste posée. Le bouton « Excel » ouvrait la modale sur « PDF » coché.
 * Aucun test existant ne pouvait le voir : `genererExport()` lit
 * `$this->formatExport` tel quel, un cas qui n'inspecte que le document
 * produit passe au vert que l'ordre soit bon ou non — seul l'ÉTAT DE LA
 * MODALE APRÈS OUVERTURE le montre. `stocks_ouvrirexport_precoche_excel()`
 * et `inventaires_ouvrirexport_precoche_excel()` couvrent ce défaut
 * précisément : éprouvés par mutation (l'ordre inversé dans les deux
 * méthodes) le 01/09/2026 — rouge sur les deux cas, vert restauré.
 */
final class ExportsExcelAjoutesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.test.'.Str::random(4),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    // =========================================================== Clients ===

    #[Test]
    public function clients_genererexport_produit_le_registre_excel(): void
    {
        // `comptable` porte `M3 = 'L'` : la lecture seule doit suffire —
        // l'export ne produit rien de neuf.
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M3'));
        $this->actingAs($comptable);

        $client = Client::create([
            'nom' => 'Agence Bénin Tour', 'prenom' => null,
            'telephone' => '01 21 45 67 89', 'type_client' => 'agence',
        ]);
        DB::table('factures')->insert([
            'id' => (string) Str::uuid(), 'client_id' => $client->id,
            'date_emission' => now()->subDays(2)->toDateString(),
            'montant_ht' => '120000.00', 'montant_tva' => '0.00', 'montant_ttc' => '120000.00',
            'statut' => 'certifiee', 'numero_mecef' => 'MECEF-TEST-'.Str::random(6),
            'utilisateur_creation_id' => $comptable->id,
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        // L'API a changé avec l'export unifié (dérogation PO du 01/09/2026,
        // rappelée le 02/09/2026) : un bouton « Exporter » ouvre la modale,
        // le format se choisit dedans.
        Livewire::test(ClientsCreances::class)
            ->call('ouvrirExport')
            ->assertSet('etatFormulaire', 'export')
            ->set('formatExport', 'excel')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertStatus(200);
    }

    /**
     * Le PDF ajouté le 02/09/2026 est un état RÉEL (dompdf, mêmes lignes que
     * l'écran) — jamais une page vide : le document est réellement produit
     * et téléchargé.
     */
    #[Test]
    public function clients_genererexport_produit_le_pdf_du_registre(): void
    {
        $comptable = $this->utilisateur('comptable');
        $this->actingAs($comptable);

        $client = Client::create([
            'nom' => 'Agence Bénin Tour', 'prenom' => null,
            'telephone' => '01 21 45 67 89', 'type_client' => 'agence',
        ]);
        DB::table('factures')->insert([
            'id' => (string) Str::uuid(), 'client_id' => $client->id,
            'date_emission' => now()->subDays(2)->toDateString(),
            'montant_ht' => '120000.00', 'montant_tva' => '0.00', 'montant_ttc' => '120000.00',
            'statut' => 'certifiee', 'numero_mecef' => 'MECEF-TEST-'.Str::random(6),
            'utilisateur_creation_id' => $comptable->id,
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        // L'horloge est FIGÉE pour nommer le fichier attendu : sans le nom,
        // une mutation qui servirait la branche Excel à la place du PDF
        // resterait verte (un .xlsx se télécharge aussi bien qu'un .pdf).
        // Éprouvé par mutation le 02/09/2026 : `formatExport !== 'excel'`
        // inversé dans `genererExport()` — rouge ici, vert restauré.
        Carbon::setTestNow(Carbon::create(2026, 9, 2, 10, 30));

        Livewire::test(ClientsCreances::class)
            ->set('formatExport', 'pdf')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertFileDownloaded('clients_creances_'.now()->format('Ymd_His').'.pdf')
            ->assertStatus(200);

        Carbon::setTestNow();
    }

    #[Test]
    public function clients_genererexport_refuse_une_liste_vide(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        Livewire::test(ClientsCreances::class)
            ->set('recherche', 'aucun-client-ne-porte-ce-nom')
            ->call('genererExport')
            ->assertHasErrors('export');
    }

    #[Test]
    public function clients_export_refuse_les_onglets_hors_liste_des_clients(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        // Le refus tombe DÈS L'OUVERTURE : ouvrir une modale qui refusera
        // toujours de générer laisserait l'utilisateur deviner pourquoi.
        Livewire::test(ClientsCreances::class)
            ->set('onglet', 'dettes')
            ->call('ouvrirExport')
            ->assertSet('etatFormulaire', null)
            ->assertHasErrors('export');

        // Et `genererExport` le refuse AUSSI : l'ouverture n'est pas la
        // seule porte (un état d'onglet peut changer modale ouverte).
        Livewire::test(ClientsCreances::class)
            ->set('onglet', 'dettes')
            ->call('genererExport')
            ->assertHasErrors('export');
    }

    // ============================================ Stocks / Inventaires ===

    /**
     * Régression du défaut décrit en tête de classe : le bouton « Excel »
     * doit ouvrir la modale avec `formatExport === 'excel'`, jamais retomber
     * sur le défaut « pdf » par l'effet du `reset()` de `ouvrirFormulaire()`.
     */
    #[Test]
    public function stocks_ouvrirexport_precoche_excel(): void
    {
        $this->actingAs($this->utilisateur('gerant'));

        Livewire::test(Stocks::class)
            ->call('ouvrirExport', 'excel')
            ->assertSet('formatExport', 'excel')
            ->assertSet('etatFormulaire', 'export');
    }

    #[Test]
    public function inventaires_ouvrirexport_precoche_excel(): void
    {
        $this->actingAs($this->utilisateur('gerant'));

        Livewire::test(Inventaires::class)
            ->call('ouvrirExport', 'excel')
            ->assertSet('formatExport', 'excel')
            ->assertSet('etatFormulaire', 'export');
    }

    // ======================================================== Facturation ===

    #[Test]
    public function facturation_genererexport_produit_le_registre_excel(): void
    {
        // `comptable` porte `M2 = 'L'`.
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M2'));
        $this->actingAs($comptable);

        $client = Client::create([
            'nom' => 'HOUNSOU', 'prenom' => 'Marceline',
            'telephone' => '01 55 44 33 22', 'type_client' => 'particulier',
        ]);
        // `utilisateur_creation_id`/`date_creation` sont NOT NULL au schema
        // et hors `$fillable` de `Facture` — même repli que
        // `SoldeClientServiceTest::facture()`.
        DB::table('factures')->insert([
            'id' => (string) Str::uuid(), 'client_id' => $client->id,
            'date_emission' => now()->toDateString(),
            'montant_ht' => '50000.00', 'montant_tva' => '0.00', 'montant_ttc' => '50000.00',
            'statut' => 'certifiee', 'numero_mecef' => 'MECEF-TEST-'.Str::random(6),
            'utilisateur_creation_id' => $comptable->id,
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        // Export unifié (dérogation PO du 01/09/2026, rappelée le
        // 02/09/2026) : « Exporter » ouvre la modale, le format se choisit
        // dedans.
        Livewire::test(Facturation::class)
            ->call('ouvrirExport')
            ->assertSet('etatFormulaire', 'export')
            ->set('formatExport', 'excel')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertStatus(200);
    }

    /**
     * Le PDF de l'ÉCRAN est le REGISTRE affiché en A4 — jamais une facture
     * (le document fiscal individuel reste `imprimerFacture()`). Ajouté le
     * 02/09/2026 avec l'export unifié : réellement produit et téléchargé.
     */
    #[Test]
    public function facturation_genererexport_produit_le_pdf_du_registre(): void
    {
        $comptable = $this->utilisateur('comptable');
        $this->actingAs($comptable);

        $client = Client::create([
            'nom' => 'HOUNSOU', 'prenom' => 'Marceline',
            'telephone' => '01 55 44 33 22', 'type_client' => 'particulier',
        ]);
        DB::table('factures')->insert([
            'id' => (string) Str::uuid(), 'client_id' => $client->id,
            'date_emission' => now()->toDateString(),
            'montant_ht' => '50000.00', 'montant_tva' => '0.00', 'montant_ttc' => '50000.00',
            'statut' => 'certifiee', 'numero_mecef' => 'MECEF-TEST-'.Str::random(6),
            'utilisateur_creation_id' => $comptable->id,
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        // Horloge figée + nom exact : voir le cas Clients — sans le nom, la
        // branche PDF pourrait servir un .xlsx sans que ce cas rougisse.
        Carbon::setTestNow(Carbon::create(2026, 9, 2, 10, 30));

        Livewire::test(Facturation::class)
            ->set('formatExport', 'pdf')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertFileDownloaded('facturation_'.now()->format('Ymd_His').'.pdf')
            ->assertStatus(200);

        Carbon::setTestNow();
    }

    #[Test]
    public function facturation_genererexport_refuse_une_liste_vide(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        Livewire::test(Facturation::class)
            ->set('recherche', 'MECEF-INEXISTANT')
            ->call('genererExport')
            ->assertHasErrors('export');
    }

    // ===================================================== Comptabilité ===

    private function comptabiliteJeu(): ExerciceComptable
    {
        $exercice = ExerciceComptable::create([
            'annee' => 2026, 'date_debut' => '2026-01-01', 'date_fin' => '2026-12-31',
            'statut' => 'ouvert',
        ]);
        $vte = JournalComptable::create(['code' => 'VTE', 'libelle' => 'Ventes']);
        $structure = CentreCout::create(['libelle' => 'Structure', 'type' => 'support']);
        $banque = CompteComptable::create(['numero_compte' => '521000', 'libelle' => 'Banque', 'classe' => '5', 'nature' => 'actif']);
        $ventes = CompteComptable::create(['numero_compte' => '706100', 'libelle' => 'Prestations', 'classe' => '7', 'nature' => 'produit']);

        $service = app(EcritureComptableService::class);
        $piece = $service->enregistrerPiece([
            'exercice_id' => $exercice->id, 'journal_id' => $vte->id,
            'date_ecriture' => '2026-07-10', 'libelle' => 'Hébergement — test export',
        ], [
            ['compte_id' => $banque->id, 'centre_id' => $structure->id, 'debit' => '10000.00', 'credit' => '0.00'],
            ['compte_id' => $ventes->id, 'centre_id' => $structure->id, 'debit' => '0.00', 'credit' => '10000.00'],
        ]);
        $service->valider($piece);

        return $exercice;
    }

    #[Test]
    public function hub_exporterexcel_produit_le_journal(): void
    {
        $exercice = $this->comptabiliteJeu();
        // `rh` porte `M10 = 'L'` — la lecture seule doit suffire.
        $rh = $this->utilisateur('rh');
        $this->assertSame('L', $rh->niveauSurModule('M10'));
        $this->actingAs($rh);

        // L'API a changé avec l'export unifié (dérogation PO) : un bouton
        // « Exporter » ouvre la modale, le format se choisit dedans.
        Livewire::test(Hub::class, ['exercice' => $exercice->id])
            ->set('exerciceId', $exercice->id)
            ->set('onglet', 'journal')
            ->set('formatExport', 'excel')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertStatus(200);
    }

    #[Test]
    public function hub_exporterexcel_refuse_les_autres_onglets(): void
    {
        $exercice = $this->comptabiliteJeu();
        $this->actingAs($this->utilisateur('comptable'));

        Livewire::test(Hub::class, ['exercice' => $exercice->id])
            ->set('exerciceId', $exercice->id)
            ->set('onglet', 'balance')
            ->call('genererExport')
            ->assertHasErrors('export');
    }

    #[Test]
    public function hub_exporterexcel_refuse_sans_exercice_choisi(): void
    {
        $this->comptabiliteJeu();
        $this->actingAs($this->utilisateur('comptable'));

        // Depuis le sélecteur d'exercice global (20/10/2026), l'écran a
        // toujours un exercice par défaut : le refus porte sur un exercice
        // INTROUVABLE (identifiant d'URL inconnu), le seul « sans exercice »
        // qui reste.
        Livewire::test(Hub::class)
            ->set('onglet', 'journal')
            ->set('exerciceId', 'exercice-inconnu')
            ->call('genererExport')
            ->assertHasErrors('export');
    }
}
