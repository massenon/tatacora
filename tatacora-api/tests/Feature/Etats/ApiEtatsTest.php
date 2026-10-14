<?php

declare(strict_types=1);

namespace Tests\Feature\Etats;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\ReportEngine\Models\EtatGenere;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Hub États & Rapports par l'API — EF-M14-02/03/04/06.
 *
 * Le moteur (`MoteurEtatsTest`) est vérifié à part ; cette suite vérifie qu'il
 * est **réellement joignable** et que les trois niveaux de RBAC tiennent sur le
 * chemin HTTP, qui est celui qu'un client Flutter emprunte.
 */
final class ApiEtatsTest extends TestCase
{
    use RefreshDatabase;

    private PointStockage $magasin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $riz = Article::create([
            'libelle' => 'Riz parfumé 50kg', 'categorie' => 'denree', 'unite_mesure' => 'sac',
            'seuil_alerte' => '10.00', 'seuil_reappro' => '50.00', 'cout_moyen_pondere' => '18000.0000',
        ]);

        // Les mouvements de stock exigent un utilisateur (colonnes d'audit)...
        $this->actingAs($this->utilisateur('magasinier'));
        app(MouvementStockService::class)->entree($riz->id, $this->magasin->id, '40.00', 'Stock initial');

        // ...mais chaque test choisit ensuite son propre porteur de jeton.
        // Sans cette remise à zéro, le test d'accès anonyme serait
        // silencieusement authentifié par le montage — et passerait pour un
        // contrôle qui n'a jamais eu lieu.
        $this->app['auth']->forgetGuards();
    }

    // ------------------------------------------------------------- Catalogue

    #[Test]
    public function le_catalogue_liste_les_etats_accessibles_au_role(): void
    {
        Sanctum::actingAs($this->utilisateur('magasinier'));

        $reponse = $this->getJson('/api/v1/etats');

        $reponse->assertOk()
            ->assertJsonPath('data.0.code', 'stocks')
            ->assertJsonPath('data.0.module', 'M6');
    }

    /**
     * 1ᵉʳ niveau RBAC : un état hors droits est **absent** du catalogue, pas
     * listé puis refusé. Le lister renseignerait sur la structure interne sans
     * aucun bénéfice.
     */
    #[Test]
    public function un_etat_hors_droits_est_absent_du_catalogue(): void
    {
        $sansAcces = Role::all()->first(fn (Role $role): bool => $role->niveauSurModule('M6') === '-');
        $this->assertNotNull($sansAcces, 'Aucun rôle sans accès M6 : matrice à vérifier.');

        Sanctum::actingAs($this->compteAvecRole($sansAcces));

        $reponse = $this->getJson('/api/v1/etats')->assertOk();

        // On vérifie l'ABSENCE de l'état concerné, pas un catalogue vide :
        // le même rôle peut légitimement avoir accès à d'autres modules, et
        // un `assertJsonCount(0)` casserait à chaque état ajouté sans rien
        // dire de la règle réellement en jeu.
        $codes = array_column($reponse->json('data'), 'code');
        $this->assertNotContains('stocks', $codes);

        // ...et aucun état d'un module interdit ne passe, quel qu'il soit.
        $modules = array_column($reponse->json('data'), 'module');
        $this->assertNotContains('M6', $modules);
    }

    #[Test]
    public function le_catalogue_exige_une_authentification(): void
    {
        $this->getJson('/api/v1/etats')->assertUnauthorized();
    }

    // ------------------------------------------------------------ Génération

    #[Test]
    public function un_pdf_est_reellement_telecharge(): void
    {
        Sanctum::actingAs($this->utilisateur('magasinier'));

        $reponse = $this->post('/api/v1/etats/generer', [
            'etat' => 'stocks',
            'format' => 'pdf',
            'filtres' => ['point_id' => $this->magasin->id],
        ]);

        $reponse->assertOk();
        $reponse->assertHeader('content-type', 'application/pdf');

        // Le flux est réellement un PDF, pas une page d'erreur en 200.
        $this->assertStringStartsWith('%PDF-', $reponse->streamedContent());

        // EF-M14-06 — l'édition a laissé sa trace.
        $this->assertSame(1, EtatGenere::count());
    }

    #[Test]
    public function le_meme_etat_se_telecharge_en_tableur(): void
    {
        Sanctum::actingAs($this->utilisateur('magasinier'));

        $reponse = $this->post('/api/v1/etats/generer', ['etat' => 'stocks', 'format' => 'excel']);

        $reponse->assertOk();
        $this->assertStringContainsString('Riz parfumé 50kg', $reponse->streamedContent());
        $this->assertSame('excel', EtatGenere::sole()->format);
    }

    /**
     * 2ᵉ niveau RBAC : le contrôle porte sur le module **source** de l'état
     * (M6), jamais sur M14. Un appel direct doit être refusé même si le
     * catalogue avait été contourné côté client.
     */
    #[Test]
    public function un_appel_direct_sans_droit_sur_le_module_source_est_refuse(): void
    {
        $sansAcces = Role::all()->first(fn (Role $role): bool => $role->niveauSurModule('M6') === '-');
        Sanctum::actingAs($this->compteAvecRole($sansAcces));

        $this->postJson('/api/v1/etats/generer', ['etat' => 'stocks'])
            ->assertForbidden();

        // Aucun document produit, donc aucune archive.
        $this->assertSame(0, EtatGenere::count());
    }

    #[Test]
    public function un_code_d_etat_inconnu_est_refuse_en_validation(): void
    {
        Sanctum::actingAs($this->utilisateur('magasinier'));

        $this->postJson('/api/v1/etats/generer', ['etat' => 'grand-livre'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('etat');
    }

    #[Test]
    public function un_format_inconnu_est_refuse_en_validation(): void
    {
        Sanctum::actingAs($this->utilisateur('magasinier'));

        $this->postJson('/api/v1/etats/generer', ['etat' => 'stocks', 'format' => 'docx'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('format');
    }

    /**
     * Les filtres traversent réellement HTTP → moteur → archive, sans quoi un
     * export « Magasin général » archiverait « toutes périodes ».
     */
    #[Test]
    public function les_filtres_transmis_sont_ceux_qui_sont_archives(): void
    {
        Sanctum::actingAs($this->utilisateur('magasinier'));

        $this->post('/api/v1/etats/generer', [
            'etat' => 'stocks',
            'filtres' => ['point_id' => $this->magasin->id],
        ])->assertOk();

        $this->assertSame('Magasin général', EtatGenere::sole()->filtres_appliques['point']);
    }

    // -------------------------------------------------------------- Archives

    #[Test]
    public function le_journal_d_edition_est_consultable_par_un_role_habilite(): void
    {
        Sanctum::actingAs($this->utilisateur('magasinier'));
        $this->post('/api/v1/etats/generer', ['etat' => 'stocks'])->assertOk();

        // M14 est un module de consultation transverse : on prend un rôle qui
        // y a réellement droit plutôt que de le supposer.
        $habilite = Role::all()->first(
            fn (Role $role): bool => in_array($role->niveauSurModule('M14'), ['C', 'L'], true),
        );
        $this->assertNotNull($habilite);

        Sanctum::actingAs($this->compteAvecRole($habilite));

        $this->getJson('/api/v1/etats/archives')
            ->assertOk()
            ->assertJsonPath('data.0.module', 'M6')
            // PA-48 exposé tel quel : un auditeur doit voir que le fichier
            // n'est pas conservé, plutôt que de croire pouvoir le récupérer.
            ->assertJsonPath('data.0.fichier_archive', null)
            ->assertJsonPath('meta.total', 1);
    }

    #[Test]
    public function le_journal_d_edition_est_refuse_a_un_role_sans_droit_sur_m14(): void
    {
        $sansAcces = Role::all()->first(fn (Role $role): bool => $role->niveauSurModule('M14') === '-');

        if ($sansAcces === null) {
            $this->markTestSkipped('Tous les rôles ont accès à M14 dans la matrice.');
        }

        Sanctum::actingAs($this->compteAvecRole($sansAcces));

        $this->getJson('/api/v1/etats/archives')->assertForbidden();
    }

    // ------------------------------------------------------------- Helpers

    private function utilisateur(string $role): User
    {
        return $this->compteAvecRole(Role::where('libelle', $role)->firstOrFail());
    }

    private function compteAvecRole(Role $role): User
    {
        return User::create([
            'login' => $role->libelle . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $role->id,
            'statut' => 'actif',
        ]);
    }
}
