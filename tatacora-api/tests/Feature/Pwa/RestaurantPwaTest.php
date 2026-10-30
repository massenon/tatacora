<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Models\User;
use App\Pwa\Livewire\Restaurant\CarteRestaurant;
use App\Pwa\Livewire\Restaurant\Restauration;
use App\Pwa\Livewire\Transverse\ClocheNotifications;
use App\Pwa\Livewire\Transverse\RechercheGlobale;
use App\Pwa\Support\MontantFcfa;
use App\Shared\Rbac\Models\Role;
use Carbon\CarbonImmutable;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\LitUnDocumentTelecharge;
use Tests\TestCase;

/**
 * M4 — Carte du restaurant et catalogue des plats.
 *
 * Vues maîtresses (PA-183) : `resources/views/pwa/restaurant/carte.blade.php`
 * (corps partagé `pwa/carte/corps.blade.php`) et
 * `resources/views/pwa/restaurant/restauration.blade.php`.
 *
 * ## Ce que ce fichier prouve
 *
 * 1. **`plats.article_id` est réellement exploité.** La colonne était déclarée
 *    sur le modèle et n'existait dans AUCUNE migration : Eloquent lisait un
 *    attribut absent comme `null`, la relation ne ramenait jamais rien, et
 *    l'écran affichait un tiret sur tout le monde.
 * 2. **« Délier » retire les DEUX colonnes.** Laisser le conditionnement
 *    derrière l'article afficherait un taux de conversion sur un plat qui ne
 *    décrémente plus rien par ce chemin.
 * 3. **Un plat à fiche technique n'est PAS compté « ne décrémente rien ».**
 *    Il décrémente par sa recette (EF-M4-02) : le compter dans la dette de
 *    couverture afficherait un écart qui n'existe pas.
 * 4. **Il n'y a plus de suppression ni de boîte native.** Le geste est
 *    « Retirer de la carte » — le motif `retire` du maître —, et il refuse un
 *    plat engagé dans une commande en cours.
 * 5. **Le formulaire exige menu ET recette**, parce que les deux colonnes sont
 *    NOT NULL : « Aucune fiche technique » faisait échouer l'insertion.
 *
 * ## Mutations RÉELLEMENT rejouées le 31/08/2026 — chaque cas prouvé non vide
 *
 * | Mutation | Cas qui rougit | Résultat |
 * |---|---|---|
 * | `CarteRestaurant::decremente()` rend `false` pour la branche « fiche technique » — la mesure du bar appliquée au restaurant | `un_plat_a_fiche_technique_ne_compte_pas_pour_ne_decremente_rien` | 1 failed |
 * | `Restauration::confirmerRetraitDuPlat()` n'évalue plus `verrousDuPlat()` | `un_plat_engage_dans_une_commande_en_cours_ne_se_retire_pas` | 1 failed |
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M4-02 Fiches techniques (recettes)
 * @see RG-02 Aucune suppression physique
 */
final class RestaurantPwaTest extends TestCase
{
    use LitUnDocumentTelecharge;
    use RefreshDatabase;

    private Menu $menu;

    private Recette $recetteGarnie;

    private Recette $recetteVide;

    private Article $bouteilleEau;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    /* ================================================= carte du restaurant */

    #[Test]
    public function la_carte_du_restaurant_est_reellement_servie(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/restaurant/carte')->assertOk()->getContent();

        $this->assertStringContainsString('<title>Carte du restaurant — LogiReStock — TATACORA AFRIQUE</title>', $html);
        $this->assertSame(1, substr_count($html, '<h1 '), 'Un seul <h1> par page.');
        $this->assertStringContainsString('>Carte du restaurant</h1>', $html);
        $this->assertStringContainsString('<body data-module="M4"', $html);

        // Le sous-titre du MAÎTRE.
        $this->assertStringContainsString('Le stock affiché est <strong>calculé</strong>, jamais saisi.', $html);
        // Le bandeau jaune « Un plat n'est pas un article de stock : c'est une
        // recette… » est RETIRÉ (PO, 30/10/2026). Blade échappe l'apostrophe.
        $this->assertStringNotContainsString('c&#039;est une recette', $html);
        $this->assertStringNotContainsString('ne décrémentent rien à la vente. La valeur', $html);

        $this->assertStringContainsString('Poulet DG', $html);
    }

    /**
     * PA-161 (b) — la marque « corrigé à la main », celle que le bar n'a pas.
     *
     * Six lignes de sandwicherie du maître la portent SANS être provisoires :
     * une étiquette manuscrite a remplacé l'imprimé, et « ce sont les prix
     * MANUSCRITS qui font foi » (`referentiel-carte.js` l.14-20). C'est pour
     * cela que les deux marques sont deux colonnes et non un seul drapeau : la
     * raison dit quoi faire — relever l'ardoise, ou réimprimer la carte.
     *
     * Le motif de refus, lui, a DISPARU : il disait qu'aucune colonne ne
     * portait ces marques, ce qui a cessé d'être vrai (PA-144).
     *
     * Prouvé par mutation (02/09/2026) : retirer le bloc `@if
     * ($ligne['prix_corrige_main'])` de `pwa/carte/corps.blade.php` rougit sur
     * la première assertion.
     */
    #[Test]
    public function la_marque_corrige_a_la_main_est_rendue_et_son_refus_a_disparu(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/restaurant/carte')->assertOk()->getContent();

        // Les classes sont celles du maître, au caractère près
        // (`carte-module.js` l.109) : ambre, sans graisse, 10 px.
        $this->assertStringContainsString(
            '<div class="text-[10px] text-amber-600">corrigé à la main</div>',
            $html,
            'La marque « corrigé à la main » du maître n\'est pas rendue avec ses classes.',
        );

        // UNE seule ligne la porte : sans le cast `boolean`, le `tinyint(1)`
        // arriverait en chaîne « 0 », vraie en PHP, et la marque s'afficherait
        // sur toute la carte.
        $this->assertSame(1, substr_count($html, '>corrigé à la main</div>'));

        $this->assertStringNotContainsString(
            'ne portent de colonne les portant',
            $html,
            'Le motif de refus des prix provisoires a cessé d\'être vrai et doit avoir disparu.',
        );
    }

    #[Test]
    public function un_profil_sans_droit_sur_m4_est_refuse(): void
    {
        $barman = $this->utilisateur('barman');
        $this->assertSame('-', $barman->niveauSurModule('M4'), 'La matrice a changé : ce cas ne vérifie plus rien.');

        $this->actingAs($barman);
        $this->get('/pwa/restaurant/carte')->assertForbidden();
        $this->get('/pwa/restaurant/plats')->assertForbidden();
    }

    /**
     * `plats.article_id` EXISTE et l'écran l'exploite : le lien direct est
     * l'exception du maître — une bouteille d'eau servie à table.
     */
    #[Test]
    public function le_lien_direct_au_stock_d_un_plat_est_ecrit_avec_son_conditionnement(): void
    {
        $this->jeuDeDonnees();
        $eau = Plat::where('libelle', 'Bouteille d\'eau 1,5 L')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteRestaurant::class)
            ->call('ouvrirLienAuStock', $eau->id)
            ->set('articleStockId', $this->bouteilleEau->id)
            ->set('unitesVendablesParUniteStock', '12')
            ->call('enregistrerLienAuStock')
            ->assertHasNoErrors();

        $eau->refresh();

        $this->assertSame($this->bouteilleEau->id, $eau->article_id);
        $this->assertSame(0, bccomp((string) $eau->unites_vendables_par_unite_stock, '12', 4));
        $this->assertTrue($eau->aUnLienDirectAuStock());
        // Un pack de 12 vendu retire exactement une unité de stock.
        $this->assertSame('1.0000', $eau->stockConsommePour('12'));
    }

    /**
     * « Délier » retire les DEUX colonnes — elles vont toujours ensemble.
     */
    #[Test]
    public function delier_retire_les_deux_colonnes_du_lien_direct(): void
    {
        $this->jeuDeDonnees();
        $eau = Plat::where('libelle', 'Bouteille d\'eau 1,5 L')->firstOrFail();
        $eau->update([
            'article_id' => $this->bouteilleEau->id,
            'unites_vendables_par_unite_stock' => '12.0000',
        ]);

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteRestaurant::class)
            ->call('ouvrirRetraitDuLien', $eau->id)
            ->assertSet('etatFormulaire', 'delier')
            ->call('confirmerRetraitDuLien')
            ->assertHasNoErrors();

        $eau->refresh();

        $this->assertNull($eau->article_id);
        $this->assertNull(
            $eau->unites_vendables_par_unite_stock,
            'Le conditionnement est resté : l\'écran afficherait un taux de conversion sur un plat '
            .'qui ne décrémente plus rien par ce chemin.',
        );
    }

    /**
     * Un plat dont la recette porte au moins un ingrédient DÉCRÉMENTE.
     *
     * Le compter « ne décrémente rien » afficherait une dette de couverture
     * qui n'existe pas, sur l'indicateur même qui sert à la résorber. Une
     * recette VIDE, en revanche, ne décrémente rien et doit être comptée.
     */
    #[Test]
    public function un_plat_a_fiche_technique_ne_compte_pas_pour_ne_decremente_rien(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/restaurant/carte?onglet=couverture')->assertOk()->getContent();

        // La ligne TOTAL du maître — aucune des deux vues livrées ne la rendait.
        $this->assertStringContainsString('TOTAL', $html);

        // Trois plats : « Poulet DG » (recette garnie) décrémente ; « Salade
        // nue » (recette vide) et « Bouteille d'eau » (sans lien) non.
        $html = (string) $this->get('/pwa/restaurant/carte?etat=sans_lien')->assertOk()->getContent();

        $this->assertStringContainsString('Salade nue', $html);
        $this->assertStringContainsString('Bouteille d&#039;eau', $html);
        $this->assertStringNotContainsString('>Poulet DG</div>', $html);
    }

    /**
     * La fiche technique est NOMMÉE dans la colonne « Article de stock » :
     * le tiret du maître confondrait « se décrémente autrement » et « ne
     * décrémente rien ».
     */
    #[Test]
    public function la_fiche_technique_est_nommee_dans_la_colonne_article_de_stock(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/restaurant/carte')->assertOk()->getContent();

        $this->assertStringContainsString('Recette Poulet DG', $html);
        $this->assertStringContainsString('Fiche technique (1 ingrédient(s))', $html);
    }

    #[Test]
    public function chaque_action_des_deux_ecrans_correspond_a_une_methode_publique(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $this->assertActionsResolubles(
            (string) $this->get('/pwa/restaurant/carte')->assertOk()->getContent(),
            CarteRestaurant::class,
        );

        $this->assertActionsResolubles(
            (string) $this->get('/pwa/restaurant/plats')->assertOk()->getContent(),
            Restauration::class,
        );
    }

    /**
     * C3 — « Delier » est le DIALOGUE PARTAGE du maitre, pas une troisieme
     * forme : icone et texte COTE A COTE, icone 36 px, titre 14 px, barre de
     * pied grise. La PWA posait l'icone AU-DESSUS, en 48 px, sans pied.
     */
    #[Test]
    public function la_modale_de_deliaison_porte_la_forme_du_dialogue_du_maitre(): void
    {
        $this->jeuDeDonnees();
        $eau = Plat::where('libelle', 'Bouteille d\'eau 1,5 L')->firstOrFail();
        $eau->update([
            'article_id' => $this->bouteilleEau->id,
            'unites_vendables_par_unite_stock' => '12.0000',
        ]);

        $this->actingAs($this->utilisateur('administrateur'));

        $html = Livewire::test(CarteRestaurant::class)
            ->call('ouvrirRetraitDuLien', $eau->id)
            ->html();

        // Le chassis et son etat d'ouverture — sans quoi la modale est dans le
        // DOM, invisible et inerte.
        $this->assertStringContainsString('class="overlay-modale no-print" style="display:flex"', $html);
        // maitre — `modal.js` l.128 : `rounded-xl w-full max-w-md` (28 rem).
        $this->assertStringContainsString('style="max-width:28rem"', $html);

        // Icone et texte COTE A COTE, 36 px — jamais 48 px au-dessus.
        $this->assertStringContainsString('flex items-start gap-3 px-5 pt-5 pb-4', $html);
        $this->assertStringContainsString('w-9 h-9 rounded-full shrink-0', $html);
        $this->assertStringNotContainsString('w-12 h-12', $html);

        // Titre 14 px en `var(--navy)`, message 13 px, detail 11,5 px.
        $this->assertStringContainsString('class="text-[14px] font-bold" style="color:var(--navy)"', $html);
        $this->assertStringContainsString('class="text-[13px] text-slate-600 mt-1 leading-relaxed"', $html);
        $this->assertStringContainsString('class="text-[11.5px] text-slate-400 mt-2 leading-relaxed"', $html);

        // La barre de pied GRISE du dialogue.
        $this->assertStringContainsString('flex justify-end gap-2.5 px-5 py-3 border-t border-slate-100 bg-slate-50', $html);

        // Le ton « alerte » du maitre : fond, bordure, texte, et bouton dore.
        $this->assertStringContainsString('background:#FFFBEB;border:1px solid #FDE68A;color:#B45309', $html);
        $this->assertStringContainsString('style="background:#B8891E"', $html);

        // ⚠ Ecart de texte DECLARE : le maitre ecrit « du bar », cette modale
        // sert les deux rayons (31/08/2026, `carte_pwa.modale_delier.detail`).
        // Blade échappe l'apostrophe du texte rendu.
        $this->assertStringContainsString('ce qui sort réellement de l&#039;établissement', $html);
    }

    /* ================================================ catalogue des plats */

    #[Test]
    public function le_catalogue_porte_le_titre_du_maitre_et_la_colonne_disponible(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/restaurant/plats')->assertOk()->getContent();

        // Le <title> porte le MÊME nom que le <h1> du maître — aligné le
        // 31/08/2026. Il disait « Catalogue Restauration » (mot de la
        // Directive) pendant que le <h1> disait déjà « Restaurant & Cuisine »
        // (mot du maître, qui gagne) : deux noms pour la même page, et
        // `BaliseTitrePwaTest` le refusait à raison.
        $this->assertStringContainsString('<title>Restaurant &amp; Cuisine — LogiReStock — TATACORA AFRIQUE</title>', $html);
        $this->assertSame(1, substr_count($html, '<h1 '), 'Un seul <h1> par page.');
        // Le mot du MAÎTRE (l.28) : la vue livrée rendait « Catalogue des
        // Plats & Restauration ».
        $this->assertStringContainsString('Restaurant &amp; Cuisine</h1>', $html);
        $this->assertStringNotContainsString('Catalogue des Plats &amp; Restauration', $html);

        // Les quatre colonnes du maître, dans SA casse.
        foreach (['Plat', 'Catégorie', 'Prix de vente', 'Disponible'] as $colonne) {
            $this->assertStringContainsString('>'.$colonne.'</th>', $html);
        }

        // ⚠ La colonne « Disponible » était PERDUE — le sujet même de l'écran
        // de disponibilité. Elle est rendue, et elle dit vrai.
        $this->assertStringContainsString('>Oui</span>', $html);
    }

    #[Test]
    public function la_colonne_disponible_reflete_l_indisponibilite_en_base(): void
    {
        $this->jeuDeDonnees();
        $poulet = Plat::where('libelle', 'Poulet DG')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteRestaurant::class)
            ->call('ouvrirRetraitDeLaCarte', $poulet->id)
            ->set('motifIndisponibilite', 'rupture')
            ->call('enregistrerRetraitDeLaCarte')
            ->assertHasNoErrors();

        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/restaurant/plats')->assertOk()->getContent();

        $this->assertStringContainsString('>Non</span>', $html);
    }

    /**
     * C5 — archiver un plat, c'est LE RETIRER DE LA CARTE. Rien n'est effacé.
     */
    #[Test]
    public function retirer_un_plat_de_la_carte_ecrit_le_motif_retire_et_n_efface_rien(): void
    {
        $this->jeuDeDonnees();
        $salade = Plat::where('libelle', 'Salade nue')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Restauration::class)
            ->call('ouvrirRetraitDuPlat', $salade->id)
            ->assertSet('etatFormulaire', 'archivage')
            ->call('confirmerRetraitDuPlat')
            ->assertHasNoErrors();

        $this->assertNotNull(Plat::find($salade->id), 'Le plat a été EFFACÉ : le « D » de CRUD n\'existe nulle part.');

        $ligne = IndisponibiliteCarte::where('plat_id', $salade->id)->firstOrFail();
        $this->assertSame('retire', $ligne->motif);
        $this->assertFalse($ligne->estTemporaire(), 'Un retrait est une décision commerciale, pas une rupture.');
    }

    /**
     * Le verrou du maître : « Élément engagé dans N opération(s) ». Le bouton
     * de confirmation est MASQUÉ, et forcer l'action ne passe pas.
     */
    #[Test]
    public function un_plat_engage_dans_une_commande_en_cours_ne_se_retire_pas(): void
    {
        $this->jeuDeDonnees();
        $poulet = Plat::where('libelle', 'Poulet DG')->firstOrFail();
        $this->commandeEnCoursSur($poulet);

        $this->actingAs($this->utilisateur('administrateur'));

        $composant = Livewire::test(Restauration::class)
            ->call('ouvrirRetraitDuPlat', $poulet->id);

        // Le maître masque le bouton quand plus rien n'est archivable : le
        // laisser visible et inerte laisserait croire à une panne.
        // ⚠ On ne peut PAS chercher l'absence du libellé « Retirer de la
        // carte » : c'est aussi celui du bouton de ligne, présent sur chaque
        // plat. C'est le CÂBLAGE de la confirmation qui doit disparaître.
        $composant->assertSee('Archivage impossible')
            ->assertSee('commande(s) en cours')
            ->assertDontSee('wire:click="confirmerRetraitDuPlat"', escape: false);

        // Et forcer l'action depuis le navigateur ne passe pas non plus.
        $composant->call('confirmerRetraitDuPlat');

        $this->assertSame(0, IndisponibiliteCarte::where('plat_id', $poulet->id)->count());
    }

    /**
     * Le formulaire exige menu ET recette : les deux colonnes sont NOT NULL,
     * et « Aucune fiche technique » faisait échouer l'insertion sur la
     * contrainte, message SQL à l'appui.
     */
    #[Test]
    public function le_formulaire_de_plat_exige_un_menu_et_une_fiche_technique(): void
    {
        $this->jeuDeDonnees();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Restauration::class)
            ->call('ouvrirCreationPlat')
            ->set('libelleSaisi', 'Wagasi grillé')
            ->set('prixVenteSaisi', '2500')
            ->set('categorieSaisie', 'plats')
            ->call('enregistrerPlat')
            ->assertHasErrors(['menuIdSaisi', 'recetteIdSaisie']);

        $this->assertNull(Plat::where('libelle', 'Wagasi grillé')->first());

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Restauration::class)
            ->call('ouvrirCreationPlat')
            ->set('libelleSaisi', 'Wagasi grillé')
            ->set('prixVenteSaisi', '2500')
            ->set('categorieSaisie', 'plats')
            ->set('menuIdSaisi', $this->menu->id)
            ->set('recetteIdSaisie', $this->recetteGarnie->id)
            ->call('enregistrerPlat')
            ->assertHasNoErrors();

        $cree = Plat::where('libelle', 'Wagasi grillé')->firstOrFail();
        $this->assertSame(0, bccomp((string) $cree->prix_vente, '2500.00', 2));
    }

    #[Test]
    public function un_role_en_lecture_seule_ne_peut_pas_creer_de_plat(): void
    {
        $this->jeuDeDonnees();
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M4'));

        $avant = Plat::count();

        foreach ([
            ['ouvrirCreationPlat', []],
            ['ouvrirModificationPlat', [Plat::where('libelle', 'Poulet DG')->firstOrFail()->id]],
            ['enregistrerPlat', []],
            ['ouvrirRetraitDuPlat', [Plat::where('libelle', 'Salade nue')->firstOrFail()->id]],
            ['confirmerRetraitDuPlat', []],
        ] as [$methode, $arguments]) {
            $this->actingAs($comptable);

            Livewire::test(Restauration::class)
                ->call($methode, ...$arguments)
                ->assertForbidden();
        }

        $this->assertSame($avant, Plat::count());
        $this->assertSame(0, IndisponibiliteCarte::count());
    }

    // =================================================================
    // LA SORTIE D'IMPASSE — menus et fiches techniques (03/09/2026)
    // =================================================================

    /**
     * Créer un menu et une fiche technique depuis l'écran les PERSISTE.
     *
     * Les deux Services existaient depuis PA-159 avec un seul appelant chacun,
     * leur contrôleur d'API : aucun geste du navigateur ne les atteignait. Ce
     * cas relit la base, pas le composant — un état Livewire correct ne prouve
     * rien d'une écriture qui n'a pas eu lieu.
     */
    #[Test]
    public function creer_un_menu_et_une_fiche_technique_depuis_l_ecran_les_persiste(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $menusAvant = Menu::count();

        Livewire::test(Restauration::class)
            ->call('ouvrirCreationMenu')
            ->assertSet('retourAuPlat', false)
            ->set('menuLibelleSaisi', 'Carte de saison sèche')
            ->set('menuTypeSaisi', 'special')
            ->set('menuDateDebutSaisie', '2026-11-01')
            ->set('menuDateFinSaisie', '2027-03-31')
            ->call('enregistrerMenu')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame($menusAvant + 1, Menu::count());

        $menu = Menu::where('libelle', 'Carte de saison sèche')->firstOrFail();
        $this->assertSame('special', $menu->type);
        $this->assertSame('2026-11-01', $menu->date_debut?->format('Y-m-d'));
        $this->assertSame('2027-03-31', $menu->date_fin?->format('Y-m-d'));

        $fiche = Livewire::test(Restauration::class)
            ->call('ouvrirCreationRecette')
            // Une ligne est offerte d'emblée : un sous-formulaire vide ne
            // dirait pas qu'on peut en ajouter.
            ->assertCount('ingredientsSaisis', 1);

        // La modale est RÉELLEMENT rendue, avec le sélecteur d'article en
        // vraie clé étrangère : PA-23 refuse le textarea du maître, et une
        // modale qui ne rend pas son sous-formulaire ne le remplace pas.
        $html = $fiche->html();
        $this->assertStringContainsString('id="ingredient-article-0"', $html);
        $this->assertStringContainsString('value="'.$this->bouteilleEau->id.'"', $html);
        $this->assertStringNotContainsString('<textarea', $html, 'Le textarea du maître est revenu (PA-23).');

        $fiche->set('recetteLibelleSaisi', 'Recette Wagasi grillé')
            ->set('ingredientsSaisis.0.article_id', $this->bouteilleEau->id)
            ->set('ingredientsSaisis.0.quantite_unitaire', '0.250')
            ->call('enregistrerRecette')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $recette = Recette::where('libelle', 'Recette Wagasi grillé')->firstOrFail();

        // La COMPOSITION est écrite, en vraies clés étrangères — c'est ce que
        // PA-23 réclame à la place du textarea « Ingrédients principaux ».
        $ligne = DB::table('ingredients_recette')
            ->where('recette_id', $recette->id)
            ->first();

        $this->assertNotNull($ligne, 'La composition de la fiche technique n\'a pas été écrite.');
        $this->assertSame($this->bouteilleEau->id, $ligne->article_id);
        $this->assertSame(0, bccomp((string) $ligne->quantite_unitaire, '0.250', 3));

        // Le coût matière est CALCULÉ et persisté par le seul service qui
        // l'écrit : 0,250 pack × 3 000 F de CMP = 750 F. Un champ de saisie
        // l'aurait fait diverger de sa composition dès le premier ingrédient.
        $this->assertSame(
            0,
            bccomp((string) $recette->refresh()->cout_matiere_calcule, '750.00', 2),
            'Le coût matière n\'a pas été recalculé depuis la composition.',
        );
    }

    /**
     * Le sélecteur de type de carte couvre EXACTEMENT l'`enum` `menus.type`.
     *
     * `Restauration::typesDeMenu()` écrit ses clés de langue en littéral — la
     * seule forme que `MessagesUtilisateurTest` sache relire. C'est donc une
     * seconde liste à côté de `Menu::TYPES`, et ce cas est ce qui l'empêche de
     * diverger : un type ajouté à la colonne et oublié ici ne serait proposé
     * nulle part, et le refus tomberait au moment de l'enregistrement.
     */
    #[Test]
    public function le_formulaire_de_menu_offre_exactement_les_types_de_l_enum(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $html = Livewire::test(Restauration::class)->call('ouvrirCreationMenu')->html();

        // Le SEUL sélecteur visé : la page en porte d'autres (filtre de
        // catégorie), et les compter tous rendrait ce contrôle sans objet.
        $this->assertSame(
            1,
            preg_match('#<select id="menu-type".*?</select>#s', $html, $selecteur),
            'Le sélecteur de type de carte n\'est pas rendu.',
        );

        $this->assertNotEmpty(Menu::TYPES, 'L\'enum est vide : ce contrôle serait vert à vide.');

        foreach (Menu::TYPES as $type) {
            $this->assertStringContainsString(
                'value="'.$type.'"',
                $selecteur[0],
                'Le type « '.$type.' » de `menus.type` n\'est proposé par aucune option.',
            );
        }

        $this->assertSame(
            count(Menu::TYPES),
            substr_count($selecteur[0], '<option value="'),
            'Le sélecteur propose un type que l\'enum ne connaît pas, ou en oublie un.',
        );
    }

    /**
     * LE PARCOURS COMPLET SUR UNE BASE SANS RÉFÉRENTIEL RESTAURANT — le cas
     * qui prouve la sortie d'impasse, et le seul qui la prouve.
     *
     * Aucun menu, aucune recette : c'est l'état d'une mise en service. L'écran
     * le DIT à l'endroit du champ, puis les deux gestes qui le lèvent sont
     * atteignables sans quitter le formulaire de plat, qui conserve sa saisie
     * et reçoit ce qui vient d'être créé.
     *
     * ⚠ MUTATION EXÉCUTÉE LE 03/09/2026, puis annulée :
     * `Restauration::enregistrerRecette()` privé de son écriture — le corps
     * réduit à `$recette = new Recette(['libelle' => …]);` sans jamais passer
     * par `ReferentielRecetteService` ni `CompositionRecetteService`. Ce cas
     * rougit sur `Recette::where('libelle', 'Recette Wagasi')->firstOrFail()`
     * (ModelNotFoundException) ; `creer_un_menu_et_une_fiche_technique…`
     * rougit également. Restauré et re-vérifié vert.
     */
    #[Test]
    public function le_parcours_complet_part_d_une_base_sans_menu_ni_recette(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        // Le référentiel de STOCK est une précondition, pas une commodité : un
        // ingrédient est une vraie clé étrangère vers `articles` (M6). Ce qui
        // manque, et que ce cas éprouve, c'est le référentiel M4.
        $cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);

        $farine = Article::create([
            'libelle' => 'Farine de maïs',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '2.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        app(MouvementStockService::class)->entree($farine->id, $cuisine->id, '50.00', 'Réception', '600.00');

        $this->assertSame(0, Menu::count(), 'La base de départ n\'est pas vierge : le cas ne prouve rien.');
        $this->assertSame(0, Recette::count());
        $this->assertSame(0, Plat::count());

        $composant = Livewire::test(Restauration::class);

        // 1. L'écran DIT le manque, à l'endroit du champ qui l'exige.
        $formulaire = $composant->call('ouvrirCreationPlat')->html();

        $this->assertStringContainsString(
            'existe encore : un plat ne peut pas être créé sans lui',
            $formulaire,
            'Le champ « Menu » ne nomme pas le manque : le sélecteur vide est une impasse.',
        );
        $this->assertStringContainsString(
            'existe encore : un plat ne peut pas être créé sans elle',
            $formulaire,
            'Le champ « Fiche technique » ne nomme pas le manque.',
        );
        $this->assertStringContainsString('Créer un menu', $formulaire);
        $this->assertStringContainsString('Créer une fiche technique', $formulaire);

        // 2. La saisie du plat commence, puis le menu se crée SANS la perdre.
        $composant->set('libelleSaisi', 'Amiwo sauce tomate')
            ->set('prixVenteSaisi', '2000')
            ->set('categorieSaisie', 'plats');

        $composant->call('ouvrirCreationMenu')
            ->assertSet('retourAuPlat', true)
            ->set('menuLibelleSaisi', 'Carte du jour')
            ->set('menuTypeSaisi', 'local')
            ->call('enregistrerMenu')
            ->assertHasNoErrors()
            // Retour au formulaire de plat, saisie intacte : la faire retaper
            // punirait l'utilisateur d'avoir suivi le seul chemin possible.
            ->assertSet('etatFormulaire', 'plat')
            ->assertSet('libelleSaisi', 'Amiwo sauce tomate')
            ->assertSet('prixVenteSaisi', '2000');

        $menu = Menu::where('libelle', 'Carte du jour')->firstOrFail();
        $composant->assertSet('menuIdSaisi', $menu->id);

        // 3. La fiche technique, avec sa composition en vraie clé étrangère.
        $composant->call('ouvrirCreationRecette')
            ->assertSet('retourAuPlat', true)
            ->set('recetteLibelleSaisi', 'Recette Wagasi')
            ->set('ingredientsSaisis.0.article_id', $farine->id)
            ->set('ingredientsSaisis.0.quantite_unitaire', '0.300')
            ->call('enregistrerRecette')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', 'plat')
            ->assertSet('libelleSaisi', 'Amiwo sauce tomate');

        $recette = Recette::where('libelle', 'Recette Wagasi')->firstOrFail();
        $composant->assertSet('recetteIdSaisie', $recette->id);

        // 4. Le plat s'enregistre — avec SES DEUX clés étrangères.
        $composant->call('enregistrerPlat')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $plat = Plat::where('libelle', 'Amiwo sauce tomate')->firstOrFail();

        $this->assertSame($menu->id, $plat->menu_id);
        $this->assertSame($recette->id, $plat->recette_id);
        $this->assertSame(0, bccomp((string) $plat->prix_vente, '2000.00', 2));

        // Et la fiche décrémente réellement : 0,300 kg × 600 F = 180 F.
        $this->assertSame(1, DB::table('ingredients_recette')->where('recette_id', $recette->id)->count());
        $this->assertSame(0, bccomp((string) $recette->refresh()->cout_matiere_calcule, '180.00', 2));
    }

    /**
     * Un rôle en LECTURE sur M4 est refusé sur chacun des gestes de référentiel.
     *
     * Y compris la fermeture : elle rend la main au formulaire de plat, dont
     * l'ouverture est déjà gardée — laisser une porte non gardée sur un état de
     * formulaire, c'est laisser un rôle `L` se placer devant une modale
     * d'écriture.
     */
    #[Test]
    public function un_role_en_lecture_seule_ne_peut_creer_ni_menu_ni_fiche_technique(): void
    {
        $this->jeuDeDonnees();

        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M4'));

        $menusAvant = Menu::count();
        $recettesAvant = Recette::count();

        foreach ([
            ['ouvrirCreationMenu', []],
            ['enregistrerMenu', []],
            ['ouvrirCreationRecette', []],
            ['enregistrerRecette', []],
            ['ajouterIngredient', []],
            ['retirerIngredient', [0]],
            ['fermerFormulaireSecondaire', []],
        ] as [$methode, $arguments]) {
            $this->actingAs($comptable);

            Livewire::test(Restauration::class)
                ->call($methode, ...$arguments)
                ->assertForbidden();
        }

        $this->assertSame($menusAvant, Menu::count());
        $this->assertSame($recettesAvant, Recette::count());
    }

    /**
     * Les refus sont AFFICHÉS et n'écrivent rien — les trois qui existent.
     *
     * 1. **Saison inversée** : la règle de la PWA est celle
     *    d'`EnregistrerMenuRequest`, parce que les deux canaux doivent refuser
     *    la même chose. Une carte qui finit avant de commencer ne rendrait
     *    jamais aucun plat, et l'écran n'en dirait rien.
     * 2. **Article inconnu** : la ligne de composition est une vraie clé
     *    étrangère. Sans le refus, l'insertion échouerait sur la contrainte,
     *    message SQL à l'appui.
     * 3. **Ingrédient en double** : `ingredients_recette` a pour clé primaire
     *    le couple `(recette_id, article_id)`.
     *
     * ⚠ Le point qui compte dans les deux derniers cas : l'ENTÊTE de recette
     * n'est pas écrite non plus. Sans la transaction, une fiche orpheline et
     * sans ingrédient resterait au sélecteur du formulaire de plat, où rien ne
     * la distinguerait d'une fiche volontairement vide.
     */
    #[Test]
    public function les_refus_du_referentiel_sont_affiches_et_n_ecrivent_rien(): void
    {
        $this->jeuDeDonnees();

        $menusAvant = Menu::count();
        $recettesAvant = Recette::count();
        $lignesAvant = DB::table('ingredients_recette')->count();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Restauration::class)
            ->call('ouvrirCreationMenu')
            ->set('menuLibelleSaisi', 'Carte impossible')
            ->set('menuTypeSaisi', 'local')
            ->set('menuDateDebutSaisie', '2026-05-01')
            ->set('menuDateFinSaisie', '2026-04-01')
            ->call('enregistrerMenu')
            ->assertHasErrors(['menuDateFinSaisie'])
            ->assertSet('etatFormulaire', 'menu');

        $this->assertSame($menusAvant, Menu::count());

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Restauration::class)
            ->call('ouvrirCreationRecette')
            ->set('recetteLibelleSaisi', 'Recette fantôme')
            ->set('ingredientsSaisis.0.article_id', (string) Str::uuid())
            ->set('ingredientsSaisis.0.quantite_unitaire', '1')
            ->call('enregistrerRecette')
            ->assertHasErrors(['ingredientsSaisis.0.article_id']);

        $this->assertSame($recettesAvant, Recette::count(), 'Une fiche orpheline a été créée malgré le refus.');

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(Restauration::class)
            ->call('ouvrirCreationRecette')
            ->set('recetteLibelleSaisi', 'Recette en double')
            ->set('ingredientsSaisis.0.article_id', $this->bouteilleEau->id)
            ->set('ingredientsSaisis.0.quantite_unitaire', '1')
            ->call('ajouterIngredient')
            ->set('ingredientsSaisis.1.article_id', $this->bouteilleEau->id)
            ->set('ingredientsSaisis.1.quantite_unitaire', '2')
            ->call('enregistrerRecette')
            ->assertHasErrors(['ingredientsSaisis.1.article_id']);

        $this->assertSame($recettesAvant, Recette::count());
        $this->assertSame($lignesAvant, DB::table('ingredients_recette')->count());
    }

    /**
     * C5 — plus aucune suppression physique ni boîte native du navigateur.
     *
     * Le contrôle relit les SOURCES : `wire:confirm` et `->delete()` ne
     * laissent aucune trace au rendu quand la page ne les atteint pas, et un
     * test de rendu resterait vert sur un code qui les porte encore.
     */
    #[Test]
    public function aucune_suppression_physique_ni_boite_native_ne_subsiste(): void
    {
        $sources = [
            app_path('Pwa/Livewire/Restaurant/Restauration.php'),
            app_path('Pwa/Livewire/Restaurant/CarteRestaurant.php'),
            app_path('Pwa/Livewire/Bar/CarteBar.php'),
            app_path('Pwa/Livewire/Concerns/EcranDeCarte.php'),
            resource_path('views/pwa/restaurant/restauration.blade.php'),
            resource_path('views/pwa/carte/corps.blade.php'),
        ];

        foreach ($sources as $source) {
            $this->assertFileExists($source);
            $code = $this->codeSansCommentaires($source);

            $this->assertDoesNotMatchRegularExpression(
                '/->\s*delete\s*\(|->\s*forceDelete\s*\(/',
                $code,
                "Une suppression physique subsiste dans {$source}.",
            );
            $this->assertStringNotContainsString(
                'wire:confirm',
                $code,
                "La boîte grise du navigateur subsiste dans {$source} : hors charte, sans nom "
                .'d\'élément ni explication.',
            );
        }
    }

    /* ----------------------------------------------------- auxiliaires */

    /**
     * Le code d'un fichier, COMMENTAIRES RETIRÉS.
     *
     * Sans cela, le contrôle rougirait sur les blocs de documentation qui
     * CITENT le défaut fermé (« `supprimerPlat()` faisait `$plat->delete()` »).
     * Nommer ce qu'on a corrigé est une exigence de ce dépôt : un contrôle qui
     * l'interdirait ferait effacer la trace, c'est-à-dire l'inverse du but.
     */
    private function codeSansCommentaires(string $chemin): string
    {
        $source = (string) file_get_contents($chemin);

        if (str_ends_with($chemin, '.blade.php')) {
            return (string) preg_replace('/\{\{--.*?--\}\}/s', '', $source);
        }

        $propre = '';

        foreach (token_get_all($source) as $jeton) {
            if (is_array($jeton) && in_array($jeton[0], [T_COMMENT, T_DOC_COMMENT], true)) {
                continue;
            }

            $propre .= is_array($jeton) ? $jeton[1] : $jeton;
        }

        return $propre;
    }

    private function assertActionsResolubles(string $html, string $composant): void
    {
        preg_match_all('/wire:click="([a-zA-Z_][a-zA-Z0-9_]*)\(/', $html, $appels);

        $publiques = array_map(
            static fn (\ReflectionMethod $m): string => $m->getName(),
            (new \ReflectionClass($composant))->getMethods(\ReflectionMethod::IS_PUBLIC),
        );

        // Les composants IMBRIQUES de la coquille (cloche de notifications,
        // recherche globale — audit PO du 01/09/2026) rendent leurs propres
        // actions sur CHAQUE page : elles se resolvent sur eux, jamais sur le
        // composant de page.
        foreach ([
            ClocheNotifications::class,
            RechercheGlobale::class,
        ] as $imbrique) {
            foreach ((new \ReflectionClass($imbrique))->getMethods(\ReflectionMethod::IS_PUBLIC) as $m) {
                $publiques[] = $m->getName();
            }
        }

        $this->assertNotEmpty($appels[1], 'Aucune action relevée : le contrôle serait vert à vide.');

        foreach (array_unique($appels[1]) as $appel) {
            $this->assertContains(
                $appel,
                $publiques,
                "Le bouton appelle `{$appel}()`, qui n'est pas une méthode publique de {$composant}.",
            );
        }
    }

    private function commandeEnCoursSur(Plat $plat): void
    {
        $commande = (string) Str::uuid();

        DB::table('commandes_restaurant')->insert([
            'id' => $commande,
            'table_ou_chambre_id' => null,
            'client_id' => null,
            'date_commande' => now(),
            'statut' => 'en_preparation',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        DB::table('lignes_commande_restaurant')->insert([
            'id' => (string) Str::uuid(),
            'commande_id' => $commande,
            'plat_id' => $plat->id,
            'quantite' => 2,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    private function jeuDeDonnees(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);
        $magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $poulet = Article::create([
            'libelle' => 'Poulet fermier',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '2.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $this->bouteilleEau = Article::create([
            'libelle' => 'Eau minérale (pack de 12)',
            'categorie' => 'Boissons',
            'unite_mesure' => 'pack',
            'seuil_alerte' => '2.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        /** @var MouvementStockService $mouvements */
        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($poulet->id, $cuisine->id, '20.00', 'Réception', '2500.00');
        $mouvements->entree($this->bouteilleEau->id, $cuisine->id, '5.00', 'Réception', '3000.00');
        $mouvements->entree($this->bouteilleEau->id, $magasin->id, '100.00', 'Réception', '3000.00');

        $this->menu = Menu::create(['libelle' => 'Carte du jour', 'type' => 'local']);

        $this->recetteGarnie = Recette::create([
            'libelle' => 'Recette Poulet DG',
            'cout_matiere_calcule' => '1800.00',
        ]);

        DB::table('ingredients_recette')->insert([
            'recette_id' => $this->recetteGarnie->id,
            'article_id' => $poulet->id,
            'quantite_unitaire' => '0.400',
        ]);

        // Une recette SANS ingrédient : elle porte un nom et rien d'autre, et
        // ne décrémente rien. La compter comme couverte masquerait la dette.
        $this->recetteVide = Recette::create([
            'libelle' => 'Recette à écrire',
            'cout_matiere_calcule' => '0.00',
        ]);

        Plat::create([
            'menu_id' => $this->menu->id,
            'recette_id' => $this->recetteGarnie->id,
            'categorie' => 'plats',
            'libelle' => 'Poulet DG',
            'prix_vente' => '4500.00',
        ]);

        Plat::create([
            'menu_id' => $this->menu->id,
            'recette_id' => $this->recetteVide->id,
            'categorie' => 'entrees',
            'libelle' => 'Salade nue',
            'prix_vente' => '2000.00',
        ]);

        // PA-161 (b) — six lignes de sandwicherie du maitre portent
        // `prix_corrige_main` SANS etre provisoires : une etiquette manuscrite
        // a remplace l'imprime, et « ce sont les prix MANUSCRITS qui font foi »
        // (`referentiel-carte.js` l.14-20). C'est la ligne qui doit porter la
        // seconde marque, celle que le bar n'a pas.
        Plat::create([
            'menu_id' => $this->menu->id,
            'recette_id' => $this->recetteVide->id,
            'categorie' => 'sandwicherie',
            'libelle' => 'Chawarma poulet',
            'prix_vente' => '3000.00',
            'prix_corrige_main' => true,
        ]);

        Plat::create([
            'menu_id' => $this->menu->id,
            'recette_id' => $this->recetteVide->id,
            'categorie' => 'boissons_maison',
            'libelle' => 'Bouteille d\'eau 1,5 L',
            'prix_vente' => '500.00',
        ]);
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

    // =================================================================
    // ONGLET « VENTES DU RESTAURANT » — ajout du 03/09/2026 (Product Owner)
    // =================================================================

    /**
     * L'AUTRE MOITIÉ du filtre de module, et c'est pour cela qu'elle existe.
     *
     * `BarPwaTest` prouve que la carte du bar ne montre pas les plats ; ce cas
     * prouve la réciproque sur le MÊME ticket. Un filtre inversé — `M5` au
     * restaurant — passerait le premier fichier et échouerait ici : c'est la
     * paire qui tient, pas l'un des deux.
     *
     * ## Mutation RÉELLEMENT exécutée puis annulée (03/09/2026)
     *
     * | Mutation | Cas qui rougit | Résultat |
     * |---|---|---|
     * | `EcranDeCarte::requeteDesVentes()` filtre `lignes_vente.module` sur `'M5'` au lieu de `static::MODULE` | `l_onglet_ventes_du_restaurant_ne_montre_que_les_lignes_du_rayon` | 1 failed (la Béninoise du même ticket apparaît à la carte du RESTAURANT) |
     *
     * Les ventes du jeu d'essai sont écrites en direct, pour la raison écrite
     * au docblock de la section jumelle de `BarPwaTest` : ces cas éprouvent
     * une lecture, pas le chemin d'encaissement.
     */
    #[Test]
    public function l_onglet_ventes_du_restaurant_ne_montre_que_les_lignes_du_rayon(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $poulet = Plat::where('libelle', 'Poulet DG')->firstOrFail();

        // UN SEUL ticket, DEUX rayons.
        $this->venteDeTest('V-TEST-M4-00001', now()->subDay(), [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 2],
            ['code' => 'BOISSON-INCONNUE', 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 3],
        ]);

        // Une vente ANNULÉE reste au registre (RG-02), marquée et hors total.
        $this->venteDeTest('V-TEST-M4-ANNULEE', now()->subDay(), [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 4],
        ], statut: 'annulee', motif: 'Commande jamais servie');

        $html = Livewire::test(CarteRestaurant::class)->set('onglet', 'ventes')->html();

        $this->assertStringContainsString('Ventes du Restaurant', $html);
        $this->assertStringContainsString('V-TEST-M4-00001', $html);
        $this->assertStringContainsString('Poulet DG', $html);
        // RG-15 — le login de qui a encaissé.
        $this->assertStringContainsString('compte.administrateur', $html);

        $this->assertStringNotContainsString(
            'Béninoise 66 cl',
            $html,
            'La boisson du même ticket est listée sur la carte du RESTAURANT : '
                .'le filtre porte sur la vente au lieu de la ligne.',
        );

        // RG-02 puis total : 2 × 4 500 = 9 000 F, les 18 000 F annulés exclus.
        $this->assertStringContainsString('V-TEST-M4-ANNULEE', $html);
        $this->assertStringContainsString('Annulée', $html);
        $this->assertStringContainsString(MontantFcfa::format('9000.00'), $html);
        $this->assertStringNotContainsString(
            MontantFcfa::format('27000.00'),
            $html,
            "Le total additionne la vente annulée : son montant n'est pas de l'argent.",
        );
    }

    /**
     * La borne haute inclut la journée entière — même piège, même mutation
     * que sur la carte du bar : `where('created_at', '<=', $fin)` ferait
     * disparaître toute vente encaissée après minuit du dernier jour.
     */
    #[Test]
    public function la_borne_haute_de_la_plage_inclut_la_journee_entiere(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $poulet = Plat::where('libelle', 'Poulet DG')->firstOrFail();
        $jour = CarbonImmutable::parse('2026-08-20 21:15:00');

        $this->venteDeTest('V-TEST-M4-DERNIERJOUR', $jour, [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);
        $this->venteDeTest('V-TEST-M4-TROPTARD', $jour->addDays(3), [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);

        Livewire::test(CarteRestaurant::class)
            ->set('onglet', 'ventes')
            ->set('debutVentes', '2026-08-19')
            ->set('finVentes', '2026-08-20')
            ->assertSee('V-TEST-M4-DERNIERJOUR')
            ->assertDontSee('V-TEST-M4-TROPTARD');
    }

    /**
     * La recherche porte sur les TROIS colonnes que le tableau rend : le nom
     * figé de la ligne, le numéro du ticket et le login de qui a encaissé.
     * Chercher sur une donnée absente de l'écran ferait disparaître des lignes
     * sans que rien ne l'explique.
     */
    #[Test]
    public function la_recherche_porte_sur_l_article_le_ticket_et_l_utilisateur(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $poulet = Plat::where('libelle', 'Poulet DG')->firstOrFail();
        $salade = Plat::where('libelle', 'Salade nue')->firstOrFail();

        $this->venteDeTest('V-TEST-M4-POULET', now()->subDay(), [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);
        $this->venteDeTest('V-TEST-M4-SALADE', now()->subDay(), [
            ['code' => $salade->id, 'nom' => 'Salade nue', 'module' => 'M4', 'prix' => '2000.00', 'qte' => 1],
        ]);

        Livewire::test(CarteRestaurant::class)
            ->set('onglet', 'ventes')
            ->set('rechercheVentes', 'Salade')
            ->assertSee('V-TEST-M4-SALADE')
            ->assertDontSee('V-TEST-M4-POULET');

        Livewire::test(CarteRestaurant::class)
            ->set('onglet', 'ventes')
            ->set('rechercheVentes', 'V-TEST-M4-POULET')
            ->assertSee('V-TEST-M4-POULET')
            ->assertDontSee('V-TEST-M4-SALADE');

        // Le login : les deux ventes portent le même, les deux restent.
        Livewire::test(CarteRestaurant::class)
            ->set('onglet', 'ventes')
            ->set('rechercheVentes', 'compte.administrateur')
            ->assertSee('V-TEST-M4-POULET')
            ->assertSee('V-TEST-M4-SALADE');
    }

    // =================================================================
    // EXPORT DE L'ONGLET « VENTES DU RESTAURANT » — 03/09/2026 (PO)
    // =================================================================

    /**
     * L'export de l'onglet Ventes du RESTAURANT, et la réciproque du cas du
     * bar : une BOISSON du même ticket ne sort pas dans ce document.
     *
     * C'est la paire qui tient, pas l'un des deux fichiers. Un aiguillage
     * inversé — le rayon du bar exporté au restaurant — passerait le cas jumeau
     * de `BarPwaTest` et échouerait ici.
     *
     * ## Mutation RÉELLEMENT exécutée puis annulée (03/09/2026)
     *
     * Rejouée sur `EcranDeCarte::lignesDeVenteDuDocument()`, qui construit ses
     * lignes depuis `LigneVente::query()->where('module', static::MODULE)` —
     * donc sans aucun filtre de l'écran — au lieu de `requeteDesVentes()` :
     * `l_export_de_l_onglet_ventes_respecte_la_plage_de_dates` (BarPwaTest)
     * rougit, ce cas-ci reste vert. Le filtre de MODULE survit à la mutation ;
     * c'est pourquoi les deux cas coexistent.
     */
    #[Test]
    public function l_export_de_l_onglet_ventes_ne_porte_que_les_lignes_du_restaurant(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $poulet = Plat::where('libelle', 'Poulet DG')->firstOrFail();

        $this->venteDeTest('V-TEST-M4-EXPORT', now()->subDay(), [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 2],
            ['code' => 'BOISSON-INCONNUE', 'nom' => 'Beninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 3],
        ]);

        // RG-02 — l'annulation reste au document, marquée, et hors du total.
        $this->venteDeTest('V-TEST-M4-EXPORT-ANNULEE', now()->subDay(), [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 4],
        ], statut: 'annulee', motif: 'Commande jamais servie');

        $composant = Livewire::test(CarteRestaurant::class)
            ->set('onglet', 'ventes')
            ->call('genererExport');

        $contenu = $this->contenuTelecharge($composant);
        $this->assertStringStartsWith('%PDF', $contenu);

        $texte = $this->texteDuPdf($contenu);

        $this->assertStringContainsString('V-TEST-M4-EXPORT', $texte);
        $this->assertStringNotContainsString(
            'Beninoise',
            $texte,
            "La boisson du même ticket sort dans l'export du RESTAURANT : "
                .'le filtre porte sur la vente au lieu de la ligne.',
        );

        // L'annulation est LISTÉE — et le total du document est celui de
        // l'écran : 2 × 4 500 = 9 000 F, les 18 000 F annulés exclus. Le
        // montant est celui de `MontantFcfa`, l'auteur unique des montants,
        // cherché sous sa forme WinAnsi (voir `montantDansUnPdf()`).
        $this->assertStringContainsString('V-TEST-M4-EXPORT-ANNULEE', $texte);
        $this->assertStringContainsString($this->montantDansUnPdf('9000.00'), $texte);
        $this->assertStringNotContainsString(
            $this->montantDansUnPdf('27000.00'),
            $texte,
            "Le total du document additionne la vente annulée : son montant n'est pas de l'argent.",
        );

        // Le TABLEAU du rayon sort aussi en classeur — « PK », signature ZIP.
        $this->actingAs($this->utilisateur('administrateur'));

        $classeur = Livewire::test(CarteRestaurant::class)
            ->set('onglet', 'ventes')
            ->set('formatExport', 'excel')
            ->call('genererExport');

        $this->assertStringStartsWith('PK', $this->contenuTelecharge($classeur));
    }

    /**
     * Le filtre de dates est respecté DANS LE DOCUMENT, et la période est
     * ÉCRITE dessus (PA-119) — les deux bornes incluses, comme au tableau.
     */
    #[Test]
    public function l_export_de_l_onglet_ventes_respecte_la_plage_de_dates(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $poulet = Plat::where('libelle', 'Poulet DG')->firstOrFail();
        $jour = CarbonImmutable::parse('2026-08-20 21:15:00');

        $this->venteDeTest('V-TEST-M4-DANSLAPLAGE', $jour, [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);
        $this->venteDeTest('V-TEST-M4-HORSPLAGE', $jour->addDays(3), [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);

        $texte = $this->texteDuPdf($this->contenuTelecharge(
            Livewire::test(CarteRestaurant::class)
                ->set('onglet', 'ventes')
                ->set('debutVentes', '2026-08-19')
                ->set('finVentes', '2026-08-20')
                ->call('genererExport'),
        ));

        $this->assertStringContainsString('V-TEST-M4-DANSLAPLAGE', $texte);
        $this->assertStringNotContainsString(
            'V-TEST-M4-HORSPLAGE',
            $texte,
            "L'export ignore la borne haute : le document est plus large que l'écran.",
        );

        $this->assertStringContainsString('19/08/2026', $texte, 'Le document ne dit pas sa période.');
        $this->assertStringContainsString('20/08/2026', $texte, 'Le document ne dit pas sa période.');
    }

    /**
     * PA-119 — une liste vide se REFUSE, et AUCUN document n'est produit.
     */
    #[Test]
    public function l_export_de_l_onglet_ventes_refuse_une_liste_vide_sans_produire_de_document(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $poulet = Plat::where('libelle', 'Poulet DG')->firstOrFail();

        $this->venteDeTest('V-TEST-M4-EXISTE', now()->subDay(), [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);

        $composant = Livewire::test(CarteRestaurant::class)
            ->set('onglet', 'ventes')
            ->set('rechercheVentes', 'aucun-plat-ne-porte-ce-nom')
            ->call('genererExport')
            ->assertHasErrors('formatExport');

        /** @var array<string, mixed> $effets */
        $effets = $composant->__get('effects');

        $this->assertArrayNotHasKey(
            'download',
            $effets,
            'Un document a été produit sur une liste vide : une page que l\'on croirait complète.',
        );
    }

    /**
     * NON-RÉGRESSION — depuis l'onglet Carte, l'export reste CELUI DE LA CARTE.
     */
    #[Test]
    public function l_export_de_l_onglet_carte_reste_celui_de_la_carte(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $poulet = Plat::where('libelle', 'Poulet DG')->firstOrFail();

        $this->venteDeTest('V-TEST-M4-NONREGRESSION', now()->subDay(), [
            ['code' => $poulet->id, 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);

        $texte = $this->texteDuPdf($this->contenuTelecharge(
            Livewire::test(CarteRestaurant::class)->call('genererExport'),
        ));

        $this->assertStringNotContainsString(
            'V-TEST-M4-NONREGRESSION',
            $texte,
            "L'export de l'onglet Carte porte le journal des ventes.",
        );
        // « Chawarma poulet » est à la carte et n'a JAMAIS été vendu : il
        // figure sur l'état de la carte et ne peut pas figurer au journal des
        // ventes. C'est ce qui distingue les deux documents par leur contenu,
        // et non par un entête que le gabarit met en majuscules.
        $this->assertStringContainsString(
            'Chawarma',
            $texte,
            "L'état de la carte ne porte plus les plats jamais vendus.",
        );

        // La MODALE nomme ce qu'elle produira, et elle change avec l'onglet.
        $this->assertStringContainsString(
            'Exporter — Carte du restaurant',
            Livewire::test(CarteRestaurant::class)->set('etatFormulaire', 'export')->html(),
        );

        $this->assertStringContainsString(
            'Exporter — Ventes du Restaurant',
            Livewire::test(CarteRestaurant::class)
                ->set('onglet', 'ventes')
                ->set('etatFormulaire', 'export')
                ->html(),
        );
    }

    /**
     * Une ligne de vente FABRIQUÉE pour éprouver l'affichage — jumelle de
     * `BarPwaTest::venteDeTest()`, et écrite en direct pour la même raison.
     *
     * `created_at` passe par `forceFill()` : la colonne n'est pas dans
     * `$fillable`, et un `Vente::create(['created_at' => …])` la laisserait
     * silencieusement à `now()` — la plage de dates serait éprouvée à vide.
     *
     * @param  list<array{code: string, nom: string, module: string, prix: string, qte: int}>  $lignes
     */
    private function venteDeTest(
        string $numero,
        \DateTimeInterface $quand,
        array $lignes,
        string $statut = 'validee',
        string $motif = '',
    ): Vente {
        $total = '0.00';

        foreach ($lignes as $ligne) {
            $total = bcadd($total, bcmul($ligne['prix'], (string) $ligne['qte'], 2), 2);
        }

        $vente = Vente::create([
            'numero' => $numero,
            'point_vente' => 'restaurant',
            'montant_total' => $total,
            'mode_paiement' => 'especes',
            'encaisse' => true,
            'statut' => $statut,
            'motif_annulation' => $motif === '' ? null : $motif,
            'annulee_at' => $statut === 'annulee' ? $quand : null,
            'utilisateur_id' => $this->utilisateur('administrateur')->id,
        ]);

        $vente->forceFill(['created_at' => $quand])->save();

        foreach ($lignes as $ligne) {
            LigneVente::create([
                'vente_id' => $vente->id,
                'code' => $ligne['code'],
                'nom' => $ligne['nom'],
                'categorie' => 'plats',
                'module' => $ligne['module'],
                'prix_unitaire' => $ligne['prix'],
                'quantite' => $ligne['qte'],
                'montant' => bcmul($ligne['prix'], (string) $ligne['qte'], 2),
            ]);
        }

        return $vente->refresh();
    }
}
