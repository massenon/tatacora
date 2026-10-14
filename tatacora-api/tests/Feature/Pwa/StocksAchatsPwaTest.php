<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Models\LigneCommandeAchat;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\Inventaire;
use App\Domain\Stocks\Models\LigneInventaire;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\RefuseLaSaisie;
use Tests\TestCase;

/**
 * Les QUATRE pages M6/M7 de la PWA — vues maîtresses (PA-183)
 * `resources/views/pwa/stocks/{stocks,inventaires}.blade.php` et
 * `resources/views/pwa/achats/{achats,approvisionnement}.blade.php`.
 *
 * Ce que ce fichier verifie, et qui ne l'est nulle part ailleurs :
 *
 *  1. Les quatre pages sont REELLEMENT SERVIES, pas seulement routees — le
 *     precedent est ecrit dans `CLAUDE.md` : « une page HTML livree vide que
 *     seule une execution reelle a revelee ».
 *  2. Le RBAC de 2e niveau, page par page, avec le module que le `data-module`
 *     du maitre designe (M6 et M7).
 *  3. AUCUNE ECRITURE. C'est le risque propre a ce lot : `m6-inventaires`
 *     porte un champ de comptage au maitre, `m6-stocks` un CRUD d'article et
 *     un mouvement de stock, `m7-achats` un CRUD complet et
 *     `m7-approvisionnement` cinq actions d'ecriture. Les quatre deviennent
 *     des consultations.
 *  4. Les chiffres viennent du SERVICE DE DOMAINE, et le stock affiche est
 *     celui que le domaine calcule — pas une colonne, qui n'existe pas.
 *  5. Article 7 : « — » quand la donnee n'existe pas, « 0 » quand elle vaut
 *     zero. Les deux ne disent pas la meme chose.
 *  6. Les refus de l'Article 8 sont NOMMES a l'ecran, avec LES MOTS DU MAITRE.
 *
 * @see LARAVEL_PWA.md §1, §3, §5, §6
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4.3, 4.5, 6, 7, 8
 */
final class StocksAchatsPwaTest extends TestCase
{
    use RefreshDatabase;
    use RefuseLaSaisie;

    /**
     * Les quatre pages, avec le module que le maitre leur donne
     * (`data-module` sur son `<body>`) et le titre exact de son `<h1>`.
     *
     * ⚠ La colonne « module » est le miroir de `routes/web.php`. Un module
     * ajoute ou retire ici sans l'etre la-bas fait rougir un cas.
     *
     * @var array<string, array{url: string, module: string, titre: string}>
     */
    private const PAGES = [
        'm6-stocks' => ['url' => '/pwa/stocks', 'module' => 'M6', 'titre' => 'Gestion des Stocks'],
        'm6-inventaires' => ['url' => '/pwa/stocks/inventaires', 'module' => 'M6', 'titre' => 'Inventaires &amp; Fiches de stock'],
        'm7-achats' => ['url' => '/pwa/achats', 'module' => 'M7', 'titre' => 'Fournisseurs &amp; Achats'],
        'm7-approvisionnement' => ['url' => '/pwa/achats/approvisionnement', 'module' => 'M7', 'titre' => 'Approvisionnement'],
    ];

    private PointStockage $magasin;

    private PointStockage $bar;

    private Article $riz;

    private Article $sucre;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    /* ------------------------------------------------------------ socle */

    #[Test]
    public function les_quatre_pages_sont_reellement_servies(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();

            $this->assertStringContainsString(
                '<h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">'.$page['titre'].'</h1>',
                $html,
                "La page {$nom} ne rend pas le titre du maitre.",
            );

            // Plancher : une page qui rendrait la coquille et rien d'autre
            // passerait le controle de titre.
            $this->assertGreaterThan(
                6000,
                strlen($html),
                "La page {$nom} est anormalement courte : la coquille sans contenu ?",
            );

            // Le `data-module` du maitre, et non la constante `M11` que le
            // gabarit portait pour toutes les pages jusqu'au 27/08/2026.
            $this->assertStringContainsString(
                '<body data-module="'.$page['module'].'"',
                $html,
                "La page {$nom} ne declare pas le module du maitre.",
            );
        }
    }

    /**
     * Le RBAC de 2e niveau — le masquage du menu ne protege rien a lui seul.
     *
     * Le `guide` est choisi a dessein : `M6` et `M7` a `'-'` dans la matrice.
     * Il est donc refuse sur les quatre pages.
     */
    #[Test]
    public function un_role_sans_droit_sur_le_module_est_refuse_sur_les_quatre_pages(): void
    {
        $this->actingAs($this->utilisateur('guide'));

        foreach (self::PAGES as $nom => $page) {
            $this->get($page['url'])->assertForbidden();
        }
    }

    /**
     * Ce cas existe pour que le precedent ne puisse pas passer en refusant
     * TOUT : un controle qui rend 403 partout serait vert sur la moitie des
     * assertions du cas ci-dessus.
     */
    #[Test]
    public function un_droit_de_lecture_sur_le_module_suffit_a_ouvrir_la_page(): void
    {
        $this->jeuDeDonnees();

        // `receptionniste` : M6 = 'L', M7 = '-'. Un seul role eprouve les deux
        // sens du controle.
        //
        // ⚠ Le role est VERIFIE contre la matrice avant d'etre utilise, jamais
        // suppose : la premiere redaction de ce cas nommait un « cuisinier »
        // qui n'existe pas — la matrice dit « cuisine ». Un role introuvable
        // aurait pu passer pour un refus RBAC.
        $receptionniste = $this->utilisateur('receptionniste');

        $this->assertSame('L', $receptionniste->niveauSurModule('M6'));
        $this->assertSame('-', $receptionniste->niveauSurModule('M7'));

        $this->actingAs($receptionniste);
        $this->get('/pwa/stocks')->assertOk();
        $this->get('/pwa/stocks/inventaires')->assertOk();
        $this->get('/pwa/achats')->assertForbidden();
        $this->get('/pwa/achats/approvisionnement')->assertForbidden();
    }

    #[Test]
    public function aucune_ecriture_http_n_atteint_les_quatre_pages(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        foreach (self::PAGES as $nom => $page) {
            foreach (['post', 'put', 'patch', 'delete'] as $methode) {
                $this->{$methode}($page['url'])->assertStatus(405);
            }
        }
    }

    /**
     * AUCUN CHAMP D'ECRITURE — le risque propre a ce lot.
     *
     * Les quatre pages sont des ecrans de SAISIE au maitre. Le controle vit
     * dans `RefuseLaSaisie`, partage avec les pages transverses : une seconde
     * definition de « champ tolere » aurait fini par diverger (Article 10).
     */
    #[Test]
    public function aucun_champ_d_ecriture_n_est_rendu_sur_les_quatre_pages(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        // Liste FERMEE des filtres, page par page. Un champ lie a autre chose
        // fait rougir ce cas AVANT d'atteindre la route Livewire (PA-67).
        $filtresRelus = [
            // `toutSelectionne` et `selection` sont arrivees sur M6 le
            // 03/09/2026 avec l'archivage du referentiel. Meme trois raisons
            // qu'en M7 ci-dessous, a une NUANCE pres qui compte : ici les
            // cases ne sont rendues QU'A qui peut archiver (`peutArchiver`),
            // parce qu'elles n'ont pas d'autre usage sur cet ecran — l'export
            // de M6 porte sur les filtres, jamais sur une selection. Une case
            // rendue a un role en lecture serait un controle qui n'ouvre rien.
            'm6-stocks' => ['recherche', 'toutSelectionne', 'selection'],
            'm6-inventaires' => ['debut', 'fin'],
            // `toutSelectionne` et `selection` (M7, relus le 31/08/2026) :
            // la case « tout cocher » de l'entete et les cases de LIGNE du
            // tableau du maitre (`crud-ui.js` l.66, `m7-approvisionnement.html`
            // l.237 et l.255). Trois precisions, parce que le motif d'origine
            // n'en donnait qu'une :
            //
            //  1. elles ne PERSISTENT rien : `updatedToutSelectionne()` ne
            //     touche que `selection`, une propriete d'affichage ;
            //  2. elles ont un USAGE, et c'est ce qui les distingue d'un
            //     controle decoratif — elles designent le perimetre que
            //     l'export reprendra, exactement ce que le conseil de la modale
            //     d'export du maitre nomme (« utilisez la case a cocher du
            //     tableau pour n'exporter qu'une selection », l.160) ;
            //  3. elles sont rendues a un role en LECTURE, et c'est VOULU :
            //     un `comptable` (M7 = 'L') doit pouvoir filtrer, selectionner
            //     et exporter. Exporter ne produit rien de neuf.
            //
            // Le formulaire d'ECRITURE, lui, ne se rend toujours pas au premier
            // GET : il vit derriere `etatFormulaire`, que seule une action
            // gardee par `exigerEcriture(self::MODULE)` ouvre.
            'm7-achats' => ['recherche', 'toutSelectionne', 'selection'],
            'm7-approvisionnement' => ['recherche', 'toutSelectionne', 'selection'],
        ];

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();
            $this->assertAucunChampDEcriture($html, $nom, $filtresRelus[$nom]);
        }
    }

    /**
     * Aucune des quatre pages ne charge de ressource distante.
     *
     * Repete ici parce que la liste de `ConformiteMaquettePwaTest` est FERMEE
     * et n'aurait pas vu ces quatre-la. Un balayage qui ne couvre pas la page
     * ajoutee est vert a vide — le defaut que PA-152 a trouve dans la garde de
     * lecture seule.
     */
    #[Test]
    public function aucune_page_metier_ne_charge_de_ressource_distante(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $hoteLocal = (string) parse_url((string) config('app.url'), PHP_URL_HOST);
        $autorises = [$hoteLocal, 'localhost', 'localhost:8000', 'www.w3.org'];

        foreach (self::PAGES as $nom => $page) {
            $html = (string) $this->get($page['url'])->assertOk()->getContent();

            preg_match_all('#https?://([^/"\'\s)<]+)#i', $html, $hotes);

            foreach (array_unique($hotes[1]) as $hote) {
                $this->assertContains($hote, $autorises, "La page {$nom} charge une ressource distante : {$hote}.");
            }
        }
    }

    /* ------------------------------------------------------- M6 Stocks */

    /**
     * Le stock affiche est celui que le DOMAINE calcule, et il n'y a aucune
     * colonne de stock a lire.
     *
     * Le jeu : riz = 10 entrees - 3 sorties = 7, seuil 5 -> disponible.
     * Sucre = 2 entrees, seuil 4 -> sous seuil. La valorisation suit le CMP.
     */
    #[Test]
    public function le_stock_et_la_valorisation_viennent_du_service_de_domaine(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/stocks')->assertOk()->getContent();

        $ligneRiz = $this->extraireLigne($html, 'article-'.$this->riz->id);
        $ligneSucre = $this->extraireLigne($html, 'article-'.$this->sucre->id);

        // 7 unites au stock, valorisees a 1 000 F le CMP -> 7 000 F.
        $this->assertStringContainsString('7.00', $ligneRiz);
        $this->assertStringContainsString('7'."\u{00A0}".'000 FCFA', $ligneRiz);

        // Sucre sous seuil : 2 unites a 500 F -> 1 000 F.
        $this->assertStringContainsString('2.00', $ligneSucre);
        $this->assertStringContainsString('1'."\u{00A0}".'000 FCFA', $ligneSucre);

        // Le compteur d'alarme porte sur TOUT le referentiel : un seul article
        // est sous son seuil.
        $this->assertStringContainsString('>1</p>', $html);
    }

    /**
     * PA-161 (a) — les trois colonnes du maitre portent leurs VALEURS.
     *
     * ⚠ Ce cas remplace `les_colonnes_absentes_du_schema_rendent_un_tiret`,
     * qui exigeait exactement trois « — » sur la ligne et la presence des trois
     * motifs de refus. Il etait juste tant que `articles` ne portait ni point,
     * ni suivi, ni prix d'achat ; la migration `2026_09_02_210000` les a
     * creees, et le laisser en place aurait FIGE le defaut qu'il decrivait.
     *
     * Prouve par mutation (02/09/2026) : remplacer la cellule « Point » par un
     * tiret en dur rougit sur « Magasin general » ; forcer `suivi` a
     * `permanent` dans la vue rougit sur le badge « Journalier ».
     */
    #[Test]
    public function les_trois_colonnes_du_maitre_portent_leurs_valeurs(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        // Le riz a ete recu au magasin a 1 000 F : les trois colonnes ont donc
        // toutes trois une valeur reelle.
        $this->riz->forceFill(['point_stockage_id' => $this->magasin->id])->save();

        $html = (string) $this->get('/pwa/stocks')->assertOk()->getContent();
        $ligne = $this->extraireLigne($html, 'article-'.$this->riz->id);

        $this->assertStringContainsString('Magasin g', $ligne, 'La colonne « Point » ne rend pas le rattachement.');
        $this->assertStringContainsString('Permanent', $ligne, 'La colonne « Suivi » ne rend pas le mode.');
        $this->assertStringContainsString('1'."\u{00A0}".'000 FCFA', $ligne, 'La colonne « Valeur d\'achat » ne rend pas le prix d\'achat.');

        // Et les trois motifs de refus ont DISPARU de l'ecran : les garder
        // aurait laisse une explication devenue fausse, ce qui ferme la
        // question au lieu de l'ouvrir (PA-144).
        foreach (['ne porte aucun point de rattachement', 'aucune colonne `suivi`', 'aucune colonne ne conserve le prix'] as $motif) {
            $this->assertStringNotContainsString(
                $motif,
                $html,
                "Le motif de refus « {$motif} » a cesse d'etre vrai et doit etre retire de l'ecran.",
            );
        }
    }

    /**
     * Article 7 — un article JAMAIS RECEPTIONNE rend « — » AVEC sa raison,
     * jamais un lieu ni un montant plausibles.
     *
     * Un « Magasin general » par defaut designerait un rattachement que
     * personne n'a decide ; un « 0 F » se lirait « achete gratuitement ».
     *
     * Prouve par mutation (02/09/2026) : remplacer le `title` de la cellule par
     * une chaine vide rougit sur l'infobulle.
     */
    #[Test]
    public function un_article_jamais_receptionne_rend_un_tiret_avec_sa_raison(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $vierge = Article::create([
            'libelle' => 'Article jamais reçu',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '1.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $html = (string) $this->get('/pwa/stocks')->assertOk()->getContent();
        $ligne = $this->extraireLigne($html, 'article-'.$vierge->id);

        // Deux cellules seulement portent le tiret : « Point » et « Valeur
        // d'achat ». Le suivi, lui, a un defaut au schema qui DECRIT le
        // comportement en vigueur — ce n'est pas une absence de donnee.
        $this->assertSame(
            2,
            substr_count($ligne, '—'),
            'Seules « Point » et « Valeur d\'achat » sont inconnues sur un article jamais receptionne.',
        );

        $this->assertStringContainsString(
            e(__('stocks_pwa.liste.jamais_receptionne')),
            $ligne,
            'Le tiret doit porter sa raison : sans elle, il est indiscernable d\'un ecran casse.',
        );
    }

    /**
     * PA-161 (a) — `prix_achat` est le DERNIER prix d'achat, jamais le CMP.
     *
     * ⚠ C'est le cas qui protege l'information utile de la colonne. Le maitre
     * affiche la derive du CMP contre le prix d'achat (`m6-stocks.html`
     * l.219-220) : y recopier le CMP rendrait cette derive nulle par
     * construction — un indicateur qui annonce « aucune hausse » sans jamais
     * avoir rien mesure.
     *
     * Deux entrees de 10 sacs a 1 000 F puis 10 sacs a 2 000 F : le CMP vaut
     * 1 500, le prix d'achat 2 000. Les confondre est visible ici, et nulle
     * part ailleurs.
     *
     * Prouve par mutation (02/09/2026) : remplacer `'prix_achat' =>
     * $coutUnitaire` par `$article->cout_moyen_pondere` dans
     * `MouvementStockService::entree()` rougit sur les deux assertions.
     */
    #[Test]
    public function le_prix_d_achat_est_celui_de_la_derniere_entree_jamais_le_cout_moyen(): void
    {
        $this->jeuDeDonnees();

        /** @var MouvementStockService $mouvements */
        $mouvements = app(MouvementStockService::class);

        $article = Article::create([
            'libelle' => 'Huile végétale (bidon 20 L)',
            'categorie' => 'Denrées',
            'unite_mesure' => 'bidon',
            'seuil_alerte' => '2.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $mouvements->entree($article->id, $this->magasin->id, '10.00', 'Première réception', '1000.00');
        $mouvements->entree($article->id, $this->magasin->id, '10.00', 'Réception au prix du jour', '2000.00');

        $article->refresh();

        $this->assertSame(0, bccomp((string) $article->prix_achat, '2000.00', 2), 'Le prix d\'achat doit être celui de la DERNIÈRE entrée.');
        $this->assertSame(0, bccomp((string) $article->cout_moyen_pondere, '1500.0000', 4), 'Le CMP doit rester la moyenne pondérée.');

        // Et l'écart entre les deux se VOIT à l'écran, en pourcentage : c'est
        // le signal d'inflation fournisseur du maître. 1 500 contre 2 000 =
        // −25 %.
        $this->actingAs($this->utilisateur('administrateur'));
        $ligne = $this->extraireLigne(
            (string) $this->get('/pwa/stocks')->assertOk()->getContent(),
            'article-'.$article->id,
        );

        $this->assertStringContainsString('-25%', $ligne, 'La dérive du CMP contre le prix d\'achat doit être rendue.');
    }

    /**
     * Un TRANSFERT ne touche pas au prix d'achat.
     *
     * `entree()` sans cout unitaire deplace une marchandise : la deplacer ne
     * l'achete pas. Poser le prix d'achat ici ferait apparaitre un achat qui
     * n'a pas eu lieu — et, sur un article jamais receptionne, remplacerait le
     * « — » honnete par un montant.
     */
    #[Test]
    public function un_transfert_sans_cout_ne_touche_pas_au_prix_d_achat(): void
    {
        $this->jeuDeDonnees();

        /** @var MouvementStockService $mouvements */
        $mouvements = app(MouvementStockService::class);

        $mouvements->entree($this->riz->id, $this->bar->id, '2.00', 'Transfert magasin → bar');

        $this->assertSame(
            0,
            bccomp((string) $this->riz->refresh()->prix_achat, '1000.00', 2),
            'Un transfert ne doit pas réécrire le dernier prix d\'achat connu.',
        );
    }

    /**
     * maitre l.380-383 — un article en suivi JOURNALIER refuse le mouvement.
     *
     * « son stock n'est pas suivi » : la fenetre ne s'ouvre pas, et le refus
     * NOMME l'article. Le refus vit a l'ecran et non dans
     * `MouvementStockService` : la deduction automatique RG-05 passe par ce
     * meme service, et un refus au niveau du domaine ferait echouer une vente
     * au comptoir sur un article de carte mal rattache.
     *
     * Prouve par mutation (02/09/2026) : retirer le `if (!
     * $existant->estSuiviEnStock())` d'`ouvrirMouvement()` rougit sur les deux
     * assertions.
     */
    #[Test]
    public function un_article_journalier_refuse_le_mouvement_de_stock(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $laitue = Article::create([
            'libelle' => 'Laitue',
            'categorie' => 'Denrées',
            'unite_mesure' => 'unité',
            'suivi' => 'journalier',
            'seuil_alerte' => '0.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        \Livewire\Livewire::test(\App\Pwa\Livewire\Stocks\Stocks::class)
            ->call('ouvrirMouvement', $laitue->id)
            ->assertSet('etatFormulaire', null)
            ->assertSet('mvtRefusJournalier', __('stocks_pwa.mouvement.refus_journalier', ['article' => 'Laitue']));

        // Le contraste : un article en suivi permanent ouvre bien la fenetre.
        \Livewire\Livewire::test(\App\Pwa\Livewire\Stocks\Stocks::class)
            ->call('ouvrirMouvement', $this->riz->id)
            ->assertSet('etatFormulaire', 'mouvement')
            ->assertSet('mvtRefusJournalier', null);
    }

    /**
     * maitre l.52-56 — le filtre « Tous les suivis » restreint reellement.
     *
     * Et un article journalier n'entre dans AUCUN filtre d'etat : son solde
     * vaut zero puisque personne ne le tient, et il apparaitrait « en
     * rupture » a perpetuite (maitre l.148-151). Une liste d'alerte pleine de
     * faux positifs cesse d'etre lue (PA-135).
     *
     * Prouve par mutation (02/09/2026) : retirer le `->where('articles.suivi',
     * self::SUIVI_AVEC_STOCK)` du filtre `rupture` rougit sur la derniere
     * assertion.
     */
    #[Test]
    public function le_filtre_des_suivis_restreint_et_ecarte_le_journalier_des_alertes(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $laitue = Article::create([
            'libelle' => 'Laitue',
            'categorie' => 'Denrées',
            'unite_mesure' => 'unité',
            'suivi' => 'journalier',
            'seuil_alerte' => '0.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $journalier = (string) $this->get('/pwa/stocks?suivi=journalier')->assertOk()->getContent();
        $this->assertStringContainsString('article-'.$laitue->id, $journalier);
        $this->assertStringNotContainsString('article-'.$this->riz->id, $journalier);

        $permanent = (string) $this->get('/pwa/stocks?suivi=permanent')->assertOk()->getContent();
        $this->assertStringContainsString('article-'.$this->riz->id, $permanent);
        $this->assertStringNotContainsString('article-'.$laitue->id, $permanent);

        // La laitue est a zero et son seuil est a zero : sans l'ecart de
        // suivi, elle serait « en rupture ».
        $rupture = (string) $this->get('/pwa/stocks?etat=rupture')->assertOk()->getContent();
        $this->assertStringNotContainsString(
            'article-'.$laitue->id,
            $rupture,
            'Un article journalier n\'a pas de stock : il ne peut pas être « en rupture ».',
        );
    }

    /**
     * Une page VIDE sous un total non nul n'est pas un resultat : c'est une
     * pagination perimee, et l'ecran la rattrape.
     *
     * Le cas se produit des qu'un filtre reduit la liste alors qu'on est en
     * page 2 — l'ecran afficherait « Aucun resultat » sous un filtre qui, lui,
     * ramene des lignes. Le rattrapage est dans `render()` plutot que dans un
     * cinquieme hamecon `updatedSuivi()` : celui-la n'aurait rien dit d'un
     * `?page=99` tape a la main, qui est le cas eprouve ici.
     *
     * Prouve par mutation (02/09/2026) : retirer le bloc `if
     * ($lignes->isEmpty() && $lignes->total() > 0)` de `Stocks::render()`
     * rougit sur la premiere assertion.
     */
    #[Test]
    public function une_page_hors_bornes_retombe_sur_la_premiere_au_lieu_de_paraitre_vide(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/stocks?page=99')->assertOk()->getContent();

        $this->assertStringContainsString(
            'article-'.$this->riz->id,
            $html,
            'Une page hors bornes doit retomber sur la première, pas afficher « Aucun résultat ».',
        );

        $this->assertStringNotContainsString(__('stocks_pwa.liste.vide_detail'), $html);
    }

    /**
     * Le filtre d'etat est un registre FERME, et une valeur inconnue ne rend
     * jamais une liste vide sous un bandeau affirmant le contraire.
     */
    #[Test]
    public function un_filtre_d_etat_inconnu_retombe_sur_tous_les_etats(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $htmlValide = (string) $this->get('/pwa/stocks?etat=sous_seuil')->assertOk()->getContent();
        $this->assertStringNotContainsString('article-'.$this->riz->id, $htmlValide);
        $this->assertStringContainsString('article-'.$this->sucre->id, $htmlValide);

        $htmlInvalide = (string) $this->get('/pwa/stocks?etat=nimporte-quoi')->assertOk()->getContent();
        $this->assertStringContainsString('article-'.$this->riz->id, $htmlInvalide);
        $this->assertStringContainsString('article-'.$this->sucre->id, $htmlInvalide);
    }

    /* --------------------------------------------- M6 Fiches et inventaires */

    /**
     * La fiche de stock rend les cumuls du Service, et son solde progressif.
     */
    #[Test]
    public function la_fiche_de_stock_rend_les_cumuls_du_service(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/stocks/inventaires?article='.$this->riz->id)
            ->assertOk()->getContent();

        $this->assertStringContainsString('Stock initial', $html);
        $this->assertStringContainsString('+10.00', $html);
        $this->assertStringContainsString('−3.00', $html);
        $this->assertStringContainsString('Détail des mouvements', $html);
    }

    /**
     * PA-135 — le drapeau de coherence NE s'affiche QUE lorsqu'il vaut, et le
     * bandeau vient AVANT le recapitulatif.
     *
     * Une mention permanente cesserait d'etre lue. Le jeu normal est coherent :
     * le bandeau doit donc etre absent.
     */
    #[Test]
    public function le_bandeau_d_incoherence_est_absent_quand_la_fiche_est_coherente(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/stocks/inventaires?article='.$this->riz->id)
            ->assertOk()->getContent();

        $this->assertStringNotContainsString('Incohérence détectée', $html);
    }

    /**
     * Et le bandeau APPARAIT des que la fiche se declare incoherente.
     *
     * ## POURQUOI CE CAS REND LA VUE DIRECTEMENT, ET NON UNE PAGE HTTP
     *
     * La premiere redaction de ce cas ecrivait un mouvement en SQL direct,
     * hors de `MouvementStockService`, en esperant faire tomber le drapeau.
     * Elle a echoue, et l'echec est INSTRUCTIF : `coherent` compare le solde
     * progressif — stock initial plus les mouvements de la periode — au stock
     * theorique, et les deux sont produits par la MEME expression SQL sur le
     * MEME ensemble de lignes. `soldeAvant(lendemain(fin))` couvre
     * `< fin+1 00:00:00`, la boucle couvre `[debut 00:00:00, fin 23:59:59]`
     * plus tout ce qui precede `debut`. Sur un `timestamp` MySQL sans partie
     * fractionnaire, les deux ensembles sont identiques : aucune ecriture,
     * quelle qu'en soit l'origine, ne peut les separer.
     *
     * Autrement dit, **ce drapeau parait structurellement toujours vrai cote
     * serveur**. C'est une observation sur `FicheStockService`, pas sur cette
     * page — elle est hors du perimetre de ce lot et remontee au rapport
     * plutot que corrigee en silence. Elle a exactement la forme de PA-59/60/61 :
     * un indicateur qui dit « tout va bien » sans qu'aucun chemin ne puisse le
     * contredire.
     *
     * Ce que ce cas verifie donc reellement, et qui reste utile : la vue REND
     * le bandeau quand le drapeau est faux, avec les mots du maitre, et elle
     * le rend AVANT le recapitulatif. Sans lui, la branche serait du texte
     * mort — et le jour ou le drapeau deviendrait atteignable, personne ne
     * saurait si elle fonctionne.
     */
    #[Test]
    public function la_vue_rend_le_bandeau_d_incoherence_avant_les_chiffres(): void
    {
        $this->jeuDeDonnees();
        $administrateur = $this->utilisateur('administrateur');
        $this->actingAs($administrateur);

        $html = $this->rendreFicheAvecCoherence(false);

        $this->assertStringContainsString('Incohérence détectée', $html);
        $this->assertStringContainsString('ne doit pas servir de justificatif', $html);

        // Le bandeau se lit AVANT le recapitulatif — meme raisonnement que
        // « ne vaut pas facture » au corps du document de reservation (PA-113).
        //
        // ⚠ Le reperage porte sur le CONTENEUR de la grille d'indicateurs, pas
        // sur le mot « Stock initial » : celui-ci ouvre aussi le sous-titre de
        // la page (« Stock initial, entrées, sorties et stock théorique sur une
        // période »), et l'assertion mesurait donc la distance au sous-titre —
        // toujours en tete, donc toujours vraie ou toujours fausse, jamais ce
        // qu'on croyait mesurer.
        $positionBandeau = strpos($html, 'Incohérence détectée');
        $positionRecap = strpos($html, 'grid grid-cols-2 lg:grid-cols-6 gap-3 mb-4');
        $this->assertIsInt($positionBandeau);
        $this->assertIsInt($positionRecap, 'La grille des six indicateurs de la fiche est introuvable.');
        $this->assertLessThan($positionRecap, $positionBandeau);

        // Et la MEME vue, drapeau vrai, ne le rend pas : une mention
        // permanente cesserait d'etre lue (PA-135).
        $this->assertStringNotContainsString('Incohérence détectée', $this->rendreFicheAvecCoherence(true));
    }

    /**
     * L'onglet « Inventaires clôturés » est RENDU, et il DIT que le schema ne
     * distingue pas un inventaire clos d'un inventaire ouvert.
     *
     * 4.5 exige l'onglet et son contenu, 6 interdit qu'il mente (PA-150).
     */
    #[Test]
    public function l_onglet_des_inventaires_dit_que_le_schema_ne_porte_aucun_statut(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/stocks/inventaires?onglet=historique')
            ->assertOk()->getContent();

        $this->assertStringContainsString('Inventaires clôturés', $html);

        // ## Converti au nouveau contrat le 31/08/2026 (directive PO) : la
        // note « clôturés ou non » et l'explication des tirets ne sont plus
        // AFFICHÉES — la déclaration vit dans le code de la vue. Les tirets,
        // eux, RESTENT rendus : c'est un fait d'écran, pas une section.
        $this->assertStringNotContainsString('clôturés ou non', $html);

        $source = file_get_contents(resource_path('views/pwa/stocks/inventaires.blade.php'));
        $this->assertStringContainsString('« Manquants » et « Excédents » rendent « — »', $source);
    }

    /**
     * PA-135, repris ici : « 7 jours » couvre SEPT jours, aujourd'hui compris.
     *
     * Le maitre recule de 7 x 86 400 000 ms, ce qui produit HUIT jours une fois
     * les deux bornes incluses — le cumul contredirait le libelle du bouton,
     * sur un document dont l'objet est de justifier un solde.
     */
    #[Test]
    public function le_raccourci_de_sept_jours_couvre_sept_jours(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/stocks/inventaires')->assertOk()->getContent();

        $attendu = 'du='.now()->subDays(6)->toDateString().'&amp;au='.now()->toDateString();
        $this->assertStringContainsString($attendu, $html, 'Le raccourci « 7 jours » ne couvre pas sept jours.');

        // Et « Ce mois » part du PREMIER du mois, pas de trente jours en
        // arriere : un rapprochement de stock se fait sur un mois calendaire.
        $this->assertStringContainsString('du='.now()->startOfMonth()->toDateString().'&amp;au=', $html);
    }

    /* ------------------------------------------------------- M7 Achats */

    #[Test]
    public function le_registre_des_fournisseurs_rend_les_valeurs_reelles_et_un_tiret_pour_l_absent(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/achats')->assertOk()->getContent();

        $this->assertStringContainsString('Grand Marché Natitingou SARL', $html);
        // L'evaluation `a_revoir` du schema porte le libelle du maitre.
        $this->assertStringContainsString('À revoir', $html);

        // Le fournisseur sans contact ni evaluation rend « — », pas une case
        // vide qu'on lirait comme une donnee non encore chargee.
        $ligne = $this->extraireLigne($html, 'fournisseur-'.Fournisseur::where('raison_sociale', 'Fournisseur muet')->firstOrFail()->id);
        $this->assertGreaterThanOrEqual(4, substr_count($ligne, '—'));
    }

    /**
     * Le montant d'une commande vient de `CommandeAchat::montantTotal()` —
     * somme des lignes en `bcadd` —, jamais d'une colonne saisie.
     */
    #[Test]
    public function le_montant_d_une_commande_est_la_somme_de_ses_lignes(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/achats?onglet=commandes')->assertOk()->getContent();

        // 4 x 1 000 + 6 x 500 = 7 000 F.
        $this->assertStringContainsString('7'."\u{00A0}".'000 FCFA', $html);
        $this->assertStringContainsString('Envoyée', $html);
    }

    /**
     * La LACUNE de schema qui subsiste est nommee, celle qui est fermee ne
     * l'est plus.
     *
     * ⚠ Ce cas s'appelait `les_deux_lacunes_…` et il a ROUGI le 03/09/2026,
     * exactement comme son commentaire l'annonçait : `fournisseurs.actif`
     * existe depuis la migration d'archivage des referentiels. C'est le
     * mecanisme de PA-144 qui a fonctionne — une declaration de lacune ne
     * survit pas a la lacune. La seconde moitie (`annulee` absent des statuts
     * de commande) reste vraie et reste verifiee.
     */
    #[Test]
    public function la_lacune_de_schema_achats_qui_subsiste_est_nommee(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/achats')->assertOk()->getContent();

        // ## Converti au nouveau contrat le 31/08/2026 (directive PO) : les
        // lacunes ne sont plus AFFICHÉES — la déclaration vit dans le code de
        // la vue, l'écran reste propre. Les deux moitiés sont tenues : sans
        // la seconde, supprimer la déclaration avec la section passerait
        // inaperçu et la lacune redeviendrait un oubli (PA-144).
        $this->assertStringNotContainsString('LACUNE OUVERTE', $html);
        $this->assertStringNotContainsString(e('aucun indicateur d\'activité'), $html);

        $source = file_get_contents(resource_path('views/pwa/achats/achats.blade.php'));
        $this->assertStringContainsString('Une seule lacune de schema subsiste', $source);
        $this->assertStringContainsString("l'annulation d'une commande", $source);

        // Le schema est bien ce que la declaration affirme — verifie, pas
        // suppose. Le jour ou `annulee` existera, cette assertion rougira et
        // la declaration devra suivre.
        $this->assertNotContains('annulee', CommandeAchat::STATUTS);

        // La lacune FERMEE l'est reellement : la colonne existe, et l'ecran
        // rend le geste. Sans cette moitie, retirer le bouton d'archivage
        // laisserait la declaration corrigee sur un ecran redevenu incapable.
        $this->assertContains('actif', DB::getSchemaBuilder()->getColumnListing('fournisseurs'));
        $this->assertStringContainsString('confirmerArchivageFournisseur', $source);
    }

    /* --------------------------------------------- M7 Approvisionnement */

    /**
     * Les besoins viennent du MEME service que l'ecran Stocks : un seul
     * article sous son seuil, et c'est le meme des deux cotes.
     */
    #[Test]
    public function les_besoins_viennent_de_la_meme_projection_que_l_ecran_stocks(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/achats/approvisionnement')->assertOk()->getContent();

        $this->assertStringContainsString('besoin-'.$this->sucre->id, $html);
        $this->assertStringNotContainsString('besoin-'.$this->riz->id, $html);

        // Le manque est calcule en `bcsub` sur les chaines : 4 - 2 = 2.
        $ligne = $this->extraireLigne($html, 'besoin-'.$this->sucre->id);
        $this->assertStringContainsString('2.00', $ligne);
    }

    /**
     * LA DETTE FOURNISSEUR EST CHIFFRÉE depuis le 02/09/2026 (PA-165) —
     * renversement assumé du cas qui portait ce nom jusque-là.
     *
     * `ReglementFournisseurService` est le premier writer de
     * `reglements_fournisseur` ; `paiements`, lui, reste un rattachement
     * CLIENT (factures + sessions de caisse) — les deux tables coexistent,
     * chacune vers son propre tiers, et ce n'est PAS une lacune.
     *
     * ⚠ Il a fallu, pour que « Reste dû » ne mente pas, corriger une
     * conséquence d'un writer manquant : `commandes_achat.montant_total`
     * n'était écrit par aucun chemin (voir le docblock daté de
     * `Approvisionnement::enregistrerCommande()`), et
     * `ReglementFournisseurService::resteDu()` LIT cette colonne. Le Service
     * n'est pas modifié ici ; l'écran synchronise sa propre colonne.
     */
    #[Test]
    public function la_dette_fournisseur_est_chiffree_depuis_le_service_de_reglement(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/achats/approvisionnement?onglet=dettes')
            ->assertOk()->getContent();

        $this->assertStringContainsString('Dettes fournisseurs', $html);

        $commande = CommandeAchat::query()->firstOrFail();
        $ligne = $this->extraireLigne($html, 'dette-cmd-'.$commande->id);

        // Le montant COMMANDE est un fait, il s'affiche, ET le RESTE DÛ,
        // désormais, est le MÊME chiffre : aucun règlement n'a encore été
        // enregistré sur cette commande.
        $this->assertSame(
            2,
            substr_count($ligne, '7'."\u{00A0}".'000 FCFA'),
            'Le montant commandé ET le reste dû doivent tous deux afficher 7 000 F '
            .'sur cette ligne de dette jamais réglée.',
        );

        // Le bouton « Régler » est offert (reste dû > 0) sur l'onglet Commandes.
        $this->assertStringContainsString('ouvrirFormulaireReglement', $html);

        // Les deux tables coexistent, chacune vers son propre tiers.
        $this->assertTrue(DB::getSchemaBuilder()->hasTable('paiements'));
        $this->assertTrue(DB::getSchemaBuilder()->hasTable('reglements_fournisseur'));
    }

    /**
     * Les indicateurs de trésorerie sont RÉELLEMENT CHIFFRÉS depuis le
     * 02/09/2026 (PA-165) — renversement assumé : ils rendaient « — » quand
     * aucun règlement fournisseur n'existait au schéma.
     */
    #[Test]
    public function les_indicateurs_de_tresorerie_sont_chiffres_depuis_le_service_de_reglement(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/achats/approvisionnement')->assertOk()->getContent();

        // La bande d'indicateurs, bornee par le conteneur d'onglets qui la
        // suit — jamais par un motif d'indentation, qui se casse au premier
        // reformatage de la vue sans rien dire.
        $bandeau = $this->extraireEntre($html, 'id="kpis-appro"', 'role="tablist"');

        // Un article sous seuil, une commande envoyee, zero reception
        // partielle — le zero est une VALEUR, il reste « 0 ».
        $this->assertStringContainsString('>1</p>', $bandeau);
        $this->assertStringContainsString('>0</p>', $bandeau);

        // « Fournisseurs à payer » : 1 (le seul fournisseur avec une dette
        // non réglée). « Total dû » : 7 000 F, le même chiffre que l'onglet
        // Dettes — une seule formule, jamais deux (voir `render()`).
        $this->assertStringContainsString('7'."\u{00A0}".'000 FCFA', $bandeau);

        // Et plus aucun tiret sur ces deux cartes.
        $this->assertSame(0, substr_count($bandeau, '—'));
    }

    /**
     * Les bons de reception sont rendus avec leur conformite reelle, et les
     * deux colonnes que le schema ne porte pas rendent « — ».
     */
    #[Test]
    public function les_receptions_rendent_leur_conformite_et_un_tiret_pour_le_detail_absent(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/achats/approvisionnement?onglet=receptions')
            ->assertOk()->getContent();

        $reception = BonReception::query()->firstOrFail();
        $ligne = $this->extraireLigne($html, 'rec-'.$reception->id);

        $this->assertStringContainsString('partielle', $ligne);
        // « Point » et « Articles » : aucune ligne de detail au schema (PA-39).
        $this->assertSame(2, substr_count($ligne, '—'));
    }

    /* ----------------------------------------------------- auxiliaires */

    /**
     * Le jeu de donnees des quatre pages.
     *
     * Les mouvements passent par `MouvementStockService`, jamais par un
     * `insert` : c'est ce qui rend la fiche COHERENTE, et le cas d'incoherence
     * n'a de sens que par contraste avec celui-ci.
     */
    private function jeuDeDonnees(): void
    {
        $auteur = $this->utilisateur('administrateur');
        $this->actingAs($auteur);

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        $this->bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);

        $this->riz = Article::create([
            'libelle' => 'Riz local (sac 50 kg)',
            'categorie' => 'Denrées',
            'unite_mesure' => 'sac',
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '12.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $this->sucre = Article::create([
            'libelle' => 'Sucre en poudre',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '4.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        /** @var MouvementStockService $mouvements */
        $mouvements = app(MouvementStockService::class);

        $mouvements->entree($this->riz->id, $this->magasin->id, '10.00', 'Réception SODIS Bénin', '1000.00');
        $mouvements->sortie($this->riz->id, $this->magasin->id, '3.00', 'Consommation cuisine');
        $mouvements->entree($this->sucre->id, $this->bar->id, '2.00', 'Réception', '500.00');

        // --- M7 -----------------------------------------------------------

        $fournisseur = Fournisseur::create([
            'raison_sociale' => 'Grand Marché Natitingou SARL',
            'contact' => '01 90 12 34 56',
            'categorie' => 'Denrées alimentaires',
            'conditions_paiement' => 'Comptant',
            'evaluation' => 'a_revoir',
        ]);

        // Article 7 : ce fournisseur-la n'a rien d'autre que sa raison
        // sociale. Les quatre colonnes `nullable` doivent rendre « — ».
        Fournisseur::create(['raison_sociale' => 'Fournisseur muet']);

        $commande = CommandeAchat::create([
            'fournisseur_id' => $fournisseur->id,
            'date_commande' => now()->subDays(45)->toDateString(),
            'statut' => 'envoyee',
            'utilisateur_id' => $auteur->id,
        ]);

        LigneCommandeAchat::create([
            'commande_id' => $commande->id,
            'article_id' => $this->riz->id,
            'quantite_commandee' => '4.00',
            'prix_unitaire' => '1000.00',
        ]);
        LigneCommandeAchat::create([
            'commande_id' => $commande->id,
            'article_id' => $this->sucre->id,
            'quantite_commandee' => '6.00',
            'prix_unitaire' => '500.00',
        ]);

        BonReception::create([
            'commande_id' => $commande->id,
            'date_reception' => now()->subDays(30)->toDateString(),
            'utilisateur_id' => $auteur->id,
            'conformite' => 'partielle',
        ]);

        $inventaire = Inventaire::create([
            'point_id' => $this->magasin->id,
            'date_inventaire' => now()->subDays(10)->toDateString(),
            'utilisateur_id' => $auteur->id,
        ]);

        LigneInventaire::create([
            'inventaire_id' => $inventaire->id,
            'article_id' => $this->riz->id,
            'quantite_theorique' => '7.00',
            'quantite_constatee' => '6.00',
            'ecart' => '-1.00',
        ]);
    }

    /**
     * La ligne `<tr>` qui porte une cle Livewire donnee.
     *
     * Compter les tirets sur la page entiere ne dirait rien : le bloc de refus
     * en contient, et le decompte resterait vert quoi qu'il arrive.
     */
    private function extraireLigne(string $html, string $cle): string
    {
        $position = strpos($html, 'wire:key="'.$cle.'"');
        $this->assertIsInt($position, "Aucune ligne ne porte la cle {$cle}.");

        $debut = strrpos(substr($html, 0, $position), '<tr');
        $this->assertIsInt($debut);

        $fin = strpos($html, '</tr>', $position);
        $this->assertIsInt($fin);

        return substr($html, $debut, $fin - $debut);
    }

    private function extraireEntre(string $html, string $debut, string $fin): string
    {
        $depart = strpos($html, $debut);
        $this->assertIsInt($depart, "Marqueur introuvable : {$debut}");

        $arrivee = strpos($html, $fin, $depart);
        $this->assertIsInt($arrivee, "Marqueur de fin introuvable apres : {$debut}");

        return substr($html, $depart, $arrivee - $depart);
    }

    /**
     * La vue de la fiche, rendue avec un drapeau de coherence FORCE.
     *
     * Les donnees viennent du vrai Service ; seul `coherent` est remplace.
     * C'est le seul moyen d'eprouver la branche tant que le drapeau reste
     * inatteignable par la base (voir le cas ci-dessus).
     */
    private function rendreFicheAvecCoherence(bool $coherent): string
    {
        /** @var \App\Domain\Stocks\Services\FicheStockService $service */
        $service = app(\App\Domain\Stocks\Services\FicheStockService::class);

        $fiche = $service->pourArticle(
            $this->riz,
            now()->subDays(29)->toDateString(),
            now()->toDateString(),
        );

        // Le Service rend `true` : la garde ci-dessous echouerait si ce
        // n'etait plus le cas, et le cas cesserait alors d'etre un rendu force.
        $this->assertTrue($fiche['coherent'], 'Le Service rend deja une fiche incoherente : ce cas doit etre repris.');

        $fiche['coherent'] = $coherent;

        return view('pwa.stocks.inventaires', [
            'utilisateur' => \Illuminate\Support\Facades\Auth::user(),
            'menu' => \App\Pwa\Support\MenuLateral::pour(\Illuminate\Support\Facades\Auth::user()),
            // Ce rendu direct reconstruit les donnees du socle a la main —
            // c'est le prix du drapeau force. `banniere` en fait partie
            // depuis le lot 0.6, calculee comme `PageMetier::socle()` le fait.
            'banniere' => \App\Pwa\Support\BanniereEcriture::pour(
                \Illuminate\Support\Facades\Auth::user(),
                \App\Pwa\Livewire\Stocks\Inventaires::class,
            ),
            // ⚠ Ces noms sont ceux que `Inventaires::render()` fournit
            // REELLEMENT (31/08/2026). La premiere redaction de ce cas en
            // inventait cinq — `article`, `pointApplique`, `registre`,
            // `syntheses`, `dernier` — pour un ecran qui n'existait pas encore ;
            // le rendu levait « Undefined variable $point » avant d'atteindre
            // la moindre assertion. Le CONTRAT de ce cas, lui, n'a pas bouge :
            // c'est ce qui est asserte plus haut, pas cet echafaudage.
            'onglet' => 'fiche',
            'articles' => Article::query()->orderBy('libelle')->get(),
            'points' => PointStockage::query()->orderBy('libelle')->get(),
            'articleSelectionne' => $this->riz,
            // Fiche UNITAIRE : « Tous les articles » (PO 06/09/2026) est le
            // second mode du meme panneau, et ce cas eprouve le premier.
            'tousLesArticles' => false,
            'ficheConsolidee' => null,
            'fiche' => $fiche,
            'debut' => $fiche['periode']['debut'],
            'fin' => $fiche['periode']['fin'],
            'point' => '',
            'articleId' => $this->riz->id,
            'etatFormulaire' => null,
            'raccourcis' => [],
            'inventaireEnCours' => null,
            // 02/09/2026 — les trois panneaux d'onglet sont rendus a chaque
            // GET (garde G5, l'inactif porte `hidden`) : le rendu direct doit
            // donc fournir les donnees des trois, et `$errors`, que le
            // middleware web partage d'ordinaire — le panneau Inventaire
            // porte un `@error` desormais toujours compile.
            'dernierInventaireParPoint' => [],
            'errors' => new \Illuminate\Support\ViewErrorBag(),
            'feuille' => [],
            'nonComptes' => 0,
            'historique' => Inventaire::query()->get(),
        ])->render();
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
    // « Tous les articles » — demande du Product Owner du 06/09/2026
    // =================================================================

    /**
     * Le detail consolide montre les mouvements de TOUS les articles, chacun
     * avec son libelle et son unite.
     *
     * ⚠ MUTATION TRANCHEE : `pourTousLesArticles()` filtre sur le premier
     * article au lieu de les parcourir tous → ce cas ROUGE (le sucre du bar
     * disparait du detail). Restauree.
     */
    #[Test]
    public function tous_les_articles_consolide_les_mouvements_avec_leur_article(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $composant = \Livewire\Livewire::test(\App\Pwa\Livewire\Stocks\Inventaires::class);
        $composant->set('onglet', 'fiche');
        $composant->set('articleId', '');

        $html = $composant->html();

        // ⚠ On compte les LIGNES DU TABLEAU, jamais le libelle dans la page :
        // le select du filtre liste deja tous les articles, et une assertion
        // sur le libelle seul restait VERTE sous la mutation (constate en la
        // tranchant). Trois mouvements au jeu : deux sur le riz, un sur le
        // sucre.
        $this->assertSame(3, substr_count($html, 'wire:key="mvt-tous-'));

        // Et chacun porte bien SON article dans la cellule dediee.
        $this->assertStringContainsString('text-slate-700">Riz local (sac 50 kg)</td>', $html);
        $this->assertStringContainsString('text-slate-700">Sucre en poudre</td>', $html);
    }

    /**
     * LES QUANTITES NE SE TOTALISENT PAS : des sacs et des kilos additionnes
     * donneraient un chiffre faux mais plausible. Le service rend un nombre
     * de mouvements et une VALEUR (unite commune), jamais un cumul.
     */
    #[Test]
    public function la_consolidation_totalise_la_valeur_jamais_les_quantites(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        /** @var \App\Domain\Stocks\Services\FicheStockService $service */
        $service = app(\App\Domain\Stocks\Services\FicheStockService::class);

        $consolidee = $service->pourTousLesArticles(
            now()->subDays(29)->toDateString(),
            now()->toDateString(),
        );

        // Trois mouvements au jeu : deux sur le riz, un sur le sucre.
        $this->assertSame(3, $consolidee['mouvements']);
        $this->assertSame(2, $consolidee['articles_avec_mouvement']);

        // Aucune cle de cumul de quantites n'existe — c'est le contrat.
        $this->assertArrayNotHasKey('entrees', $consolidee);
        $this->assertArrayNotHasKey('sorties', $consolidee);
        $this->assertArrayNotHasKey('stock_theorique', $consolidee);

        // La valeur, elle, est bien la somme : 7 sacs a 1 000 + 2 kg a 500.
        $this->assertSame(0, bccomp($consolidee['valeur_stock_theorique'], '8000.00', 2));
    }

    /**
     * L'export refuse « Tous les articles » et DIT pourquoi : le document de
     * fiche de stock est etabli pour UN article — en produire un consolide
     * sans revoir le gabarit imprimerait des unites differentes additionnees.
     */
    #[Test]
    public function l_export_refuse_tous_les_articles_et_nomme_sa_raison(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $composant = \Livewire\Livewire::test(\App\Pwa\Livewire\Stocks\Inventaires::class);
        $composant->set('onglet', 'fiche');
        $composant->set('articleId', '');
        $composant->call('genererExport');
        $composant->assertHasErrors('formatExport');
    }
}
