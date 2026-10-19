<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les mouvements de stock saisis sur un poste — lot 10f (audit de couverture
 * du 18/10/2026). Écrits par `MouvementStockService` sous l'UUID du poste ;
 * une sortie que le serveur ne couvre pas est enregistrée (elle a eu lieu) et
 * signalée si le poste ne l'avait pas forcée.
 */
final class MouvementsStockSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $magasinier;

    private PointStockage $magasin;

    private Article $riz;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-18 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->magasinier = $this->creerUtilisateur('magasinier');
        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        $this->riz = Article::create([
            'libelle' => 'Riz parfumé 50kg', 'categorie' => 'denree', 'unite_mesure' => 'sac',
            'seuil_alerte' => '5.00', 'seuil_reappro' => '12.00', 'cout_moyen_pondere' => '0.0000',
        ]);
    }

    /**
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function mouvement(string $id, string $type, int $centiemes, array $surcharges = []): array
    {
        return $this->creation('mouvements_stock', $id, [
            'article_id' => $this->riz->id, 'point_id' => $this->magasin->id, 'type_mouvement' => $type,
            'quantite' => $centiemes, 'motif' => 'Saisie du poste', 'date_mouvement' => '2026-10-18 09:30:00',
            ...$surcharges,
        ]);
    }

    private function stock(): string
    {
        return app(StockTheoriqueService::class)->stock($this->riz->id, $this->magasin->id);
    }

    #[Test]
    public function l_entree_puis_la_sortie_du_poste_passent_par_le_service_sous_son_uuid(): void
    {
        $entree = $this->uuid();
        $this->pousser([$this->mouvement($entree, 'entree', 1000, ['cout_unitaire' => 250000000])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $m = MouvementStock::findOrFail($entree);
        $this->assertSame(['entree', '10.00', '2026-10-18 09:30:00'], [$m->type_mouvement, (string) $m->quantite, $m->date_mouvement->format('Y-m-d H:i:s')]);
        $this->assertSame('25000.00', (string) $this->riz->refresh()->prix_achat);

        $this->pousser([$this->mouvement($this->uuid(), 'perte', 250)], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('7.50', $this->stock());

        // Rejeu sous un autre uuid_operation : rien n'est doublé.
        $this->pousser([$this->mouvement($entree, 'entree', 1000)], $this->magasinier)
            ->assertJsonPath('resultats.0.document_deja_enregistre', true);
        $this->assertSame(2, MouvementStock::count());
    }

    #[Test]
    public function une_sortie_que_le_serveur_ne_couvre_pas_est_enregistree_et_signalee(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->mouvement($id, 'sortie', 300)], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('-3.00', $this->stock());
        $this->assertTrue(AnomalieSynchronisation::query()->where('entite_id', $id)->where('type', AnomalieSynchronisation::MOUVEMENT_RUPTURE_SERVEUR)->exists());

        // Forcée sur le poste : la rupture est assumée, rien à signaler.
        $force = $this->uuid();
        $this->pousser([$this->mouvement($force, 'sortie', 100, ['rupture_forcee' => true])], $this->magasinier);
        $this->assertFalse(AnomalieSynchronisation::query()->where('entite_id', $force)->exists());
    }

    #[Test]
    public function refus_sans_reference_ou_sans_droit_cout_hors_entree(): void
    {
        $this->pousser([$this->mouvement($this->uuid(), 'entree', 100, ['article_id' => $this->uuid()])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->pousser([$this->mouvement($this->uuid(), 'sortie', 100, ['cout_unitaire' => 1])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->pousser([$this->mouvement($this->uuid(), 'entree', 100)], $this->creerUtilisateur('guide'))
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame(0, MouvementStock::count());
    }
}
