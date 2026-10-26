<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\HistoriquePrixCarte;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * L'HISTORIQUE DES PRIX de la carte descend vers les postes (26/10/2026,
 * « le poste fait ce que le web fait ») : l'écran « Historique des prix » du bar
 * et du restaurant se lit sans serveur.
 *
 * Le serveur reste l'UNIQUE auteur de la trace (les deux observateurs) : le
 * poste ne la pousse pas, il la reçoit. Ce qui est prouvé ici :
 *
 *  - un changement de prix fait SUR UN POSTE (modification poussée) est tracé
 *    par l'observateur, avec le compte du poste, et la trace descend avec le
 *    LOGIN de l'auteur (`par`) et sa date (`created_at`) ;
 *  - le droit est celui du RAYON : le bar (M5) ne reçoit pas les prix des plats
 *    (M4), et inversement ; un compte sans l'un ni l'autre n'en reçoit aucun,
 *    et `nonLivrees` compte ce qui n'est pas livré ;
 *  - l'ordre de `COLONNES` place l'historique après les boissons et les plats.
 */
final class HistoriquePrixCarteDescendantTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $barman;

    private User $cuisinier;

    private User $gerant;

    private User $achats;

    private CarteBoisson $biere;

    private Plat $plat;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->barman = $this->creerUtilisateur('barman');
        $this->cuisinier = $this->creerUtilisateur('cuisine');
        $this->gerant = $this->creerUtilisateur('gerant');
        $this->achats = $this->creerUtilisateur('achats');

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

    /**
     * @return list<array<string, mixed>>
     */
    private function telecharger(User $utilisateur): array
    {
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($utilisateur);
        $elements = [];
        $curseur = null;

        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        return array_values(array_filter($elements, static fn (array $e): bool => $e['table'] === 'historique_prix_carte'));
    }

    #[Test]
    public function un_prix_change_sur_un_poste_est_trace_et_descend_avec_son_auteur(): void
    {
        $this->pousser([$this->operation('cartes_boisson', 'modification', $this->biere->id, ['prix_vente' => 1200])], $this->barman, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $traces = $this->telecharger($this->barman);

        $this->assertCount(1, $traces);
        $this->assertSame(HistoriquePrixCarte::query()->value('id'), $traces[0]['id']);
        $this->assertSame([
            'source' => 'carte_boisson',
            'source_id' => $this->biere->id,
            'champ' => 'prix_vente',
            'ancien_prix' => '1000.00',
            'nouveau_prix' => '1200.00',
            'par' => $this->barman->login,
        ], array_intersect_key($traces[0]['donnees'], array_flip(['source', 'source_id', 'champ', 'ancien_prix', 'nouveau_prix', 'par'])));
        $this->assertMatchesRegularExpression('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $traces[0]['donnees']['created_at']);
        // Le login descend, JAMAIS l'identifiant du compte.
        $this->assertArrayNotHasKey('utilisateur_creation_id', $traces[0]['donnees']);
    }

    #[Test]
    public function une_trace_sans_auteur_descend_avec_un_par_nul(): void
    {
        Auth::logout();
        $this->plat->update(['prix_vente' => '2500.00']);

        $traces = $this->telecharger($this->cuisinier);

        $this->assertCount(1, $traces);
        $this->assertNull($traces[0]['donnees']['par']);
        $this->assertSame(['plat', '2000.00', '2500.00'], [$traces[0]['donnees']['source'], $traces[0]['donnees']['ancien_prix'], $traces[0]['donnees']['nouveau_prix']]);
    }

    #[Test]
    public function le_droit_est_celui_du_rayon_et_nonlivrees_compte_le_reste(): void
    {
        $this->biere->update(['prix_vente' => '1100.00']);
        $this->plat->update(['prix_vente' => '2100.00']);

        $this->assertSame(['carte_boisson'], array_column(array_column($this->telecharger($this->barman), 'donnees'), 'source'));
        $this->assertSame(['plat'], array_column(array_column($this->telecharger($this->cuisinier), 'donnees'), 'source'));
        $this->assertEqualsCanonicalizing(['carte_boisson', 'plat'], array_column(array_column($this->telecharger($this->gerant), 'donnees'), 'source'));
        // Ni M4 ni M5 : rien n'est livré, et la table figure parmi les non livrées.
        $this->assertSame([], $this->telecharger($this->achats));

        $service = app(CatalogueDescendantService::class);
        $this->assertSame(1, $service->nonLivrees($this->barman)['historique_prix_carte'] ?? 0, 'le bar ne reçoit pas le prix du plat');
        $this->assertSame(1, $service->nonLivrees($this->cuisinier)['historique_prix_carte'] ?? 0);
        $this->assertSame(2, $service->nonLivrees($this->achats)['historique_prix_carte'] ?? 0);
        $this->assertArrayNotHasKey('historique_prix_carte', $service->nonLivrees($this->gerant));
    }

    #[Test]
    public function la_trace_descend_apres_les_boissons_et_les_plats_et_restants_la_compte(): void
    {
        $ordre = array_keys(CatalogueDescendantService::COLONNES);
        $this->assertGreaterThan(array_search('cartes_boisson', $ordre, true), array_search('historique_prix_carte', $ordre, true));
        $this->assertGreaterThan(array_search('plats', $ordre, true), array_search('historique_prix_carte', $ordre, true));

        $this->biere->update(['prix_vente' => '1300.00']);
        $this->plat->update(['prix_vente' => '2300.00']);
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();

        $restants = app(CatalogueDescendantService::class)->restants($this->barman, 'poste-b', null);
        $this->assertSame(1, $restants['historique_prix_carte'], 'seule la trace du bar est restante pour le barman');
    }
}
