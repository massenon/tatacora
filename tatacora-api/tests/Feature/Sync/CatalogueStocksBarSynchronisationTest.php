<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Models\User;
use App\Shared\Sync\Models\CorrespondanceSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Catalogue M6/M5 créé hors connexion — lot S2 (décision du Product Owner du
 * 15/10/2026) : points de stockage, articles, boissons de la carte du bar.
 *
 * Le serveur est maître ; un poste peut créer, et un équivalent serveur (clé
 * naturelle) est FUSIONNÉ — aucun doublon, rien d'écrasé, correspondance
 * retenue. Les références citées passent par les correspondances.
 */
final class CatalogueStocksBarSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $magasinier;

    private User $barman;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        // `magasinier` : M6 = C, M5 = L. `barman` : M5 = C, M6 = C.
        $this->magasinier = $this->creerUtilisateur('magasinier');
        $this->barman = $this->creerUtilisateur('barman');
    }

    // ------------------------------------------------------- Points de stockage

    #[Test]
    public function un_point_cree_hors_connexion_est_cree_sous_l_uuid_du_poste_par_le_service(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->creation('points_stockage', $id, ['libelle' => 'Cave', 'type' => 'magasin'])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $id)
            ->assertJsonMissingPath('resultats.0.fusionne_avec');

        $point = PointStockage::findOrFail($id);
        $this->assertSame('magasin', $point->type);
        // Par Eloquent : l'audit RG-15 est tenu.
        $this->assertSame($this->magasinier->id, $point->utilisateur_creation_id);
        $this->assertDatabaseHas('journal_audit', ['entite_concernee' => 'points_stockage', 'entite_id' => $id]);
    }

    #[Test]
    public function un_point_homonyme_est_fusionne_sans_ecraser_son_type(): void
    {
        $serveur = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        $idPoste = $this->uuid();

        $this->pousser([$this->creation('points_stockage', $idPoste, ['libelle' => '  MAGASIN  general ', 'type' => 'bar'])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $serveur->id)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id);

        $this->assertSame(1, PointStockage::count());
        $this->assertSame('magasin', $serveur->fresh()->type);
        $this->assertDatabaseHas('correspondances_synchronisation', [
            'poste_id' => 'poste-windows-1', 'table_concernee' => 'points_stockage',
            'id_poste' => $idPoste, 'id_serveur' => $serveur->id,
        ]);
    }

    #[Test]
    public function un_type_de_point_hors_registre_est_rejete_avec_sa_phrase(): void
    {
        $this->pousser([$this->creation('points_stockage', $this->uuid(), ['libelle' => 'Cuisines', 'type' => 'cuisines'])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('stocks.validation.point_type_inconnu'));

        $this->assertSame(0, PointStockage::count());
    }

    // ---------------------------------------------------------------- Articles

    /**
     * Le lot type d'un poste isolé : un point, un article qui le cite, une
     * boisson qui cite l'article — tout sous les UUID du poste, dans l'ordre.
     */
    #[Test]
    public function point_article_et_boisson_crees_dans_le_meme_lot_se_citent_par_leurs_uuid(): void
    {
        [$point, $article, $boisson] = [$this->uuid(), $this->uuid(), $this->uuid()];

        $this->pousser([
            $this->creation('points_stockage', $point, ['libelle' => 'Bar piscine', 'type' => 'bar']),
            $this->creation('articles', $article, $this->article('Béninoise 33cl', 'bouteille', ['point_stockage_id' => $point])),
            $this->creation('cartes_boisson', $boisson, [
                'libelle' => 'Béninoise 33 cl', 'article_id' => $article, 'categorie' => 'locale', 'prix_vente' => '700',
            ]),
        ], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.2.statut', 'synchronise');

        $this->assertSame($point, Article::findOrFail($article)->point_stockage_id);
        $this->assertSame($article, CarteBoisson::findOrFail($boisson)->article_id);
    }

    /**
     * Le point a été fusionné : l'article qui le cite sous l'UUID du poste est
     * rattaché au point SERVEUR — sinon la règle `exists` le rejetterait pour
     * « point inconnu », alors que l'utilisateur l'a saisi.
     */
    #[Test]
    public function un_article_citant_un_point_fusionne_est_rattache_au_point_serveur(): void
    {
        $serveur = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);
        [$pointPoste, $article] = [$this->uuid(), $this->uuid()];

        $this->pousser([
            $this->creation('points_stockage', $pointPoste, ['libelle' => 'cuisine']),
            $this->creation('articles', $article, $this->article('Tomate', 'kg', ['point_stockage_id' => $pointPoste])),
        ], $this->magasinier)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id)
            ->assertJsonPath('resultats.1.statut', 'synchronise');

        $this->assertSame($serveur->id, Article::findOrFail($article)->point_stockage_id);
    }

    /**
     * Clé naturelle = libellé ET unité : « Riz » au kilo et « Riz » au sac sont
     * deux articles — les fondre ferait compter des kilos et des sacs dans la
     * même colonne.
     */
    #[Test]
    public function un_article_fusionne_sur_libelle_et_unite_jamais_sur_le_libelle_seul(): void
    {
        $serveur = $this->articleServeur('Riz parfumé', 'kg', seuil: '5.00');
        [$memeUnite, $autreUnite] = [$this->uuid(), $this->uuid()];

        $this->pousser([
            $this->creation('articles', $memeUnite, $this->article('RIZ PARFUME', ' KG ', ['seuil_alerte' => '99'])),
            $this->creation('articles', $autreUnite, $this->article('Riz parfumé', 'sac 50 kg')),
        ], $this->magasinier)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id)
            ->assertJsonPath('resultats.1.entite_id', $autreUnite)
            ->assertJsonMissingPath('resultats.1.fusionne_avec');

        $this->assertSame(2, Article::count());
        // Le serveur est maître : le seuil du poste n'a rien écrasé.
        $this->assertSame('5.00', (string) $serveur->fresh()->seuil_alerte);
    }

    #[Test]
    public function une_fusion_sur_un_article_archive_avertit_le_poste(): void
    {
        $serveur = $this->articleServeur('Sucre', 'kg');
        app(ReferentielArticleService::class)->archiver($serveur);

        $this->pousser([$this->creation('articles', $this->uuid(), $this->article('sucre', 'kg'))], $this->magasinier)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id)
            ->assertJsonPath('resultats.0.cible_archivee', true);

        $this->assertSame(1, Article::count());
        $this->assertFalse((bool) $serveur->fresh()->actif);
    }

    /**
     * PA-24 : le stock d'ouverture saisi sur le poste remonte comme un
     * MOUVEMENT, jamais comme une colonne — mêmes règles et phrases que l'API.
     */
    #[Test]
    public function un_article_portant_une_valeur_calculee_est_rejete_avec_la_phrase_de_l_api(): void
    {
        $this->pousser([$this->creation('articles', $this->uuid(), $this->article('Farine', 'kg', ['stock_initial' => '40']))], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('stocks.validation.valeur_calculee'))
            ->assertJsonPath('resultats.0.erreurs.stock_initial.0', __('stocks.validation.valeur_calculee'));

        $this->assertSame(0, Article::count());
    }

    /**
     * Remplace le test « modification refusée, le serveur est maître » (lot
     * S2) — décision PO du 15/10/2026 : la modification d'un article est
     * appliquée par le service, PARTIELLE (le libellé et l'unité ne bougent
     * pas), et les valeurs calculées restent refusées comme à l'API.
     */
    #[Test]
    public function une_modification_d_article_est_appliquee_par_le_service_valeurs_calculees_refusees(): void
    {
        $serveur = $this->articleServeur('Huile', 'litre', seuil: '3.00');

        $this->pousser([$this->operation('articles', 'modification', $serveur->id, ['seuil_alerte' => '0'])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $serveur->id);

        $fiche = $serveur->fresh();
        $this->assertSame(['0.00', 'Huile', 'litre'], [(string) $fiche->seuil_alerte, $fiche->libelle, $fiche->unite_mesure]);
        $this->assertSame($this->magasinier->id, $fiche->utilisateur_modification_id);

        $this->pousser([$this->operation('articles', 'modification', $serveur->id, ['seuil_alerte' => '9', 'cout_moyen_pondere' => '1'])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.erreurs.cout_moyen_pondere.0', __('stocks.validation.valeur_calculee'));

        $this->assertSame('0.00', (string) $serveur->fresh()->seuil_alerte);
    }

    #[Test]
    public function deux_postes_creant_le_meme_article_fusionnent_sur_le_meme_element_et_le_rejeu_est_idempotent(): void
    {
        [$idA, $idB] = [$this->uuid(), $this->uuid()];
        $operationB = $this->creation('articles', $idB, $this->article('Café moulu', 'kg'));

        $this->pousser([$this->creation('articles', $idA, $this->article('Cafe moulu', 'KG'))], $this->magasinier, 'poste-a')
            ->assertJsonPath('resultats.0.entite_id', $idA);

        $this->pousser([$operationB], $this->magasinier, 'poste-b')->assertJsonPath('resultats.0.fusionne_avec', $idA);
        $this->pousser([$operationB], $this->magasinier, 'poste-b')
            ->assertJsonPath('resultats.0.rejeu_idempotent', true)
            ->assertJsonPath('resultats.0.fusionne_avec', $idA);

        $this->assertSame([$idA], Article::pluck('id')->all());
        $this->assertSame(1, CorrespondanceSynchronisation::count());
    }

    // ------------------------------------------------------------------- RBAC

    /**
     * M6 en `C` est exigé pour points et articles, M5 en `C` pour la carte :
     * `receptionniste` (M6 = L) et `magasinier` sur la carte (M5 = L) sont
     * refusés, chaque refus tracé.
     */
    #[Test]
    public function sans_ecriture_sur_le_module_rien_n_est_cree_et_le_refus_est_trace(): void
    {
        $receptionniste = $this->creerUtilisateur('receptionniste');
        $article = $this->articleServeur('Coca 33cl', 'bouteille');

        $this->pousser([
            $this->creation('points_stockage', $this->uuid(), ['libelle' => 'Réserve']),
            $this->creation('articles', $this->uuid(), $this->article('Gaz', 'bouteille')),
        ], $receptionniste)
            ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'))
            ->assertJsonPath('resultats.1.motif', __('auth.module_refuse'));

        $this->pousser([$this->creation('cartes_boisson', $this->uuid(), [
            'libelle' => 'Coca', 'article_id' => $article->id, 'categorie' => 'importee', 'prix_vente' => '800',
        ])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'));

        $this->assertSame(0, PointStockage::count());
        $this->assertSame(1, Article::count());
        $this->assertSame(0, CarteBoisson::count());
        $this->assertDatabaseHas('journal_securite', ['utilisateur_id' => $receptionniste->id, 'module_concerne' => 'M6']);
        $this->assertDatabaseHas('journal_securite', ['utilisateur_id' => $this->magasinier->id, 'module_concerne' => 'M5']);
    }

    // ------------------------------------------------------------------ Carte du bar

    #[Test]
    public function une_boisson_homonyme_est_fusionnee_et_son_prix_serveur_reste(): void
    {
        $article = $this->articleServeur('Flag 65cl', 'bouteille');
        $serveur = CarteBoisson::create([
            'libelle' => 'Flag 65 cl', 'article_id' => $article->id, 'categorie' => 'locale', 'prix_vente' => '900',
        ]);
        $idPoste = $this->uuid();

        $this->pousser([$this->creation('cartes_boisson', $idPoste, [
            'libelle' => 'FLAG 65 CL', 'article_id' => $article->id, 'categorie' => 'locale', 'prix_vente' => '1000',
        ])], $this->barman)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id);

        $this->assertSame(1, CarteBoisson::count());
        $this->assertSame('900.00', (string) $serveur->fresh()->prix_vente);
    }

    #[Test]
    public function une_boisson_citant_un_article_jamais_synchronise_est_rejetee_avec_la_phrase_du_bar(): void
    {
        $this->pousser([$this->creation('cartes_boisson', $this->uuid(), [
            'libelle' => 'Youki', 'article_id' => $this->uuid(), 'categorie' => 'locale', 'prix_vente' => '500',
        ])], $this->barman)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('bar.validation.article_inexistant'));

        $this->assertSame(0, CarteBoisson::count());
    }

    /**
     * L'article a été fusionné lors d'un lot PRÉCÉDENT : la boisson créée
     * ensuite cite toujours l'UUID local, et pointe sur l'article serveur.
     */
    #[Test]
    public function une_boisson_citant_un_article_fusionne_hier_pointe_sur_l_article_serveur(): void
    {
        $serveur = $this->articleServeur('Eau minérale 1,5L', 'bouteille');
        $articlePoste = $this->uuid();

        $this->pousser([$this->creation('articles', $articlePoste, $this->article('Eau minerale 1,5l', 'Bouteille'))], $this->barman)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id);

        $boisson = $this->uuid();
        $this->pousser([$this->creation('cartes_boisson', $boisson, [
            'libelle' => 'Eau 1,5 L', 'article_id' => $articlePoste, 'categorie' => 'locale', 'prix_vente' => '600',
        ])], $this->barman)->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame($serveur->id, CarteBoisson::findOrFail($boisson)->article_id);
    }

    // ---------------------------------------------------------------- Helpers

    /**
     * @param  array<string, mixed>  $complements
     * @return array<string, mixed>
     */
    private function article(string $libelle, string $unite, array $complements = []): array
    {
        return [
            'libelle' => $libelle, 'categorie' => 'Épicerie', 'unite_mesure' => $unite, 'seuil_alerte' => '2',
            ...$complements,
        ];
    }

    private function articleServeur(string $libelle, string $unite, string $seuil = '1.00'): Article
    {
        return app(ReferentielArticleService::class)->creer([
            'libelle' => $libelle, 'categorie' => 'Épicerie', 'unite_mesure' => $unite, 'seuil_alerte' => $seuil,
        ]);
    }
}
