<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Domain\Ventes\Services\VenteService;
use App\Models\User;
use App\Pwa\Livewire\Restaurant\Restauration;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * M4 — l'onglet « Fiches techniques », et la sortie du blocage du POS.
 *
 * ## LE BLOCAGE, mesuré et non supposé (04/09/2026)
 *
 * Constat du Product Owner : **aucune vente possible au point de vente
 * restaurant**. Relevé en base de développement — 83 plats, 83 recettes,
 * **3 lignes d'`ingredients_recette` en tout**. Chaque plat avait donc bien sa
 * fiche technique, et 82 sur 83 étaient VIDES.
 *
 * ⚠ LEVÉ le 30/10/2026 (décision du PO, « le stock s'ajoute après ») : une
 * fiche vide se vend désormais, sans mouvement de stock. Ce qui suit est
 * l'HISTORIQUE du blocage du 04/09/2026 : `DeductionStockCuisineService`
 * levait alors `RecetteManquanteException` sur une nomenclature vide, pour
 * qu'un plat ne se vende jamais sans décrémenter quoi que ce soit. Le blocage
 * était donc la conséquence exacte d'une garde correcte posée sur une donnée
 * absente — la même forme que PA-128 et PA-129, à ceci près qu'ici la donnée
 * existait à moitié : l'entête sans son contenu. C'est pourquoi aucun compte
 * de couverture fondé sur `recettes` ne pouvait le voir, et pourquoi
 * `RestaurantPwaTest` restait vert avec ses 28 cas.
 *
 * ## Le geste qui manquait n'était PAS la création
 *
 * `ouvrirCreationRecette()` était livrée depuis le 03/09/2026. Il n'existait
 * aucun `ouvrirModificationRecette()` : les 83 fiches déjà rattachées aux 83
 * plats étaient inatteignables, et la seule sortie apparente — créer une 84e
 * fiche puis rebrancher chaque plat dessus — aurait laissé 83 fiches
 * orphelines derrière elle.
 *
 * ## Ce que ce fichier prouve, de bout en bout
 *
 * Le premier cas est le seul qui compte vraiment, et il enchaîne les trois
 * moments : la vente SANS mouvement sur une fiche vide, la composition faite
 * depuis l'écran, la MÊME vente qui décrémente, et le stock des deux articles
 * descendu de la quantité exacte. Un cas qui s'arrêterait à « la ligne est en base »
 * prouverait une écriture, pas un déblocage.
 *
 * ## Mutations RÉELLEMENT exécutées puis annulées (04/09/2026)
 *
 * | Mutation | Cas qui rougit | Résultat |
 * |---|---|---|
 * | `Restauration::enregistrerRecette()` n'appelle plus `remplacerComposition()` — seul l'entête est écrit | `une_fiche_vide_se_vend_sans_mouvement_et_la_composition_depuis_l_ecran_fait_decrementer` | 1 failed, l.162 : « La composition n'a pas été écrite par le service. » |
 * | `remplacerComposition()` insère `bcadd('1', …)` au lieu de la quantité de la ligne | idem | 1 failed, l.169 : le riz descend de 2,00 au lieu de 0,50 |
 * | `remplacerComposition()` écrit `$provisoire ?? true` — la marque ne tombe jamais | `la_marque_provisoire_tombe_quand_la_composition_est_enregistree` | 1 failed, l.369 |
 *
 * ⚠ La troisième a d'abord été écrite en RETIRANT la ligne d'`update()`, et
 * elle rougissait alors sur la mauvaise moitié du cas — l'assertion qui vérifie
 * que le seeder POSE la marque, jamais celle qui vérifie qu'elle TOMBE. Une
 * mutation qui rougit ne prouve pas ce qu'on croit tant qu'on n'a pas lu QUELLE
 * assertion a cédé.
 *
 * @see EF-M4-02 Gestion des fiches techniques de recette
 * @see RG-05 Sortie de stock automatique — c'est la composition qui la rend possible
 * @see PA-23 Le textarea « Ingrédients principaux » remplacé par de vraies clés étrangères
 */
final class FichesTechniquesPwaTest extends TestCase
{
    use RefreshDatabase;

    private PointStockage $cuisine;

    private Menu $menu;

    private Article $riz;

    private Article $poulet;

    private Recette $ficheVide;

    private Recette $ficheComposee;

    private Plat $platBloque;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    // =====================================================================
    // LE CAS QUI PROUVE LA SORTIE DE BLOCAGE
    // =====================================================================

    /**
     * Décision du PO du 30/10/2026 (« le stock s'ajoute après ») : une fiche
     * VIDE ne bloque plus la vente. Le plat se vend, sans AUCUN mouvement de
     * stock ; composer la fiche depuis l'écran fait ensuite décrémenter la MÊME
     * vente, de la quantité exacte. (Avant : la première vente était refusée par
     * `RecetteManquanteException`.)
     *
     * ⚠ La vente passe par `VenteService::enregistrer()`, le chemin RÉEL du
     * point de vente — pas par `DeductionStockCuisineService` appelé à la main.
     * C'est la leçon de PA-63 : un essai qui appelle directement le mécanisme
     * prouve que le mécanisme est correct, jamais qu'un écran y mène.
     */
    #[Test]
    public function une_fiche_vide_se_vend_sans_mouvement_et_la_composition_depuis_l_ecran_fait_decrementer(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $stocks = app(StockTheoriqueService::class);
        $rizAvant = $stocks->stock($this->riz->id, $this->cuisine->id);
        $pouletAvant = $stocks->stock($this->poulet->id, $this->cuisine->id);

        // 1. LA VENTE PASSE — la fiche du plat est vide, et rien ne sort du stock.
        $premiere = $this->encaisserLePlat();

        $this->assertDatabaseHas('ventes', ['id' => $premiere->id]);
        $this->assertSame(0, bccomp($stocks->stock($this->riz->id, $this->cuisine->id), $rizAvant, 2));
        $this->assertSame(0, bccomp($stocks->stock($this->poulet->id, $this->cuisine->id), $pouletAvant, 2));
        $this->assertSame(
            'plat_sans_composition',
            $premiere->refresh()->stock_non_impacte[0]['cause'],
            'La vente doit DIRE que ce plat n\'a rien sorti du stock.',
        );

        // 2. LE CUISINIER COMPOSE LA FICHE, depuis l'onglet « Fiches techniques ».
        Livewire::test(Restauration::class)
            ->set('onglet', 'fiches')
            ->call('ouvrirModificationRecette', $this->ficheVide->id)
            ->assertSet('recetteCibleId', $this->ficheVide->id)
            ->assertSet('recetteLibelleSaisi', $this->ficheVide->libelle)
            // Une fiche vide reçoit UNE ligne vierge : sans elle, l'écran
            // n'offrirait aucun champ sur la fiche qu'on vient d'ouvrir pour
            // la remplir.
            ->assertCount('ingredientsSaisis', 1)
            ->set('ingredientsSaisis.0.article_id', $this->riz->id)
            ->set('ingredientsSaisis.0.quantite_unitaire', '0.250')
            ->call('ajouterIngredient')
            ->set('ingredientsSaisis.1.article_id', $this->poulet->id)
            ->set('ingredientsSaisis.1.quantite_unitaire', '0.500')
            ->call('enregistrerRecette')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $lignes = app(CompositionRecetteService::class)->lignes($this->ficheVide->refresh());
        $this->assertCount(2, $lignes, 'La composition n\'a pas été écrite par le service.');

        // 3. LA MÊME VENTE, fiche composée : le stock a bougé de la quantité exacte.
        $vente = $this->encaisserLePlat();

        $this->assertDatabaseHas('ventes', ['id' => $vente->id]);

        $this->assertSame(
            0,
            bccomp($stocks->stock($this->riz->id, $this->cuisine->id), bcsub($rizAvant, '0.50', 2), 2),
            'Le riz n\'a pas baissé de 0,250 × 2 portions.',
        );

        $this->assertSame(
            0,
            bccomp($stocks->stock($this->poulet->id, $this->cuisine->id), bcsub($pouletAvant, '1.00', 2), 2),
            'Le poulet n\'a pas baissé de 0,500 × 2 portions.',
        );
    }

    // =====================================================================
    // L'ÉCRAN
    // =====================================================================

    /**
     * L'onglet est réellement SERVI, et il nomme l'état de chaque fiche.
     *
     * `RestaurantPwaTest` prouve la page ; ce cas prouve l'onglet, qui n'est
     * pas rendu au premier GET (une entrée d'onglet inerte est ce que
     * l'Article 3.3 de la Directive interdit).
     */
    #[Test]
    public function l_onglet_fiches_techniques_liste_les_fiches_avec_leur_etat(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = Livewire::test(Restauration::class)->set('onglet', 'fiches')->html();

        $this->assertStringContainsString('Fiches techniques', $html);
        $this->assertStringContainsString($this->ficheVide->libelle, $html);
        $this->assertStringContainsString($this->ficheComposee->libelle, $html);

        // L'ÉTAT, qui est le sujet de l'onglet : une fiche vide doit se
        // repérer, c'est elle qui ne sort aucun stock à la vente.
        $this->assertStringContainsString('Vide — ne décrémente rien', $html);
        $this->assertStringContainsString('Composée', $html);

        // Le PLAT servi : « Fiche à écrire » ne dit rien, « Fiche à écrire —
        // Riz sauce » dit quel plat ne sort aucun stock.
        $this->assertStringContainsString($this->platBloque->libelle, $html);
    }

    /**
     * LE TROISIEME ETAT : composee, et pourtant elle ne decremente rien.
     *
     * Une fiche dont tous les ingredients sont des articles `journalier`
     * (laitue, tomate, oignon, concombre — achetes le matin, jamais
     * inventories) ne fait bouger aucun stock. C'est la verite d'une salade
     * verte, et la vente passe : `DeductionStockCuisineService` ecarte les
     * articles non suivis depuis le 04/09/2026, sans quoi chacun de ces plats
     * levait `RuptureStockException` au comptoir sur un article a zero que
     * personne ne reapprovisionne.
     *
     * Rendue « Composee » sans plus, elle se lirait comme une fiche qui
     * decremente — un indicateur qui affirme un etat qu'il n'a pas verifie
     * (PA-59/60/61). L'ecran en fait donc un etat a part.
     */
    #[Test]
    public function une_fiche_dont_rien_n_est_suivi_le_dit_au_lieu_de_se_dire_composee(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        // Un article suivi « au jour le jour » : pas de mouvement, pas
        // d'inventaire, pas de valorisation (`Article::estSuiviEnStock`).
        $laitue = Article::create([
            'libelle' => 'Laitue',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'suivi' => 'journalier',
            'seuil_alerte' => '0.00',
            'seuil_reappro' => '0.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $salade = Recette::create(['libelle' => 'Fiche de la salade verte']);
        app(CompositionRecetteService::class)->remplacerComposition($salade, [
            ['article_id' => $laitue->id, 'quantite_unitaire' => '0.080'],
        ]);

        $this->assertFalse($salade->refresh()->load('ingredients')->decrementeUnStockSuivi());

        $html = Livewire::test(Restauration::class)->set('onglet', 'fiches')->html();

        $this->assertStringContainsString('Aucun stock suivi', $html);

        // Et elle n'est ni « vide » ni annoncee comme decrementante : les trois
        // etats sont distincts, sinon l'ecran n'en dirait qu'un.
        $this->assertGreaterThan(0, $salade->ingredients()->count());
    }

    /**
     * Le filtre « fiches vides seulement » ne montre QUE les vides.
     *
     * Avec 83 fiches sur neuf pages, les repérer à l'œil est impraticable :
     * c'est exactement la situation où l'on conclut « l'écran ne marche pas »
     * plutôt que « la donnée manque ».
     */
    #[Test]
    public function le_filtre_fiches_vides_ne_montre_que_les_vides(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = Livewire::test(Restauration::class)
            ->set('onglet', 'fiches')
            ->set('videsSeulement', true)
            ->html();

        $this->assertStringContainsString($this->ficheVide->libelle, $html);
        $this->assertStringNotContainsString(
            $this->ficheComposee->libelle,
            $html,
            'Le filtre « fiches vides » laisse passer une fiche composée.',
        );
    }

    /**
     * Le coût matière affiché est celui du SERVICE, dans ses trois états.
     *
     * Le recalculer dans l'écran en ferait une seconde formule, et les deux
     * divergeraient au premier changement (PA-121). Et un « 0 F » à la place
     * de « non calculable » ou d'« incomplet » se lirait comme un plat
     * gratuit, sur la liste même où l'on décide quoi corriger (PA-126).
     */
    #[Test]
    public function le_cout_matiere_affiche_vient_du_service_et_porte_ses_trois_etats(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $compositions = app(CompositionRecetteService::class);

        // Une TROISIÈME fiche, dont l'unique article n'a jamais été
        // réceptionné : son coût moyen pondéré vaut zéro, elle n'est donc pas
        // gratuite — elle est NON VALORISÉE.
        $sansCout = Article::create([
            'libelle' => 'Piment frais (jamais réceptionné)',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '1.00',
            'seuil_reappro' => '2.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $ficheIncomplete = Recette::create(['libelle' => 'Fiche au piment']);
        $compositions->remplacerComposition($ficheIncomplete, [
            ['article_id' => $sansCout->id, 'quantite_unitaire' => '0.050'],
        ]);

        $html = Livewire::test(Restauration::class)->set('onglet', 'fiches')->html();

        // 1. Un MONTANT — celui que le service calcule, jamais un autre.
        $attendu = $compositions->coutMatiere($this->ficheComposee);
        $this->assertNotNull($attendu->montant);
        $this->assertStringContainsString(
            \App\Pwa\Support\MontantFcfa::format((string) $attendu->montant),
            $html,
        );

        // 2. INCOMPLET, et l'article fautif est NOMMÉ.
        $this->assertStringContainsString('Incomplet', $html);
        $this->assertStringContainsString('Piment frais (jamais réceptionné)', $html);

        // 3. NON CALCULABLE sur la composition vide — jamais « 0 FCFA »
        //    (suffixe « FCFA » depuis PA-186 : le cas suit le format réel, sans
        //    quoi il passerait à vide).
        $this->assertStringContainsString('Non calculable', $html);
        $this->assertStringNotContainsString(
            '>0 FCFA<',
            $html,
            'Un « 0 FCFA » sur une fiche sans coût se lirait comme un plat gratuit (PA-126).',
        );
    }

    /**
     * Un rôle en lecture seule sur M4 est refusé sur les DEUX ouvertures et
     * sur l'enregistrement.
     *
     * L'ouverture compte autant que l'écriture : présenter un formulaire à
     * quelqu'un qui ne pourra pas le soumettre lui fait perdre sa saisie et ne
     * lui apprend rien.
     */
    #[Test]
    public function un_role_en_lecture_seule_ne_peut_pas_composer_une_fiche(): void
    {
        $this->jeuDeDonnees();

        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M4'));

        $lignesAvant = DB::table('ingredients_recette')->count();

        foreach ([
            ['ouvrirModificationRecette', [$this->ficheVide->id]],
            ['ouvrirModificationMenu', [$this->menu->id]],
        ] as [$methode, $arguments]) {
            $this->actingAs($comptable);

            Livewire::test(Restauration::class)
                ->call($methode, ...$arguments)
                ->assertForbidden();
        }

        $this->assertSame($lignesAvant, DB::table('ingredients_recette')->count());
    }

    // =====================================================================
    // LA MARQUE « COMPOSITION PROVISOIRE » (04/09/2026)
    // =====================================================================

    /**
     * La marque TOMBE toute seule dès que la composition est enregistrée.
     *
     * C'est un FAIT, pas une case à cocher : composer la fiche EST le geste
     * qui cesse de rendre « provisoire » vrai. Demander en plus de le déclarer
     * reviendrait à faire déclarer ce qu'on vient de faire, et on l'oublierait
     * — le raisonnement de `MarquesDePrix` sur `prix_corrige_main`.
     */
    #[Test]
    public function la_marque_provisoire_tombe_quand_la_composition_est_enregistree(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        // Une fiche POSÉE par le référentiel de démonstration : des quantités
        // plausibles, jamais pesées.
        app(CompositionRecetteService::class)->remplacerComposition(
            $this->ficheVide,
            [['article_id' => $this->riz->id, 'quantite_unitaire' => '0.010']],
            provisoire: true,
        );

        $this->assertTrue($this->ficheVide->refresh()->composition_provisoire);

        // Elle est DITE à l'écran — sans quoi une quantité devinée et une
        // quantité pesée seraient indiscernables, et l'écart ne se verrait
        // qu'à l'inventaire, imputé à une perte physique qui n'a pas eu lieu.
        $html = Livewire::test(Restauration::class)->set('onglet', 'fiches')->html();
        $this->assertStringContainsString('Provisoire', $html);

        Livewire::test(Restauration::class)
            ->call('ouvrirModificationRecette', $this->ficheVide->id)
            ->set('ingredientsSaisis.0.quantite_unitaire', '0.300')
            ->call('enregistrerRecette')
            ->assertHasNoErrors();

        $this->assertFalse(
            $this->ficheVide->refresh()->composition_provisoire,
            'La marque « provisoire » doit tomber d\'elle-même à l\'enregistrement.',
        );
    }

    /**
     * Le référentiel de démonstration ne laisse AUCUNE fiche vide, et marque
     * tout ce qu'il pose.
     *
     * ⚠ Les deux moitiés comptent. Sans la première, le point de vente
     * restaurant ne décrémente rien sur une base neuve — c'est le défaut du
     * 04/09/2026. Sans la seconde, 82 grammages devinés seraient
     * indiscernables des grammages relevés en cuisine.
     *
     * Le Tchep au poisson est la SEULE fiche non marquée : c'est la seule dont
     * les quantités viennent de la cuisine et non d'un fichier de seeder.
     */
    #[Test]
    public function le_referentiel_de_demonstration_ne_laisse_aucune_fiche_vide(): void
    {
        $this->seed(\Database\Seeders\StocksSeeder::class);
        $this->seed(\Database\Seeders\RestaurantSeeder::class);

        $total = Recette::query()->count();
        $this->assertGreaterThanOrEqual(83, $total, 'Le référentiel des 83 préparations est amputé.');

        $vides = Recette::query()->whereDoesntHave('ingredients')->count();
        $this->assertSame(
            0,
            $vides,
            "Le référentiel laisse {$vides} fiche(s) vide(s) : autant de plats dont la vente ne "
            .'sortirait aucun stock.',
        );

        $this->assertSame(
            $total - 1,
            Recette::query()->where(Recette::PROVISOIRE, true)->count(),
            'Toute composition posée par le seeder doit porter la marque « provisoire », sauf la '
            .'seule fiche réellement pesée (Tchep au poisson).',
        );

        $this->assertFalse(
            Recette::query()->where('libelle', 'Tchep au poisson')->firstOrFail()->composition_provisoire,
            'La seule fiche pesée ne doit pas être marquée provisoire.',
        );

        // ⚠ La quantité de STOCK est un DECIMAL(10,2) alors que la fiche est
        // au millième (PA-38) : une quantité sous 0,005 est ramenée à `0.00`
        // par `arrondirQuantite()`. Une ligne posée sous ce seuil figurerait à
        // la fiche sans rien décrémenter — exactement ce que la fiche existe
        // pour empêcher.
        $tropFines = DB::table('ingredients_recette')
            ->where('quantite_unitaire', '<', '0.005')
            ->count();

        $this->assertSame(
            0,
            $tropFines,
            'Une quantité sous 0,005 est arrondie à zéro à la sortie de stock (PA-38) : la ligne '
            .'figurerait à la fiche sans rien décrémenter.',
        );
    }

    // =====================================================================
    // L'ONGLET « MENUS » ET LE PARCOURS COMPLET
    // =====================================================================

    /**
     * L'onglet Menus liste les cartes existantes ET permet de les corriger.
     *
     * `menus` n'avait qu'une écriture — la création : une saison mal saisie
     * était définitive, et la table n'a aucune colonne d'archivage (RG-02, le
     * « D » de CRUD n'existe nulle part).
     */
    #[Test]
    public function l_onglet_menus_liste_les_cartes_et_permet_de_les_corriger(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = Livewire::test(Restauration::class)->set('onglet', 'menus')->html();

        $this->assertStringContainsString($this->menu->libelle, $html);
        // Le menu du jeu d'essai n'a pas de saison : « Permanent », jamais un
        // tiret qui se lirait comme une donnée manquante.
        $this->assertStringContainsString('Permanent', $html);

        Livewire::test(Restauration::class)
            ->set('onglet', 'menus')
            ->call('ouvrirModificationMenu', $this->menu->id)
            ->assertSet('menuCibleId', $this->menu->id)
            ->assertSet('menuLibelleSaisi', $this->menu->libelle)
            ->set('menuLibelleSaisi', 'Carte de saison sèche')
            ->set('menuDateDebutSaisie', '2026-11-01')
            ->set('menuDateFinSaisie', '2027-03-31')
            ->call('enregistrerMenu')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $menu = $this->menu->refresh();
        $this->assertSame('Carte de saison sèche', $menu->libelle);
        $this->assertSame('2026-11-01', $menu->date_debut?->format('Y-m-d'));

        // Rien n'a été créé au passage : modifier n'est pas dupliquer.
        $this->assertSame(1, Menu::count());
    }

    /**
     * Le parcours COMPLET depuis cet écran : un menu, une fiche composée, un
     * plat — sans jamais quitter la page.
     *
     * Exigence explicite du Product Owner (04/09/2026) : « rendre la tâche
     * facile à l'user ». Les trois gestes sont sur le même écran, et le
     * bouton « Nouveau plat » y est réellement rendu — un bouton absent est
     * indiscernable d'une fonction manquante.
     */
    #[Test]
    public function le_parcours_menu_fiche_plat_tient_sur_le_seul_ecran_restauration(): void
    {
        // `mouvements_stock.utilisateur_id` est NOT NULL (RG-15) : une
        // réception doit porter le nom de qui l'a saisie.
        $this->actingAs($this->utilisateur('administrateur'));

        $cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);
        $farine = Article::create([
            'libelle' => 'Farine de blé',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '2.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '0.0000',
        ]);
        app(MouvementStockService::class)->entree($farine->id, $cuisine->id, '50.00', 'Réception', '600.00');

        // Le bouton du geste est RENDU sur la page servie.
        $premierRendu = Livewire::test(Restauration::class)->html();
        $this->assertStringContainsString('wire:click="ouvrirCreationPlat"', $premierRendu);
        $this->assertStringContainsString('Nouveau plat', $premierRendu);

        $ecran = Livewire::test(Restauration::class)
            ->call('ouvrirCreationPlat')
            // Depuis le formulaire de plat : créer le menu qui manque, et
            // revenir SANS perdre la saisie.
            ->set('libelleSaisi', 'Crêpe du gîte')
            ->set('prixVenteSaisi', '1500')
            ->call('ouvrirCreationMenu')
            ->assertSet('retourAuPlat', true)
            ->set('menuLibelleSaisi', 'Carte du jour')
            ->call('enregistrerMenu')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', 'plat')
            ->assertSet('libelleSaisi', 'Crêpe du gîte')
            // Puis la fiche technique, COMPOSÉE d'emblée.
            ->call('ouvrirCreationRecette')
            ->assertSet('retourAuPlat', true)
            ->set('recetteLibelleSaisi', 'Fiche crêpe')
            ->set('ingredientsSaisis.0.article_id', $farine->id)
            ->set('ingredientsSaisis.0.quantite_unitaire', '0.100')
            ->call('enregistrerRecette')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', 'plat');

        // Les deux sélecteurs sont PRÉ-SÉLECTIONNÉS : faire retaper le plat
        // serait punir l'utilisateur d'avoir suivi le seul chemin possible.
        $ecran->assertSet('menuIdSaisi', Menu::where('libelle', 'Carte du jour')->firstOrFail()->id);
        $ecran->assertSet('recetteIdSaisie', Recette::where('libelle', 'Fiche crêpe')->firstOrFail()->id);

        $ecran->call('enregistrerPlat')->assertHasNoErrors()->assertSet('etatFormulaire', null);

        $plat = Plat::where('libelle', 'Crêpe du gîte')->firstOrFail();

        // La fiche du plat neuf n'est PAS vide : le parcours produit un plat
        // réellement vendable, pas un plat de plus à corriger.
        $this->assertTrue($plat->recette->ingredients->isNotEmpty());
        $this->assertFalse($plat->recette->composition_provisoire);
    }

    /**
     * L'écran du catalogue est ATTEIGNABLE par un clic — il ne l'était pas.
     *
     * `/pwa/restaurant/plats` porte « Nouveau plat », les fiches techniques et
     * les menus. L'entrée de menu « Restaurant » pointe sur
     * `pwa.restaurant.carte` (le maître n'a qu'une entrée par rayon), et
     * AUCUNE vue du dépôt ne renvoyait vers l'autre : seule la recherche
     * globale y menait. Un écran livré qu'aucun clic n'atteint est le
     * symétrique exact de l'entrée de menu inerte que l'Article 3.3 interdit —
     * et c'est ce qui a fait croire que le geste de composition n'existait pas.
     *
     * ⚠ Le cas vérifie le lien ET la page d'arrivée. Un `href` vers une route
     * qu'un rôle ne peut pas ouvrir serait le même défaut sous une autre forme.
     */
    #[Test]
    public function l_ecran_du_catalogue_est_atteignable_depuis_la_carte_du_restaurant(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $carte = (string) $this->get('/pwa/restaurant/carte')->assertOk()->getContent();

        $this->assertStringContainsString('href="'.route('pwa.restaurant.plats').'"', $carte);
        $this->assertStringContainsString('Plats, fiches techniques &amp; menus', $carte);

        $catalogue = (string) $this->get(route('pwa.restaurant.plats'))->assertOk()->getContent();
        $this->assertStringContainsString('Fiches techniques', $catalogue);
    }

    // =====================================================================
    // Décor
    // =====================================================================

    /**
     * Encaisse deux portions du plat bloqué par le chemin RÉEL du comptoir.
     */
    private function encaisserLePlat(): \App\Domain\Ventes\Models\Vente
    {
        return app(VenteService::class)->enregistrer([
            'point_vente' => 'Restaurant',
            'mode_paiement' => 'especes',
            'lignes' => [
                ['module' => 'M4', 'reference_id' => $this->platBloque->id, 'quantite' => 2],
            ],
        ]);
    }

    private function jeuDeDonnees(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $this->cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);

        $this->riz = Article::create([
            'libelle' => 'Riz local (kg)',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '20.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $this->poulet = Article::create([
            'libelle' => 'Poulet fermier',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '2.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($this->riz->id, $this->cuisine->id, '40.00', 'Réception', '800.00');
        $mouvements->entree($this->poulet->id, $this->cuisine->id, '30.00', 'Réception', '3500.00');

        $this->menu = Menu::create(['libelle' => 'Carte du restaurant', 'type' => 'local']);

        // LA FICHE VIDE — celle qui bloque la vente.
        $this->ficheVide = Recette::create(['libelle' => 'Fiche à écrire']);

        $this->ficheComposee = Recette::create(['libelle' => 'Fiche du poulet rôti']);
        app(CompositionRecetteService::class)->remplacerComposition($this->ficheComposee, [
            ['article_id' => $this->poulet->id, 'quantite_unitaire' => '0.400'],
        ]);

        $this->platBloque = Plat::create([
            'menu_id' => $this->menu->id,
            'recette_id' => $this->ficheVide->id,
            'categorie' => 'Plats complets',
            'libelle' => 'Riz sauce arachide',
            'prix_vente' => '2500.00',
        ]);

        Plat::create([
            'menu_id' => $this->menu->id,
            'recette_id' => $this->ficheComposee->id,
            'categorie' => 'Plats complets',
            'libelle' => 'Poulet rôti',
            'prix_vente' => '4500.00',
        ]);

        /*
         * Le référentiel comptable fait partie du décor MINIMAL d'une vente
         * depuis la règle du 31/08/2026 : un encaissement sans pièce n'est
         * plus enregistré du tout. Un cas qui vendrait sans plan comptable
         * décrirait le refus, pas la vente.
         */
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->assertTrue(JournalComptable::query()->where('code', 'VTE')->exists());
    }

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.'.$role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
