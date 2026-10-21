<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le retrait d'un article de la carte du jour, fait sur un poste (21/10/2026,
 * « ce que le web fait, le poste le fait ») : création à l'instant du poste,
 * fusion quand l'article est déjà indisponible, remise à la carte, droit du
 * RAYON (boisson = M5, plat = M4), et descente vers les autres postes.
 */
final class IndisponibilitesCarteSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $barman;

    private User $cuisinier;

    private CarteBoisson $biere;

    private Plat $plat;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->barman = $this->creerUtilisateur('barman');
        $this->cuisinier = $this->creerUtilisateur('cuisine');

        $article = Article::create(['libelle' => 'Bière', 'categorie' => 'Boissons', 'unite_mesure' => 'bouteille', 'seuil_alerte' => '0.00', 'cout_moyen_pondere' => '0.0000']);
        $this->biere = CarteBoisson::create([
            'article_id' => $article->id, 'libelle' => 'Béninoise', 'categorie' => 'locale',
            'prix_vente' => '1000.00', 'unites_vendables_par_unite_stock' => '1.0000',
        ]);
        $menu = Menu::create(['libelle' => 'Carte du jour', 'type' => 'local']);
        $recette = Recette::create(['libelle' => 'Riz', 'cout_matiere_calcule' => '0.00']);
        $this->plat = Plat::create([
            'menu_id' => $menu->id, 'recette_id' => $recette->id, 'categorie' => 'plats',
            'libelle' => 'Riz sauce', 'prix_vente' => '2000.00',
        ]);
    }

    #[Test]
    public function un_retrait_du_poste_est_ecrit_a_son_instant_puis_remis_a_la_carte(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->creation('indisponibilites_carte', $id, [
            'boisson_id' => $this->biere->id, 'plat_id' => null, 'motif' => 'rupture',
            'commentaire' => 'Plus de glace', 'date_indisponibilite' => '2026-10-21T09:30:00Z',
        ])], $this->barman)->assertJsonPath('resultats.0.statut', 'synchronise');

        $ligne = IndisponibiliteCarte::findOrFail($id);
        $this->assertSame(['rupture', 'Plus de glace'], [$ligne->motif, $ligne->commentaire]);
        $this->assertSame('2026-10-21 09:30:00', $ligne->date_indisponibilite->utc()->format('Y-m-d H:i:s'));
        $this->assertNull($ligne->date_retour_disponibilite);

        $this->pousser([$this->operation('indisponibilites_carte', 'modification', $id, [
            'date_retour_disponibilite' => '2026-10-21T15:00:00Z',
        ])], $this->barman)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertNotNull($ligne->refresh()->date_retour_disponibilite);

        // Déjà remise à la carte (par un autre poste) : pas un rejet.
        $this->pousser([$this->operation('indisponibilites_carte', 'modification', $id, [
            'date_retour_disponibilite' => '2026-10-21T16:00:00Z',
        ])], $this->barman, 'poste-b')->assertJsonPath('resultats.0.statut', 'synchronise');
    }

    #[Test]
    public function un_article_deja_indisponible_fusionne_au_lieu_de_se_doubler(): void
    {
        $premier = $this->uuid();
        $this->pousser([$this->creation('indisponibilites_carte', $premier, [
            'boisson_id' => $this->biere->id, 'motif' => 'saison',
        ])], $this->barman, 'poste-a');

        $this->pousser([$this->creation('indisponibilites_carte', $this->uuid(), [
            'boisson_id' => $this->biere->id, 'motif' => 'rupture',
        ])], $this->barman, 'poste-b')->assertJsonPath('resultats.0.fusionne_avec', $premier);

        $this->assertSame(1, IndisponibiliteCarte::query()->count());
    }

    #[Test]
    public function le_droit_est_celui_du_rayon_et_les_cas_invalides_sont_refuses(): void
    {
        // Le barman (M5) ne retire pas un plat (M4) ; le cuisinier (M4) si.
        $this->pousser([$this->creation('indisponibilites_carte', $this->uuid(), [
            'plat_id' => $this->plat->id, 'motif' => 'rupture',
        ])], $this->barman)->assertJsonPath('resultats.0.statut', 'rejete');

        $this->pousser([$this->creation('indisponibilites_carte', $this->uuid(), [
            'plat_id' => $this->plat->id, 'motif' => 'rupture',
        ])], $this->cuisinier)->assertJsonPath('resultats.0.statut', 'synchronise');

        // Ni les deux, ni aucun, ni un motif inconnu.
        foreach ([
            ['boisson_id' => $this->biere->id, 'plat_id' => $this->plat->id, 'motif' => 'rupture'],
            ['motif' => 'rupture'],
            ['boisson_id' => $this->biere->id, 'motif' => 'inconnu'],
        ] as $payload) {
            $this->pousser([$this->creation('indisponibilites_carte', $this->uuid(), $payload)], $this->barman)
                ->assertJsonPath('resultats.0.statut', 'rejete');
        }
    }

    #[Test]
    public function le_retrait_descend_vers_les_autres_postes(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('indisponibilites_carte', $id, [
            'boisson_id' => $this->biere->id, 'motif' => 'rupture',
        ])], $this->barman, 'poste-a');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($this->barman);
        $elements = [];
        $curseur = null;

        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        $ligne = collect($elements)->firstWhere('table', 'indisponibilites_carte');
        $this->assertSame($id, $ligne['id']);
        $this->assertSame($this->biere->id, $ligne['donnees']['boisson_id']);
        $this->assertSame('rupture', $ligne['donnees']['motif']);
        $this->assertNull($ligne['donnees']['date_retour_disponibilite']);
    }
}
