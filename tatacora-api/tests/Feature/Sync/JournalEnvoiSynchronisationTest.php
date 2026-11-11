<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Permission;
use App\Shared\Sync\Models\EtatPosteSynchronisation;
use App\Shared\Sync\Models\JournalEnvoiSynchronisation;
use App\Shared\Sync\Services\CatalogueDescendantService;
use App\Shared\Sync\Services\JournalEnvoiService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le journal d'ENVOI (26/10/2026) : ce que `GET /api/v1/referentiels` livre à
 * chaque poste — éléments par table, curseur rendu, tables non livrées faute
 * de droit, refus « génération périmée » — et « Redescendre depuis le début »,
 * qui fait ignorer au serveur le curseur du poste au prochain passage.
 */
final class JournalEnvoiSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-26 08:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->admin = $this->creerUtilisateur('administrateur');

        PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        foreach (['Riz', 'Huile', 'Sel'] as $libelle) {
            Article::create([
                'libelle' => $libelle, 'categorie' => 'test', 'unite_mesure' => 'kg',
                'seuil_alerte' => '0.00', 'seuil_reappro' => '10.00', 'cout_moyen_pondere' => '500.0000',
            ]);
        }

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
    }

    #[Test]
    public function chaque_passage_est_consigne_par_poste_et_par_table(): void
    {
        $page = $this->telecharger($this->admin, 'poste-a');

        $livres = JournalEnvoiSynchronisation::where('poste_id', 'poste-a')->pluck('livres_total', 'table_concernee')->all();
        $this->assertSame(3, $livres['articles']);
        $this->assertSame(1, $livres['points_stockage']);
        $this->assertSame(3, JournalEnvoiSynchronisation::where('poste_id', 'poste-a')->where('table_concernee', 'articles')->value('dernier_passage_nb'));

        $etat = EtatPosteSynchronisation::where('poste_id', 'poste-a')->sole();
        $this->assertSame($page->json('meta.curseur'), $etat->curseur_descente);
        $this->assertSame((bool) $page->json('meta.complet'), $etat->descente_complete);
        $this->assertNotNull($etat->derniere_descente_le);

        // Un second passage ne livre rien de neuf : le total ne bouge pas.
        $this->telecharger($this->admin, 'poste-a', $page->json('meta.curseur'));
        $this->assertSame(3, JournalEnvoiSynchronisation::where('poste_id', 'poste-a')->where('table_concernee', 'articles')->value('livres_total'));

        // Un autre poste a son propre compte.
        $this->assertSame(0, JournalEnvoiSynchronisation::where('poste_id', 'poste-b')->count());
    }

    #[Test]
    public function le_detail_dit_ce_qui_reste_a_livrer_apres_le_curseur_rendu(): void
    {
        $total = count($this->telecharger($this->admin, 'poste-b')->json('data.elements'));
        $this->telecharger($this->admin, 'poste-a', limite: 2);

        $detail = app(JournalEnvoiService::class)->detail('poste-a', app(CatalogueDescendantService::class));
        $restants = array_sum(array_column($detail['tables'], 'restants'));

        // Tout le flux compte N éléments ; 2 ont été livrés, N - 2 restent.
        $this->assertSame($total - 2, $restants);
        $this->assertNotNull($detail['curseur']);
    }

    #[Test]
    public function les_tables_non_livrees_faute_de_droit_sont_comptees_puis_levees(): void
    {
        $receptionniste = $this->creerUtilisateur('guide');
        $this->telecharger($receptionniste, 'poste-r');

        // Le rôle « guide » ne lit pas M6 (stocks) : il n'est pas lisible : les articles existent, ne sont pas livrés.
        $ligne = JournalEnvoiSynchronisation::where(['poste_id' => 'poste-r', 'table_concernee' => 'articles'])->sole();
        $this->assertSame(3, $ligne->en_attente_droits);
        $this->assertSame(0, $ligne->livres_total);

        // Le droit est accordé : le compte repasse à zéro, et les articles descendent.
        $receptionniste->role->permissions()->attach(Permission::where(['module' => 'M6', 'action' => 'lire'])->value('id'));
        $receptionniste->unsetRelation('role');
        $this->app['auth']->forgetGuards();

        $this->telecharger(User::findOrFail($receptionniste->id), 'poste-r');

        $ligne->refresh();
        $this->assertSame(0, $ligne->en_attente_droits);
        $this->assertSame(3, $ligne->livres_total);
    }

    #[Test]
    public function un_refus_generation_perimee_est_compte_pour_le_poste(): void
    {
        Sanctum::actingAs($this->admin);

        $this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-a', 'generation' => 'ancienne']))->assertStatus(409);
        $this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-a', 'generation' => 'ancienne']))->assertStatus(409);

        $etat = EtatPosteSynchronisation::where('poste_id', 'poste-a')->sole();
        $this->assertSame(2, $etat->generation_perimee_nb);
        $this->assertNotNull($etat->generation_perimee_le);
    }

    #[Test]
    public function redescendre_depuis_le_debut_fait_ignorer_le_curseur_du_poste_une_seule_fois(): void
    {
        $premiere = $this->telecharger($this->admin, 'poste-a');
        $curseur = $premiere->json('meta.curseur');
        $this->assertTrue($premiere->json('meta.complet'));
        $total = count($premiere->json('data.elements'));
        $this->assertGreaterThan(0, $total);

        // Poste à jour : avec son curseur, plus rien.
        $this->assertSame([], $this->telecharger($this->admin, 'poste-a', $curseur)->json('data.elements'));

        $this->assertTrue(app(JournalEnvoiService::class)->demanderRedescente('poste-a', $this->admin));
        $this->assertDatabaseHas('journal_audit', ['action' => 'redescente_demandee', 'utilisateur_id' => $this->admin->id]);
        // Une seconde demande n'en crée pas une autre.
        $this->assertFalse(app(JournalEnvoiService::class)->demanderRedescente('poste-a', $this->admin));
        $this->assertSame(1, JournalAudit::where('action', 'redescente_demandee')->count());

        // Au prochain passage, le curseur présenté est ignoré : tout redescend.
        $this->assertCount($total, $this->telecharger($this->admin, 'poste-a', $curseur)->json('data.elements'));
        $etat = EtatPosteSynchronisation::where('poste_id', 'poste-a')->sole();
        $this->assertNull($etat->redescente_demandee_le);
        $this->assertNotNull($etat->redescente_faite_le);

        // La demande est consommée : le passage suivant est de nouveau normal.
        $this->assertSame([], $this->telecharger($this->admin, 'poste-a', $curseur)->json('data.elements'));
    }

    #[Test]
    public function la_redescente_est_reservee_aux_administrateurs_et_a_un_poste_connu(): void
    {
        $this->telecharger($this->admin, 'poste-a');
        $comptable = $this->creerUtilisateur('comptable');

        try {
            app(JournalEnvoiService::class)->demanderRedescente('poste-a', $comptable);
            $this->fail('Le comptable ne peut pas demander une redescente.');
        } catch (RuntimeException $e) {
            $this->assertSame(__('synchronisation_journal.ecran.refus_admin'), $e->getMessage());
        }

        $this->expectExceptionMessage(__('synchronisation_journal.ecran.poste_inconnu'));
        app(JournalEnvoiService::class)->demanderRedescente('poste-fantome', $this->admin);
    }

    private function telecharger(User $utilisateur, string $poste, ?string $depuis = null, ?int $limite = null): TestResponse
    {
        Sanctum::actingAs($utilisateur);
        $parametres = array_filter(['poste_id' => $poste, 'depuis' => $depuis, 'limite' => $limite], static fn ($v): bool => $v !== null);

        return $this->getJson('/api/v1/referentiels?' . http_build_query($parametres))->assertOk();
    }
}
