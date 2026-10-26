<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Models\User;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Shared\Backup\Services\ReinitialisationDonneesTestService;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\DemonstrationSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Symfony\Component\Process\Process;
use Tests\TestCase;

/**
 * « Réinitialiser comme neuf » — demande du Product Owner du 14/10/2026 (lot E).
 *
 * Le jeu de démonstration COMPLET est semé (`DemonstrationSeeder`, le même que
 * `db:seed --class=DemonstrationSeeder`), puis la réinitialisation est déclenchée par le CHEMIN DE
 * L'ÉCRAN (composant Livewire, saisie du mot de confirmation) et vérifiée
 * TABLE PAR TABLE : chaque table gardée reste peuplée, chaque table vidée
 * est vide — y compris les tiers que la version du 02/09/2026 préservait
 * (clients, employés, fournisseurs, guides) et les tables de framework que
 * le PO a nommées (cache, cache_locks, failed_jobs).
 */
final class ReinitialisationCommeNeufTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Les tables GARDÉES que la démonstration peuple — elles doivent rester
     * non vides après la réinitialisation.
     */
    private const GARDEES_PEUPLEES = [
        'utilisateurs', 'roles', 'permissions', 'permission_role', 'parametres_systeme',
        'journal_audit',
        'categories_hebergement', 'unites_hebergement', 'canaux_reservation',
        'points_stockage', 'tables_salle',
        'vehicules', 'circuits',
        'plan_comptable', 'journaux_comptables', 'exercices_comptables', 'centres_cout',
        'services', 'modeles_notification',
    ];

    /**
     * Les tables VIDÉES que la démonstration peuple — non vides AVANT (sinon
     * le test passerait à vide), vides APRÈS.
     */
    private const VIDEES_PEUPLEES = [
        'clients', 'employes', 'fournisseurs', 'guides',
        'reservations', 'mouvements_stock', 'ecritures_comptables',
        'ventes', 'lignes_vente', 'commandes_achat', 'depenses',
        'contrats_location', 'reservations_tour', 'sessions_caisse',
        'factures', 'commandes_restaurant', 'inventaires',
        // Correction du PO : le catalogue (et ses jointures) se vide aussi.
        'articles', 'menus', 'recettes', 'ingredients_recette', 'plats', 'cartes_boisson',
        'cache', 'cache_locks', 'failed_jobs',
    ];

    #[Test]
    public function la_demonstration_complete_est_videe_comme_neuve_et_les_referentiels_gardes(): void
    {
        if (! $this->mysqldumpDisponible()) {
            $this->markTestSkipped('mysqldump introuvable : la sauvegarde préalable ne peut pas être éprouvée ici.');
        }

        $this->seed(DemonstrationSeeder::class);
        $this->peuplerFramework();
        $administrateur = $this->utilisateur('administrateur');
        $this->ouvrirBascule();

        foreach (self::VIDEES_PEUPLEES as $table) {
            $this->assertGreaterThan(0, DB::table($table)->count(), "La démonstration ne peuple pas `{$table}` : le cas passerait à vide.");
        }

        $this->actingAs($administrateur);

        Livewire::test(ImportExport::class, ['onglet' => 'seeders'])
            ->call('ouvrirReinitialisation')
            ->set('phraseConfirmationReset', 'vider')
            ->call('reinitialiserDonneesTest')
            ->assertHasNoErrors();

        // Chaque table vidée est VIDE — mesurée sur la base, pas sur la liste.
        $service = app(ReinitialisationDonneesTestService::class);
        foreach ($service->tablesEffacables() as $table) {
            $this->assertSame(0, DB::table($table)->count(), "`{$table}` n'a pas été vidée.");
        }

        foreach (self::VIDEES_PEUPLEES as $table) {
            $this->assertContains($table, $service->tablesEffacables());
        }

        // Chaque table gardée reste PEUPLÉE.
        foreach (self::GARDEES_PEUPLEES as $table) {
            $this->assertContains($table, $service->tablesPreservees());
            $this->assertGreaterThan(0, DB::table($table)->count(), "`{$table}` devait être gardée.");
        }

        // Les comptes survivent, détachés des fiches employé vidées.
        $this->assertSame(0, DB::table('utilisateurs')->whereNotNull('employe_id')->count());
        $this->assertNotNull(User::find($administrateur->id));

        // Aucun statut opérationnel ne survit à son support.
        $this->assertSame(0, DB::table('unites_hebergement')->whereIn('statut', ['occupee', 'reservee', 'nettoyage'])->count());
        $this->assertSame(0, DB::table('vehicules')->where('statut', 'loue')->count());

        // RG-15 : la réinitialisation est écrite au journal d'audit gardé.
        $trace = DB::table('journal_audit')
            ->where('action', 'Réinitialisation')
            ->where('utilisateur_id', $administrateur->id)
            ->first();
        $this->assertNotNull($trace);

        /** @var array{sauvegarde: string} $apres */
        $apres = json_decode((string) $trace->valeur_apres, true);
        $this->assertFileExists(storage_path('app/sauvegardes/'.$apres['sauvegarde']));
        @unlink(storage_path('app/sauvegardes/'.$apres['sauvegarde']));
    }

    #[Test]
    public function l_ordre_de_vidage_place_chaque_enfant_avant_son_parent(): void
    {
        $service = app(ReinitialisationDonneesTestService::class);
        $ordre = array_flip($service->ordreDeVidage());

        $this->assertSame(count($service->tablesEffacables()), count($ordre));

        $references = DB::select(
            'SELECT TABLE_NAME AS source, REFERENCED_TABLE_NAME AS cible FROM information_schema.KEY_COLUMN_USAGE'
            .' WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL',
        );

        foreach ($references as $reference) {
            if ($reference->source !== $reference->cible
                && isset($ordre[$reference->source], $ordre[$reference->cible])) {
                $this->assertLessThan(
                    $ordre[$reference->cible],
                    $ordre[$reference->source],
                    "`{$reference->source}` doit être vidée avant `{$reference->cible}`.",
                );
            }
        }
    }

    #[Test]
    public function la_reinitialisation_est_refusee_hors_administration(): void
    {
        $this->seed(RolePermissionSeeder::class);
        $this->ouvrirBascule();
        $client = $this->client();
        $gerant = $this->utilisateur('gerant');

        // Le service refuse, quel que soit le chemin d'appel…
        try {
            app(ReinitialisationDonneesTestService::class)->executer($gerant);
            $this->fail('Un gérant a pu réinitialiser.');
        } catch (RuntimeException $refus) {
            $this->assertSame(__('pwa.import_export.reset_refuse_role'), $refus->getMessage());
        }

        // …et l'écran refuse d'ouvrir la modale comme d'exécuter.
        $this->actingAs($gerant);
        Livewire::test(ImportExport::class, ['onglet' => 'seeders'])
            ->call('ouvrirReinitialisation')
            ->assertForbidden();
        Livewire::test(ImportExport::class, ['onglet' => 'seeders'])
            ->set('phraseConfirmationReset', 'VIDER')
            ->call('reinitialiserDonneesTest')
            ->assertForbidden();

        $this->assertNotNull($client->fresh());
    }

    #[Test]
    public function la_reinitialisation_est_refusee_en_production(): void
    {
        $this->seed(RolePermissionSeeder::class);
        $this->ouvrirBascule();
        $client = $this->client();
        $administrateur = $this->utilisateur('administrateur');

        $this->app->detectEnvironment(static fn (): string => 'production');
        $this->assertTrue(app()->isProduction());

        $this->actingAs($administrateur);
        Livewire::test(ImportExport::class, ['onglet' => 'seeders'])
            ->set('phraseConfirmationReset', 'VIDER')
            ->call('reinitialiserDonneesTest')
            ->assertHasErrors('phraseConfirmationReset');

        $this->assertNotNull($client->fresh());

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage((string) __('pwa.import_export.reset_refuse_production'));
        app(ReinitialisationDonneesTestService::class)->executer($administrateur);
    }

    #[Test]
    public function la_reinitialisation_est_refusee_sans_le_mot_de_confirmation(): void
    {
        $this->seed(RolePermissionSeeder::class);
        $this->ouvrirBascule();
        $client = $this->client();

        $this->actingAs($this->utilisateur('administrateur'));

        foreach (['', 'OUI', 'VIDE'] as $saisie) {
            Livewire::test(ImportExport::class, ['onglet' => 'seeders'])
                ->call('ouvrirReinitialisation')
                ->set('phraseConfirmationReset', $saisie)
                ->call('reinitialiserDonneesTest')
                ->assertHasErrors('phraseConfirmationReset');
        }

        $this->assertNotNull($client->fresh());
    }

    // ---------------------------------------------------------------- privé

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.reinitialisation-'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    private function client(): Client
    {
        return Client::create([
            'nom' => 'Client Témoin',
            'telephone' => '+229 01 00 00 00 12',
            'type_client' => 'particulier',
        ]);
    }

    private function ouvrirBascule(): void
    {
        ParametreSysteme::updateOrCreate(
            ['cle' => ReinitialisationDonneesTestService::CLE_BASCULE],
            ['valeur' => 'true'],
        );
    }

    /**
     * Les tables de framework nommées par le PO — la démonstration ne les
     * peuple pas, le test le fait pour qu'elles prouvent quelque chose.
     */
    private function peuplerFramework(): void
    {
        DB::table('cache')->insert(['key' => 'temoin', 'value' => 's:1:"x";', 'expiration' => time() + 3600]);
        DB::table('cache_locks')->insert(['key' => 'verrou-temoin', 'owner' => 'test', 'expiration' => time() + 3600]);
        DB::table('failed_jobs')->insert([
            'uuid' => (string) Str::uuid(),
            'connection' => 'database',
            'queue' => 'default',
            'payload' => '{}',
            'exception' => 'temoin',
        ]);
    }

    private function mysqldumpDisponible(): bool
    {
        $processus = new Process([config('backup.mysqldump', 'mysqldump'), '--version']);
        $processus->setTimeout(15);
        $processus->run();

        return $processus->isSuccessful();
    }
}
