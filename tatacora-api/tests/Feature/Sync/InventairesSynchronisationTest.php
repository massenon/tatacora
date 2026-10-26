<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\Inventaire;
use App\Domain\Stocks\Models\LigneInventaire;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * L'inventaire physique CLÔTURÉ sur un poste (21/10/2026, « tout au complet »).
 *
 * Le poste pousse UN document (l'en-tête et ses lignes, dans une transaction),
 * puis la régularisation en mouvements saisis — l'excédent en `inventaire`, le
 * manquant en `perte`. Les valeurs du poste sont écrites telles quelles
 * (théorique figé au comptage), le rejeu ne double rien, et l'inventaire
 * redescend aux autres postes avec ses lignes.
 */
final class InventairesSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $magasinier;

    private PointStockage $magasin;

    private Article $riz;

    private Article $huile;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-21 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->magasinier = $this->creerUtilisateur('magasinier');
        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        $this->riz = Article::create([
            'libelle' => 'Riz parfumé 50kg', 'categorie' => 'denree', 'unite_mesure' => 'sac',
            'seuil_alerte' => '5.00', 'seuil_reappro' => '12.00', 'cout_moyen_pondere' => '0.0000',
        ]);
        $this->huile = Article::create([
            'libelle' => 'Huile 20 L', 'categorie' => 'denree', 'unite_mesure' => 'bidon',
            'seuil_alerte' => '2.00', 'seuil_reappro' => '6.00', 'cout_moyen_pondere' => '0.0000',
        ]);

        // Stock de départ du SERVEUR : 10 sacs de riz, 4 bidons d'huile.
        $this->actingAs($this->magasinier);
        app(MouvementStockService::class)->entree($this->riz->id, $this->magasin->id, '10.00', 'Ouverture', '25000.0000');
        app(MouvementStockService::class)->entree($this->huile->id, $this->magasin->id, '4.00', 'Ouverture', '30000.0000');
    }

    /**
     * @param  list<array<string, mixed>>  $lignes
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function inventaire(string $id, array $lignes, array $surcharges = []): array
    {
        return $this->creation('inventaires', $id, [
            'point_id' => $this->magasin->id,
            'date_inventaire' => '2026-10-21',
            'lignes' => $lignes,
            ...$surcharges,
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function ligne(Article $article, int $theorique, int $constate, ?int $ecart = null): array
    {
        return [
            'id' => $this->uuid(), 'article_id' => $article->id,
            'quantite_theorique' => $theorique, 'quantite_constatee' => $constate,
            'ecart' => $ecart ?? $constate - $theorique,
        ];
    }

    private function stock(Article $article): string
    {
        return app(StockTheoriqueService::class)->stock($article->id, $this->magasin->id);
    }

    #[Test]
    public function l_inventaire_clos_du_poste_est_ecrit_tel_quel_avec_ses_lignes_et_sa_regularisation(): void
    {
        $id = $this->uuid();
        // Riz : 12 comptés pour 10 attendus (+2). Huile : 3 comptés pour 4 (-1).
        $lignes = [$this->ligne($this->riz, 1000, 1200), $this->ligne($this->huile, 400, 300)];

        $this->pousser([
            $this->inventaire($id, $lignes),
            $this->creation('mouvements_stock', $this->uuid(), [
                'article_id' => $this->riz->id, 'point_id' => $this->magasin->id, 'type_mouvement' => 'inventaire',
                'quantite' => 200, 'motif' => 'Régularisation inventaire', 'date_mouvement' => '2026-10-21 09:30:00',
            ]),
            $this->creation('mouvements_stock', $this->uuid(), [
                'article_id' => $this->huile->id, 'point_id' => $this->magasin->id, 'type_mouvement' => 'perte',
                'quantite' => 100, 'motif' => 'Régularisation inventaire', 'date_mouvement' => '2026-10-21 09:30:00',
            ]),
        ], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.2.statut', 'synchronise');

        $inventaire = Inventaire::findOrFail($id);
        $this->assertSame($this->magasin->id, $inventaire->point_id);
        $this->assertSame('2026-10-21', $inventaire->date_inventaire->toDateString());
        $this->assertSame($this->magasinier->id, $inventaire->utilisateur_id);

        $ligneRiz = LigneInventaire::query()->where('inventaire_id', $id)->where('article_id', $this->riz->id)->firstOrFail();
        $this->assertSame(['10.00', '12.00', '2.00'], [(string) $ligneRiz->quantite_theorique, (string) $ligneRiz->quantite_constatee, (string) $ligneRiz->ecart]);
        $ligneHuile = LigneInventaire::query()->where('inventaire_id', $id)->where('article_id', $this->huile->id)->firstOrFail();
        $this->assertSame('-1.00', (string) $ligneHuile->ecart);

        // Le stock suit le constaté : l'excédent en `inventaire`, le manquant en `perte`.
        $this->assertSame('12.00', $this->stock($this->riz));
        $this->assertSame('3.00', $this->stock($this->huile));
        $this->assertSame(
            ['inventaire', 'perte'],
            MouvementStock::query()->where('motif', 'Régularisation inventaire')->pluck('type_mouvement')->sort()->values()->all(),
        );
        // Un excédent n'achète rien : le coût moyen pondéré n'a pas bougé.
        $this->assertSame('25000.0000', (string) $this->riz->fresh()->cout_moyen_pondere);
    }

    #[Test]
    public function le_theorique_fige_par_le_poste_n_est_pas_recalcule_et_le_rejeu_ne_double_rien(): void
    {
        $id = $this->uuid();
        // Le poste avait 7 en tête (des ventes sont arrivées depuis au serveur : 10) : on garde 7.
        $this->pousser([$this->inventaire($id, [$this->ligne($this->riz, 700, 700)])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame('7.00', (string) LigneInventaire::query()->where('inventaire_id', $id)->firstOrFail()->quantite_theorique);

        // Rejeu sous une autre opération : le document n'est pas écrit deux fois.
        $this->pousser([$this->inventaire($id, [$this->ligne($this->riz, 700, 700)])], $this->magasinier)
            ->assertJsonPath('resultats.0.document_deja_enregistre', true);
        $this->assertSame(1, Inventaire::count());
        $this->assertSame(1, LigneInventaire::count());
    }

    #[Test]
    public function un_inventaire_incoherent_est_rejete_en_entier_sans_rien_ecrire(): void
    {
        // Écart qui n'est pas constaté − théorique.
        $this->pousser([$this->inventaire($this->uuid(), [$this->ligne($this->riz, 1000, 1200, 500)])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.stocks.inventaire_ecart_incoherent', ['article' => 'Riz parfumé 50kg']));

        // Un article compté deux fois.
        $this->pousser([$this->inventaire($this->uuid(), [$this->ligne($this->riz, 1000, 1000), $this->ligne($this->riz, 1000, 900)])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.stocks.inventaire_article_double', ['article' => 'Riz parfumé 50kg']));

        // Article inconnu du serveur : la ligne bonne n'est pas gardée seule.
        $inconnu = $this->ligne($this->huile, 400, 400);
        $inconnu['article_id'] = $this->uuid();
        $this->pousser([$this->inventaire($this->uuid(), [$this->ligne($this->riz, 1000, 1000), $inconnu])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete');

        // Point inconnu ; quantité constatée négative.
        $this->pousser([$this->inventaire($this->uuid(), [], ['point_id' => $this->uuid()])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.stocks.inventaire_point_inconnu'));
        $this->pousser([$this->inventaire($this->uuid(), [$this->ligne($this->riz, 1000, -100)])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete');

        $this->assertSame(0, Inventaire::count());
        $this->assertSame(0, LigneInventaire::count());
    }

    #[Test]
    public function sans_droit_d_ecriture_sur_les_stocks_l_inventaire_est_rejete(): void
    {
        $this->pousser([$this->inventaire($this->uuid(), [$this->ligne($this->riz, 1000, 1000)])], $this->creerUtilisateur('guide'))
            ->assertJsonPath('resultats.0.statut', 'rejete');

        $this->assertSame(0, Inventaire::count());
    }

    #[Test]
    public function un_inventaire_sans_aucune_ligne_est_admis(): void
    {
        // Clôture « partielle » sans rien de compté : l'en-tête existe, sans ligne.
        $id = $this->uuid();
        $this->pousser([$this->inventaire($id, [])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(0, LigneInventaire::query()->where('inventaire_id', $id)->count());
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function inventairesDuFlux(User $utilisateur): array
    {
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($utilisateur);
        $elements = [];
        $curseur = null;

        do {
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter([
                'poste_id' => 'poste-2', 'depuis' => $curseur, 'limite' => 50,
            ], static fn ($v): bool => $v !== null)))->assertOk();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        return array_values(array_filter($elements, static fn (array $e): bool => $e['table'] === 'inventaires'));
    }

    #[Test]
    public function l_inventaire_descend_aux_autres_postes_avec_ses_lignes_sous_le_droit_m6(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->inventaire($id, [$this->ligne($this->riz, 1000, 1200), $this->ligne($this->huile, 400, 300)])], $this->magasinier);

        $recus = $this->inventairesDuFlux($this->creerUtilisateur('magasinier'));

        $this->assertCount(1, $recus);
        $this->assertSame($id, $recus[0]['id']);
        $this->assertSame($this->magasin->id, $recus[0]['donnees']['point_id']);
        $this->assertSame('2026-10-21', substr((string) $recus[0]['donnees']['date_inventaire'], 0, 10));
        $this->assertArrayNotHasKey('utilisateur_id', $recus[0]['donnees']);

        $lignes = collect($recus[0]['donnees']['lignes'])->keyBy('article_id');
        $this->assertCount(2, $lignes);
        $this->assertSame(['10.00', '12.00', '2.00'], [
            $lignes[$this->riz->id]['quantite_theorique'], $lignes[$this->riz->id]['quantite_constatee'], $lignes[$this->riz->id]['ecart'],
        ]);
        $this->assertSame('-1.00', $lignes[$this->huile->id]['ecart']);

        // Un rôle sans lecture sur M6 ne reçoit rien.
        $this->assertSame([], $this->inventairesDuFlux($this->creerUtilisateur('guide')));
    }

    #[Test]
    public function l_archivage_d_un_article_descend_avec_son_etat_et_son_verrou_de_stock_tient(): void
    {
        $admin = $this->creerUtilisateur('administrateur');

        // Du stock au serveur : l'archivage est refusé avec la phrase du verrou.
        $this->pousser([$this->operation('articles', 'modification', $this->riz->id, ['actif' => false])], $admin)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('stocks_pwa.archivage.verrou_stock', ['quantite' => '10.00']));
        $this->assertTrue((bool) $this->riz->fresh()->actif);

        // Vidé (perte du tout), l'article s'archive, puis se restaure.
        $this->actingAs($admin);
        app(MouvementStockService::class)->perte($this->riz->id, $this->magasin->id, '10.00', 'Casse');
        $this->pousser([$this->operation('articles', 'modification', $this->riz->id, ['actif' => false])], $admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertFalse((bool) $this->riz->fresh()->actif);

        $descendu = $this->articleDuFlux($admin, $this->riz->id);
        $this->assertFalse($descendu['actif']);

        $this->pousser([$this->operation('articles', 'modification', $this->riz->id, ['actif' => true])], $admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue($this->articleDuFlux($admin, $this->riz->id)['actif']);
    }

    /**
     * @return array<string, mixed>
     */
    private function articleDuFlux(User $utilisateur, string $id): array
    {
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($utilisateur);
        $curseur = null;

        do {
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter([
                'poste_id' => 'poste-3', 'depuis' => $curseur, 'limite' => 50,
            ], static fn ($v): bool => $v !== null)))->assertOk();

            foreach ($reponse->json('data.elements') as $e) {
                if ($e['table'] === 'articles' && $e['id'] === $id) {
                    return $e;
                }
            }

            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        $this->fail('L\'article n\'est pas dans le flux.');
    }
}
