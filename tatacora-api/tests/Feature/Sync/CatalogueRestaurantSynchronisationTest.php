<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Models\User;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Carte du restaurant créée hors connexion — lot S2 (décision du Product
 * Owner du 15/10/2026) : menus, fiches techniques (avec composition), plats.
 *
 * Un plat exige son menu et sa fiche (NOT NULL) : les trois remontent, dans
 * l'ordre, et le plat cite les deux autres sous les UUID du poste — traduits
 * par les correspondances quand ils ont été fusionnés.
 */
final class CatalogueRestaurantSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $cuisinier;

    private Article $poulet;

    private Article $oignon;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        // `cuisine` : M4 = C.
        $this->cuisinier = $this->creerUtilisateur('cuisine');

        $articles = app(ReferentielArticleService::class);
        $this->poulet = $articles->creer(['libelle' => 'Poulet', 'categorie' => 'Viandes', 'unite_mesure' => 'kg', 'seuil_alerte' => '1']);
        $this->oignon = $articles->creer(['libelle' => 'Oignon', 'categorie' => 'Légumes', 'unite_mesure' => 'kg', 'seuil_alerte' => '1']);
    }

    #[Test]
    public function menu_fiche_composee_et_plat_crees_dans_le_meme_lot(): void
    {
        [$menu, $recette, $plat] = [$this->uuid(), $this->uuid(), $this->uuid()];

        $this->pousser([
            $this->creation('menus', $menu, ['libelle' => 'Carte locale', 'type' => 'local']),
            $this->creation('recettes', $recette, ['libelle' => 'Poulet DG', 'lignes' => [
                ['article_id' => $this->poulet->id, 'quantite_unitaire' => '0.250'],
                ['article_id' => $this->oignon->id, 'quantite_unitaire' => '0.05'],
            ]]),
            $this->creation('plats', $plat, [
                'libelle' => 'Poulet DG', 'menu_id' => $menu, 'recette_id' => $recette, 'prix_vente' => '4500',
            ]),
        ], $this->cuisinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.2.statut', 'synchronise');

        $cree = Plat::findOrFail($plat);
        $this->assertSame([$menu, $recette], [$cree->menu_id, $cree->recette_id]);

        // La composition est passée par `CompositionRecetteService` : lignes
        // écrites, marque « provisoire » tombée, auteur tracé.
        $composition = DB::table('ingredients_recette')->where('recette_id', $recette)
            ->pluck('quantite_unitaire', 'article_id')->map(fn (mixed $q): string => (string) $q)->all();
        $attendue = [$this->poulet->id => '0.250', $this->oignon->id => '0.050'];
        ksort($composition);
        ksort($attendue);
        $this->assertSame($attendue, $composition);
        $this->assertFalse((bool) Recette::findOrFail($recette)->composition_provisoire);
        $this->assertSame($this->cuisinier->id, Recette::findOrFail($recette)->utilisateur_creation_id);
    }

    /**
     * Menu et fiche existent côté serveur : le poste les fusionne, et son plat
     * — qui les cite sous ses UUID locaux — est créé dans le menu et sur la
     * fiche du SERVEUR. La composition reçue pour la fiche fusionnée n'écrase
     * pas celle du serveur.
     */
    #[Test]
    public function un_plat_citant_un_menu_et_une_fiche_fusionnes_est_rattache_aux_elements_serveur(): void
    {
        $menuServeur = app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Carte locale', 'type' => 'local']);
        $ficheServeur = app(ReferentielRecetteService::class)->creer(['libelle' => 'Poulet braisé']);
        app(CompositionRecetteService::class)->remplacerComposition($ficheServeur, [
            ['article_id' => $this->poulet->id, 'quantite_unitaire' => '0.300'],
        ]);
        [$menu, $recette, $plat] = [$this->uuid(), $this->uuid(), $this->uuid()];

        $this->pousser([
            $this->creation('menus', $menu, ['libelle' => 'CARTE  LOCALE', 'type' => 'local']),
            $this->creation('recettes', $recette, ['libelle' => 'poulet braise', 'lignes' => [
                ['article_id' => $this->oignon->id, 'quantite_unitaire' => '1'],
            ]]),
            $this->creation('plats', $plat, [
                'libelle' => 'Poulet braisé', 'menu_id' => $menu, 'recette_id' => $recette, 'prix_vente' => '5000',
            ]),
        ], $this->cuisinier)
            ->assertJsonPath('resultats.0.fusionne_avec', $menuServeur->id)
            ->assertJsonPath('resultats.1.fusionne_avec', $ficheServeur->id)
            ->assertJsonPath('resultats.2.entite_id', $plat);

        $cree = Plat::findOrFail($plat);
        $this->assertSame([$menuServeur->id, $ficheServeur->id], [$cree->menu_id, $cree->recette_id]);
        $this->assertSame(1, Menu::count());
        $this->assertSame(1, Recette::count());
        $this->assertSame(
            [$this->poulet->id],
            DB::table('ingredients_recette')->where('recette_id', $ficheServeur->id)->pluck('article_id')->all(),
        );
    }

    /**
     * Clé du plat : libellé normalisé DANS son menu ; clé du menu : libellé ET
     * type (la catégorie d'un plat est le type de son menu).
     */
    #[Test]
    public function un_plat_fusionne_dans_son_menu_et_un_menu_d_un_autre_type_est_un_autre_menu(): void
    {
        $carte = app(CartePlatMenuService::class);
        $local = $carte->creerMenu(['libelle' => 'Fête', 'type' => 'local']);
        $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Igname pilée']);
        $existant = $carte->creerPlat([
            'libelle' => 'Igname pilée', 'menu_id' => $local->id, 'recette_id' => $fiche->id, 'prix_vente' => '3000',
        ]);
        [$special, $memeMenu, $autreMenu] = [$this->uuid(), $this->uuid(), $this->uuid()];

        $this->pousser([
            $this->creation('menus', $special, ['libelle' => 'Fete', 'type' => 'special']),
            $this->creation('plats', $memeMenu, [
                'libelle' => 'IGNAME PILEE', 'menu_id' => $local->id, 'recette_id' => $fiche->id, 'prix_vente' => '9999',
            ]),
            $this->creation('plats', $autreMenu, [
                'libelle' => 'Igname pilée', 'menu_id' => $special, 'recette_id' => $fiche->id, 'prix_vente' => '3500',
            ]),
        ], $this->cuisinier)
            ->assertJsonPath('resultats.0.entite_id', $special)
            ->assertJsonMissingPath('resultats.0.fusionne_avec')
            ->assertJsonPath('resultats.1.fusionne_avec', $existant->id)
            ->assertJsonPath('resultats.2.entite_id', $autreMenu)
            ->assertJsonMissingPath('resultats.2.fusionne_avec');

        $this->assertSame(2, Menu::count());
        $this->assertSame(2, Plat::count());
        $this->assertSame('3000.00', (string) $existant->fresh()->prix_vente);
    }

    #[Test]
    public function les_refus_de_l_api_s_appliquent_avec_leurs_phrases(): void
    {
        $menu = app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Carte', 'type' => 'local']);
        $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Riz gras']);

        $this->pousser([
            // La catégorie d'un plat EST le type de son menu (PA-23).
            $this->creation('plats', $this->uuid(), [
                'libelle' => 'Riz gras', 'menu_id' => $menu->id, 'recette_id' => $fiche->id,
                'prix_vente' => '2500', 'categorie' => 'Plats',
            ]),
            // Le même ingrédient deux fois — le contrôle `withValidator` de
            // la route de composition, pas une seconde règle écrite ici.
            $this->creation('recettes', $this->uuid(), ['libelle' => 'Sauce', 'lignes' => [
                ['article_id' => $this->oignon->id, 'quantite_unitaire' => '0.1'],
                ['article_id' => $this->oignon->id, 'quantite_unitaire' => '0.2'],
            ]]),
            // Le coût matière se CALCULE.
            $this->creation('recettes', $this->uuid(), ['libelle' => 'Pâte', 'cout_matiere_calcule' => '150']),
            $this->creation('plats', $this->uuid(), [
                'libelle' => 'Sans menu', 'menu_id' => $this->uuid(), 'recette_id' => $fiche->id, 'prix_vente' => '100',
            ]),
        ], $this->cuisinier)
            ->assertJsonPath('resultats.0.motif', __('restaurant.validation.categorie_du_menu'))
            ->assertJsonPath('resultats.1.motif', __('restaurant.validation.ingredient_en_double'))
            ->assertJsonPath('resultats.2.motif', __('restaurant.validation.cout_matiere_calcule'))
            ->assertJsonPath('resultats.3.motif', __('restaurant.validation.menu_inexistant'));

        $this->assertSame(0, Plat::count());
        $this->assertSame(1, Recette::count());
    }

    /**
     * Adapté le 15/10/2026 (décision PO « offline-first total ») : sans le
     * droit d'écriture sur M4, création ET modification restent refusées ;
     * avec lui, la modification d'un menu est désormais appliquée.
     */
    #[Test]
    public function sans_ecriture_sur_m4_rien_n_est_cree_ni_modifie(): void
    {
        $menu = app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Carte', 'type' => 'local']);

        // `barman` : M4 = '-' ; `receptionniste` : M4 = 'L'.
        foreach (['barman', 'receptionniste'] as $role) {
            $this->pousser([
                $this->creation('menus', $this->uuid(), ['libelle' => 'Menu ' . $role, 'type' => 'local']),
                $this->creation('recettes', $this->uuid(), ['libelle' => 'Fiche ' . $role]),
                $this->operation('menus', 'modification', $menu->id, ['libelle' => 'Renommé ' . $role]),
            ], $this->creerUtilisateur($role))
                ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'))
                ->assertJsonPath('resultats.1.motif', __('auth.module_refuse'))
                ->assertJsonPath('resultats.2.motif', __('auth.module_refuse'));
        }

        $this->assertSame(['Carte'], Menu::pluck('libelle')->all());
        $this->assertSame(0, Recette::count());

        // Avec le droit : la modification est appliquée par le service.
        $this->pousser([$this->operation('menus', 'modification', $menu->id, ['libelle' => 'Renommé'])], $this->cuisinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(['Renommé'], Menu::pluck('libelle')->all());
        $this->assertSame('local', $menu->fresh()->type);
    }

    /**
     * « Lier au stock » du poste (v36) : la modification du plat porte l'article
     * ET son conditionnement ; le retrait les remet à null ENSEMBLE. Sans ce
     * gestionnaire, `validated()` jetait les deux champs en silence.
     */
    #[Test]
    public function un_plat_se_lie_au_stock_puis_se_delie_par_la_modification(): void
    {
        $menu = app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Carte', 'type' => 'local']);
        $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Eau']);
        $plat = app(CartePlatMenuService::class)->creerPlat([
            'libelle' => 'Eau 50 cl', 'menu_id' => $menu->id, 'recette_id' => $fiche->id, 'prix_vente' => '500',
        ]);

        $this->pousser([
            $this->operation('plats', 'modification', $plat->id, [
                'article_id' => $this->poulet->id, 'unites_vendables_par_unite_stock' => '24.0000',
            ]),
        ], $this->cuisinier)->assertJsonPath('resultats.0.statut', 'synchronise');

        $lie = $plat->fresh();
        $this->assertSame($this->poulet->id, $lie->article_id);
        $this->assertSame('24.0000', (string) $lie->unites_vendables_par_unite_stock);
        $this->assertTrue($lie->aUnLienDirectAuStock());

        $this->pousser([
            $this->operation('plats', 'modification', $plat->id, [
                'article_id' => null, 'unites_vendables_par_unite_stock' => null,
            ]),
        ], $this->cuisinier)->assertJsonPath('resultats.0.statut', 'synchronise');

        $delie = $plat->fresh();
        $this->assertNull($delie->article_id);
        $this->assertNull($delie->unites_vendables_par_unite_stock);
    }

    #[Test]
    public function un_lien_incomplet_ou_inconnu_est_refuse_et_rien_n_est_ecrit(): void
    {
        $menu = app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Carte', 'type' => 'local']);
        $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Eau']);
        $plat = app(CartePlatMenuService::class)->creerPlat([
            'libelle' => 'Eau 50 cl', 'menu_id' => $menu->id, 'recette_id' => $fiche->id, 'prix_vente' => '500',
        ]);

        $this->pousser([
            // Un article sans conditionnement : la phrase du service.
            $this->operation('plats', 'modification', $plat->id, ['article_id' => $this->poulet->id]),
            // Un conditionnement nul.
            $this->operation('plats', 'modification', $plat->id, [
                'article_id' => $this->poulet->id, 'unites_vendables_par_unite_stock' => '0',
            ]),
            // Un article inconnu.
            $this->operation('plats', 'modification', $plat->id, [
                'article_id' => $this->uuid(), 'unites_vendables_par_unite_stock' => '24',
            ]),
        ], $this->cuisinier)
            ->assertJsonPath('resultats.0.motif', __('carte.conversion_requise_avec_lien', ['article' => 'Eau 50 cl']))
            ->assertJsonPath('resultats.1.statut', 'rejete')
            ->assertJsonPath('resultats.2.statut', 'rejete');

        $this->assertNull($plat->fresh()->article_id);
    }

    /** Un plat créé AVEC son lien (poste hors connexion) l'a au serveur. */
    #[Test]
    public function un_plat_cree_avec_son_lien_le_garde(): void
    {
        $menu = app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Carte', 'type' => 'local']);
        $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Eau']);
        $id = $this->uuid();

        $this->pousser([
            $this->creation('plats', $id, [
                'libelle' => 'Eau 1,5 l', 'menu_id' => $menu->id, 'recette_id' => $fiche->id, 'prix_vente' => '700',
                'article_id' => $this->oignon->id, 'unites_vendables_par_unite_stock' => '6',
            ]),
        ], $this->cuisinier)->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame($this->oignon->id, Plat::findOrFail($id)->article_id);
    }
}
