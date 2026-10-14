<?php

declare(strict_types=1);

namespace Tests\Feature\Planification;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Jobs\RejouerCertificationsMecefEnEchecJob;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Stocks\Events\SeuilStockAtteint;
use App\Domain\Stocks\Jobs\VerifierSeuilsStockJob;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Shared\Audit\Jobs\PurgerJournalAuditJob;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Backup\Jobs\SauvegardeBaseQuotidienneJob;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Jobs\NettoyerDeduplicationSyncJob;
use App\Shared\Sync\Models\DeduplicationSynchronisation;
use App\Shared\Sync\Services\SynchronisationService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Tâches planifiées — LISTE_DES_CRON_JOBS_CPANEL.md.
 *
 * Comble une catégorie de NFR qui était entièrement à zéro : sauvegarde,
 * alertes planifiées, purges de rétention.
 */
final class TachesPlanifieesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    // ------------------------------------------------------- Planification

    #[Test]
    public function les_taches_implementees_sont_bien_planifiees(): void
    {
        $planifiees = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())
            ->map(fn ($evenement): string => $evenement->getSummaryForDisplay())
            ->implode(' | ');

        foreach ([
            VerifierSeuilsStockJob::class,
            RejouerCertificationsMecefEnEchecJob::class,
            SauvegardeBaseQuotidienneJob::class,
            NettoyerDeduplicationSyncJob::class,
            PurgerJournalAuditJob::class,
        ] as $job) {
            $this->assertStringContainsString($job, $planifiees, "{$job} n'est pas planifié.");
        }

        // Contournement cPanel : pas de worker persistant, la file est vidée
        // par salves d'une minute.
        $this->assertStringContainsString('queue:work', $planifiees);
    }

    /**
     * Les trois tâches dont le domaine n'est pas implémenté ne doivent PAS
     * être planifiées : une tâche qui s'exécute sans rien faire rend le
     * planning faussement complet.
     */
    #[Test]
    public function les_taches_sans_domaine_implemente_ne_sont_pas_planifiees(): void
    {
        $planifiees = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())
            ->map(fn ($evenement): string => $evenement->getSummaryForDisplay())
            ->implode(' | ');

        foreach (['SyntheseQuotidienne', 'ExecuterEtatsPlanifies', 'VerifierCouvertureConges'] as $absente) {
            $this->assertStringNotContainsString($absente, $planifiees);
        }
    }

    // ----------------------------------------------------------- RG-07

    #[Test]
    public function rg07_le_job_de_seuil_alerte_sur_les_articles_critiques(): void
    {
        Event::fake([SeuilStockAtteint::class]);
        $this->actingAs($this->utilisateur('magasinier'));

        $point = PointStockage::create(['libelle' => 'Magasin', 'type' => 'magasin']);
        $article = $this->article('Riz', seuil: '10.00');
        app(MouvementStockService::class)->entree($article->id, $point->id, '3.00', 'Réception');

        $nb = (new VerifierSeuilsStockJob())->handle(app(\App\Domain\Stocks\Services\VerificationSeuilService::class));

        $this->assertSame(1, $nb);
        Event::assertDispatched(SeuilStockAtteint::class);
    }

    /**
     * Le cas que la vérification synchrone ne peut pas couvrir : un seuil
     * relevé sans qu'aucun mouvement ne survienne.
     */
    #[Test]
    public function rg07_un_seuil_releve_sans_mouvement_est_detecte_par_le_job(): void
    {
        $this->actingAs($this->utilisateur('magasinier'));

        $point = PointStockage::create(['libelle' => 'Magasin', 'type' => 'magasin']);
        $article = $this->article('Riz', seuil: '5.00');
        app(MouvementStockService::class)->entree($article->id, $point->id, '20.00', 'Réception');

        // Stock 20, seuil 5 : rien à signaler.
        $this->assertSame(0, (new VerifierSeuilsStockJob())->handle(app(\App\Domain\Stocks\Services\VerificationSeuilService::class)));

        // Le gestionnaire relève le seuil à 25 — aucun mouvement n'a lieu.
        $article->update(['seuil_alerte' => '25.00']);

        $this->assertSame(1, (new VerifierSeuilsStockJob())->handle(app(\App\Domain\Stocks\Services\VerificationSeuilService::class)));
    }

    // ----------------------------------------------------------- RG-03

    #[Test]
    public function rg03_le_job_rejoue_les_certifications_en_echec(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        $facture = Facture::create([
            'client_id' => Client::factory()->create()->id,
            'date_emission' => '2026-08-01',
            'montant_ht' => '100000.00', 'montant_tva' => '0.00', 'montant_ttc' => '100000.00',
            'statut' => 'echec_certification',
        ]);

        $bilan = (new RejouerCertificationsMecefEnEchecJob())->handle(
            app(\App\Domain\Facturation\Services\EmissionFactureService::class),
        );

        $this->assertSame(1, $bilan['certifiees']);
        $this->assertSame('certifiee', $facture->fresh()->statut);
        $this->assertNotNull($facture->fresh()->numero_mecef);
    }

    #[Test]
    public function rg03_une_facture_deja_certifiee_n_est_pas_rejouee(): void
    {
        $this->actingAs($this->utilisateur('comptable'));

        Facture::create([
            'client_id' => Client::factory()->create()->id,
            'date_emission' => '2026-08-01',
            'montant_ht' => '100000.00', 'montant_tva' => '0.00', 'montant_ttc' => '100000.00',
            'statut' => 'certifiee', 'numero_mecef' => 'MECEF-DEMO-EXISTANT',
        ]);

        $bilan = (new RejouerCertificationsMecefEnEchecJob())->handle(
            app(\App\Domain\Facturation\Services\EmissionFactureService::class),
        );

        // Un rejeu écraserait un NIM déjà obtenu (RG-03).
        $this->assertSame(0, $bilan['tentees']);
    }

    // ----------------------------------------------------- Idempotence sync

    #[Test]
    public function le_job_purge_la_memoire_d_idempotence_expiree(): void
    {
        $utilisateur = $this->utilisateur('receptionniste');

        DeduplicationSynchronisation::create([
            'uuid_operation' => (string) Str::uuid(), 'utilisateur_id' => $utilisateur->id,
            'poste_id' => 'p1', 'table_concernee' => 'clients', 'entite_id' => (string) Str::uuid(),
            'resultat' => ['statut' => 'synchronise'],
            'date_traitement' => now()->subDays(SynchronisationService::TTL_DEDUPLICATION_JOURS + 1),
        ]);
        DeduplicationSynchronisation::create([
            'uuid_operation' => (string) Str::uuid(), 'utilisateur_id' => $utilisateur->id,
            'poste_id' => 'p1', 'table_concernee' => 'clients', 'entite_id' => (string) Str::uuid(),
            'resultat' => ['statut' => 'synchronise'],
            'date_traitement' => now()->subDay(),
        ]);

        $purgees = (new NettoyerDeduplicationSyncJob())->handle(app(SynchronisationService::class));

        // Seule l'entrée expirée part : purger trop tôt ferait re-executer les
        // opérations d'un poste resté hors connexion.
        $this->assertSame(1, $purgees);
        $this->assertSame(1, DeduplicationSynchronisation::count());
    }

    // ------------------------------------------------------------- PA-08

    /**
     * Le job de purge d'audit doit rester INERTE tant que la durée de
     * rétention contractuelle n'est pas définie.
     */
    #[Test]
    public function pa08_la_purge_d_audit_ne_supprime_rien_sans_duree_definie(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        Client::factory()->create();
        JournalAudit::query()->update(['date_heure' => now()->subYears(5)]);

        $bilan = (new PurgerJournalAuditJob())->handle(app(\App\Shared\Parametres\Services\ParametreSystemeService::class));

        // Une valeur par defaut, meme « raisonnable », detruirait des traces
        // dont la conservation est une obligation contractuelle.
        $this->assertFalse($bilan['actif']);
        $this->assertSame(0, $bilan['purgees']);
        $this->assertGreaterThan(0, JournalAudit::count());
    }

    #[Test]
    public function pa08_la_purge_s_active_des_que_la_duree_est_renseignee(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        Client::factory()->create();
        JournalAudit::query()->update(['date_heure' => now()->subYears(5)]);

        ParametreSysteme::create([
            'cle' => PurgerJournalAuditJob::CLE_RETENTION,
            'valeur' => '365',
            'description' => 'Durée de rétention du journal d\'audit, en jours.',
        ]);

        $bilan = (new PurgerJournalAuditJob())->handle(app(\App\Shared\Parametres\Services\ParametreSystemeService::class));

        $this->assertTrue($bilan['actif']);
        $this->assertGreaterThan(0, $bilan['purgees']);
    }

    // ---------------------------------------------------------- Sauvegarde

    #[Test]
    public function la_commande_de_sauvegarde_cible_la_base_configuree(): void
    {
        $commande = (new SauvegardeBaseQuotidienneJob())->commande('/tmp/test.sql');

        $this->assertStringContainsString('mysqldump', $commande[0]);
        $this->assertContains('--single-transaction', $commande);
        $this->assertContains('--result-file=/tmp/test.sql', $commande);
        // La base de test, pas une base codee en dur.
        $this->assertSame(config('database.connections.mysql.database'), end($commande));
    }

    #[Test]
    public function la_commande_est_un_tableau_d_arguments_jamais_une_chaine_shell(): void
    {
        // Un mot de passe contenant des metacaracteres ne doit pas pouvoir
        // s'echapper de la commande.
        config(['database.connections.mysql.password' => 'mot;de$passe`bizarre']);

        $commande = (new SauvegardeBaseQuotidienneJob())->commande('/tmp/test.sql');

        // Le mot de passe est transmis comme UN argument entier, jamais
        // concatene dans une chaine que le shell interpreterait.
        $this->assertContains('--password=mot;de$passe`bizarre', $commande);
    }

    // ------------------------------------------------------------- Helpers

    private function article(string $libelle, string $seuil): Article
    {
        return Article::create([
            'libelle' => $libelle, 'categorie' => 'denree', 'unite_mesure' => 'kg',
            'seuil_alerte' => $seuil, 'seuil_reappro' => '50.00', 'cout_moyen_pondere' => '800.0000',
        ]);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
