<?php

declare(strict_types=1);

namespace Tests\Feature\ProcessusMetiers;

use App\Domain\Etats\Services\CatalogueEtatsService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\ReportEngine\Models\EtatGenere;
use App\Shared\ReportEngine\Services\GenerateurEtatService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Processus métier n°7 — Reporting et pilotage.
 *
 * « Consolidation continue (M1–M13) → Tableaux de bord (M11) → États
 * périodiques normalisés (M14) → Diffusion automatique à la Direction (M12),
 * en remplacement du reporting manuel WhatsApp »
 * (`05_MODULE_SPECIFICATIONS.md` §Processus transverses).
 *
 * ## Périmètre réellement couvert
 *
 * Le dernier maillon — **diffusion automatique (M12)** — n'est pas exercé : le
 * domaine Notifications est vide et l'API WhatsApp n'est pas contractée
 * (RG-20). Le processus s'arrête donc à l'état édité. Le nommer explicitement
 * évite de laisser croire que le remplacement du reporting manuel est acquis :
 * c'est précisément l'objectif métier de ce processus, et il n'est pas atteint.
 *
 * ## Ce que ce niveau attrape et qu'aucun autre ne voit
 *
 * M11 et M14 ne possèdent **aucune donnée propre** : ils relisent les tables
 * de tous les autres domaines. Un changement dans M6 ou M8 se propage donc
 * jusqu'au tableau de bord et jusqu'aux états sans qu'aucun test de M6 ou M8
 * ne le détecte — la configuration exacte décrite par `07_TESTING_QA.md` §8.
 */
final class ReportingEtPilotageTest extends TestCase
{
    use RefreshDatabase;

    private User $gerant;

    private PointStockage $magasin;

    private Article $riz;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        // Le catalogue M14 porte des états comptables depuis la vague F
        // (01/09/2026) : la balance exige un exercice ouvert — le
        // référentiel comptable fait partie du décor minimal du hub.
        $this->seed(\Database\Seeders\ComptabiliteReferentielSeeder::class);

        $this->gerant = $this->utilisateur('gerant');
        $this->actingAs($this->gerant);

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $this->riz = Article::create([
            'libelle' => 'Riz parfumé 50kg', 'categorie' => 'denree', 'unite_mesure' => 'sac',
            'seuil_alerte' => '10.00', 'seuil_reappro' => '50.00', 'cout_moyen_pondere' => '18000.0000',
        ]);

        Vehicule::create([
            'categorie' => '4x4', 'immatriculation' => 'AB 1234 RB', 'annee' => 2019,
            'transmission' => 'automatique', 'capacite' => 7,
            'tarif_jour' => '65000.00', 'statut' => 'disponible',
        ]);
    }

    /**
     * La chaîne complète : une opération métier remonte jusqu'au document
     * édité, sans aucune saisie intermédiaire.
     */
    #[Test]
    public function une_operation_metier_remonte_jusqu_au_document_edite(): void
    {
        // --- 1. Consolidation continue : un mouvement de stock en M6...
        app(MouvementStockService::class)->entree($this->riz->id, $this->magasin->id, '40.00', 'Stock initial');

        // --- 2. ...se voit immédiatement au tableau de bord M11, sans job ni cache
        $indicateurs = app(TableauDeBordService::class);
        $this->assertSame('720000.00', $indicateurs->valeurStock());

        // --- 3. ...et dans l'état des stocks M14, à la même valeur
        $document = app(GenerateurEtatService::class)->generer(
            app(CatalogueEtatsService::class)->resoudre('stocks'),
            ['point_id' => $this->magasin->id],
            'pdf',
        );

        $ligneRiz = collect($document->resultat->lignes)
            ->firstOrFail(fn (array $l): bool => $l[0] === 'Riz parfumé 50kg');

        $this->assertSame('40.00', $ligneRiz[3]);
        $this->assertSame('720000.00', $ligneRiz[6]);

        // --- 4. Le document porte l'en-tête normalisée (RG-19) et le vrai auteur
        $this->assertSame('TATACORA AFRIQUE', $document->entete->raisonSociale);
        $this->assertStringContainsString($this->gerant->login, $document->entete->auteur);

        // --- 5. L'édition est archivée (EF-M14-06)
        $this->assertSame(1, EtatGenere::count());
    }

    /**
     * **La régression que ce niveau existe pour attraper.**
     *
     * Une sortie de stock en M6 doit se répercuter simultanément sur le KPI de
     * M11 et sur l'état de M14. Si l'un des deux calculait autrement — une
     * colonne figée, un cache, un arrondi différent — les deux divergeraient,
     * et aucun test de M6, M11 ou M14 pris isolément ne le verrait.
     */
    #[Test]
    public function le_tableau_de_bord_et_l_etat_ne_peuvent_pas_diverger(): void
    {
        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($this->riz->id, $this->magasin->id, '40.00', 'Stock initial');
        $mouvements->sortie($this->riz->id, $this->magasin->id, '15.00', 'Consommation cuisine');

        $kpi = app(TableauDeBordService::class)->valeurStock();

        $document = app(GenerateurEtatService::class)->generer(
            app(CatalogueEtatsService::class)->resoudre('stocks'),
            [],
            'excel',
        );
        $valeurEtat = $document->resultat->kpis[__('stocks.etat.kpi_valeur')];

        // 25 sacs × 18 000 — les deux chemins doivent tomber au centime près.
        $this->assertSame('450000.00', $kpi);
        $this->assertSame(0, bccomp($kpi, $valeurEtat, 2), "M11 dit {$kpi}, M14 dit {$valeurEtat}.");
    }

    /**
     * RG-19 traverse tout le processus : quel que soit le module d'origine de
     * l'état, l'en-tête institutionnelle est identique. C'est ce qui permet à
     * la Direction de recevoir des documents comparables.
     */
    #[Test]
    public function tous_les_etats_du_hub_portent_la_meme_entete(): void
    {
        $generateur = app(GenerateurEtatService::class);
        $catalogue = app(CatalogueEtatsService::class);

        $entetes = [];

        foreach ($catalogue->codesDisponibles() as $code) {
            $entetes[$code] = $generateur->generer($catalogue->resoudre($code), [], 'pdf')->entete;
        }

        // Au moins trois états, sinon la comparaison ne prouve rien.
        $this->assertGreaterThanOrEqual(3, count($entetes));

        $reference = reset($entetes);

        foreach ($entetes as $code => $entete) {
            $this->assertSame($reference->raisonSociale, $entete->raisonSociale, "État {$code}");
            $this->assertSame($reference->adresse, $entete->adresse, "État {$code}");
            $this->assertSame($reference->mentionInstitutionnelle, $entete->mentionInstitutionnelle, "État {$code}");
            $this->assertSame($reference->auteur, $entete->auteur, "État {$code}");
        }

        // Chaque édition a laissé sa trace — le journal permet de savoir qui a
        // diffusé quoi, ce que le reporting WhatsApp ne permettait pas.
        $this->assertSame(count($entetes), EtatGenere::count());
    }

    /**
     * Le filtrage de période traverse M11 → M14 : un état exporté doit porter
     * la période **réellement** demandée, jamais une valeur par défaut muette
     * (`RESPECT_TABLEAU_RAPPORT.md`, grille point 3).
     */
    #[Test]
    public function la_periode_demandee_traverse_le_tableau_de_bord_jusqu_a_l_etat(): void
    {
        $document = app(GenerateurEtatService::class)->generer(
            app(CatalogueEtatsService::class)->resoudre('tableau-de-bord'),
            ['periode' => Periode::SEPT_JOURS],
            'pdf',
        );

        $attendue = Periode::depuisCode(Periode::SEPT_JOURS);

        $this->assertSame($attendue->libelle(), $document->entete->periode);
        $this->assertSame(Periode::SEPT_JOURS, EtatGenere::sole()->filtres_appliques['periode']);
        // Et surtout : pas le défaut 30 jours.
        $this->assertNotSame(
            Periode::depuisCode(Periode::TRENTE_JOURS)->libelle(),
            $document->entete->periode,
        );
    }

    /**
     * Le filtrage RBAC survit à la consolidation : un rôle sans droit sur un
     * module ne doit pas en recevoir les données par le biais d'un état
     * consolidé (`RESPECT_TABLEAU_RAPPORT.md` §4, non-conformité recensée).
     */
    #[Test]
    public function la_consolidation_ne_contourne_pas_le_rbac_du_module_source(): void
    {
        $sansStocks = Role::all()->first(fn (Role $role): bool => $role->niveauSurModule('M6') === '-');
        $this->assertNotNull($sansStocks, 'Aucun rôle sans accès M6 : matrice à vérifier.');

        $intrus = $this->compteAvecRole($sansStocks);

        $codes = array_column(app(CatalogueEtatsService::class)->pourUtilisateur($intrus), 'code');

        $this->assertNotContains('stocks', $codes);

        // Et l'appel direct est refusé, catalogue contourné ou non.
        $this->assertThrows(
            fn () => app(GenerateurEtatService::class)->generer(
                app(CatalogueEtatsService::class)->resoudre('stocks'),
                [],
                'pdf',
                $intrus,
            ),
            \RuntimeException::class,
        );

        $this->assertSame(0, EtatGenere::count());
    }

    /**
     * RG-20 non atteinte : le dernier maillon du processus — diffusion
     * automatique en remplacement du reporting WhatsApp manuel — n'existe
     * pas. Le test fige cette absence pour qu'elle reste visible.
     */
    #[Test]
    public function rg20_la_diffusion_automatique_n_est_pas_implementee(): void
    {
        $this->assertFalse(
            class_exists(\App\Domain\Notifications\Jobs\SyntheseQuotidienneJob::class),
            'RG-20 livrée ? Mettre à jour 07_TESTING_QA.md §8.1 et ce test.',
        );

        $planifiees = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())
            ->map(fn ($e): string => $e->getSummaryForDisplay())
            ->implode(' | ');

        // Une tâche planifiée qui ne diffuse rien rendrait le planning
        // faussement complet — même discipline qu'en TachesPlanifieesTest.
        $this->assertStringNotContainsString('SyntheseQuotidienne', $planifiees);
    }

    // ------------------------------------------------------------- Helpers

    private function utilisateur(string $role): User
    {
        return $this->compteAvecRole(Role::where('libelle', $role)->firstOrFail());
    }

    private function compteAvecRole(Role $role): User
    {
        return User::create([
            'login' => $role->libelle . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $role->id,
            'statut' => 'actif',
        ]);
    }
}
