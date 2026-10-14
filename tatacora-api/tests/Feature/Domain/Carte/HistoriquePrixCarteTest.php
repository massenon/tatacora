<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Carte;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Carte\Models\HistoriquePrixCarte;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Historique des prix de la carte — demande du Product Owner du 01/09/2026 :
 * « on peut modifier le prix d'un article de la restauration ou boisson — il
 * ne faut pas que le changement de ce prix impute les ventes précédentes ou
 * la comptabilité ; on doit retracer les changements de prix » (M4/M5).
 *
 * ## Ce fichier ne prouve QUE la traçabilité
 *
 * L'IMMUNITÉ des ventes déjà encaissées — le premier volet de la demande —
 * est prouvée dans `VenteServiceTest::le_prix_est_fige_a_l_encaissement…`, qui
 * était déjà vraie avant cette vague (PA-98) et dont le contrôle a été étendu
 * le 01/09/2026 pour couvrir aussi la pièce comptable.
 *
 * ## Le SEUL auteur de `historique_prix_carte`
 *
 * `CarteBoissonObserver` et `PlatObserver` sont les DEUX SEULES portes
 * d'écriture — aucun service ne crée de ligne ici. Les cas ci-dessous
 * appellent donc les services de modification EXISTANTS
 * (`CarteBoissonService::modifier()`, `CartePlatMenuService::modifierPlat()`)
 * plutôt que d'écrire directement dans la table : c'est la garantie que
 * l'Observer couvre réellement le chemin par lequel un prix change en
 * production, pas un raccourci de test.
 *
 * ## Mutation RÉELLEMENT rejouée le 01/09/2026
 *
 * | Mutation | Cas qui rougit | Résultat |
 * |---|---|---|
 * | `TraceurHistoriquePrix::estIdentique()` retournée `false` sans condition (comparaison retirée) | `un_enregistrement_sans_changement_de_prix_ne_trace_rien` | échoue sur `assertCount(0, …)`, qui devient 2 |
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see PA-98 Prix et libellé figés à l'encaissement
 */
final class HistoriquePrixCarteTest extends TestCase
{
    use RefreshDatabase;

    private Article $article;

    private User $administrateur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->administrateur = $this->utilisateur('administrateur');
        $this->actingAs($this->administrateur);

        $this->article = Article::create([
            'libelle' => 'Casier EKU 66 cl',
            'categorie' => 'Boissons',
            'unite_mesure' => 'casier',
            'seuil_alerte' => '2.00',
            'cout_moyen_pondere' => '0.0000',
        ]);
    }

    // ------------------------------------------------------------- Bar (M5)

    #[Test]
    public function un_changement_reel_de_prix_de_boisson_est_trace(): void
    {
        $boisson = $this->boisson('1000.00');

        app(CarteBoissonService::class)->modifier($boisson, ['prix_vente' => '1500.00']);

        $lignes = HistoriquePrixCarte::query()
            ->where('source', HistoriquePrixCarte::SOURCE_BOISSON)
            ->where('source_id', $boisson->id)
            ->get();

        $this->assertCount(1, $lignes, 'Un seul champ a changé : une seule ligne.');

        $ligne = $lignes->first();
        $this->assertSame(HistoriquePrixCarte::CHAMP_PRIX_VENTE, $ligne->champ);
        $this->assertSame(0, bccomp('1000.00', (string) $ligne->ancien_prix, 2));
        $this->assertSame(0, bccomp('1500.00', (string) $ligne->nouveau_prix, 2));
        $this->assertSame($this->administrateur->id, $ligne->utilisateur_creation_id);
    }

    /**
     * `1000` et `1000.00` sont le MÊME montant — l'écran rouvre et referme
     * une modale sans que rien n'ait changé, un cas quotidien.
     */
    #[Test]
    public function un_enregistrement_sans_changement_de_prix_ne_trace_rien(): void
    {
        $boisson = $this->boisson('1200.00');

        app(CarteBoissonService::class)->modifier($boisson, [
            'prix_vente' => '1200',
            'libelle' => 'EKU 66 cl',
        ]);

        $this->assertCount(
            0,
            HistoriquePrixCarte::where('source_id', $boisson->id)->get(),
            '« 1200 » et « 1200.00 » ne sont pas deux prix (bccomp, jamais ==).',
        );
    }

    /**
     * Corriger au clavier le prix d'un tarif PROVISOIRE pose AUSSI
     * `prix_corrige_main` (PA-161 (b), `MarquesDePrix::completer()`) : les
     * DEUX champs changent dans la MÊME sauvegarde, donc DEUX lignes,
     * distinguées par `champ`.
     */
    #[Test]
    public function une_correction_qui_pose_aussi_la_marque_produit_deux_lignes(): void
    {
        $boisson = $this->boisson('1200.00', provisoire: true);

        app(CarteBoissonService::class)->modifier($boisson, ['prix_vente' => '1500.00']);

        $lignes = HistoriquePrixCarte::where('source_id', $boisson->id)
            ->get()
            ->keyBy('champ');

        $this->assertCount(2, $lignes);

        $prix = $lignes[HistoriquePrixCarte::CHAMP_PRIX_VENTE];
        $this->assertSame(0, bccomp('1200.00', (string) $prix->ancien_prix, 2));
        $this->assertSame(0, bccomp('1500.00', (string) $prix->nouveau_prix, 2));

        $marque = $lignes[HistoriquePrixCarte::CHAMP_PRIX_CORRIGE_MAIN];
        $this->assertSame(0, bccomp('0.00', (string) $marque->ancien_prix, 2), 'La marque partait à faux.');
        $this->assertSame(0, bccomp('1.00', (string) $marque->nouveau_prix, 2), 'Et a été posée par la déduction.');
    }

    // --------------------------------------------------------- Restaurant (M4)

    /**
     * La MÊME règle vaut pour un plat — c'est pour cela que la comparaison
     * vit dans `TraceurHistoriquePrix`, partagée entre `CarteBoissonObserver`
     * et `PlatObserver`, jamais recopiée.
     */
    #[Test]
    public function un_changement_reel_de_prix_de_plat_est_trace(): void
    {
        $plat = $this->plat('2500.00');

        app(CartePlatMenuService::class)->modifierPlat($plat, ['prix_vente' => '3000.00']);

        $lignes = HistoriquePrixCarte::query()
            ->where('source', HistoriquePrixCarte::SOURCE_PLAT)
            ->where('source_id', $plat->id)
            ->get();

        $this->assertCount(1, $lignes);
        $this->assertSame(HistoriquePrixCarte::CHAMP_PRIX_VENTE, $lignes->first()->champ);
        $this->assertSame(0, bccomp('2500.00', (string) $lignes->first()->ancien_prix, 2));
        $this->assertSame(0, bccomp('3000.00', (string) $lignes->first()->nouveau_prix, 2));
    }

    #[Test]
    public function un_changement_hors_prix_ne_trace_rien(): void
    {
        $plat = $this->plat('2500.00');

        app(CartePlatMenuService::class)->modifierPlat($plat, ['libelle' => 'Chawarma poulet XL']);

        $this->assertCount(0, HistoriquePrixCarte::where('source_id', $plat->id)->get());
    }

    /* -------------------------------------------------------- fabriques */

    private function boisson(string $prix, bool $provisoire = false): CarteBoisson
    {
        return app(CarteBoissonService::class)->creer([
            'article_id' => $this->article->id,
            'unites_vendables_par_unite_stock' => '1.0000',
            'libelle' => 'EKU 66 cl',
            'categorie' => 'importee',
            'prix_vente' => $prix,
            'prix_provisoire' => $provisoire,
        ]);
    }

    private function plat(string $prix, bool $provisoire = false): Plat
    {
        $menu = Menu::create(['libelle' => 'Carte du jour', 'type' => 'local']);
        $recette = Recette::create(['libelle' => 'Chawarma poulet']);

        return app(CartePlatMenuService::class)->creerPlat([
            'menu_id' => $menu->id,
            'recette_id' => $recette->id,
            'libelle' => 'Chawarma poulet',
            'prix_vente' => $prix,
            'prix_provisoire' => $provisoire,
        ]);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
