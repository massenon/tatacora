<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Models\User;
use App\Pwa\Livewire\Stocks\Stocks;
use App\Pwa\Livewire\Transverse\ImportExport;
use App\Shared\ImportExport\Data\ReferentielsImport;
use App\Shared\ImportExport\Services\CarteGiteChezNoelService;
use App\Shared\ImportExport\Services\ControleImportService;
use App\Shared\ImportExport\Services\TableurService;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PhpOffice\PhpSpreadsheet\IOFactory;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les modèles d'import sont de VRAIS classeurs `.xlsx` (30/10/2026).
 *
 * Cause du bogue rapporté par le PO — « toutes les colonnes se retrouvent
 * dans une seule colonne » : le modèle était un CSV au point-virgule
 * (`fputcsv($sortie, …, ';')`, `text/csv`), qu'un Excel réglé sur la virgule
 * ouvre en UNE colonne. Ce fichier prouve que :
 *
 *  - chaque modèle vide se relit avec ses en-têtes, une cellule par colonne ;
 *  - l'import lit le `.xlsx` PAR NOM d'en-tête, et garde le CSV en secours
 *    (`;`, `,`, tabulation, BOM, Windows-1252, `sep=;`) ;
 *  - les trois fichiers de la carte du Gîte Chez Noël, importés dans l'ordre
 *    m6 → m5 → m4, créent exactement les lignes attendues, sans mouvement
 *    de stock.
 */
final class ImportXlsxTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs(User::create([
            'login' => 'administrateur.xlsx',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]));
    }

    private function fichier(string $nom, string $contenu): UploadedFile
    {
        return UploadedFile::fake()->createWithContent($nom, $contenu);
    }

    // ------------------------------------------------------------- modèles

    #[Test]
    public function chaque_modele_vide_est_un_xlsx_qui_se_relit_avec_ses_en_tetes(): void
    {
        $tableur = app(TableurService::class);

        foreach (ReferentielsImport::definitions() as $module) {
            $octets = $tableur->ecrireClasseur($module->nom, $module->description, $module->colonnes);

            // Un VRAI classeur : signature ZIP, pas du texte séparé par des points-virgules.
            $this->assertStringStartsWith("PK\x03\x04", $octets, $module->cle);

            $tableau = $tableur->lireContenu($octets);
            $this->assertSame(
                array_map(static fn ($c): string => $c->libelle, $module->colonnes),
                $tableau[0],
                'Une cellule par colonne : '.$module->cle,
            );
            // Une ligne d'exemple, sous les en-têtes.
            $this->assertCount(2, $tableau, $module->cle);
            $this->assertSame(
                array_map(static fn ($c, int $i): string => ($i === 0 ? TableurService::PREFIXE_EXEMPLE : '').$c->exemple, $module->colonnes, array_keys($module->colonnes)),
                $tableau[1],
                'Les nombres redeviennent le texte qu\'Excel affiche : '.$module->cle,
            );

            // Feuille « Aide » : une ligne par colonne.
            $fichier = tempnam(sys_get_temp_dir(), 'aide');
            file_put_contents($fichier, $octets);
            $classeur = IOFactory::load($fichier);
            unlink($fichier);
            $this->assertSame(['Modèle', 'Aide'], $classeur->getSheetNames());
            $aide = $classeur->getSheetByName('Aide')?->toArray(null, true, false, false) ?? [];
            $libellesAide = array_column(array_slice($aide, 6), 0);
            $this->assertSame(array_map(static fn ($c): string => $c->libelle, $module->colonnes), $libellesAide, $module->cle);
        }
    }

    #[Test]
    public function le_telechargement_est_un_xlsx_au_bon_type_mime(): void
    {
        $reponse = Livewire::test(ImportExport::class)
            ->set('moduleImport', 'm5-bar')
            ->call('telechargerModele');

        $reponse->assertFileDownloaded('modele_import_m5-bar.xlsx');
        $this->assertStringContainsString(
            'spreadsheetml.sheet',
            (string) data_get($reponse->effects, 'download.contentType'),
        );
    }

    #[Test]
    public function un_modele_telecharge_puis_laisse_tel_quel_ne_cree_aucune_ligne(): void
    {
        $octets = app(TableurService::class)->ecrireClasseur('Clients', '', ReferentielsImport::parCle('m3-clients')->colonnes);

        $composant = Livewire::test(ImportExport::class)
            ->set('moduleImport', 'm3-clients')
            ->set('fichierImport', $this->fichier('modele.xlsx', $octets))
            ->call('controlerFichierImport');

        $rapport = $composant->get('rapportControle');
        $this->assertSame(0, $rapport['resume']['total']);
        $this->assertSame(1, count($rapport['avertissements']), 'La ligne d\'exemple est signalée, ignorée.');
    }

    // -------------------------------------------------------------- lecture

    #[Test]
    public function les_en_tetes_se_lisent_par_nom_pas_par_position(): void
    {
        $module = ReferentielsImport::parCle('m5-bar');
        $this->assertNotNull($module);

        // Colonnes permutées, casse et accents changés, colonne en trop.
        $csv = "ARTICLE DE STOCK LIE;prix de vente (fcfa);Commentaire;CATEGORIE;nom de la boisson\n"
            ."Jus X;1500;libre;maison;Jus X\n";

        $controle = app(ControleImportService::class);
        // L'article n'existe pas : c'est la seule erreur attendue, nommée avec ligne et colonne.
        $rapport = $controle->controler($module, $controle->analyserCsv($csv));

        $this->assertFalse($rapport->ok);
        $this->assertCount(1, $rapport->erreurs);
        $this->assertSame(2, $rapport->erreurs[0]['ligne']);
        $this->assertSame('Article de stock lié', $rapport->erreurs[0]['colonne']);
        $this->assertStringContainsString('aucun enregistrement « Jus X »', $rapport->erreurs[0]['message']);
        $this->assertSame('Commentaire', $rapport->avertissements[0]['colonne']);
    }

    #[Test]
    public function une_colonne_obligatoire_absente_dit_la_ligne_la_colonne_et_ce_qui_a_ete_lu(): void
    {
        $module = ReferentielsImport::parCle('m5-bar');
        $controle = app(ControleImportService::class);

        $rapport = $controle->controler($module, $controle->analyserCsv("Nom de la boisson;Catégorie\nJus;maison\n"));

        $this->assertFalse($rapport->ok);
        $messages = array_column($rapport->erreurs, 'message');
        $this->assertStringContainsString('Ligne 1 : colonne obligatoire « Prix de vente (FCFA) » absente', $messages[0]);
        $this->assertStringContainsString('Colonnes trouvées : Nom de la boisson ; Catégorie', $messages[0]);
    }

    #[Test]
    public function le_csv_de_secours_est_lu_quel_que_soit_le_separateur_ou_l_encodage(): void
    {
        $tableur = app(TableurService::class);
        $attendu = [['Nom', 'Prix'], ['Crêpe', '1000']];

        foreach ([';', ',', "\t"] as $sep) {
            $this->assertSame($attendu, $tableur->lireCsv("Nom{$sep}Prix\r\nCrêpe{$sep}1000\r\n"), 'séparateur '.json_encode($sep));
            $this->assertSame($attendu, $tableur->lireCsv("\xEF\xBB\xBFNom{$sep}Prix\nCrêpe{$sep}1000"), 'BOM UTF-8');
        }

        // « CSV (séparateur : point-virgule) » d'Excel Windows : Windows-1252, sans BOM.
        $this->assertSame($attendu, $tableur->lireCsv(mb_convert_encoding("Nom;Prix\nCrêpe;1000\n", 'Windows-1252', 'UTF-8')));
        // UTF-16 avec BOM (« Texte Unicode » d'Excel).
        $this->assertSame($attendu, $tableur->lireCsv("\xFF\xFE".mb_convert_encoding("Nom\tPrix\nCrêpe\t1000\n", 'UTF-16LE', 'UTF-8')));
        // La ligne `sep=;` qu'Excel sait écrire.
        $this->assertSame($attendu, $tableur->lireCsv("sep=;\nNom;Prix\nCrêpe;1000\n"));
        // Un champ entre guillemets qui contient le séparateur.
        $this->assertSame([['Nom', 'Prix'], ['Dégué, cake', '1500']], $tableur->lireCsv("Nom;Prix\n\"Dégué, cake\";1500\n"));
    }

    #[Test]
    public function un_ancien_xls_est_refuse_avec_la_marche_a_suivre(): void
    {
        $this->expectExceptionMessage('.xlsx');
        app(TableurService::class)->lireContenu("\xD0\xCF\x11\xE0".str_repeat("\0", 64));
    }

    #[Test]
    public function un_import_csv_au_point_virgule_entre_toujours_par_le_depot(): void
    {
        $csv = "Nom / Raison sociale;Type de client;Téléphone\nAgence Bénin Tour;agence;+229 01 97 00 00 00\n";

        Livewire::test(ImportExport::class)
            ->set('moduleImport', 'm3-clients')
            ->set('fichierImport', $this->fichier('clients.csv', $csv))
            ->call('controlerFichierImport')
            ->call('confirmerImport');

        $this->assertDatabaseHas('clients', ['nom' => 'Agence Bénin Tour']);
    }

    // ------------------------------------------------------ carte du Gîte

    #[Test]
    public function la_carte_du_gite_s_importe_dans_l_ordre_m6_m5_m4_sans_aucun_stock(): void
    {
        $carte = app(CarteGiteChezNoelService::class);

        $import = function (string $cle) use ($carte): void {
            $composant = Livewire::test(ImportExport::class)
                ->set('moduleImport', $cle)
                ->set('fichierImport', $this->fichier("modele_import_{$cle}.xlsx", $carte->classeur($cle)))
                ->call('controlerFichierImport');

            $rapport = $composant->get('rapportControle');
            $this->assertTrue($rapport['ok'], $cle.' : '.json_encode($rapport['erreurs'], JSON_UNESCAPED_UNICODE));
            $composant->call('confirmerImport')->assertHasNoErrors();
        };

        // m5 AVANT m6 : refusé, nommément — la boisson se lie à un article existant.
        $composant = Livewire::test(ImportExport::class)
            ->set('moduleImport', 'm5-bar')
            ->set('fichierImport', $this->fichier('bar.xlsx', $carte->classeur('m5-bar')))
            ->call('controlerFichierImport');
        $this->assertFalse($composant->get('rapportControle')['ok']);
        $this->assertStringContainsString('aucun enregistrement', $composant->get('rapportControle')['erreurs'][0]['message']);

        $import('m6-stocks');
        $import('m5-bar');
        $import('m4-restaurant');

        // m6 — neuf articles de boisson, tous à seuil 0, AUCUN mouvement.
        $this->assertSame(9, Article::count());
        $this->assertSame(0, MouvementStock::count(), 'Le stock s\'ajoute après : aucune quantité importée.');
        $this->assertSame('Boissons', Article::where('libelle', 'Café double')->firstOrFail()->categorie);

        // m5 — neuf boissons, une par taille, liées à l'article du même nom.
        $this->assertSame(9, CarteBoisson::count());
        $this->assertSame('1500.00', (string) CarteBoisson::where('libelle', "Jus d'ananas (moyen)")->firstOrFail()->prix_vente);
        $this->assertSame('2000.00', (string) CarteBoisson::where('libelle', "Jus d'ananas (grand)")->firstOrFail()->prix_vente);
        $this->assertSame('500.00', (string) CarteBoisson::where('libelle', 'Café simple')->firstOrFail()->prix_vente);
        $this->assertSame('1000.00', (string) CarteBoisson::where('libelle', 'Café double')->firstOrFail()->prix_vente);
        $this->assertSame(
            Article::where('libelle', 'Café expresso')->firstOrFail()->id,
            CarteBoisson::where('libelle', 'Café expresso')->firstOrFail()->article_id,
        );
        $this->assertSame(2, CarteBoisson::where('libelle', 'like', 'Jus de banane%')->count());

        // m4 — 86 plats ; menu et fiches créés vides, prix vide = 0 provisoire.
        $this->assertSame(86, Plat::count());
        $this->assertSame(1, Menu::count());
        $this->assertSame(86, Recette::count());
        $this->assertSame('4000.00', (string) Plat::where('libelle', 'Salade du Chef')->firstOrFail()->prix_vente);
        $this->assertSame('pizzas', Plat::where('libelle', 'Pizza du gîte (grande)')->firstOrFail()->categorie);
        $this->assertSame(1, Plat::where('libelle', 'Piron')->count());
        $this->assertSame(3, Plat::where('libelle', 'like', 'Panini%')->count());
        $surCommande = Plat::where('libelle', 'Wassa wassa')->firstOrFail();
        $this->assertSame('0.00', (string) $surCommande->prix_vente);
        $this->assertTrue($surCommande->prix_provisoire);
        $this->assertTrue(Recette::where('libelle', 'Wassa wassa')->firstOrFail()->composition_provisoire);
        $this->assertSame(0, MouvementStock::count());

        // Les descriptions de l'affiche (colonne facultative « Description ») sont importées ;
        // les plats qui n'en portent pas ont NULL.
        $this->assertSame(9, Plat::whereNotNull('description')->count());
        $this->assertSame('Sauce tomate, bœuf hachée, saucisse, fromage peuilh, fromage mozza', Plat::where('libelle', 'Pizza du gîte (grande)')->firstOrFail()->description);
        $this->assertSame('Viande de bœuf, saucisse', Plat::where('libelle', 'Chawarma mixte')->firstOrFail()->description);
        $this->assertNull($surCommande->description);
    }

    #[Test]
    public function les_doublons_de_la_carte_sont_ecartes_et_listes(): void
    {
        $carte = app(CarteGiteChezNoelService::class);

        $ecartes = array_map(static fn (array $d): string => $d['nom'].'|'.$d['rubrique'], $carte->doublonsEcartes());
        sort($ecartes);

        $this->assertSame(['Piron|Accompagnement (affiche 6)'], $ecartes);

        $noms = array_column($carte->lignes('m4-restaurant'), 'libelle');
        $this->assertSame($noms, array_values(array_unique($noms)), 'Aucun nom en double dans le fichier.');
        $this->assertContains('Panini jambon', $noms);
        $this->assertContains('Panini', $noms);
        $this->assertContains('Panini (sur commande)', $noms);
        $this->assertContains('Igname pilé (sur commande)', $noms);
        $this->assertNotContains('Jus de banane', array_column($carte->lignes('m5-bar'), 'libelle'));
        $this->assertContains('Pommes sautées', $noms);
    }

    #[Test]
    public function les_fichiers_deposes_dans_docs_data_sont_ceux_que_l_application_genere(): void
    {
        $dossier = base_path('../docs/data');

        if (! is_dir($dossier)) {
            $this->markTestSkipped('Le dossier docs/ n\'est pas déployé.');
        }

        $this->assertFileEquals($dossier.'/carte_gite_chez_noel_2026.json', database_path('data/carte_gite_chez_noel_2026.json'));

        $carte = app(CarteGiteChezNoelService::class);
        $tableur = app(TableurService::class);

        foreach (CarteGiteChezNoelService::MODULES as $cle) {
            $chemin = "{$dossier}/modele_import_{$cle}.xlsx";
            $this->assertFileExists($chemin);

            $module = ReferentielsImport::parCle($cle);
            $lu = $tableur->lire($chemin);
            $attendu = $tableur->lireContenu($carte->classeur($cle));

            $this->assertSame($attendu, $lu, "docs/data/modele_import_{$cle}.xlsx est périmé : relancer `php artisan import:generer-carte-gite`.");
            $this->assertSame(array_map(static fn ($c): string => $c->libelle, $module->colonnes), $lu[0]);
            $this->assertCount(count($carte->lignes($cle)) + 1, $lu);
        }
    }

    // ----------------------------------------------------------- écran Stocks

    #[Test]
    public function l_import_d_articles_de_l_ecran_stocks_lit_le_xlsx_par_nom_d_en_tete(): void
    {
        $magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        // Colonnes dans le désordre, dont deux absentes : lues par nom.
        $colonnes = ReferentielsImport::colonnesArticlesEcranStocks();
        $ordre = ['unite_mesure', 'nom', 'stock_initial', 'point_stockage', 'prix_achat', 'categorie'];
        $enTetes = array_map(fn (string $champ): string => collect($colonnes)->firstWhere('champ', $champ)->libelle, $ordre);

        $classeur = new \PhpOffice\PhpSpreadsheet\Spreadsheet();
        $feuille = $classeur->getActiveSheet()->setTitle('Modèle');
        $feuille->fromArray($enTetes, null, 'A1');
        $feuille->fromArray(['kg', 'Sucre en poudre', 10, 'Magasin général', 32000, 'Denrées'], null, 'A2');
        $chemin = tempnam(sys_get_temp_dir(), 'stk');
        (new \PhpOffice\PhpSpreadsheet\Writer\Xlsx($classeur))->save($chemin);
        $octets = (string) file_get_contents($chemin);
        unlink($chemin);

        Livewire::test(Stocks::class)
            ->call('ouvrirImport')
            ->set('fichierImport', $this->fichier('articles.xlsx', $octets))
            ->call('lancerImport')
            ->assertHasNoErrors();

        $article = Article::where('libelle', 'Sucre en poudre')->firstOrFail();
        $this->assertSame('kg', $article->unite_mesure);
        $this->assertSame('10.00', (string) MouvementStock::where('article_id', $article->id)->firstOrFail()->quantite);
        $this->assertSame($magasin->id, MouvementStock::where('article_id', $article->id)->firstOrFail()->point_id);
    }

    #[Test]
    public function le_modele_de_l_ecran_stocks_est_un_xlsx_dont_les_en_tetes_sont_les_colonnes_du_contrat(): void
    {
        $reponse = Livewire::test(Stocks::class)->call('telechargerModele');
        $reponse->assertFileDownloaded('modele_import_articles.xlsx');

        $octets = app(TableurService::class)->ecrireClasseur('x', 'y', ReferentielsImport::colonnesArticlesEcranStocks());
        $this->assertSame(Stocks::COLONNES_IMPORT, app(TableurService::class)->lireContenu($octets)[0]);
    }
}
