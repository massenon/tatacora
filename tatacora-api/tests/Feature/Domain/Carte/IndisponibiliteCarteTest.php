<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Carte;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Carte\Services\DisponibiliteCarteService;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Indisponibilité d'un article de carte — PA-159 lot 0b, T3.
 *
 * `enregistrerDispo()` écrivait dans `Session::put(...)`. Trois défauts dans un
 * seul stockage : un plat retiré revenait tout seul à l'expiration de la
 * session, aucun autre poste ne le voyait retiré, et la décision n'était
 * imputable à personne.
 *
 * S'y ajoutait une divergence de codes invisible à l'écran — le maître écrit
 * `rupture` / `saison` / `retire`, la PWA écrivait `rupture` / `hors_saison` /
 * `retrait` pour des libellés identiques.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 */
final class IndisponibiliteCarteTest extends TestCase
{
    use RefreshDatabase;

    private DisponibiliteCarteService $service;

    private CarteBoisson $boisson;

    private Plat $plat;

    private User $barman;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->service = app(DisponibiliteCarteService::class);
        $this->barman = $this->utilisateur('barman');
        $this->actingAs($this->barman);

        $article = Article::create([
            'libelle' => 'Béninoise 65cl',
            'categorie' => 'boisson',
            'unite_mesure' => 'bouteille',
            'seuil_alerte' => '10.00',
            'seuil_reappro' => '24.00',
            'cout_moyen_pondere' => '450.0000',
        ]);

        $this->boisson = CarteBoisson::create([
            'article_id' => $article->id,
            'libelle' => 'Béninoise 65cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
            'unites_vendables_par_unite_stock' => '1.0000',
        ]);

        $recette = Recette::create(['libelle' => 'Poulet DG', 'cout_matiere_calcule' => '0.00']);
        $menu = Menu::create(['libelle' => 'Carte principale', 'type' => 'local']);

        $this->plat = Plat::create([
            'menu_id' => $menu->id,
            'recette_id' => $recette->id,
            'libelle' => 'Poulet DG',
            'prix_vente' => '4500.00',
        ]);
    }

    // ------------------------------------------------- Persistance (le défaut)

    #[Test]
    public function une_indisponibilite_survit_a_la_session_et_est_visible_de_tous_les_postes(): void
    {
        $this->service->rendreIndisponible($this->boisson, 'rupture', 'Livraison en retard');

        // Rien en session : la seule trace est en base, donc lisible par
        // n'importe quel autre poste.
        $this->assertFalse(session()->has('bar_boissons_indisponibles'));
        $this->assertDatabaseHas('indisponibilites_carte', [
            'boisson_id' => $this->boisson->id,
            'motif' => 'rupture',
            'commentaire' => 'Livraison en retard',
            'utilisateur_id' => $this->barman->id,
            'date_retour_disponibilite' => null,
        ]);

        $this->assertFalse($this->service->estDisponible($this->boisson));
    }

    #[Test]
    public function la_decision_est_imputable_a_un_utilisateur(): void
    {
        Auth::logout();

        $this->expectException(RuntimeException::class);

        $this->service->rendreIndisponible($this->boisson, 'rupture');
    }

    // ------------------------------------------------------ Codes du maître

    #[Test]
    public function les_trois_motifs_sont_ceux_du_maitre_et_rien_d_autre(): void
    {
        $this->assertSame(
            ['rupture', 'saison', 'retire'],
            array_keys(IndisponibiliteCarte::MOTIFS),
        );

        foreach (['hors_saison', 'retrait', 'indisponible'] as $codeDeLaPwa) {
            try {
                $this->service->rendreIndisponible($this->plat, $codeDeLaPwa);
                $this->fail("Le motif « {$codeDeLaPwa} » aurait dû être refusé.");
            } catch (RuntimeException $refus) {
                $this->assertStringContainsString($codeDeLaPwa, $refus->getMessage());
            }
        }
    }

    #[Test]
    public function temporaire_distingue_ce_qui_revient_de_ce_qui_est_retire(): void
    {
        $rupture = $this->service->rendreIndisponible($this->boisson, 'rupture');
        $retrait = $this->service->rendreIndisponible($this->plat, 'retire');

        $this->assertTrue($rupture->estTemporaire(), 'Une rupture revient au réapprovisionnement.');
        $this->assertFalse($retrait->estTemporaire(), 'Un retrait est une décision commerciale.');

        // Le caractère temporaire n'est PAS une colonne : le stocker
        // permettrait de le contredire.
        $this->assertArrayNotHasKey('temporaire', $rupture->getAttributes());
    }

    // ---------------------------------------------------- Lever, pas supprimer

    #[Test]
    public function lever_une_indisponibilite_la_CLOT_au_lieu_de_l_effacer(): void
    {
        $posee = $this->service->rendreIndisponible($this->boisson, 'rupture');

        $levee = $this->service->rendreDisponible($this->boisson);

        $this->assertSame($posee->id, $levee->id);
        $this->assertNotNull($levee->date_retour_disponibilite);
        $this->assertSame($this->barman->id, $levee->utilisateur_retour_id);
        $this->assertFalse($levee->estEnCours());

        // La ligne EXISTE toujours : l'historique des ruptures est ce sur quoi
        // se décide un réapprovisionnement.
        $this->assertSame(1, IndisponibiliteCarte::count());
        $this->assertTrue($this->service->estDisponible($this->boisson));
    }

    #[Test]
    public function un_article_deja_indisponible_ne_recoit_pas_un_second_motif(): void
    {
        $this->service->rendreIndisponible($this->boisson, 'rupture');

        $this->expectException(RuntimeException::class);

        $this->service->rendreIndisponible($this->boisson, 'saison');
    }

    #[Test]
    public function lever_un_article_deja_a_la_carte_est_refuse_plutot_que_confirme(): void
    {
        $this->expectException(RuntimeException::class);

        $this->service->rendreDisponible($this->plat);
    }

    #[Test]
    public function un_article_peut_etre_retire_puis_remis_puis_retire_a_nouveau(): void
    {
        $this->service->rendreIndisponible($this->boisson, 'rupture');
        $this->service->rendreDisponible($this->boisson);
        $seconde = $this->service->rendreIndisponible($this->boisson, 'saison');

        $this->assertSame(2, IndisponibiliteCarte::count());
        $this->assertSame('saison', $seconde->motif);
        $this->assertSame($seconde->id, $this->service->indisponibilite($this->boisson)?->id);
    }

    // ------------------------------------------------------------- Intégrité

    #[Test]
    public function une_ligne_ne_peut_pas_viser_les_deux_rayons_ni_aucun(): void
    {
        foreach ([
            ['boisson_id' => $this->boisson->id, 'plat_id' => $this->plat->id],
            ['boisson_id' => null, 'plat_id' => null],
        ] as $cible) {
            try {
                DB::table('indisponibilites_carte')->insert(array_merge($cible, [
                    'id' => (string) Str::uuid(),
                    'motif' => 'rupture',
                    'date_indisponibilite' => now(),
                    'utilisateur_id' => $this->barman->id,
                    'date_creation' => now(),
                ]));
                $this->fail('La contrainte CHECK aurait dû refuser cette ligne.');
            } catch (QueryException) {
                $this->addToAssertionCount(1);
            }
        }
    }

    #[Test]
    public function le_lot_du_rayon_est_lu_en_une_seule_requete(): void
    {
        $this->service->rendreIndisponible($this->boisson, 'rupture');

        DB::enableQueryLog();
        $lot = $this->service->indisponibilitesEnCours('boisson');
        $requetes = DB::getQueryLog();
        DB::disableQueryLog();

        $this->assertCount(1, $requetes, 'Une requête par ligne serait un N+1 sur une carte de cinquante articles.');
        $this->assertTrue($lot->has($this->boisson->id));
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
