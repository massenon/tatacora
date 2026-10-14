<?php

declare(strict_types=1);

namespace Tests\Feature\Audit;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Rh\Models\Conge;
use App\Domain\Rh\Models\Planning;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\Inventaire;
use App\Domain\Stocks\Models\LigneInventaire;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Vehicules\Models\EntretienVehicule;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Audit\Traits\Auditable;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * RG-15 étendue aux RÉFÉRENTIELS — préalable au CRUD PWA (PA-159, lot 0b).
 *
 * Jusqu'au 28/08/2026, le trait `Auditable` ne couvrait que les tables
 * transactionnelles. La PWA passant en CRUD sur les référentiels, changer un
 * seuil, un tarif ou un prix devient un geste tracé : ce test verrouille
 * la paire migration + trait sur les quinze tables du lot.
 *
 * La liste est FERMÉE et son plancher est le nombre exact du plan : un modèle
 * retiré de la migration ou du trait fait échouer la suite — c'est la garde
 * contre le retour silencieux de l'erreur SQL « Unknown column » que la
 * migration existe pour empêcher.
 *
 * @see RG-15 Journalisation intégrale
 */
final class AuditReferentielsTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Les quinze référentiels du lot 0b — même liste que la migration
     * `2026_08_28_000001_ajouter_audit_referentiels`, classe => table.
     *
     * @var array<class-string, string>
     */
    private const REFERENTIELS_AUDITES = [
        Article::class => 'articles',
        PointStockage::class => 'points_stockage',
        MouvementStock::class => 'mouvements_stock',
        Inventaire::class => 'inventaires',
        LigneInventaire::class => 'lignes_inventaire',
        CarteBoisson::class => 'cartes_boisson',
        Plat::class => 'plats',
        Menu::class => 'menus',
        Recette::class => 'recettes',
        Vehicule::class => 'vehicules',
        EntretienVehicule::class => 'entretiens_vehicule',
        Circuit::class => 'circuits',
        Guide::class => 'guides',
        Planning::class => 'plannings',
        Conge::class => 'conges',
    ];

    private const COLONNES_AUDIT = [
        'utilisateur_creation_id',
        'date_creation',
        'utilisateur_modification_id',
        'date_modification',
    ];

    private User $utilisateur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->utilisateur = User::create([
            'login' => 'magasinier.test',
            'mot_de_passe_hash' => 'mot-de-passe-de-test',
            'role_id' => Role::where('libelle', 'magasinier')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * Le couple trait + colonnes est vérifié ENSEMBLE : un modèle portant le
     * trait sans les colonnes est une erreur SQL à la première écriture, des
     * colonnes sans le trait sont un audit que rien ne remplit (PA-59/60/61).
     */
    #[Test]
    public function rg15_les_quinze_referentiels_portent_le_trait_et_leurs_colonnes_d_audit(): void
    {
        $this->assertCount(
            15,
            self::REFERENTIELS_AUDITES,
            'Le plan PA-159 mesure quinze référentiels — la liste ne doit ni maigrir ni grossir sans relecture.',
        );

        foreach (self::REFERENTIELS_AUDITES as $classe => $table) {
            $this->assertContains(
                Auditable::class,
                class_uses_recursive($classe),
                sprintf('%s ne porte pas le trait Auditable.', $classe),
            );

            $this->assertTrue(
                Schema::hasColumns($table, self::COLONNES_AUDIT),
                sprintf('La table `%s` n\'a pas ses quatre colonnes d\'audit.', $table),
            );
        }
    }

    #[Test]
    public function rg15_la_creation_d_un_article_renseigne_les_colonnes_et_le_journal(): void
    {
        $this->actingAs($this->utilisateur);

        $article = Article::create([
            'libelle' => 'Riz parfumé 25 kg',
            'categorie' => 'denree',
            'unite_mesure' => 'sac',
            'seuil_alerte' => '5.00',
        ])->refresh();

        $this->assertSame($this->utilisateur->id, $article->utilisateur_creation_id);
        $this->assertNotNull($article->date_creation);

        $entree = JournalAudit::where('entite_concernee', 'articles')
            ->where('entite_id', $article->id)
            ->sole();

        $this->assertSame('creation', $entree->action);
        $this->assertSame($this->utilisateur->id, $entree->utilisateur_id);
    }

    /**
     * L'avant/après est la substance de l'audit d'un référentiel : la question
     * posée après un changement de seuil n'est jamais « qui ? » seul, mais
     * « à partir de quelle valeur ? » — sans elle, rien n'est corrigeable.
     */
    #[Test]
    public function rg15_la_modification_d_un_article_journalise_l_avant_et_l_apres(): void
    {
        $this->actingAs($this->utilisateur);

        $article = Article::create([
            'libelle' => 'Huile végétale 5 L',
            'categorie' => 'denree',
            'unite_mesure' => 'bidon',
            'seuil_alerte' => '4.00',
        ]);

        $article->update(['seuil_alerte' => '8.00']);

        $entree = JournalAudit::where('entite_concernee', 'articles')
            ->where('entite_id', $article->id)
            ->where('action', 'modification')
            ->sole();

        $this->assertSame('4.00', (string) $entree->valeur_avant['seuil_alerte']);
        $this->assertSame('8.00', (string) $entree->valeur_apres['seuil_alerte']);

        $this->assertSame(
            $this->utilisateur->id,
            $article->refresh()->utilisateur_modification_id,
        );
    }
}
