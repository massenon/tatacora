<?php

declare(strict_types=1);

namespace Tests\Feature\Restaurant;

use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Services\RapprochementPlatsStockService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Models\User;
use App\Pwa\Livewire\Restaurant\CarteRestaurant;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Shared\ImportExport\Services\CarteGiteChezNoelService;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « Lier au stock » vide et « Stock vendable : non suivi » sur les 81 plats
 * importés (PO, 09/11/2026).
 *
 * CAUSE PROUVÉE — l'import des trois modèles ne créait AUCUN article de stock
 * pour la cuisine : m6 ne portait que les neuf boissons (point de stockage
 * vide), m4 créait 81 plats + 81 fiches VIDES sans jamais les relier. Le bar
 * est « rapproché » parce que `cartes_boisson.article_id` est NOT NULL ; un plat,
 * lui, n'a aucun lien obligatoire — donc aucun lien, donc « non suivi ».
 */
final class RapprochementPlatsStockTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs(User::create([
            'login' => 'administrateur.cuisine',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]));
    }

    private function importer(string $cle): \Livewire\Features\SupportTesting\Testable
    {
        $carte = app(CarteGiteChezNoelService::class);
        $composant = Livewire::test(ImportExport::class)
            ->set('moduleImport', $cle)
            ->set('fichierImport', UploadedFile::fake()->createWithContent("{$cle}.xlsx", $carte->classeur($cle)))
            ->call('controlerFichierImport');

        $rapport = $composant->get('rapportControle');
        $this->assertTrue($rapport['ok'], $cle.' : '.json_encode($rapport['erreurs'], JSON_UNESCAPED_UNICODE));
        return $composant->call('confirmerImport')->assertHasNoErrors();
    }

    private function importerLaCarte(): void
    {
        foreach (['m6-stocks', 'm5-bar', 'm4-restaurant'] as $cle) {
            $this->importer($cle);
        }
    }

    /** L'état du PO avant correctif : plats importés SANS lien, ni article de cuisine, ni point. */
    private function etatDuPo(): void
    {
        $this->importer('m4-restaurant');
        Plat::query()->update(['article_id' => null, 'unites_vendables_par_unite_stock' => null]);
        Article::query()->delete();
        PointStockage::query()->delete();
        $this->assertSame(0, Plat::whereNotNull('article_id')->count());
        $this->assertSame(0, Article::count());
    }

    #[Test]
    public function apres_l_import_les_81_plats_sont_rapproches_du_stock_cuisine(): void
    {
        $this->importerLaCarte();

        $cuisine = PointStockage::where('type', 'cuisine')->first();
        $this->assertNotNull($cuisine, 'Le point « Cuisine » est posé par l\'import.');
        $this->assertSame('Cuisine', $cuisine->libelle);

        $this->assertSame(81, Plat::count());
        $this->assertSame(81, Plat::whereNotNull('article_id')->count(), 'Chaque plat est relié à un article de stock.');
        $this->assertSame(90, Article::count(), '9 boissons + 81 articles de cuisine.');
        $this->assertSame(81, Article::where('point_stockage_id', $cuisine->id)->count());
        $this->assertSame(0, MouvementStock::count(), 'Aucune quantité inventée.');

        $plat = Plat::where('libelle', 'Akassa')->firstOrFail();
        $this->assertSame('Akassa', $plat->article->libelle);
        $this->assertSame('permanent', $plat->article->suivi);
        $this->assertSame('1.0000', (string) $plat->unites_vendables_par_unite_stock);
        $this->assertNull($plat->article->prix_achat, 'Aucun prix inventé.');
    }

    #[Test]
    public function le_bilan_de_l_import_dit_combien_de_plats_sont_rapproches(): void
    {
        $this->importer('m6-stocks');
        $this->importer('m4-restaurant')->assertSee('81 plats rapprochés du stock');
    }

    #[Test]
    public function sans_le_modele_stocks_l_import_m4_cree_l_article_de_cuisine_et_relie_le_plat(): void
    {
        $this->importer('m4-restaurant')->assertSee('81 plats rapprochés du stock')->assertSee('81 articles de stock créés au point Cuisine');

        $this->assertSame(81, Plat::whereNotNull('article_id')->count());
        $this->assertSame(81, Article::count());
        $this->assertSame('cuisine', PointStockage::firstOrFail()->type);
        $this->assertSame(0, MouvementStock::count());
        $this->assertNull(Article::first()->prix_achat, 'Aucune valeur d\'achat inventée.');
    }

    private function fichierPerso(string $cle, array $entetes, array $lignes): UploadedFile
    {
        $module = \App\Shared\ImportExport\Data\ReferentielsImport::parCle($cle);
        $contenu = app(\App\Shared\ImportExport\Services\TableurService::class)->ecrireClasseur(
            $module->nom,
            $module->description,
            array_map(static fn (string $e) => new \App\Shared\ImportExport\Data\ColonneImport($e, $e, false, 'texte'), $entetes),
            $lignes,
        );

        return UploadedFile::fake()->createWithContent("{$cle}.xlsx", $contenu);
    }

    private function importerFichier(string $cle, UploadedFile $fichier): \Livewire\Features\SupportTesting\Testable
    {
        $composant = Livewire::test(ImportExport::class)->set('moduleImport', $cle)->set('fichierImport', $fichier)->call('controlerFichierImport');
        $this->assertTrue($composant->get('rapportControle')['ok'], json_encode($composant->get('rapportControle')['erreurs'], JSON_UNESCAPED_UNICODE));

        return $composant->call('confirmerImport')->assertHasNoErrors();
    }

    #[Test]
    public function m6_accepte_point_stock_seuil_et_valeur_d_achat_sans_inventer_de_quantite(): void
    {
        PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $this->importerFichier('m6-stocks', $this->fichierPerso('m6-stocks',
            ['Désignation de l’article', 'Catégorie', 'Unité de mesure', 'Seuil', 'Point Stock', 'Valeur d’achat'],
            [
                ['Désignation de l’article' => 'Riz', 'Catégorie' => 'Denrées', 'Unité de mesure' => 'kg', 'Seuil' => '5', 'Point Stock' => 'Magasin général', 'Valeur d’achat' => '650'],
                ['Désignation de l’article' => 'Sel', 'Catégorie' => 'Denrées', 'Unité de mesure' => 'kg', 'Seuil' => '', 'Point Stock' => '', 'Valeur d’achat' => ''],
            ],
        ));

        $riz = Article::where('libelle', 'Riz')->firstOrFail();
        $this->assertSame('5.00', (string) $riz->seuil_alerte);
        $this->assertSame('Magasin général', $riz->pointStockage->libelle);
        $this->assertSame('650.00', (string) $riz->prix_achat);
        $sel = Article::where('libelle', 'Sel')->firstOrFail();
        $this->assertNull($sel->prix_achat, 'Valeur d\'achat vide : « — », jamais 0 provisoire.');
        $this->assertSame('0.00', (string) $sel->seuil_alerte);
        $this->assertSame(0, MouvementStock::count());
    }

    #[Test]
    public function m6_seul_cree_les_81_articles_de_cuisine_au_point_cuisine_sans_prix_ni_quantite(): void
    {
        $this->importer('m6-stocks');

        $cuisine = PointStockage::where('type', 'cuisine')->firstOrFail();
        $this->assertSame(90, Article::count());
        $this->assertSame(81, Article::where('point_stockage_id', $cuisine->id)->count());
        $this->assertSame(0, Plat::count());
        $this->assertSame(0, MouvementStock::count());
        $this->assertSame(0, Article::whereNotNull('prix_achat')->count());
        $this->assertTrue(Article::where('libelle', 'Akassa')->where('point_stockage_id', $cuisine->id)->exists());
    }

    #[Test]
    public function un_point_deja_pose_n_est_jamais_remplace_par_un_import(): void
    {
        $magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $article = Article::create(['libelle' => 'Limonade', 'categorie' => 'Boissons', 'unite_mesure' => 'unité', 'suivi' => 'permanent', 'seuil_alerte' => '0', 'point_stockage_id' => $magasin->id]);

        $this->importerFichier('m5-bar', $this->fichierPerso('m5-bar',
            ['Nom de la boisson', 'Catégorie', 'Prix de vente (FCFA)', 'Point Stock'],
            [['Nom de la boisson' => 'Limonade', 'Catégorie' => 'locale', 'Prix de vente (FCFA)' => '500', 'Point Stock' => 'Bar']],
        ));

        $this->assertSame($magasin->id, $article->fresh()->point_stockage_id);
    }

    #[Test]
    public function un_ancien_fichier_m6_sans_les_nouvelles_colonnes_reste_valide(): void
    {
        $this->importerFichier('m6-stocks', $this->fichierPerso('m6-stocks',
            ['libelle', 'categorie', 'unite_mesure', 'seuil_alerte'],
            [['libelle' => 'Farine', 'categorie' => 'Denrées', 'unite_mesure' => 'kg', 'seuil_alerte' => '2']],
        ));

        $this->assertNull(Article::where('libelle', 'Farine')->firstOrFail()->prix_achat);
    }

    #[Test]
    public function m5_sans_article_rapproche_par_le_nom_ou_cree_et_ne_remplace_jamais_une_valeur(): void
    {
        $bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $existant = Article::create(['libelle' => 'BIÈRE Pils', 'categorie' => 'Boissons', 'unite_mesure' => 'unité', 'suivi' => 'permanent', 'seuil_alerte' => '7']);
        $existant->forceFill(['prix_achat' => '500'])->save();

        $this->importerFichier('m5-bar', $this->fichierPerso('m5-bar',
            ['Nom de la boisson', 'Catégorie', 'Prix de vente (FCFA)', 'Point Stock', 'Seuil', 'Valeur d\'achat'],
            [
                ['Nom de la boisson' => 'Bière Pils', 'Catégorie' => 'locale', 'Prix de vente (FCFA)' => '1000', 'Point Stock' => 'Bar', 'Seuil' => '99', 'Valeur d\'achat' => '900'],
                ['Nom de la boisson' => 'Jus de gingembre', 'Catégorie' => 'maison', 'Prix de vente (FCFA)' => '500', 'Point Stock' => '', 'Seuil' => '3', 'Valeur d\'achat' => '150'],
            ],
        ));

        $this->assertSame(2, Article::count(), 'La bière reprend l\'article existant : aucun doublon.');
        $this->assertSame($existant->id, \App\Domain\Bar\Models\CarteBoisson::where('libelle', 'Bière Pils')->firstOrFail()->article_id);
        $existant->refresh();
        $this->assertSame('500.00', (string) $existant->prix_achat, 'Une valeur d\'achat déjà posée n\'est jamais écrasée.');
        $this->assertSame('7.00', (string) $existant->seuil_alerte, 'Un seuil déjà posé n\'est jamais écrasé.');
        $this->assertSame($bar->id, $existant->point_stockage_id, 'Le point VIDE est complété.');

        $jus = Article::where('libelle', 'Jus de gingembre')->firstOrFail();
        $this->assertSame('Boissons', $jus->categorie);
        $this->assertSame($bar->id, $jus->point_stockage_id, 'Au Bar par défaut.');
        $this->assertSame('3.00', (string) $jus->seuil_alerte);
        $this->assertSame('150.00', (string) $jus->prix_achat);
        $this->assertSame($jus->id, \App\Domain\Bar\Models\CarteBoisson::where('libelle', 'Jus de gingembre')->firstOrFail()->article_id);
    }

    #[Test]
    public function m4_avec_les_colonnes_de_stock_cree_l_article_au_bon_point_avec_seuil_et_valeur(): void
    {
        $this->importerFichier('m4-restaurant', $this->fichierPerso('m4-restaurant',
            ['Nom du plat', 'Catégorie', 'Prix de vente (FCFA)', 'Seuil', 'Valeur d\'achat'],
            [
                ['Nom du plat' => 'Brochette', 'Catégorie' => 'plats', 'Prix de vente (FCFA)' => '1500', 'Seuil' => '4', 'Valeur d\'achat' => '700'],
                ['Nom du plat' => 'Igname', 'Catégorie' => 'plats', 'Prix de vente (FCFA)' => '', 'Seuil' => '', 'Valeur d\'achat' => ''],
            ],
        ));

        $b = Plat::where('libelle', 'Brochette')->firstOrFail()->article;
        $this->assertSame('4.00', (string) $b->seuil_alerte);
        $this->assertSame('700.00', (string) $b->prix_achat);
        $this->assertSame('cuisine', $b->pointStockage->type);
        $this->assertNull(Plat::where('libelle', 'Igname')->firstOrFail()->article->prix_achat);
    }

    #[Test]
    public function la_valeur_d_achat_importee_s_affiche_dans_stocks_sans_toucher_au_cmp(): void
    {
        $this->importerFichier('m6-stocks', $this->fichierPerso('m6-stocks',
            ['libelle', 'categorie', 'unite_mesure', 'valeur_achat'],
            [['libelle' => 'Huile', 'categorie' => 'Denrées', 'unite_mesure' => 'L', 'valeur_achat' => '1200']],
        ));
        $article = Article::where('libelle', 'Huile')->firstOrFail();

        $this->assertSame('1200.00', (string) $article->prix_achat);
        $this->assertSame('0.0000', (string) $article->cout_moyen_pondere, 'Le CMP reste calculé depuis les entrées valorisées.');
        Livewire::test(\App\Pwa\Livewire\Stocks\Stocks::class)->assertSee(\App\Pwa\Support\MontantFcfa::format('1200.00'));
    }

    #[Test]
    public function un_reimport_ne_cree_aucun_doublon_et_ne_touche_pas_aux_saisies(): void
    {
        $this->importerLaCarte();

        // Saisies du PO : un prix, une quantité en stock.
        $plat = Plat::where('libelle', 'Akassa')->firstOrFail();
        $plat->update(['prix_vente' => '700']);
        $cuisine = PointStockage::where('type', 'cuisine')->firstOrFail();
        app(\App\Domain\Stocks\Services\MouvementStockService::class)->entree(
            articleId: (string) $plat->article_id,
            pointId: (string) $cuisine->id,
            quantite: '12',
            motif: 'test',
        );

        $this->importerLaCarte2();

        $this->assertSame(90, Article::count());
        $this->assertSame(81, Plat::count());
        $this->assertSame(1, MouvementStock::count());
        $plat->refresh();
        $this->assertSame('700.00', (string) $plat->prix_vente);
        $this->assertNotNull($plat->article_id);
    }

    /** Le second passage : les fichiers déjà importés ne créent rien (lignes ignorées). */
    private function importerLaCarte2(): void
    {
        foreach (['m6-stocks', 'm4-restaurant'] as $cle) {
            $carte = app(CarteGiteChezNoelService::class);
            $composant = Livewire::test(ImportExport::class)
                ->set('moduleImport', $cle)
                ->set('fichierImport', UploadedFile::fake()->createWithContent("{$cle}.xlsx", $carte->classeur($cle)))
                ->call('controlerFichierImport');
            if ($composant->get('rapportControle')['ok']) {
                $composant->call('confirmerImport');
            }
        }
    }

    #[Test]
    public function la_modale_lier_au_stock_propose_les_articles_de_la_cuisine(): void
    {
        $this->importerLaCarte();
        $plat = Plat::where('libelle', 'Aileron')->firstOrFail();
        $plat->update(['article_id' => null, 'unites_vendables_par_unite_stock' => null]);

        $composant = Livewire::test(CarteRestaurant::class)
            ->call('ouvrirLienAuStock', (string) $plat->id);

        $libelles = $composant->viewData('articlesDeStock')->pluck('libelle')->all();
        $this->assertContains('Aileron', $libelles);
        $this->assertContains('Akassa', $libelles);
        $this->assertGreaterThanOrEqual(81, count($libelles));

        $composant->set('rechercheArticleStock', 'akas');
        $this->assertSame(['Akassa'], $composant->viewData('articlesDeStock')->pluck('libelle')->all());
    }

    #[Test]
    public function un_article_archive_n_est_pas_propose_a_la_modale(): void
    {
        $this->importerLaCarte();
        Article::where('libelle', 'Akassa')->firstOrFail()->forceFill(['actif' => false])->save();
        $plat = Plat::where('libelle', 'Aileron')->firstOrFail();

        $composant = Livewire::test(CarteRestaurant::class)->call('ouvrirLienAuStock', (string) $plat->id);

        $this->assertNotContains('Akassa', $composant->viewData('articlesDeStock')->pluck('libelle')->all());
    }

    #[Test]
    public function la_modale_sans_article_dit_comment_en_avoir(): void
    {
        $this->etatDuPo();
        $plat = Plat::firstOrFail();

        Livewire::test(CarteRestaurant::class)
            ->call('ouvrirLienAuStock', (string) $plat->id)
            ->assertSee('Aucun article de stock en cuisine : importez le modèle Stocks (point Cuisine) ou créez l\'article dans Stocks');
    }

    #[Test]
    public function le_stock_vendable_passe_de_non_suivi_a_zero_des_le_lien(): void
    {
        $this->importerLaCarte();

        $composant = Livewire::test(CarteRestaurant::class);
        $ligne = collect($composant->viewData('lignes'))->first(fn ($l) => $l['nom'] === 'Akassa');

        $this->assertNotNull($ligne['stock']);
        $this->assertFalse($ligne['stock']['non_consulte']);
        $this->assertSame('0', $ligne['stock']['unites_vendables']);
    }

    #[Test]
    public function le_rattrapage_relie_une_base_deja_importee_sans_rien_ecraser(): void
    {
        // État du PO : plats importés SANS lien, ni article de cuisine, ni point.
        $this->etatDuPo();

        // Un plat déjà relié à la main, un plat avec une vraie fiche.
        $service = app(RapprochementPlatsStockService::class);
        $manuel = Article::create(['libelle' => 'Farine spéciale', 'categorie' => 'Denrées', 'unite_mesure' => 'kg', 'suivi' => 'permanent', 'seuil_alerte' => '0']);
        $relie = Plat::where('libelle', 'Aileron')->firstOrFail();
        $relie->update(['article_id' => $manuel->id, 'unites_vendables_par_unite_stock' => '4']);
        $avecFiche = Plat::where('libelle', 'Akassa')->firstOrFail();
        \Illuminate\Support\Facades\DB::table('ingredients_recette')->insert([
            'recette_id' => $avecFiche->recette_id,
            'article_id' => $manuel->id, 'quantite_unitaire' => '0.5',
        ]);

        $bilan = $service->rapprocher();

        $this->assertSame(79, $bilan['rapproches']);
        $this->assertSame(79, $bilan['articles_crees']);
        $this->assertSame(1, $bilan['deja_lies']);
        $this->assertSame(1, $bilan['avec_fiche']);
        $this->assertSame($manuel->id, $relie->refresh()->article_id);
        $this->assertSame('4.0000', (string) $relie->unites_vendables_par_unite_stock);
        $this->assertNull($avecFiche->refresh()->article_id, 'Un plat décomposé en ingrédients garde sa fiche.');
        $this->assertSame('cuisine', PointStockage::firstOrFail()->type);

        // Idempotent : rien de plus au second passage.
        $second = $service->rapprocher();
        $this->assertSame(0, $second['rapproches']);
        $this->assertSame(0, $second['articles_crees']);
        $this->assertSame(1 + 79, Article::count());
    }

    #[Test]
    public function le_rattrapage_reprend_un_article_existant_de_meme_nom_au_lieu_d_en_creer_un(): void
    {
        $point = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);
        $existant = Article::create(['libelle' => 'AKASSA', 'categorie' => 'Denrées', 'unite_mesure' => 'unité', 'suivi' => 'permanent', 'seuil_alerte' => '0', 'point_stockage_id' => $point->id]);
        $this->importer('m4-restaurant');

        app(RapprochementPlatsStockService::class)->rapprocher();

        $this->assertSame($existant->id, Plat::where('libelle', 'Akassa')->firstOrFail()->article_id);
        $this->assertSame(1, Article::whereRaw('lower(libelle) = ?', ['akassa'])->count());
    }

    #[Test]
    public function la_commande_artisan_et_le_bouton_du_catalogue_font_le_rattrapage(): void
    {
        $this->etatDuPo();

        $this->assertSame(0, Artisan::call('restaurant:rapprocher-plats-stock'));
        $this->assertStringContainsString('81 plat(s) rapproché(s)', Artisan::output());
        $this->assertSame(81, Plat::whereNotNull('article_id')->count());

        Plat::query()->update(['article_id' => null, 'unites_vendables_par_unite_stock' => null]);

        Livewire::test(CarteRestaurant::class)->call('rapprocherLesPlatsDuStock')->assertHasNoErrors();
        $this->assertSame(81, Plat::whereNotNull('article_id')->count());
        $this->assertSame(90 - 9, Article::count());
    }
}
