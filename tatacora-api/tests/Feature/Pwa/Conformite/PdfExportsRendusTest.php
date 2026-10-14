<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Domain\Crm\Models\Client;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Service as ServiceRh;
use App\Domain\Rh\Services\BulletinPaieService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\InventaireService;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Pwa\Livewire\Comptabilite\Hub as HubComptabilite;
use App\Pwa\Livewire\Crm\ClientsCreances;
use App\Pwa\Livewire\Notifications\Hub as HubNotifications;
use App\Pwa\Livewire\Rh\Paie;
use App\Pwa\Livewire\Stocks\Inventaires;
use App\Pwa\Livewire\Stocks\Stocks;
use App\Shared\Rbac\Models\Role;
use App\Shared\ReportEngine\Data\EnTeteRapport;
use ArrayObject;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\View;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Domain\Rh\Concerns\PoseLeReferentielDePaie;
use Tests\TestCase;

/**
 * Les six exports PDF qu'AUCUN test ne rendait — mesuré le 11/09/2026 (PA-194)
 * en traçant les vues `pdf.*` rendues par les seize fichiers de test qui
 * appellent un export : `comptabilite-journal-rapport`, `fiche-stock`,
 * `inventaire-rapport`, `notifications`, `paie` et `stocks-etat` n'y
 * figuraient pas.
 *
 * `PdfExportConformiteTest` relit le SOURCE des gabarits : il ne voit pas un
 * écran qui oublie de passer `entete` — le document lèverait « Undefined
 * variable $entete » au premier clic, et la garde resterait verte. Ces cas
 * exécutent donc réellement le chemin de l'écran jusqu'à dompdf, et relèvent
 * au passage ce que les trois partiels ont reçu : l'en-tête RG-19 porte le
 * titre du document, et la zone de signatures et le pied sont bien rendus.
 *
 * S'y ajoutent deux documents REMIS AU CLIENT qu'aucun test ne rendait non
 * plus — le relevé client et le bulletin de paie : identité prise à la source
 * unique, et AUCUN visa (règle de PA-194).
 *
 * @see RG-19 Entête normalisée obligatoire sur tout état édité
 */
final class PdfExportsRendusTest extends TestCase
{
    use PoseLeReferentielDePaie;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs($this->administrateur());
    }

    #[Test]
    public function l_etat_des_stocks_est_rendu_avec_l_en_tete_rg19(): void
    {
        [$article, $point] = $this->articleEnStock();
        $rendu = $this->capturer();

        Livewire::test(Stocks::class)
            ->set('formatExport', 'pdf')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertStatus(200);

        $this->assertRenduConforme($rendu, __('stocks_pwa.export.document_stocks'));
    }

    #[Test]
    public function la_fiche_de_stock_est_rendue_avec_l_en_tete_rg19(): void
    {
        [$article] = $this->articleEnStock();
        $rendu = $this->capturer();

        Livewire::test(Inventaires::class)
            ->set('onglet', 'fiche')
            ->set('articleId', $article->id)
            ->set('formatExport', 'pdf')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertStatus(200);

        $this->assertRenduConforme($rendu, __('stocks_pwa.export.document_fiche', ['article' => $article->libelle]));
    }

    #[Test]
    public function le_rapport_d_inventaire_est_rendu_avec_l_en_tete_rg19(): void
    {
        [$article, $point] = $this->articleEnStock();
        $inventaires = app(InventaireService::class);
        $inventaire = $inventaires->ouvrir($point);
        $inventaires->compter($inventaire, $article, '6.00');
        $rendu = $this->capturer();

        Livewire::test(Inventaires::class)
            ->set('onglet', 'inventaire')
            ->set('formatExport', 'pdf')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertStatus(200);

        $this->assertRenduConforme($rendu, __('stocks_pwa.export.document_inventaire'));
        // La période de l'en-tête nomme le magasin inventorié.
        $this->assertStringContainsString('Magasin général', $rendu['entete']->periode);
    }

    #[Test]
    public function le_journal_comptable_est_rendu_avec_l_en_tete_rg19(): void
    {
        $exercice = $this->exerciceAvecUnePiece();
        $rendu = $this->capturer();

        Livewire::test(HubComptabilite::class, ['exercice' => $exercice->id])
            ->set('exerciceId', $exercice->id)
            ->set('onglet', 'journal')
            ->set('formatExport', 'pdf')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertStatus(200);

        $this->assertRenduConforme($rendu, __('comptabilite_pwa.export_journal_titre'));
        $this->assertSame(__('rapports.periode.exercice', ['annee' => 2026]), $rendu['entete']->periode);
    }

    #[Test]
    public function l_export_des_notifications_est_rendu_avec_l_en_tete_rg19(): void
    {
        $rendu = $this->capturer();

        // `declencheurs` vient du registre : il a des lignes sans rien semer.
        Livewire::test(HubNotifications::class)
            ->set('onglet', 'declencheurs')
            ->set('formatExport', 'pdf')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertStatus(200);

        $this->assertRenduConforme($rendu, null);
    }

    #[Test]
    public function l_export_de_la_paie_est_rendu_avec_l_en_tete_rg19(): void
    {
        $rendu = $this->capturer();

        // `livre` rend ses totaux même sur une période sans bulletin.
        Livewire::test(Paie::class)
            ->set('periode', '2026-07')
            ->set('onglet', 'livre')
            ->set('formatExport', 'pdf')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertStatus(200);

        $this->assertRenduConforme($rendu, null);
    }

    // ============================================ Documents remis au client ===

    /**
     * Le relevé est remis au CLIENT : l'en-tête RG-19, mais ni visa ni pied
     * de rapport. Il imprimait jusqu'ici un second téléphone que les
     * paramètres ne portent pas (PA-194).
     */
    #[Test]
    public function le_releve_client_prend_l_en_tete_rg19_sans_visa(): void
    {
        $client = Client::create([
            'nom' => 'Agence Bénin Tour', 'prenom' => null,
            'telephone' => '01 21 45 67 89', 'type_client' => 'agence',
        ]);
        $rendu = $this->capturer();

        Livewire::test(ClientsCreances::class)
            ->set('historiqueClientId', $client->id)
            ->call('imprimerReleveClient')
            ->assertHasNoErrors()
            ->assertStatus(200);

        $this->assertSame(['pdf.partials.entete-rapport'], array_values(array_unique($rendu['partiels'])));
        $this->assertSame(__('pwa.clients.releve_document'), $rendu['entete']->typeRapport);
        $this->assertSame($client->nomComplet(), $rendu['entete']->periode);
    }

    /**
     * Le bulletin garde sa mise en page ; son identité vient désormais de
     * `ReportHeaderService`, et il ne porte aucun visa.
     */
    #[Test]
    public function le_bulletin_de_paie_prend_l_identite_a_la_source_unique(): void
    {
        $this->poserLeReferentielDePaie();
        $employe = Employe::create([
            'matricule' => 'EMP-2026-'.random_int(10000, 99999),
            'nom' => 'HOUNSOU', 'prenom' => 'Marceline', 'poste' => 'Réceptionniste',
            'service_id' => ServiceRh::firstOrCreate(['libelle' => 'Réception'])->id,
            'date_embauche' => '2023-02-01', 'salaire_base' => '150000.00', 'statut' => 'actif',
        ]);
        $bulletin = app(BulletinPaieService::class)->etablirBulletin($employe, '2026-07');
        $rendu = $this->capturer(['pdf.*']);

        Livewire::test(Paie::class)
            ->call('exporterPdf', $bulletin->id)
            ->assertStatus(200);

        // Aucun partiel d'export : ni en-tête de rapport, ni visa, ni pied.
        $this->assertSame(['pdf.paie-bulletin'], array_values(array_unique($rendu['partiels'])));
        $this->assertInstanceOf(EnTeteRapport::class, $rendu['entete']);
        $this->assertSame(__('rh_pwa.bulletin_entete'), $rendu['entete']->typeRapport);
    }

    // =================================================================

    /**
     * Relève ce que les trois partiels de la Directive §6 ont réellement
     * reçu au rendu.
     *
     * @param  list<string>  $vues
     * @return ArrayObject<string, mixed>
     */
    private function capturer(array $vues = ['pdf.partials.entete-rapport', 'pdf.partials.signatures', 'pdf.partials.pied-rapport']): ArrayObject
    {
        /** @var ArrayObject<string, mixed> $rendu */
        $rendu = new ArrayObject(['partiels' => []]);

        View::composer(
            $vues,
            static function (\Illuminate\View\View $vue) use ($rendu): void {
                $partiels = $rendu['partiels'];
                $partiels[] = $vue->getName();
                $rendu['partiels'] = $partiels;
                $rendu['entete'] = $vue->getData()['entete'] ?? null;
            },
        );

        return $rendu;
    }

    /** @param  ArrayObject<string, mixed>  $rendu */
    private function assertRenduConforme(ArrayObject $rendu, ?string $titre): void
    {
        $this->assertSame(
            ['pdf.partials.entete-rapport', 'pdf.partials.signatures', 'pdf.partials.pied-rapport'],
            array_values(array_unique($rendu['partiels'])),
            'L\'en-tête, la zone de signatures et le pied doivent être rendus, dans cet ordre.',
        );
        $this->assertInstanceOf(EnTeteRapport::class, $rendu['entete']);
        $this->assertNotSame('', $rendu['entete']->typeRapport);
        $this->assertNotSame('', $rendu['entete']->periode);

        if ($titre !== null) {
            $this->assertSame($titre, $rendu['entete']->typeRapport);
        }
    }

    private function administrateur(): User
    {
        return User::create([
            'login' => 'admin.pdf.'.Str::random(4),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /** @return array{Article, PointStockage} */
    private function articleEnStock(): array
    {
        $point = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        $article = Article::create([
            'libelle' => 'Riz local (sac 50 kg)',
            'categorie' => 'Denrées',
            'unite_mesure' => 'sac',
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '12.00',
            'cout_moyen_pondere' => '0.0000',
        ]);
        app(MouvementStockService::class)->entree($article->id, $point->id, '10.00', 'Réception', '1000.00');

        return [$article, $point];
    }

    private function exerciceAvecUnePiece(): ExerciceComptable
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
}
