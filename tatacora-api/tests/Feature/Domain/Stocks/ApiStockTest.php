<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Stocks;

use App\Domain\Stocks\Etats\EtatStocks;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Policies\MouvementStockPolicy;
use App\Domain\Stocks\Services\ConsultationStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * API M6 — Stocks. Routes consommées par le client Flutter et la PWA.
 *
 * @see EF-M6-01 Référentiel articles
 * @see EF-M6-02 Entrées et sorties
 * @see EF-M6-03 Valorisation au coût moyen pondéré
 * @see EF-M6-04 Fiche de stock
 * @see EF-M6-05 Alerte de sous-stock
 * @see EF-M6-06 Traçabilité intégrale
 * @see RG-06 Blocage au-delà du disponible
 * @see RG-16 RBAC de 2e niveau
 *
 * ## Ce que cette suite existe pour empêcher
 *
 * 1. **Qu'un stock calculé redevienne un champ saisi** (PA-24). Le prototype
 *    porte « Stock disponible » en saisie libre ; le laisser entrer par l'API
 *    ferait diverger le stock affiché du stock réel dès la première vente,
 *    sans que rien ne le signale.
 * 2. **Que deux chemins calculent le même stock différemment** (PA-121). La
 *    liste agrège en une requête groupée, `StockTheoriqueService` calcule
 *    article par article, `EtatStocks` édite le PDF : les trois sont comparés
 *    ici, sur les mêmes données.
 * 3. **Qu'une route d'écriture perde sa garde RBAC** (PA-65). Les rôles sont
 *    dérivés de `RolePermissionSeeder::MATRICE`, jamais écrits en dur : le
 *    jour où la matrice change, la suite suit — ou échoue en le disant.
 */
final class ApiStockTest extends TestCase
{
    use RefreshDatabase;

    private PointStockage $magasin;

    private PointStockage $bar;

    private Article $riz;

    private Article $biere;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        $this->bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);

        $this->riz = Article::create([
            'libelle' => 'Riz parfumé 50kg',
            'categorie' => 'denree',
            'unite_mesure' => 'sac',
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '12.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $this->biere = Article::create([
            'libelle' => 'Bière La Béninoise 65cl',
            'categorie' => 'boisson',
            'unite_mesure' => 'bouteille',
            'seuil_alerte' => '10.00',
            'seuil_reappro' => '24.00',
            'cout_moyen_pondere' => '450.0000',
        ]);
    }

    // ------------------------------------------------------- Authentification

    /**
     * Aucune des neuf routes n'est publique. La liste est explicite : une route
     * ajoutée au groupe sans jeton passerait sinon inaperçue.
     */
    #[Test]
    public function aucune_route_de_stock_n_est_accessible_sans_jeton(): void
    {
        $this->getJson('/api/v1/stocks/articles')->assertUnauthorized();
        $this->getJson('/api/v1/stocks/points')->assertUnauthorized();
        $this->getJson('/api/v1/stocks/etat')->assertUnauthorized();
        $this->getJson('/api/v1/stocks/mouvements')->assertUnauthorized();
        $this->getJson("/api/v1/stocks/articles/{$this->riz->id}")->assertUnauthorized();
        $this->getJson("/api/v1/stocks/articles/{$this->riz->id}/fiche?debut=2026-08-01&fin=2026-08-31")
            ->assertUnauthorized();
        $this->postJson('/api/v1/stocks/mouvements', [])->assertUnauthorized();
        $this->postJson('/api/v1/stocks/articles', [])->assertUnauthorized();
        $this->putJson("/api/v1/stocks/articles/{$this->riz->id}", [])->assertUnauthorized();
    }

    // ------------------------------------------------------------------ RBAC

    /**
     * RG-16 — un rôle sans aucun accès à M6 est refusé, en lecture comme en
     * écriture. Le rôle est DÉRIVÉ de la matrice : l'écrire en dur ferait
     * passer la suite au vert le jour où la matrice changerait.
     */
    #[Test]
    public function rg16_un_role_sans_acces_a_m6_est_refuse_partout(): void
    {
        $role = $this->roleAvecNiveauM6('-');
        Sanctum::actingAs($this->utilisateur($role));

        $this->getJson('/api/v1/stocks/articles')->assertForbidden();
        $this->getJson('/api/v1/stocks/points')->assertForbidden();
        $this->getJson('/api/v1/stocks/etat')->assertForbidden();
        $this->getJson('/api/v1/stocks/mouvements')->assertForbidden();
        $this->postJson('/api/v1/stocks/mouvements', $this->mouvementValide())->assertForbidden();

        $this->assertSame(0, MouvementStock::count());
    }

    /**
     * RG-16 — un rôle en LECTURE seule consulte tout et n'écrit rien.
     */
    #[Test]
    public function rg16_un_role_en_lecture_seule_consulte_mais_n_ecrit_pas(): void
    {
        $role = $this->roleAvecNiveauM6('L');
        Sanctum::actingAs($this->utilisateur($role));

        $this->getJson('/api/v1/stocks/articles')->assertOk();
        $this->getJson('/api/v1/stocks/points')->assertOk();
        $this->getJson('/api/v1/stocks/etat')->assertOk();
        $this->getJson('/api/v1/stocks/mouvements')->assertOk();

        $this->postJson('/api/v1/stocks/mouvements', $this->mouvementValide())->assertForbidden();
        $this->postJson('/api/v1/stocks/articles', $this->articleValide())->assertForbidden();
        $this->putJson("/api/v1/stocks/articles/{$this->riz->id}", $this->articleValide())->assertForbidden();

        $this->assertSame(0, MouvementStock::count());
        $this->assertSame(2, Article::count());
    }

    /**
     * Le refus RBAC est traduit, jamais écrit en dur dans le middleware.
     */
    #[Test]
    public function rg16_le_refus_est_un_message_traduit(): void
    {
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM6('-')));

        $this->getJson('/api/v1/stocks/articles')
            ->assertForbidden()
            ->assertJsonPath('message', __('auth.module_refuse'));
    }

    /**
     * Garde STRUCTURELLE à liste fermée — chaque route du groupe `stocks`
     * déclare le niveau RBAC qu'elle exige, et la suite échoue tant qu'une
     * route nouvelle n'y est pas inscrite.
     *
     * ## Pourquoi un test de structure en plus des tests de comportement
     *
     * Retirer `module:M6,C` de `POST /stocks/mouvements` ne fait rougir aucun
     * test de comportement : le `FormRequest` refuse aussi, en 3ᵉ niveau, et le
     * 403 reste un 403. La garde disparue serait donc invisible — jusqu'au jour
     * où quelqu'un ajouterait une route d'écriture SANS FormRequest, et où plus
     * rien ne la tiendrait. C'est exactement la forme de PA-65 :
     * `POST /api/v1/sync` n'avait aucun contrôle, et 421 tests verts ne le
     * montraient pas.
     *
     * La liste ci-dessous est donc la spécification : une route ajoutée au
     * groupe sans y figurer fait échouer la suite, donc se fait relire.
     */
    #[Test]
    public function rg16_chaque_route_du_groupe_stocks_porte_sa_garde_rbac(): void
    {
        $attendu = [
            'GET|HEAD api/v1/stocks/points' => 'M6,L',
            'GET|HEAD api/v1/stocks/etat' => 'M6,L',
            'GET|HEAD api/v1/stocks/mouvements' => 'M6,L',
            'POST api/v1/stocks/mouvements' => 'M6,C',
            'GET|HEAD api/v1/stocks/articles' => 'M6,L',
            'POST api/v1/stocks/articles' => 'M6,C',
            'GET|HEAD api/v1/stocks/articles/{article}' => 'M6,L',
            'PUT api/v1/stocks/articles/{article}' => 'M6,C',
            'GET|HEAD api/v1/stocks/articles/{article}/fiche' => 'M6,L',
        ];

        $constate = [];

        foreach (\Illuminate\Support\Facades\Route::getRoutes()->getRoutes() as $route) {
            if (! str_starts_with($route->uri(), 'api/v1/stocks/')) {
                continue;
            }

            $middlewares = $route->gatherMiddleware();

            $gardes = array_values(array_filter(
                $middlewares,
                fn (mixed $m): bool => is_string($m) && str_starts_with($m, 'module:'),
            ));

            $cle = implode('|', array_diff($route->methods(), ['HEAD'])) . ' ' . $route->uri();
            $cle = str_contains($cle, 'GET ') ? str_replace('GET ', 'GET|HEAD ', $cle) : $cle;

            $constate[$cle] = $gardes === []
                ? 'AUCUNE GARDE'
                : str_replace('module:', '', $gardes[0]);

            // Toute route de ce groupe exige aussi un jeton : le RBAC ne dit
            // rien d'un appelant anonyme.
            $this->assertContains(
                'auth:sanctum',
                $middlewares,
                "La route {$cle} est accessible sans authentification.",
            );
        }

        ksort($attendu);
        ksort($constate);

        $this->assertSame(
            $attendu,
            $constate,
            'Une route du groupe `stocks` a perdu sa garde RBAC, ou une route nouvelle n\'est pas inscrite ici.',
        );
    }

    // ------------------------------------------------------ Liste des articles

    #[Test]
    public function la_liste_expose_le_stock_calcule_en_lecture_seule(): void
    {
        $this->approvisionner($this->biere, $this->bar, '24.00', '450.0000');
        Sanctum::actingAs($this->magasinier());

        $reponse = $this->getJson('/api/v1/stocks/articles')->assertOk();

        $biere = collect((array) $reponse->json('data'))->firstWhere('id', $this->biere->id);

        $this->assertNotNull($biere);
        // Chaîne, jamais float : un réarrondi côté client ferait diverger
        // l'affichage du chiffre réellement stocké.
        $this->assertSame('24.00', $biere['stock']);
        $this->assertIsString($biere['stock']);
        $this->assertSame('10800.00', $biere['valeur_stock']);
        $this->assertSame('tous_points', $biere['portee']);
        $this->assertNull($biere['point_id']);
        $this->assertFalse($biere['sous_seuil']);
        $this->assertFalse($biere['rupture']);
        $this->assertTrue($biere['stock_lecture_seule']);

        // Le riz n'a aucun mouvement : zéro, et non une absence de clé.
        $riz = collect((array) $reponse->json('data'))->firstWhere('id', $this->riz->id);
        $this->assertSame('0.00', $riz['stock']);
        $this->assertTrue($riz['rupture']);
        $this->assertTrue($riz['sous_seuil']);
    }

    /**
     * Le stock rendu par la liste — agrégation groupée — doit être IDENTIQUE
     * au calcul unitaire de `StockTheoriqueService`. Sans cette comparaison,
     * une divergence de convention de signe entre les deux chemins afficherait
     * deux stocks différents pour le même article, chacun paraissant juste
     * (PA-121).
     */
    #[Test]
    public function le_stock_de_la_liste_est_identique_au_service_article_par_article(): void
    {
        $this->approvisionner($this->biere, $this->bar, '24.00', '450.0000');
        $this->approvisionner($this->biere, $this->magasin, '60.00', '440.0000');
        $this->approvisionner($this->riz, $this->magasin, '8.00', '22000.0000');
        $this->sortir($this->biere, $this->bar, '7.50');
        $this->perdre($this->riz, $this->magasin, '1.25');

        $service = app(StockTheoriqueService::class);
        Sanctum::actingAs($this->magasinier());

        // Portée « tous points »
        foreach ($this->getJson('/api/v1/stocks/articles')->assertOk()->json('data') as $ligne) {
            $this->assertSame(
                $service->stockTousPoints($ligne['id']),
                $ligne['stock'],
                "Divergence tous points sur l'article {$ligne['id']}",
            );
        }

        // Portée « un point »
        foreach ([$this->bar, $this->magasin] as $point) {
            $data = $this->getJson('/api/v1/stocks/articles?point_id=' . $point->id)->assertOk()->json('data');

            foreach ($data as $ligne) {
                $this->assertSame(
                    $service->stock($ligne['id'], $point->id),
                    $ligne['stock'],
                    "Divergence au point {$point->libelle} sur l'article {$ligne['id']}",
                );
                $this->assertSame('point', $ligne['portee']);
                $this->assertSame($point->id, $ligne['point_id']);
            }
        }
    }

    #[Test]
    public function la_liste_se_filtre_par_recherche_categorie_point_et_etat(): void
    {
        $this->approvisionner($this->biere, $this->bar, '24.00', '450.0000');
        Sanctum::actingAs($this->magasinier());

        $this->getJson('/api/v1/stocks/articles?recherche=Béninoise')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $this->biere->id);

        $this->getJson('/api/v1/stocks/articles?categorie=denree')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $this->riz->id);

        // Sous seuil / rupture : le riz n'a aucun mouvement, la bière en a 24.
        $this->getJson('/api/v1/stocks/articles?etat=rupture')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $this->riz->id);

        // Au BAR, la bière est à 24 ; au MAGASIN elle est à 0, donc sous seuil.
        // C'est tout l'intérêt de raisonner par couple (article, point).
        $this->getJson('/api/v1/stocks/articles?point_id=' . $this->magasin->id . '&etat=sous_seuil')
            ->assertOk()
            ->assertJsonCount(2, 'data');
    }

    /**
     * Un filtre incompris doit se REFUSER, pas se taire : ignoré, il rendrait
     * le référentiel entier sous un intitulé qui promet « En rupture »
     * (même famille que PA-119).
     */
    #[Test]
    public function un_filtre_inconnu_est_refuse_et_non_ignore(): void
    {
        Sanctum::actingAs($this->magasinier());

        $this->getJson('/api/v1/stocks/articles?etat=presque_vide')
            ->assertStatus(422)
            ->assertJsonValidationErrors('etat');

        $this->getJson('/api/v1/stocks/articles?point_id=' . Str::uuid())
            ->assertStatus(422)
            ->assertJsonValidationErrors('point_id');
    }

    /**
     * La pagination est déterministe : deux articles homonymes ne doivent ni
     * disparaître ni apparaître deux fois entre deux pages.
     */
    #[Test]
    public function la_pagination_est_stable_sur_des_libelles_identiques(): void
    {
        for ($i = 0; $i < 6; $i++) {
            Article::create([
                'libelle' => 'Article homonyme',
                'categorie' => 'divers',
                'unite_mesure' => 'unite',
                'seuil_alerte' => '0.00',
                'cout_moyen_pondere' => '0.0000',
            ]);
        }

        Sanctum::actingAs($this->magasinier());

        $vus = [];

        foreach ([1, 2, 3, 4] as $page) {
            foreach ($this->getJson("/api/v1/stocks/articles?par_page=2&page={$page}")->assertOk()->json('data') as $l) {
                $vus[] = $l['id'];
            }
        }

        $this->assertSame(8, count($vus), 'Une ligne a été perdue ou dupliquée entre deux pages.');
        $this->assertSame(count($vus), count(array_unique($vus)));
    }

    #[Test]
    public function la_taille_de_page_est_bornee(): void
    {
        Sanctum::actingAs($this->magasinier());

        $this->getJson('/api/v1/stocks/articles?par_page=' . (ConsultationStockService::PAR_PAGE_MAX + 1))
            ->assertStatus(422)
            ->assertJsonValidationErrors('par_page');
    }

    // ---------------------------------------------- Points et ventilation

    /**
     * Le référentiel des points descend ENTIER, sans enveloppe de pagination :
     * un point resté sur une page non demandée n'apparaîtrait pas au sélecteur
     * et le mouvement serait imputé ailleurs.
     */
    #[Test]
    public function les_points_de_stockage_descendent_entiers_et_non_pagines(): void
    {
        Sanctum::actingAs($this->magasinier());

        $reponse = $this->getJson('/api/v1/stocks/points')->assertOk();

        $reponse->assertJsonCount(2, 'data');
        $this->assertNull($reponse->json('meta'), 'Le référentiel des points ne doit pas être paginé.');
        $this->assertSame(
            ['Bar', 'Magasin général'],
            array_column($reponse->json('data'), 'libelle'),
        );
        // Le type descend tel quel : c'est lui que le bar interroge.
        $this->assertSame('bar', $reponse->json('data.0.type'));
    }

    #[Test]
    public function la_fiche_article_ventile_le_stock_point_par_point(): void
    {
        $this->approvisionner($this->biere, $this->bar, '24.00', '450.0000');
        $this->approvisionner($this->biere, $this->magasin, '60.00', '450.0000');
        $this->sortir($this->biere, $this->bar, '4.00');

        Sanctum::actingAs($this->magasinier());

        $reponse = $this->getJson("/api/v1/stocks/articles/{$this->biere->id}")->assertOk();

        $this->assertSame('80.00', $reponse->json('data.stock_total'));
        $this->assertTrue($reponse->json('data.stock_lecture_seule'));

        $ventilation = collect((array) $reponse->json('data.ventilation'))->keyBy('point_libelle');
        $this->assertSame('20.00', $ventilation['Bar']['stock']);
        $this->assertSame('60.00', $ventilation['Magasin général']['stock']);
    }

    /**
     * Un point sans mouvement est rendu à zéro, JAMAIS omis : l'omettre
     * laisserait croire que l'article ne peut pas y être stocké.
     */
    #[Test]
    public function un_point_sans_mouvement_apparait_a_zero_et_n_est_pas_omis(): void
    {
        $this->approvisionner($this->riz, $this->magasin, '8.00', '22000.0000');
        Sanctum::actingAs($this->magasinier());

        $ventilation = $this->getJson("/api/v1/stocks/articles/{$this->riz->id}")
            ->assertOk()
            ->json('data.ventilation');

        $this->assertCount(2, $ventilation);
        $this->assertSame('0.00', collect((array) $ventilation)->firstWhere('point_libelle', 'Bar')['stock']);
    }

    // ------------------------------------------------------- État consolidé

    #[Test]
    public function l_etat_consolide_rend_ses_kpi_et_dit_son_filtre(): void
    {
        $this->approvisionner($this->biere, $this->bar, '24.00', '450.0000');
        Sanctum::actingAs($this->magasinier());

        $reponse = $this->getJson('/api/v1/stocks/etat')->assertOk();

        $reponse->assertJsonPath('data.kpis.references', 2)
            // Le riz est à 0 pour un seuil de 5 : sous seuil ET en rupture.
            ->assertJsonPath('data.kpis.sous_seuil', 1)
            ->assertJsonPath('data.kpis.rupture', 1)
            ->assertJsonPath('data.kpis.valeur_stock', '10800.00')
            ->assertJsonPath('data.kpis.mouvements_30_jours', 1);

        // Sans filtre, l'état le dit : l'objet est vide, pas absent.
        $this->assertSame([], (array) $reponse->json('data.filtres_appliques'));
        $this->assertNotNull($reponse->json('data.arrete_au'));

        $filtre = $this->getJson('/api/v1/stocks/etat?point_id=' . $this->bar->id . '&sous_seuil=1')
            ->assertOk();

        $filtre->assertJsonPath('data.filtres_appliques.point', 'Bar')
            ->assertJsonPath('data.filtres_appliques.sous_seuil', 'oui');

        // Au bar, le riz est à 0 : c'est la seule ligne sous seuil.
        $filtre->assertJsonCount(1, 'data.lignes')
            ->assertJsonPath('data.lignes.0.id', $this->riz->id);
    }

    /**
     * L'état JSON et l'état PDF/CSV (`EtatStocks`, RG-19) portent le même titre
     * et doivent porter les mêmes chiffres. Les laisser diverger produirait
     * deux vérités sur le même écran et le même papier (PA-121).
     */
    #[Test]
    public function l_etat_json_et_l_etat_imprime_annoncent_les_memes_chiffres(): void
    {
        $this->approvisionner($this->biere, $this->bar, '24.00', '450.0000');
        $this->approvisionner($this->riz, $this->magasin, '3.00', '22000.0000');
        $this->sortir($this->biere, $this->bar, '20.00');

        Sanctum::actingAs($this->magasinier());

        foreach ([[], ['point_id' => $this->bar->id], ['sous_seuil' => true]] as $filtres) {
            $imprime = app(EtatStocks::class)->calculer(array_map(
                // `sous_seuil` arrive en booleen, les identifiants en chaine :
                // l'etat, lui, ne lit que des chaines.
                // `sous_seuil` arrive en booleen — toujours `true` dans ces
                // jeux —, les identifiants en chaine ; l'etat ne lit que des
                // chaines. Ecrire une branche pour un `false` qui n'arrive
                // jamais donnerait un chemin qu'aucun test n'emprunte.
                static fn (mixed $v): string => is_bool($v) ? '1' : (string) $v,
                $filtres,
            ));

            $json = $this->getJson('/api/v1/stocks/etat?' . http_build_query($filtres))->assertOk();

            $contexte = 'Filtres : ' . json_encode($filtres);

            $this->assertSame(
                (int) $imprime->kpis[__('stocks.etat.kpi_references')],
                $json->json('data.kpis.references'),
                "Nombre de références divergent entre l'écran et le papier. {$contexte}",
            );
            $this->assertSame(
                (int) $imprime->kpis[__('stocks.etat.kpi_critiques')],
                $json->json('data.kpis.sous_seuil'),
                "Compteur d'alerte divergent entre l'écran et le papier. {$contexte}",
            );
            $this->assertSame(
                $imprime->kpis[__('stocks.etat.kpi_valeur')],
                $json->json('data.kpis.valeur_stock'),
                "Valorisation divergente entre l'écran et le papier. {$contexte}",
            );
        }
    }

    // -------------------------------------------------- Journal des mouvements

    #[Test]
    public function le_journal_des_mouvements_dit_qui_quoi_quand_pourquoi(): void
    {
        $magasinier = $this->magasinier();
        Sanctum::actingAs($magasinier);

        $this->postJson('/api/v1/stocks/mouvements', [
            'article_id' => $this->biere->id,
            'point_id' => $this->bar->id,
            'type_mouvement' => 'entree',
            'quantite' => '24',
            'motif' => 'Réception SODIS Bénin',
            'cout_unitaire' => '450',
        ])->assertCreated();

        $ligne = $this->getJson('/api/v1/stocks/mouvements')->assertOk()->json('data.0');

        $this->assertSame($this->biere->id, $ligne['article_id']);
        $this->assertSame($this->bar->id, $ligne['point_id']);
        $this->assertSame('entree', $ligne['type_mouvement']);
        $this->assertSame('entree', $ligne['sens']);
        $this->assertSame('24.00', $ligne['quantite']);
        $this->assertSame('Réception SODIS Bénin', $ligne['motif']);
        // EF-M6-06 : l'auteur est l'appelant, jamais un utilisateur technique.
        $this->assertSame($magasinier->id, $ligne['utilisateur_id']);
        $this->assertSame($magasinier->login, $ligne['utilisateur']['login']);
        $this->assertSame('Bière La Béninoise 65cl', $ligne['article']['libelle']);
    }

    /**
     * Le SENS est dérivé du type : une sortie retranche, quelle que soit la
     * façon dont la quantité est stockée (toujours positive au schéma).
     */
    #[Test]
    public function le_sens_d_un_mouvement_suit_la_convention_de_signe_du_service(): void
    {
        $this->approvisionner($this->biere, $this->bar, '24.00', '450.0000');
        $this->sortir($this->biere, $this->bar, '4.00');
        $this->perdre($this->biere, $this->bar, '1.00');

        Sanctum::actingAs($this->magasinier());

        $sens = collect((array) $this->getJson('/api/v1/stocks/mouvements')->assertOk()->json('data'))
            ->pluck('sens', 'type_mouvement')
            ->all();

        $this->assertSame(
            ['perte' => 'sortie', 'sortie' => 'sortie', 'entree' => 'entree'],
            $sens,
        );
    }

    #[Test]
    public function le_journal_se_filtre_par_article_point_type_et_periode(): void
    {
        $this->approvisionner($this->biere, $this->bar, '24.00', '450.0000');
        $this->approvisionner($this->riz, $this->magasin, '8.00', '22000.0000');
        $this->sortir($this->biere, $this->bar, '4.00');

        Sanctum::actingAs($this->magasinier());

        $this->getJson('/api/v1/stocks/mouvements?article_id=' . $this->riz->id)
            ->assertOk()->assertJsonCount(1, 'data');

        $this->getJson('/api/v1/stocks/mouvements?point_id=' . $this->bar->id)
            ->assertOk()->assertJsonCount(2, 'data');

        $this->getJson('/api/v1/stocks/mouvements?type_mouvement=sortie')
            ->assertOk()->assertJsonCount(1, 'data');

        $this->getJson('/api/v1/stocks/mouvements?date_debut=' . now()->addDay()->toDateString())
            ->assertOk()->assertJsonCount(0, 'data');

        // Le type `inventaire` est consultable même s'il n'est pas saisissable.
        $this->getJson('/api/v1/stocks/mouvements?type_mouvement=inventaire')
            ->assertOk()->assertJsonCount(0, 'data');

        $this->getJson('/api/v1/stocks/mouvements?type_mouvement=transfert')
            ->assertStatus(422)->assertJsonValidationErrors('type_mouvement');
    }

    // -------------------------------------------------- Écriture d'un mouvement

    #[Test]
    public function une_entree_valorisee_recalcule_le_cout_moyen_pondere(): void
    {
        Sanctum::actingAs($this->magasinier());

        // 10 sacs à 20 000, puis 10 à 24 000 → CMP = 22 000.
        foreach ([['10', '20000'], ['10', '24000']] as [$quantite, $cout]) {
            $this->postJson('/api/v1/stocks/mouvements', [
                'article_id' => $this->riz->id,
                'point_id' => $this->magasin->id,
                'type_mouvement' => 'entree',
                'quantite' => $quantite,
                'motif' => 'Réception fournisseur',
                'cout_unitaire' => $cout,
            ])->assertCreated();
        }

        $this->riz->refresh();

        // `bccomp`, jamais une égalité flottante (règle projet).
        $this->assertSame(0, bccomp((string) $this->riz->cout_moyen_pondere, '22000.0000', 4));

        $this->getJson("/api/v1/stocks/articles/{$this->riz->id}")
            ->assertOk()
            ->assertJsonPath('data.stock_total', '20.00')
            ->assertJsonPath('data.valeur_totale', '440000.00');
    }

    /**
     * Un transfert entre points ne revalorise RIEN : déplacer une marchandise
     * ne change pas son coût d'acquisition.
     */
    #[Test]
    public function une_entree_sans_cout_ne_touche_pas_au_cout_moyen_pondere(): void
    {
        Sanctum::actingAs($this->magasinier());

        $this->postJson('/api/v1/stocks/mouvements', [
            'article_id' => $this->biere->id,
            'point_id' => $this->bar->id,
            'type_mouvement' => 'entree',
            'quantite' => '12',
            'motif' => 'Transfert magasin vers bar',
            'cout_unitaire' => null,
        ])->assertCreated();

        $this->assertSame(0, bccomp((string) $this->biere->refresh()->cout_moyen_pondere, '450.0000', 4));
    }

    /**
     * RG-06 — une sortie au-delà du disponible rend 422 avec le drapeau que le
     * client traduit en demande de confirmation, jamais un 500. Et surtout :
     * AUCUN mouvement n'est écrit.
     */
    #[Test]
    public function rg06_une_sortie_au_dela_du_disponible_demande_une_confirmation(): void
    {
        $this->approvisionner($this->biere, $this->bar, '3.00', '450.0000');
        Sanctum::actingAs($this->magasinier());

        $this->postJson('/api/v1/stocks/mouvements', [
            'article_id' => $this->biere->id,
            'point_id' => $this->bar->id,
            'type_mouvement' => 'sortie',
            'quantite' => '10',
            'motif' => 'Service en salle',
        ])
            ->assertStatus(422)
            ->assertJsonPath('necessite_validation_rupture', true)
            ->assertJsonPath('stock_disponible', '3.00')
            ->assertJsonPath('quantite_demandee', '10');

        $this->assertSame(1, MouvementStock::count(), 'Le refus a laissé un mouvement derrière lui.');
    }

    /**
     * RG-06 — la rupture assumée passe, et laisse une trace NOMINATIVE : une
     * rupture forcée est une décision de gestion, elle doit être imputable.
     */
    #[Test]
    public function rg06_une_rupture_validee_passe_et_laisse_une_trace_d_audit(): void
    {
        $this->approvisionner($this->biere, $this->bar, '3.00', '450.0000');
        $magasinier = $this->magasinier();
        Sanctum::actingAs($magasinier);

        $this->postJson('/api/v1/stocks/mouvements', [
            'article_id' => $this->biere->id,
            'point_id' => $this->bar->id,
            'type_mouvement' => 'sortie',
            'quantite' => '10',
            'motif' => 'Service en salle',
            'validation_rupture' => true,
        ])->assertCreated();

        $this->assertSame('-7.00', app(StockTheoriqueService::class)->stock($this->biere->id, $this->bar->id));

        $trace = JournalAudit::where('action', 'rupture_stock_forcee')->firstOrFail();
        $this->assertSame($magasinier->id, $trace->utilisateur_id);
    }

    // ------------------------------------- PA-24 : les valeurs calculées

    /**
     * PA-24 — aucun champ de stock n'est accepté en entrée. Refusé, pas
     * ignoré : un champ ignoré laisse le client croire qu'il a compté, et
     * l'écart ne se voit qu'à l'inventaire suivant.
     */
    #[Test]
    public function pa24_aucun_stock_calcule_n_est_accepte_sur_un_mouvement(): void
    {
        Sanctum::actingAs($this->magasinier());

        foreach (['stock', 'stock_disponible', 'quantite_stock', 'cout_moyen_pondere', 'valeur_stock'] as $champ) {
            $this->postJson('/api/v1/stocks/mouvements', $this->mouvementValide([$champ => '999']))
                ->assertStatus(422)
                ->assertJsonValidationErrors($champ);
        }

        $this->assertSame(0, MouvementStock::count());
    }

    /**
     * PA-24 — même refus sur le référentiel : ni stock d'ouverture, ni coût
     * moyen pondéré. Le premier est un mouvement, le second un calcul.
     */
    #[Test]
    public function pa24_aucun_stock_ni_cmp_n_est_accepte_sur_un_article(): void
    {
        Sanctum::actingAs($this->magasinier());

        foreach (['stock', 'stock_initial', 'stock_disponible', 'quantite_stock', 'cout_moyen_pondere'] as $champ) {
            $this->postJson('/api/v1/stocks/articles', $this->articleValide([$champ => '42']))
                ->assertStatus(422)
                ->assertJsonValidationErrors($champ);
        }

        $this->assertSame(2, Article::count());
    }

    /**
     * Un article créé par l'API naît SANS stock : la seule façon d'en poser est
     * un mouvement daté, motivé et imputable.
     */
    #[Test]
    public function un_article_cree_par_l_api_nait_sans_stock(): void
    {
        Sanctum::actingAs($this->magasinier());

        $reponse = $this->postJson('/api/v1/stocks/articles', $this->articleValide())->assertCreated();

        $reponse->assertJsonPath('data.stock_total', '0.00')
            ->assertJsonPath('data.cout_moyen_pondere', '0.0000');

        $this->assertSame(0, MouvementStock::where('article_id', $reponse->json('data.id'))->count());
    }

    #[Test]
    public function l_uuid_genere_cote_client_est_conserve_sur_un_article(): void
    {
        Sanctum::actingAs($this->magasinier());
        $uuid = (string) Str::uuid();

        $this->postJson('/api/v1/stocks/articles', $this->articleValide(['id' => $uuid]))
            ->assertCreated()
            ->assertJsonPath('data.id', $uuid);

        // Un second POST sur le même identifiant est une anomalie qui se voit,
        // jamais une mise à jour déguisée.
        $this->postJson('/api/v1/stocks/articles', $this->articleValide(['id' => $uuid]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('id');
    }

    // ------------------------------------------------- Refus de saisie divers

    /**
     * `inventaire` n'est pas saisissable : un écart naît d'un comptage clôturé.
     * L'ouvrir permettrait de réécrire n'importe quel solde sans comptage.
     */
    #[Test]
    public function un_ecart_d_inventaire_ne_se_saisit_pas_par_l_api_des_mouvements(): void
    {
        Sanctum::actingAs($this->magasinier());

        $this->postJson('/api/v1/stocks/mouvements', $this->mouvementValide(['type_mouvement' => 'inventaire']))
            ->assertStatus(422)
            ->assertJsonValidationErrors('type_mouvement');

        $this->assertSame(0, MouvementStock::count());
    }

    /**
     * Une quantité saisie à zéro n'est pas un mouvement — même piège que celui
     * évité côté panier : « absente » et « zéro » ne se confondent pas.
     */
    #[Test]
    public function une_quantite_nulle_ou_negative_est_refusee(): void
    {
        Sanctum::actingAs($this->magasinier());

        foreach (['0', '-3', '0.00'] as $quantite) {
            $this->postJson('/api/v1/stocks/mouvements', $this->mouvementValide(['quantite' => $quantite]))
                ->assertStatus(422)
                ->assertJsonValidationErrors('quantite');
        }
    }

    /**
     * EF-M6-06 — pas de mouvement sans motif : l'historique serait inopposable.
     */
    #[Test]
    public function un_mouvement_sans_motif_est_refuse(): void
    {
        Sanctum::actingAs($this->magasinier());

        $sansMotif = $this->mouvementValide();
        unset($sansMotif['motif']);

        $this->postJson('/api/v1/stocks/mouvements', $sansMotif)
            ->assertStatus(422)
            ->assertJsonValidationErrors('motif');
    }

    /**
     * Un coût unitaire sur une sortie n'aurait aucun effet — les sorties ne
     * modifient pas le CMP. Le laisser passer laisserait croire l'inverse.
     */
    #[Test]
    public function un_cout_unitaire_sur_une_sortie_est_refuse(): void
    {
        Sanctum::actingAs($this->magasinier());

        $this->postJson('/api/v1/stocks/mouvements', $this->mouvementValide([
            'type_mouvement' => 'sortie',
            'cout_unitaire' => '450',
        ]))->assertStatus(422)->assertJsonValidationErrors('cout_unitaire');
    }

    /**
     * L'identifiant client est refusé, et le message dit pourquoi : aucun
     * mécanisme de rejeu n'existe sur cette table, et l'accepter laisserait
     * croire à une idempotence qui n'a pas lieu (PA-59/60/61).
     */
    #[Test]
    public function un_mouvement_ne_recoit_pas_d_identifiant_du_client(): void
    {
        Sanctum::actingAs($this->magasinier());

        $this->postJson('/api/v1/stocks/mouvements', $this->mouvementValide(['id' => (string) Str::uuid()]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('id');
    }

    #[Test]
    public function une_cle_etrangere_inconnue_est_refusee(): void
    {
        Sanctum::actingAs($this->magasinier());

        $this->postJson('/api/v1/stocks/mouvements', $this->mouvementValide(['article_id' => (string) Str::uuid()]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('article_id');

        $this->postJson('/api/v1/stocks/mouvements', $this->mouvementValide(['point_id' => (string) Str::uuid()]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('point_id');
    }

    /**
     * Aucun message de validation ne doit fuir sa clé de traduction : le client
     * Flutter afficherait « stocks.validation.type_inconnu » à l'écran.
     */
    #[Test]
    public function les_refus_sont_rediges_en_francais_et_non_en_cles(): void
    {
        Sanctum::actingAs($this->magasinier());

        $erreurs = $this->postJson('/api/v1/stocks/mouvements', [])
            ->assertStatus(422)
            ->json('errors');

        $this->assertNotSame([], $erreurs);

        foreach ($erreurs as $champ => $messages) {
            foreach ($messages as $message) {
                $this->assertStringNotContainsString('validation.', $message, "Champ {$champ}");
                $this->assertStringNotContainsString('stocks.', $message, "Champ {$champ}");
            }
        }
    }

    // ------------------------------------------------ Aucune suppression

    /**
     * `mouvements_stock` est en ajout seul. Aucun verbe destructeur n'est
     * routé — c'est la seule preuve solide qu'il n'existe pas — et la Policy le
     * refuse en second niveau.
     */
    #[Test]
    public function aucune_suppression_ni_modification_de_mouvement_n_est_exposee(): void
    {
        $this->approvisionner($this->biere, $this->bar, '24.00', '450.0000');
        $mouvement = MouvementStock::firstOrFail();

        Sanctum::actingAs($this->magasinier());

        // 404 et non 405 : aucune URL `/mouvements/{id}` n'est routée, quel que
        // soit le verbe. C'est la preuve la plus forte — il n'y a pas de
        // ressource individuelle à modifier, pas seulement un verbe fermé.
        $this->deleteJson("/api/v1/stocks/mouvements/{$mouvement->id}")->assertStatus(404);
        $this->putJson("/api/v1/stocks/mouvements/{$mouvement->id}", [])->assertStatus(404);
        $this->patchJson("/api/v1/stocks/mouvements/{$mouvement->id}", [])->assertStatus(404);

        // 405 ici : `/articles/{id}` existe bien en GET et en PUT, et le refus
        // porte donc sur le VERBE. Un article ne se supprime pas — des
        // mouvements le référencent, et la clé étrangère est `restrictOnDelete`.
        $this->deleteJson("/api/v1/stocks/articles/{$this->biere->id}")->assertStatus(405);

        $this->assertDatabaseHas('mouvements_stock', ['id' => $mouvement->id]);
    }

    /**
     * La Policy refuse la suppression et la modification d'un mouvement même à
     * l'Administrateur : sur ce projet la suppression est l'exception, et sur
     * une table transactionnelle elle n'existe pas.
     */
    #[Test]
    public function la_policy_refuse_la_suppression_d_un_mouvement_a_tous_les_roles(): void
    {
        $policy = new MouvementStockPolicy();

        foreach (array_keys(RolePermissionSeeder::MATRICE) as $role) {
            $utilisateur = $this->utilisateur($role);

            $this->assertFalse($policy->delete($utilisateur), "Le rôle {$role} peut supprimer un mouvement.");
            $this->assertFalse($policy->update($utilisateur), "Le rôle {$role} peut modifier un mouvement.");
        }
    }

    // --------------------------------------------------------- Fiche de stock

    /**
     * EF-M6-04 — la fiche justifie un solde, et VÉRIFIE son égalité. Le
     * drapeau `coherent` est remonté tel quel : un document de justification
     * qui tairait son propre doute vaudrait moins que pas de document.
     */
    #[Test]
    public function la_fiche_de_stock_justifie_le_solde_et_porte_son_drapeau_de_coherence(): void
    {
        $this->approvisionner($this->riz, $this->magasin, '10.00', '22000.0000');
        $this->sortir($this->riz, $this->magasin, '3.00');
        $this->perdre($this->riz, $this->magasin, '1.00');

        Sanctum::actingAs($this->magasinier());

        $jour = now()->toDateString();
        $reponse = $this->getJson("/api/v1/stocks/articles/{$this->riz->id}/fiche?debut={$jour}&fin={$jour}")
            ->assertOk();

        $reponse->assertJsonPath('data.stock_initial', '0.00')
            ->assertJsonPath('data.entrees', '10.00')
            ->assertJsonPath('data.sorties', '3.00')
            ->assertJsonPath('data.pertes', '1.00')
            ->assertJsonPath('data.stock_theorique', '6.00')
            ->assertJsonPath('data.coherent', true)
            ->assertJsonCount(3, 'data.lignes');

        // Le filtre de portée est remonté : une fiche restreinte à un point qui
        // ne le dirait pas serait lue comme la fiche complète de l'article.
        $this->assertNull($reponse->json('data.point_id'));

        $restreinte = $this->getJson(
            "/api/v1/stocks/articles/{$this->riz->id}/fiche?debut={$jour}&fin={$jour}&point_id={$this->bar->id}",
        )->assertOk();

        $restreinte->assertJsonPath('data.point_id', $this->bar->id)
            ->assertJsonPath('data.stock_theorique', '0.00')
            ->assertJsonCount(0, 'data.lignes');
    }

    /**
     * Une fiche sans période serait un document dont personne ne saurait dire
     * ce qu'il couvre, alors que son objet est de justifier un solde.
     */
    #[Test]
    public function une_fiche_sans_periode_est_refusee(): void
    {
        Sanctum::actingAs($this->magasinier());

        $this->getJson("/api/v1/stocks/articles/{$this->riz->id}/fiche")
            ->assertStatus(422)
            ->assertJsonValidationErrors(['debut', 'fin']);

        $this->getJson("/api/v1/stocks/articles/{$this->riz->id}/fiche?debut=2026-08-31&fin=2026-08-01")
            ->assertStatus(422)
            ->assertJsonValidationErrors('fin');
    }

    // ----------------------------------------------------------------- Outils

    /**
     * Le rôle est DÉRIVÉ de la matrice RBAC, jamais écrit en dur : la matrice
     * est la source de vérité unique, et un test qui la recopierait resterait
     * vert le jour où elle changerait.
     */
    private function roleAvecNiveauM6(string $niveau): string
    {
        foreach (RolePermissionSeeder::MATRICE as $role => $droits) {
            if ($droits['M6'] === $niveau) {
                return $role;
            }
        }

        $this->fail("Aucun rôle de la matrice ne porte M6 = '{$niveau}'.");
    }

    private function magasinier(): User
    {
        return $this->utilisateur($this->roleAvecNiveauM6('C'));
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(8),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function mouvementValide(array $surcharges = []): array
    {
        return array_merge([
            'article_id' => $this->biere->id,
            'point_id' => $this->bar->id,
            'type_mouvement' => 'entree',
            'quantite' => '6',
            'motif' => 'Réception fournisseur',
        ], $surcharges);
    }

    /**
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function articleValide(array $surcharges = []): array
    {
        return array_merge([
            'libelle' => 'Huile de palme 20L',
            'categorie' => 'denree',
            'unite_mesure' => 'bidon',
            'seuil_alerte' => '4.00',
            'seuil_reappro' => '10.00',
        ], $surcharges);
    }

    /**
     * Les fixtures passent par le SERVICE, jamais par un `create()` direct :
     * une insertion directe contournerait le contrôle de disponibilité, le
     * verrou et la vérification de seuil — et le test validerait alors un état
     * que l'application ne peut pas produire.
     */
    private function approvisionner(Article $article, PointStockage $point, string $quantite, string $cout): void
    {
        $this->actingAs($this->magasinier());

        app(\App\Domain\Stocks\Services\MouvementStockService::class)
            ->entree($article->id, $point->id, $quantite, 'Fixture de test', $cout);
    }

    private function sortir(Article $article, PointStockage $point, string $quantite): void
    {
        $this->actingAs($this->magasinier());

        app(\App\Domain\Stocks\Services\MouvementStockService::class)
            ->sortie($article->id, $point->id, $quantite, 'Fixture de test');
    }

    private function perdre(Article $article, PointStockage $point, string $quantite): void
    {
        $this->actingAs($this->magasinier());

        app(\App\Domain\Stocks\Services\MouvementStockService::class)
            ->perte($article->id, $point->id, $quantite, 'Fixture de test');
    }
}
