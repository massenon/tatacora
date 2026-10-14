<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Stocks;

use App\Domain\Stocks\Events\SeuilStockAtteint;
use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Domain\Stocks\Services\VerificationSeuilService;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * RG-05 / RG-06 / RG-07 — mouvements de stock.
 *
 * Les trois cas obligatoires de 07_TESTING_QA.md §2 sont couverts :
 * vente avec stock suffisant → décrémentation correcte ; vente dépassant le
 * stock sans validation → rejet ; avec validation explicite → passage forcé
 * ET entrée `journal_audit`.
 */
final class Rg06SortieStockTest extends TestCase
{
    use RefreshDatabase;

    private MouvementStockService $mouvements;

    private StockTheoriqueService $stock;

    private Article $article;

    private PointStockage $point;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->mouvements = app(MouvementStockService::class);
        $this->stock = app(StockTheoriqueService::class);

        $this->article = Article::create([
            'libelle' => 'Bière La Béninoise 65cl',
            'categorie' => 'boisson',
            'unite_mesure' => 'bouteille',
            'seuil_alerte' => '10.00',
            'seuil_reappro' => '24.00',
            'cout_moyen_pondere' => '450.0000',
        ]);

        $this->point = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);

        $this->actingAs($this->utilisateur('barman'));
    }

    #[Test]
    public function le_stock_est_calcule_depuis_les_mouvements_jamais_stocke(): void
    {
        $this->assertSame('0.00', $this->stock->stock($this->article->id, $this->point->id));

        $this->mouvements->entree($this->article->id, $this->point->id, '48.00', 'Réception');

        $this->assertSame('48.00', $this->stock->stock($this->article->id, $this->point->id));

        // Aucune colonne de stock n'existe sur `articles` — et il ne faut
        // jamais en ajouter (A1_MASTER_PROMPT.md §2.2).
        $this->assertFalse(
            in_array('stock', array_keys($this->article->fresh()->getAttributes()), true),
        );
    }

    #[Test]
    public function rg06_une_sortie_dans_la_limite_du_stock_decremente_correctement(): void
    {
        $this->mouvements->entree($this->article->id, $this->point->id, '48.00');

        $this->mouvements->sortie($this->article->id, $this->point->id, '3.00', 'Vente bar');

        $this->assertSame('45.00', $this->stock->stock($this->article->id, $this->point->id));
    }

    #[Test]
    public function rg06_une_sortie_depassant_le_stock_sans_validation_est_rejetee(): void
    {
        $this->mouvements->entree($this->article->id, $this->point->id, '5.00');

        try {
            $this->mouvements->sortie($this->article->id, $this->point->id, '8.00', 'Vente bar');
            $this->fail('La sortie aurait dû être refusée (RG-06).');
        } catch (RuptureStockException $e) {
            $this->assertSame('5.00', $e->stockDisponible);
            $this->assertSame('8.00', $e->quantiteDemandee);
            // Le drapeau qui permet au client Flutter d'afficher une
            // confirmation plutôt qu'une erreur définitive.
            $this->assertTrue($e->versReponse()['necessite_validation_rupture']);
        }

        // Le stock est intact et aucun mouvement fantôme n'a été créé.
        $this->assertSame('5.00', $this->stock->stock($this->article->id, $this->point->id));
        $this->assertSame(1, MouvementStock::count());
    }

    #[Test]
    public function rg06_une_sortie_forcee_avec_validation_explicite_passe_et_est_tracee(): void
    {
        $this->mouvements->entree($this->article->id, $this->point->id, '5.00');

        $mouvement = $this->mouvements->sortie(
            $this->article->id,
            $this->point->id,
            '8.00',
            'Rupture assumée — service en cours',
            validationRupture: true,
        );

        // Le stock devient négatif : c'est la conséquence assumée d'une
        // rupture validée, pas une anomalie à masquer.
        $this->assertSame('-3.00', $this->stock->stock($this->article->id, $this->point->id));

        $trace = JournalAudit::where('action', 'rupture_stock_forcee')->sole();
        $this->assertSame($mouvement->id, $trace->entite_id);
        $this->assertSame('5.00', $trace->valeur_avant['stock_disponible']);
        $this->assertSame('8.00', $trace->valeur_apres['quantite_sortie']);
        $this->assertNotNull($trace->utilisateur_id);
    }

    #[Test]
    public function rg06_une_sortie_exactement_egale_au_stock_est_acceptee(): void
    {
        $this->mouvements->entree($this->article->id, $this->point->id, '5.00');

        $this->mouvements->sortie($this->article->id, $this->point->id, '5.00');

        $this->assertSame('0.00', $this->stock->stock($this->article->id, $this->point->id));
        $this->assertSame(0, JournalAudit::where('action', 'rupture_stock_forcee')->count());
    }

    #[Test]
    public function le_stock_est_cloisonne_par_point_de_stockage(): void
    {
        $magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $this->mouvements->entree($this->article->id, $magasin->id, '100.00');

        // 100 bouteilles au magasin ne permettent pas de servir au bar.
        $this->assertSame('0.00', $this->stock->stock($this->article->id, $this->point->id));
        $this->assertSame('100.00', $this->stock->stockTousPoints($this->article->id));

        $this->expectException(RuptureStockException::class);
        $this->mouvements->sortie($this->article->id, $this->point->id, '1.00');
    }

    #[Test]
    public function une_perte_est_soumise_au_meme_controle_qu_une_sortie(): void
    {
        $this->mouvements->entree($this->article->id, $this->point->id, '2.00');

        $this->expectException(RuptureStockException::class);
        $this->mouvements->perte($this->article->id, $this->point->id, '5.00', 'Casse');
    }

    #[Test]
    public function un_ecart_d_inventaire_ajuste_le_stock_sans_controle_de_disponibilite(): void
    {
        $this->mouvements->entree($this->article->id, $this->point->id, '10.00');

        // Un inventaire constate le réel : on retrouve 2 bouteilles.
        $this->mouvements->ecartInventaire($this->article->id, $this->point->id, '2.00');
        $this->assertSame('12.00', $this->stock->stock($this->article->id, $this->point->id));

        // Ou l'on en a perdu 4 sans mouvement enregistré.
        $this->mouvements->ecartInventaire($this->article->id, $this->point->id, '-4.00');
        $this->assertSame('8.00', $this->stock->stock($this->article->id, $this->point->id));
    }

    #[Test]
    public function rg07_le_franchissement_du_seuil_emet_une_alerte_synchrone(): void
    {
        Event::fake([SeuilStockAtteint::class]);

        $this->mouvements->entree($this->article->id, $this->point->id, '12.00');
        Event::assertNotDispatched(SeuilStockAtteint::class);

        // Seuil d'alerte à 10 : on descend à 9.
        $this->mouvements->sortie($this->article->id, $this->point->id, '3.00');

        Event::assertDispatched(
            SeuilStockAtteint::class,
            fn (SeuilStockAtteint $e): bool => $e->articleId === $this->article->id
                && $e->stockActuel === '9.00'
                && $e->seuilAlerte === '10.00',
        );
    }

    #[Test]
    public function rg07_le_seuil_atteint_exactement_declenche_aussi_l_alerte(): void
    {
        Event::fake([SeuilStockAtteint::class]);

        $this->mouvements->entree($this->article->id, $this->point->id, '12.00');
        $this->mouvements->sortie($this->article->id, $this->point->id, '2.00');

        // stock == seuil : le moment précis où l'alerte est utile.
        Event::assertDispatched(SeuilStockAtteint::class);
    }

    #[Test]
    public function rg07_le_balayage_planifie_liste_les_articles_critiques(): void
    {
        $this->mouvements->entree($this->article->id, $this->point->id, '3.00');

        $critiques = app(VerificationSeuilService::class)->articlesCritiques();

        $this->assertCount(1, $critiques);
        $this->assertSame($this->article->id, $critiques->first()['article_id']);
        $this->assertSame('3.00', $critiques->first()['stock']);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
