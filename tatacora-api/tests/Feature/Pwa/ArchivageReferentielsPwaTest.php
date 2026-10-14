<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Pwa\Livewire\Achats\Achats;
use App\Pwa\Livewire\Crm\ClientsCreances;
use App\Pwa\Livewire\Stocks\Stocks;
use App\Shared\Parametres\Services\OptionsSystemeService;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « SUPPRIMER = ARCHIVER » sur les trois référentiels que le Gîte manipule
 * tous les jours — clients (M3), articles (M6), fournisseurs (M7).
 *
 * Demande du Product Owner du 03/09/2026 : « mettre le bouton Supprimer sur
 * chaque table, ou la suppression en bulk », pour `administrateur` et
 * `super_admin`.
 *
 * ## Ce que ce fichier éprouve, et pourquoi chaque cas existe
 *
 * `PwaEcritureAutoriseeTest` vérifie que la garde est ÉCRITE. Elle ne dit rien
 * de ce qui se passe quand elle tourne : c'est la leçon PA-59/60/61 du dépôt,
 * dans sa forme la plus directe. Les cas ci-dessous empruntent donc réellement
 * le chemin, et chacun répond à une question distincte :
 *
 * 1. **L'Administrateur archive, bascule FERMÉE.** C'est le défaut d'une
 *    installation neuve — `OptionsSystemeService::DEFAUTS` pose la bascule à
 *    `false` —, et c'est l'état que le PO a constaté : aucun bouton nulle part.
 * 2. **Un rôle ordinaire en `C` est refusé, bascule fermée.** `receptionniste`
 *    (M3), `magasinier` (M6) et `achats` (M7) écrivent sur leur module : sans
 *    ce cas, lever la bascule pour l'Administrateur l'aurait levée pour eux
 *    aussi, en silence.
 * 3. **Un élément ENGAGÉ est refusé avec son motif, et reste intact.** Le
 *    verrou est recontrôlé par le Service au moment d'agir, pas seulement à
 *    l'affichage.
 * 4. **Le lot traite la sélection ENTIÈRE.** Un geste de lot qui n'archiverait
 *    que la première ligne laisserait croire au reste que le travail est fait.
 *
 * ## Les mutations tranchées (03/09/2026)
 *
 * Chaque verrou de Service a été retiré, la suite relancée, le ROUGE constaté,
 * puis le verrou restauré :
 *
 * - `ReferentielFournisseurService::archiver()` sans son bloc `engagements` :
 *   `un_fournisseur_engage_est_refuse_et_reste_intact` ROUGE.
 * - `ReferentielArticleService::archiver()` sans son bloc `verrous` :
 *   `un_article_avec_du_stock_est_refuse_et_reste_intact` ROUGE.
 * - `ReferentielClientService::archiver()` sans son bloc `verrous` :
 *   `un_client_engage_est_refuse_et_reste_intact` ROUGE.
 * - `AutoriseArchivage::exigerArchivage()` sans son `abort(403)` : les trois
 *   cas de refus de rôle ROUGES.
 *
 * @see docs/DIRECTIVE_CONFORMITE_100.md Article 3.3
 * @see LARAVEL_PWA.md §3, §5
 */
final class ArchivageReferentielsPwaTest extends TestCase
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
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * La bascule est bien FERMÉE au départ — vérifié, pas supposé.
     *
     * Sans ce contrôle, tous les cas « bascule fermée » de ce fichier
     * pourraient tourner sous une bascule ouverte par un défaut modifié, et
     * prouver exactement le contraire de ce qu'ils annoncent.
     */
    #[Test]
    public function la_bascule_de_suppression_est_fermee_par_defaut(): void
    {
        $this->assertFalse(app(OptionsSystemeService::class)->suppressionActive());
    }

    // =====================================================================
    // M7 — Fournisseurs
    // =====================================================================

    #[Test]
    public function un_administrateur_archive_un_fournisseur_bascule_fermee(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $fournisseur = Fournisseur::create(['raison_sociale' => 'SODIS Bénin']);

        Livewire::test(Achats::class)
            ->call('confirmerArchivageFournisseur', $fournisseur->id)
            ->assertSet('etatFormulaire', 'archivage')
            ->assertSet('archivageBloque', false)
            ->call('archiverFournisseurs')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        // ARCHIVÉ, pas SUPPRIMÉ : la fiche existe toujours.
        $this->assertDatabaseHas('fournisseurs', ['id' => $fournisseur->id, 'actif' => 0]);
    }

    #[Test]
    public function un_role_ordinaire_ne_peut_pas_archiver_un_fournisseur_bascule_fermee(): void
    {
        // `achats` porte bien `M7 = C` — il écrit, mais il n'archive pas.
        $this->assertSame('C', Role::where('libelle', 'achats')->firstOrFail()->niveauSurModule('M7'));

        $this->actingAs($this->utilisateur('achats'));
        $fournisseur = Fournisseur::create(['raison_sociale' => 'SODIS Bénin']);

        Livewire::test(Achats::class)
            ->call('confirmerArchivageFournisseur', $fournisseur->id)
            ->assertForbidden();

        $this->assertDatabaseHas('fournisseurs', ['id' => $fournisseur->id, 'actif' => 1]);
    }

    #[Test]
    public function un_role_ordinaire_archive_un_fournisseur_bascule_ouverte(): void
    {
        $this->ouvrirLaBascule();
        $this->actingAs($this->utilisateur('achats'));
        $fournisseur = Fournisseur::create(['raison_sociale' => 'SODIS Bénin']);

        Livewire::test(Achats::class)
            ->call('confirmerArchivageFournisseur', $fournisseur->id)
            ->call('archiverFournisseurs')
            ->assertHasNoErrors();

        $this->assertDatabaseHas('fournisseurs', ['id' => $fournisseur->id, 'actif' => 0]);
    }

    #[Test]
    public function un_fournisseur_engage_est_refuse_et_reste_intact(): void
    {
        $auteur = $this->utilisateur('administrateur');
        $this->actingAs($auteur);

        $fournisseur = Fournisseur::create(['raison_sociale' => 'SODIS Bénin']);
        CommandeAchat::create([
            'fournisseur_id' => $fournisseur->id,
            'date_commande' => now()->subDays(3)->toDateString(),
            'statut' => 'envoyee',
            'utilisateur_id' => $auteur->id,
        ]);

        $composant = Livewire::test(Achats::class)
            ->call('confirmerArchivageFournisseur', $fournisseur->id)
            // ÉTAT 1 de la modale du maître : tout le lot est bloqué, le
            // bouton de confirmation disparaît.
            ->assertSet('archivageBloque', true);

        $this->assertStringContainsString(
            'commande',
            implode(' ', $composant->get('verrousArchivage')),
        );

        // Et le geste forcé depuis le navigateur ne passe pas non plus : le
        // Service recontrôle au moment d'agir.
        $composant->set('fournisseursAArchiver', [$fournisseur->id])
            ->call('archiverFournisseurs')
            ->assertHasErrors('archivage');

        $this->assertDatabaseHas('fournisseurs', ['id' => $fournisseur->id, 'actif' => 1]);
    }

    #[Test]
    public function le_lot_archive_la_selection_entiere_de_fournisseurs(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $ids = collect(['Alpha Négoce', 'Beta Distribution', 'Gamma Import'])
            ->map(static fn (string $nom): string => Fournisseur::create(['raison_sociale' => $nom])->id)
            ->all();

        Livewire::test(Achats::class)
            ->set('selection', $ids)
            ->call('confirmerArchivageFournisseur')
            ->assertSet('archivageBloque', false)
            ->call('archiverFournisseurs')
            ->assertHasNoErrors()
            // La sélection est vidée : la laisser cochée ferait rouvrir la
            // modale sur des lignes déjà archivées.
            ->assertSet('selection', []);

        $this->assertSame(0, Fournisseur::query()->where('actif', true)->count());
        $this->assertSame(3, Fournisseur::query()->where('actif', false)->count());
    }

    #[Test]
    public function un_fournisseur_archive_se_restaure_bascule_fermee(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $fournisseur = Fournisseur::create(['raison_sociale' => 'SODIS Bénin']);
        $fournisseur->forceFill(['actif' => false])->save();

        // Restaurer n'est PAS derrière la bascule, délibérément : la fermer
        // ne doit jamais enfermer un fournisseur aux archives (PA-59/60/61).
        Livewire::test(Achats::class)
            ->call('restaurerFournisseur', $fournisseur->id)
            ->assertHasNoErrors();

        $this->assertDatabaseHas('fournisseurs', ['id' => $fournisseur->id, 'actif' => 1]);
    }

    // =====================================================================
    // M6 — Articles
    // =====================================================================

    #[Test]
    public function un_administrateur_archive_un_article_bascule_fermee(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $article = $this->article('Serviettes de table');

        Livewire::test(Stocks::class)
            ->call('confirmerArchivageArticle', $article->id)
            ->assertSet('etatFormulaire', 'archivage')
            ->assertSet('archivageBloque', false)
            ->call('archiverArticles')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertDatabaseHas('articles', ['id' => $article->id, 'actif' => 0]);
    }

    #[Test]
    public function un_role_ordinaire_ne_peut_pas_archiver_un_article_bascule_fermee(): void
    {
        $this->assertSame('C', Role::where('libelle', 'magasinier')->firstOrFail()->niveauSurModule('M6'));

        $this->actingAs($this->utilisateur('magasinier'));
        $article = $this->article('Serviettes de table');

        Livewire::test(Stocks::class)
            ->call('confirmerArchivageArticle', $article->id)
            ->assertForbidden();

        $this->assertDatabaseHas('articles', ['id' => $article->id, 'actif' => 1]);
    }

    #[Test]
    public function un_article_avec_du_stock_est_refuse_et_reste_intact(): void
    {
        $auteur = $this->utilisateur('administrateur');
        $this->actingAs($auteur);

        $article = $this->article('Riz local (sac 50 kg)');
        $point = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        app(MouvementStockService::class)->entree($article->id, $point->id, '10.00', 'Réception', '1000.00');

        $composant = Livewire::test(Stocks::class)
            ->call('confirmerArchivageArticle', $article->id)
            ->assertSet('archivageBloque', true);

        $this->assertStringContainsString('stock', implode(' ', $composant->get('verrousArchivage')));

        $composant->set('articlesAArchiver', [$article->id])
            ->call('archiverArticles')
            ->assertHasErrors('archivage');

        $this->assertDatabaseHas('articles', ['id' => $article->id, 'actif' => 1]);
    }

    #[Test]
    public function le_lot_archive_la_selection_entiere_d_articles(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $ids = collect(['Nappes', 'Serviettes', 'Bougies'])
            ->map(fn (string $nom): string => $this->article($nom)->id)
            ->all();

        Livewire::test(Stocks::class)
            ->set('selection', $ids)
            ->call('confirmerArchivageArticle')
            ->assertSet('archivageBloque', false)
            ->call('archiverArticles')
            ->assertHasNoErrors()
            ->assertSet('selection', []);

        $this->assertSame(0, Article::query()->where('actif', true)->count());
        $this->assertSame(3, Article::query()->where('actif', false)->count());
    }

    // =====================================================================
    // M3 — Clients
    // =====================================================================

    #[Test]
    public function un_administrateur_archive_un_client_bascule_fermee(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $client = $this->client('Kora', 'Aïcha');

        Livewire::test(ClientsCreances::class)
            ->call('confirmerArchivageClient', $client->id)
            ->assertSet('etatFormulaire', 'archivage')
            ->assertSet('archivageBloque', false)
            ->call('archiverClients')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        // RG-18 : la fiche UNIQUE survit — archivée, jamais effacée.
        $this->assertDatabaseHas('clients', ['id' => $client->id, 'actif' => 0]);
    }

    #[Test]
    public function un_role_ordinaire_ne_peut_pas_archiver_un_client_bascule_fermee(): void
    {
        $this->assertSame('C', Role::where('libelle', 'receptionniste')->firstOrFail()->niveauSurModule('M3'));

        $this->actingAs($this->utilisateur('receptionniste'));
        $client = $this->client('Kora', 'Aïcha');

        Livewire::test(ClientsCreances::class)
            ->call('confirmerArchivageClient', $client->id)
            ->assertForbidden();

        $this->assertDatabaseHas('clients', ['id' => $client->id, 'actif' => 1]);
    }

    #[Test]
    public function un_client_engage_est_refuse_et_reste_intact(): void
    {
        $auteur = $this->utilisateur('administrateur');
        $this->actingAs($auteur);

        $client = $this->client('Kora', 'Aïcha');

        $categorie = CategorieHebergement::create([
            'libelle' => 'Chambre standard',
            'tarif_base' => '15000.00',
            'capacite_max' => 2,
        ]);
        $unite = UniteHebergement::create([
            'numero' => 'C-01',
            'categorie_id' => $categorie->id,
            'statut' => 'libre',
        ]);

        // Par le SERVICE, jamais un `DB::table()` : `reservations` est gardée
        // par RG-01 sous verrou pessimiste, et l'insertion directe le
        // contournerait sans la moindre erreur visible.
        app(ReservationService::class)->creer([
            'client_id' => $client->id,
            'unite_id' => $unite->id,
            'date_arrivee' => now()->addDays(3)->toDateString(),
            'date_depart' => now()->addDays(6)->toDateString(),
        ]);

        $composant = Livewire::test(ClientsCreances::class)
            ->call('confirmerArchivageClient', $client->id)
            ->assertSet('archivageBloque', true);

        $this->assertStringContainsString('séjour', implode(' ', $composant->get('verrousArchivage')));

        $composant->set('clientsAArchiver', [$client->id])
            ->call('archiverClients')
            ->assertHasErrors('archivage');

        $this->assertDatabaseHas('clients', ['id' => $client->id, 'actif' => 1]);
    }

    #[Test]
    public function le_lot_archive_la_selection_entiere_de_clients(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $ids = [
            $this->client('Alpha', 'Un')->id,
            $this->client('Beta', 'Deux')->id,
            $this->client('Gamma', 'Trois')->id,
        ];

        Livewire::test(ClientsCreances::class)
            ->set('selection', $ids)
            ->call('confirmerArchivageClient')
            ->assertSet('archivageBloque', false)
            ->call('archiverClients')
            ->assertHasNoErrors()
            ->assertSet('selection', []);

        $this->assertSame(0, Client::query()->where('actif', true)->count());
        $this->assertSame(3, Client::query()->where('actif', false)->count());
    }

    /**
     * Un client ARCHIVÉ reste dans la liste, marqué — jamais masqué.
     *
     * Le masquer le rendrait indiscernable d'une fiche inexistante, et
     * « reste restaurable » ne serait tenue nulle part (PA-59/60/61).
     */
    #[Test]
    public function un_client_archive_reste_affiche_avec_son_badge(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));
        $client = $this->client('Kora', 'Aïcha');
        $client->forceFill(['actif' => false])->save();

        Livewire::test(ClientsCreances::class)
            ->assertSee('Kora')
            ->assertSee('Archivé');
    }

    // ------------------------------------------------------------ fixtures

    private function ouvrirLaBascule(): void
    {
        \App\Shared\Parametres\Models\ParametreSysteme::updateOrCreate(
            ['cle' => OptionsSystemeService::CLE_SUPPRESSION],
            ['valeur' => '1'],
        );
    }

    private function article(string $libelle): Article
    {
        return Article::create([
            'libelle' => $libelle,
            'categorie' => 'Fournitures',
            'unite_mesure' => 'unité',
            'seuil_alerte' => '2.00',
            'seuil_reappro' => '5.00',
            'cout_moyen_pondere' => '0.0000',
        ]);
    }

    private function client(string $nom, string $prenom): Client
    {
        return Client::create([
            'nom' => $nom,
            'prenom' => $prenom,
            'telephone' => '01 90 00 00 00',
            'type_client' => 'particulier',
        ]);
    }
}
