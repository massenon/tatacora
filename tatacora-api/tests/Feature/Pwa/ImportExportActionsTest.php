<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ParcHebergementService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Shared\Backup\Services\ExportTableService;
use App\Shared\Backup\Services\ReinitialisationDonneesTestService;
use App\Shared\ImportExport\Data\ReferentielsImport;
use App\Shared\ImportExport\Models\JournalImport;
use App\Shared\ImportExport\Services\ControleImportService;
use App\Shared\ImportExport\Services\ImportReferentielsService;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Symfony\Component\Process\Process;
use Tests\TestCase;

/**
 * Import & Export — les QUATRE onglets, RÉELLEMENT exécutés (02/09/2026).
 *
 * Chaque cas exerce le geste complet, jamais un rendu seul : un import CSV
 * qui entre en base, un fichier fautif qui n'écrit RIEN (transaction unique),
 * une restauration d'archive qui change le statut réel, une purge refusée
 * avec son motif, une réinitialisation qui vide les tables transactionnelles
 * en préservant référentiels, comptes et journaux.
 *
 * ## Preuves par mutation (02/09/2026)
 *
 * - `l_import_est_tout_ou_rien…` : `DB::transaction()` retiré du corps
 *   d'`ImportReferentielsService::appliquer()` → ROUGE (la première boisson
 *   restait en base après le refus de la seconde) ; restauré → vert.
 * - `une_unite_engagee_ne_s_archive_pas…` : le verrou d'engagement commenté
 *   dans `ParcHebergementService::archiver()` → ROUGE (l'unité passait
 *   `hors_service` malgré sa réservation) ; restauré → vert.
 */
final class ImportExportActionsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    // =====================================================================
    // Onglet 1 — Importer
    // =====================================================================

    #[Test]
    public function le_modele_csv_vient_de_la_meme_declaration_que_le_controle(): void
    {
        $module = ReferentielsImport::parCle('m3-clients');
        $this->assertNotNull($module);

        // La déclaration porte les huit modules du maître — pas un de moins.
        $this->assertCount(8, ReferentielsImport::definitions());

        // Chaque colonne déclarée a un libellé et un exemple : c'est ce qui
        // remplit à la fois la fiche, le modèle et le contrôle.
        foreach ($module->colonnes as $colonne) {
            $this->assertNotSame('', $colonne->libelle);
            $this->assertNotSame('', $colonne->exemple);
        }
    }

    #[Test]
    public function un_import_csv_valide_entre_reellement_en_base_et_s_historise(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $csv = "Nom / Raison sociale;Type de client;Téléphone;Email\n"
            ."Agence Bénin Tour;agence;+229 01 97 00 00 00;contact@exemple.bj\n"
            ."NABOGOU Pascal;particulier;+229 01 97 11 22 33;\n";

        $composant = Livewire::test(ImportExport::class)
            ->set('moduleImport', 'm3-clients')
            ->set('fichierImport', UploadedFile::fake()->createWithContent('clients.csv', $csv))
            ->call('controlerFichierImport');

        $rapport = $composant->get('rapportControle');
        $this->assertTrue($rapport['ok'], 'Le fichier de test doit passer le contrôle.');
        $this->assertSame(2, $rapport['resume']['valides']);

        // Le contrôle N'IMPORTE RIEN (démarche du maître, étape 4).
        $this->assertSame(0, Client::count());

        $composant->call('confirmerImport');

        $this->assertSame(2, Client::count());
        $this->assertSame('agence', Client::where('nom', 'Agence Bénin Tour')->firstOrFail()->type_client);

        // L'historique est RÉEL : module, nombre de lignes, auteur.
        $entree = JournalImport::firstOrFail();
        $this->assertSame('m3-clients', $entree->module_cle);
        $this->assertSame(2, $entree->nombre_lignes);
        $this->assertNotNull($entree->utilisateur_id);
    }

    #[Test]
    public function un_fichier_fautif_est_refuse_au_controle_et_rien_n_est_ecrit(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        // « inconnu » est hors de l'énumération de la base ; la seconde ligne
        // est un doublon interne au fichier.
        $csv = "Nom / Raison sociale;Type de client;Téléphone\n"
            ."Client Un;inconnu;+229 01 00 00 00 01\n"
            ."Client Deux;agence;+229 01 00 00 00 02\n"
            ."Client Deux;agence;+229 01 00 00 00 03\n";

        $composant = Livewire::test(ImportExport::class)
            ->set('moduleImport', 'm3-clients')
            ->set('fichierImport', UploadedFile::fake()->createWithContent('clients.csv', $csv))
            ->call('controlerFichierImport');

        $rapport = $composant->get('rapportControle');
        $this->assertFalse($rapport['ok']);
        // Deux anomalies bloquantes : la valeur hors liste et le doublon —
        // chacune avec son numéro de ligne compté comme Excel.
        $this->assertSame([2, 4], array_column($rapport['erreurs'], 'ligne'));

        // Même en forçant la confirmation, le RECONTRÔLE refuse tout.
        $composant->call('confirmerImport');
        $this->assertSame(0, Client::count());
        $this->assertSame(0, JournalImport::count());
    }

    /**
     * AUCUN IMPORT PARTIEL — le refus d'UNE ligne par le domaine annule TOUT.
     *
     * Le contrôle passe (les deux articles existent), puis l'un des deux
     * disparaît avant l'application : la première boisson s'insère, la
     * seconde casse sur sa clé étrangère — et la transaction doit emporter
     * la première avec elle, historique compris.
     */
    #[Test]
    public function l_import_est_tout_ou_rien_meme_quand_le_domaine_refuse_apres_un_controle_vert(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $articleA = Article::create(['libelle' => 'Béninoise 66 cl', 'categorie' => 'Boissons', 'unite_mesure' => 'bouteille', 'seuil_alerte' => '5']);
        $articleB = Article::create(['libelle' => 'Coca 33 cl', 'categorie' => 'Boissons', 'unite_mesure' => 'bouteille', 'seuil_alerte' => '5']);

        $module = ReferentielsImport::parCle('m5-bar');
        $this->assertNotNull($module);

        $controle = app(ControleImportService::class);
        $rapport = $controle->controler($module, [
            ['Nom de la boisson', 'Catégorie', 'Prix de vente (FCFA)', 'Article de stock lié'],
            ['Béninoise 66 cl', 'locale', '1200', 'Béninoise 66 cl'],
            ['Coca 33 cl', 'importee', '600', 'Coca 33 cl'],
        ]);
        $this->assertTrue($rapport->ok);

        // L'état change ENTRE le contrôle et l'application — le cas TOCTOU.
        $articleB->delete();

        try {
            app(ImportReferentielsService::class)->appliquer($module, $rapport->lignes);
            $this->fail('Le lot aurait dû être refusé.');
        } catch (RuntimeException $refus) {
            // La ligne fautive est NOMMÉE, avec le numéro du fichier.
            $this->assertStringContainsString('Coca 33 cl', $refus->getMessage());
        }

        // Rien — ni la première boisson (pourtant valide), ni l'historique.
        $this->assertSame(0, CarteBoisson::count());
        $this->assertSame(0, JournalImport::count());
        $this->assertNotNull($articleA->fresh());
    }

    // =====================================================================
    // Onglet 2 — Sauvegardes / export d'une table
    // =====================================================================

    #[Test]
    public function l_export_d_une_table_rend_le_contenu_reel_et_refuse_les_tables_sensibles(): void
    {
        Client::create(['nom' => 'Client Export', 'telephone' => '+229 01 02 03 04 05', 'type_client' => 'particulier']);

        $service = app(ExportTableService::class);

        $json = $service->exporterJson('clients');
        $this->assertStringContainsString('Client Export', $json);

        // La liste est FERMÉE : ni les comptes, ni les jetons, ni le
        // technique framework.
        foreach (ExportTableService::TABLES_EXCLUES as $exclue) {
            $this->assertNotContains($exclue, $service->tablesExportables());
        }

        $this->expectException(RuntimeException::class);
        $service->exporterJson('utilisateurs');
    }

    /**
     * L'export d'une table est une LECTURE : un rôle en L sur PARAM (le
     * gérant) obtient son fichier — même famille que PA-119. Le délégué
     * `ouvrirFormulaire()` exigerait le niveau C, et c'est précisément
     * pourquoi `ouvrirExport()` ne l'emploie pas.
     */
    #[Test]
    public function un_role_en_lecture_sur_param_peut_exporter_une_table(): void
    {
        $this->actingAs($this->utilisateur('gerant'));

        Client::create(['nom' => 'Client Lecture', 'telephone' => '+229 01 00 00 00 12', 'type_client' => 'particulier']);

        Livewire::test(ImportExport::class)
            ->call('ouvrirExport')
            ->set('tableExport', 'clients')
            ->call('exporterTable')
            ->assertHasNoErrors()
            ->assertFileDownloaded('clients.json');
    }

    // =====================================================================
    // Onglet 3 — Restaurer
    // =====================================================================

    #[Test]
    public function une_unite_engagee_ne_s_archive_pas_et_le_verrou_est_celui_du_service(): void
    {
        $unite = $this->unite('BNG-01');
        $client = Client::create(['nom' => 'Client Verrou', 'telephone' => '+229 01 00 00 00 09', 'type_client' => 'particulier']);

        // Fixture de test : la réservation est posée directement, comme dans
        // les autres suites — le verrou RG-01 n'est pas l'objet de ce cas.
        Reservation::create([
            'client_id' => $client->id,
            'unite_id' => $unite->id,
            'date_arrivee' => now()->addDay()->toDateString(),
            'date_depart' => now()->addDays(3)->toDateString(),
            'statut' => 'confirmee',
        ]);

        try {
            app(ParcHebergementService::class)->archiver($unite);
            $this->fail('Une unité engagée ne doit pas s\'archiver.');
        } catch (RuntimeException) {
            // Le refus est motivé — et l'unité n'a pas bougé.
        }

        $this->assertSame('libre', $unite->fresh()->statut);
    }

    #[Test]
    public function l_onglet_restaurer_liste_les_archives_reelles_et_les_remet_en_place(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $unite = $this->unite('BNG-02');
        app(ParcHebergementService::class)->archiver($unite);
        $this->assertSame('hors_service', $unite->fresh()->statut);

        $composant = Livewire::test(ImportExport::class, ['onglet' => 'restaurer']);
        $composant->assertSee('BNG-02');

        $composant->call('restaurerArchive', 'unite_hebergement', $unite->id);

        // La restauration est RÉELLE — même chemin que l'écran M1.
        $this->assertSame('libre', $unite->fresh()->statut);

        // Et « Déjà restaurées » la retrouve depuis le JOURNAL (trait
        // Auditable), jamais depuis un drapeau dénormalisé (PA-126).
        $restaurees = app(\App\Shared\ImportExport\Services\RegistreArchivesService::class)->restaurees();
        $this->assertContains('BNG-02', array_column($restaurees, 'libelle'));
    }

    #[Test]
    public function la_purge_est_reservee_au_super_admin_et_refusee_sur_un_element_reference(): void
    {
        // Depuis le 03/09/2026 (directive PO), la purge est reservee au
        // SUPER_ADMIN : meme l'administrateur est refuse net — restaurer et
        // reinitialiser restent a lui, purger non.
        $this->actingAs($this->utilisateur('administrateur'));
        $vehicule = Vehicule::create(['immatriculation' => 'AB 0001 RB', 'categorie' => '4x4', 'annee' => 2022, 'tarif_jour' => '45000', 'statut' => 'hors_service']);

        Livewire::test(ImportExport::class)
            ->call('ouvrirPurge', 'vehicule', $vehicule->id)
            ->assertForbidden();

        // Le SUPER_ADMIN, lui, reçoit un REFUS MOTIVÉ sur un véhicule que
        // des contrats passés référencent encore (FK restrictOnDelete).
        $this->actingAs($admin = $this->utilisateur('super_admin'));

        $client = Client::create(['nom' => 'Client Contrat', 'telephone' => '+229 01 00 00 00 10', 'type_client' => 'particulier']);
        ContratLocation::create([
            'vehicule_id' => $vehicule->id,
            'client_id' => $client->id,
            'date_debut' => now()->subDays(10)->toDateString(),
            'date_fin' => now()->subDays(5)->toDateString(),
        ]);

        $composant = Livewire::test(ImportExport::class)
            ->call('ouvrirPurge', 'vehicule', $vehicule->id)
            ->call('purgerArchive');

        $composant->assertHasErrors('purge');
        $this->assertNotNull($vehicule->fresh(), 'Le véhicule référencé ne doit pas disparaître.');

        // Sans référence, la purge d'un élément ARCHIVÉ aboutit — le seul
        // endroit de l'application où une donnée disparaît vraiment.
        $unite = $this->unite('BNG-03');
        $unite->update(['statut' => 'hors_service']);

        Livewire::test(ImportExport::class)
            ->call('ouvrirPurge', 'unite_hebergement', $unite->id)
            ->call('purgerArchive')
            ->assertHasNoErrors();

        $this->assertNull(UniteHebergement::find($unite->id));
    }

    // =====================================================================
    // Onglet 4 — Réinitialiser
    // =====================================================================

    #[Test]
    public function la_reinitialisation_est_refusee_tant_que_la_bascule_serveur_est_fermee(): void
    {
        $service = app(ReinitialisationDonneesTestService::class);

        // Aucune clé en base : le défaut est FERMÉ — l'absence d'un réglage
        // n'ouvre jamais une fonction destructrice.
        $this->assertFalse($service->estOuverte());

        $this->expectException(RuntimeException::class);
        $service->executer($this->utilisateur('administrateur'));
    }

    #[Test]
    public function la_reinitialisation_vide_le_transactionnel_et_preserve_referentiels_comptes_et_journaux(): void
    {
        if (! $this->mysqldumpDisponible()) {
            $this->markTestSkipped('mysqldump introuvable : la sauvegarde préalable ne peut pas être éprouvée ici.');
        }

        $administrateur = $this->utilisateur('administrateur');
        $this->actingAs($administrateur);
        $this->ouvrirBascule();

        // Un référentiel, une donnée transactionnelle, un tiers.
        $unite = $this->unite('BNG-04');
        $client = Client::create(['nom' => 'Client Reset', 'telephone' => '+229 01 00 00 00 11', 'type_client' => 'particulier']);
        Reservation::create([
            'client_id' => $client->id,
            'unite_id' => $unite->id,
            'date_arrivee' => now()->addDay()->toDateString(),
            'date_depart' => now()->addDays(2)->toDateString(),
            'statut' => 'confirmee',
        ]);
        $utilisateursAvant = User::count();

        $resultat = app(ReinitialisationDonneesTestService::class)->executer($administrateur);

        $this->assertGreaterThan(0, $resultat['videes']);
        // La sauvegarde-filet a RÉELLEMENT été produite avant le vidage.
        $this->assertFileExists(storage_path('app/sauvegardes/'.$resultat['sauvegarde']));
        @unlink(storage_path('app/sauvegardes/'.$resultat['sauvegarde']));

        // Le transactionnel ET les tiers sont vidés (PO, 14/10/2026)…
        $this->assertSame(0, Reservation::count());
        $this->assertNull($client->fresh());
        // …les référentiels, les comptes et la trace restent.
        $this->assertNotNull($unite->fresh());
        $this->assertSame($utilisateursAvant, User::count());
        $this->assertSame(1, ParametreSysteme::where('cle', ReinitialisationDonneesTestService::CLE_BASCULE)->count());
    }

    /**
     * La garde de COHÉRENCE du partage préservé/effaçable : aucune table
     * préservée ne référence une table effaçable, à UNE exception nommée —
     * `utilisateurs.employe_id` (nullable), que le service remet à NULL avant
     * de vider `employes` (demande PO du 14/10/2026 : les employés se vident,
     * les comptes restent). Toute autre référence apparue demain doit être
     * arbitrée ici, pas découverte au premier vidage.
     */
    #[Test]
    public function aucune_table_preservee_ne_reference_une_table_effacable(): void
    {
        $service = app(ReinitialisationDonneesTestService::class);
        $preservees = $service->tablesPreservees();
        $effacables = $service->tablesEffacables();

        $this->assertNotSame([], $preservees);
        $this->assertNotSame([], $effacables);

        $references = DB::select(
            'SELECT TABLE_NAME AS source, REFERENCED_TABLE_NAME AS cible'
            .' FROM information_schema.KEY_COLUMN_USAGE'
            .' WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL',
        );

        $pendantes = [];
        foreach ($references as $reference) {
            if (in_array($reference->source, $preservees, true)
                && in_array($reference->cible, $effacables, true)) {
                $pendantes[] = $reference->source.' -> '.$reference->cible;
            }
        }

        $this->assertSame(['utilisateurs -> employes'], array_values(array_unique($pendantes)), implode("\n", $pendantes));
    }

    // =====================================================================
    // Rendu HTTP réel des quatre onglets — « une page HTML livrée vide que
    // seule une exécution réelle a révélée » (CLAUDE.md).
    // =====================================================================

    #[Test]
    public function les_quatre_onglets_sont_reellement_servis_dans_leurs_deux_etats(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (['importer', 'sauvegardes', 'restaurer', 'seeders'] as $onglet) {
            $this->get('/pwa/import-export?onglet='.$onglet)->assertOk();
        }

        // L'état VERROUILLÉ du quatrième onglet (bascule fermée) porte le
        // cadenas et le renvoi vers Paramètres…
        $html = (string) $this->get('/pwa/import-export?onglet=seeders')->assertOk()->getContent();
        $this->assertStringContainsString(e((string) __('pwa.import_export.seeders_verrouille_titre')), $html);

        // …et l'état OUVERT rend les deux listes dérivées du réel.
        $this->ouvrirBascule();
        $html = (string) $this->get('/pwa/import-export?onglet=seeders')->assertOk()->getContent();
        $this->assertStringContainsString(e((string) __('pwa.import_export.seeders_vide_titre')), $html);
        $this->assertStringContainsString(e((string) __('pwa.import_export.seeders_conserve_titre')), $html);
        $this->assertStringContainsString('journal_audit', $html);
        $this->assertStringContainsString('reservations', $html);
    }

    // ---------------------------------------------------------------- privé

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.import-export',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    private function unite(string $numero): UniteHebergement
    {
        $categorie = CategorieHebergement::firstOrCreate(
            ['libelle' => 'Bungalow'],
            ['tarif_base' => '25000', 'capacite_max' => 2],
        );

        return UniteHebergement::create([
            'numero' => $numero,
            'categorie_id' => $categorie->id,
            'statut' => 'libre',
        ]);
    }

    private function ouvrirBascule(): void
    {
        // La clé est posée directement : `RegistreParametres` ne la déclare
        // pas encore (lot « bascules d'activation », agent parallèle du
        // 02/09/2026) — le service la lit avec un défaut FERMÉ quoi qu'il
        // arrive.
        ParametreSysteme::create([
            'cle' => ReinitialisationDonneesTestService::CLE_BASCULE,
            'valeur' => '1',
        ]);
    }

    private function mysqldumpDisponible(): bool
    {
        $binaire = config('backup.mysqldump', 'mysqldump');
        $processus = new Process([$binaire, '--version']);
        $processus->setTimeout(15);
        $processus->run();

        return $processus->isSuccessful();
    }
}
