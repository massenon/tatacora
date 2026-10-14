<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\TableauxDeBord;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Indicateurs consolidés — EF-M11-01/03/04.
 *
 * ## Ce que cette suite protège
 *
 * M11 ne possède **aucune table** : chaque KPI relit une source appartenant à
 * un autre domaine. C'est exactement la configuration que `07_TESTING_QA.md`
 * §8 décrit comme dangereuse — un changement dans M6 ou M2 casse M11 sans
 * qu'aucun test de M6 ou M2 ne le détecte.
 *
 * Trois KPI sont en outre **dérivés autrement que ne l'écrit le prototype**
 * (PA-49), faute des colonnes qu'il suppose. Les tests fixent la dérivation
 * réellement retenue, pour que personne ne la « corrige » vers une colonne
 * qui n'existe pas.
 */
final class TableauDeBordTest extends TestCase
{
    use RefreshDatabase;

    private User $gerant;

    private UniteHebergement $unite;

    private Client $client;

    private ?string $sessionCaisseId = null;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->gerant = $this->utilisateur('gerant');
        $this->actingAs($this->gerant);

        $this->client = Client::factory()->create();

        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow', 'capacite_max' => 4, 'tarif_base' => '25000.00',
        ]);
        $this->unite = UniteHebergement::create([
            'categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre',
        ]);
    }

    private function service(): TableauDeBordService
    {
        return app(TableauDeBordService::class);
    }

    private function periode(): Periode
    {
        return Periode::depuisCode(Periode::TRENTE_JOURS);
    }

    // ------------------------------------------------------- KPI 2 / RG-02

    /**
     * Le taux d'occupation est calculé en **nuitées depuis `reservations`**,
     * jamais lu dans `unites_hebergement.statut`.
     *
     * C'est la divergence la plus importante avec le prototype : `statut` est
     * un état opérationnel (nettoyage, hors service), et RG-02 impose que la
     * disponibilité soit toujours calculée.
     */
    #[Test]
    public function le_taux_d_occupation_est_calcule_en_nuitees_et_non_lu_dans_une_colonne(): void
    {
        // Une seule unité, 30 jours de fenêtre → capacité de 30 nuitées.
        $arrivee = now()->subDays(5)->toDateString();
        $depart = now()->subDays(2)->toDateString();

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => $arrivee, 'date_depart' => $depart,
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);

        // 3 nuitées sur 30 = 10 %.
        $this->assertSame('10.00', $this->service()->tauxOccupation($this->periode()));

        // La colonne `statut` reste à 'libre' : si le KPI la lisait, il
        // renverrait 0 %. Le test échouerait donc si quelqu'un « corrigeait »
        // le calcul vers la colonne.
        $this->assertSame('libre', $this->unite->fresh()->statut);
    }

    /**
     * Une réservation qui déborde de la fenêtre ne compte que ses nuits
     * intérieures — sinon le taux dépasserait 100 % en fin de période.
     */
    #[Test]
    public function une_reservation_a_cheval_ne_compte_que_ses_nuits_dans_la_fenetre(): void
    {
        // La fenêtre « 30 derniers jours » commence à J-29 à minuit et se
        // termine demain à minuit (exclu) : 30 journées pleines.
        $periode = $this->periode();
        $this->assertSame(30, $periode->nombreJours());

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            // 7 nuitées au total (J-32 → J-25), dont seulement 4 tombent dans
            // la fenêtre : celles de J-29 à J-25.
            'date_arrivee' => now()->subDays(32)->toDateString(),
            'date_depart' => now()->subDays(25)->toDateString(),
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);

        $taux = $this->service()->tauxOccupation($periode);

        // 4/30, jamais 7/30 : compter la réservation entière ferait dépasser
        // 100 % dès que plusieurs séjours débordent en fin de période.
        $this->assertSame('13.33', $taux);
        $this->assertNotSame('23.33', $taux);
    }

    #[Test]
    public function une_reservation_annulee_ne_compte_pas_dans_l_occupation(): void
    {
        $reservation = app(ReservationService::class)->creer([
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => now()->subDays(5)->toDateString(),
            'date_depart' => now()->subDays(2)->toDateString(),
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);

        $this->assertSame('10.00', $this->service()->tauxOccupation($this->periode()));

        app(ReservationService::class)->annuler($reservation);

        $this->assertSame('0.00', $this->service()->tauxOccupation($this->periode()));
    }

    /**
     * Une unité hors service n'est pas louable : la compter au dénominateur
     * ferait chuter le taux sans qu'aucune vente n'ait été manquée.
     */
    #[Test]
    public function une_unite_hors_service_ne_pese_pas_sur_le_denominateur(): void
    {
        $categorie = CategorieHebergement::sole();
        UniteHebergement::create([
            'categorie_id' => $categorie->id, 'numero' => 'B-02', 'statut' => 'hors_service',
        ]);

        app(ReservationService::class)->creer([
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => now()->subDays(5)->toDateString(),
            'date_depart' => now()->subDays(2)->toDateString(),
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);

        // Toujours 3/30, pas 3/60.
        $this->assertSame('10.00', $this->service()->tauxOccupation($this->periode()));
    }

    // ------------------------------------------------------------ KPI 1 / 6

    /**
     * Le CA est la somme des **encaissements**, jamais un statut de facture :
     * `factures.statut` est le cycle de certification MECeF et ne contient
     * aucune valeur « payée » (PA-49).
     */
    #[Test]
    public function le_chiffre_d_affaires_provient_des_paiements_et_non_d_un_statut(): void
    {
        $facture = $this->facture('100000.00');

        // Facture certifiée mais non réglée : aucun CA encaissé.
        $this->assertSame('0.00', $this->service()->chiffreAffairesEncaisse($this->periode()));
        $this->assertSame('100000.00', $this->service()->chiffreAffairesFacture($this->periode()));

        $this->paiement($facture, '60000.00');

        $this->assertSame('60000.00', $this->service()->chiffreAffairesEncaisse($this->periode()));
        // Le facturé ne bouge pas : l'écart entre les deux EST l'information
        // de recouvrement.
        $this->assertSame('100000.00', $this->service()->chiffreAffairesFacture($this->periode()));
    }

    #[Test]
    public function une_facture_partiellement_reglee_reste_comptee_comme_non_soldee(): void
    {
        $facture = $this->facture('100000.00');
        $this->paiement($facture, '99999.99');

        $this->assertSame(1, $this->service()->facturesImpayees($this->periode()));

        $this->paiement($facture, '0.01');

        // Soldée au centime près — comparaison en DECIMAL, jamais en flottant.
        $this->assertSame(0, $this->service()->facturesImpayees($this->periode()));
    }

    // -------------------------------------------------------------- KPI 7

    #[Test]
    public function la_valeur_du_stock_est_valorisee_au_cout_moyen_pondere(): void
    {
        $point = PointStockage::create(['libelle' => 'Magasin', 'type' => 'magasin']);
        $riz = Article::create([
            'libelle' => 'Riz', 'categorie' => 'denree', 'unite_mesure' => 'sac',
            'seuil_alerte' => '10.00', 'seuil_reappro' => '50.00', 'cout_moyen_pondere' => '18000.0000',
        ]);

        $mouvements = app(MouvementStockService::class);
        $mouvements->entree($riz->id, $point->id, '40.00', 'Stock initial');
        $mouvements->sortie($riz->id, $point->id, '10.00', 'Consommation');

        // 30 sacs × 18 000 — au CMP, jamais au prix de vente.
        $this->assertSame('540000.00', $this->service()->valeurStock());
    }

    // -------------------------------------------------------- EF-M11-03

    /**
     * La variation compare deux fenêtres de même durée, et la période
     * précédente doit être réellement exclue de la courante.
     */
    #[Test]
    public function la_variation_compare_bien_deux_fenetres_distinctes(): void
    {
        $facture = $this->facture('100000.00');

        // Un encaissement dans la période courante...
        $this->paiement($facture, '20000.00', now()->subDays(3));
        // ...et un autre dans la précédente (J-45, hors des 30 derniers jours).
        $this->paiement($facture, '10000.00', now()->subDays(45));

        $indicateurs = $this->service()->indicateurs($this->periode());
        $ca = $indicateurs['chiffre_affaires_encaisse'];

        $this->assertSame('20000.00', $ca['valeur']);
        $this->assertSame('10000.00', $ca['precedent']);
        // +100 % : de 10 000 à 20 000.
        $this->assertSame('100.00', $ca['variation_pct']);
    }

    /**
     * Passer de 0 à 1 n'est pas « +100 % », c'est un démarrage. Renvoyer un
     * pourcentage sur une base nulle afficherait un chiffre spectaculaire et
     * dépourvu de sens.
     */
    #[Test]
    public function une_base_precedente_nulle_ne_produit_aucun_pourcentage(): void
    {
        $this->paiement($this->facture('50000.00'), '50000.00', now()->subDays(3));

        $ca = $this->service()->indicateurs($this->periode())['chiffre_affaires_encaisse'];

        $this->assertSame('50000.00', $ca['valeur']);
        $this->assertSame('0.00', $ca['precedent']);
        $this->assertNull($ca['variation_pct']);
    }

    // ------------------------------------------------------------- API

    #[Test]
    public function l_api_expose_les_huit_indicateurs(): void
    {
        \Laravel\Sanctum\Sanctum::actingAs($this->gerant);

        $reponse = $this->getJson('/api/v1/tableau-de-bord');

        $reponse->assertOk()->assertJsonPath('data.periode.code', Periode::TRENTE_JOURS);

        foreach ([
            'chiffre_affaires_encaisse', 'taux_occupation', 'tresorerie_caisse',
            'depenses_cumulees', 'reservations_en_attente', 'factures_impayees',
            'valeur_stock', 'employes_actifs',
        ] as $kpi) {
            $reponse->assertJsonStructure(['data' => ['indicateurs' => [$kpi => ['valeur', 'precedent', 'unite']]]]);
        }
    }

    #[Test]
    public function l_api_refuse_une_periode_hors_liste(): void
    {
        \Laravel\Sanctum\Sanctum::actingAs($this->gerant);

        $this->getJson('/api/v1/tableau-de-bord?periode=ce_siecle')
            ->assertStatus(422)
            ->assertJsonValidationErrors('periode');
    }

    /**
     * RG-16 — 2ᵉ niveau : le masquage d'écran ne protège rien, un appel direct
     * doit être refusé ici.
     */
    #[Test]
    public function l_api_est_refusee_a_un_role_sans_droit_sur_m11(): void
    {
        $sansAcces = Role::all()->first(fn (Role $role): bool => $role->niveauSurModule('M11') === '-');

        if ($sansAcces === null) {
            $this->markTestSkipped('Tous les rôles ont accès à M11 dans la matrice.');
        }

        \Laravel\Sanctum\Sanctum::actingAs($this->compteAvecRole($sansAcces));

        $this->getJson('/api/v1/tableau-de-bord')->assertForbidden();
    }

    // ------------------------------------------------------- EF-M11-05

    /**
     * L'export passe par le moteur partagé (RG-19) et non par une génération
     * ad hoc — l'écart relevé en `SPEC_ECRAN_M11_TABLEAU_DE_BORD.md` §7.
     */
    #[Test]
    public function le_tableau_de_bord_s_exporte_via_le_moteur_partage(): void
    {
        \Laravel\Sanctum\Sanctum::actingAs($this->gerant);

        $reponse = $this->post('/api/v1/etats/generer', [
            'etat' => 'tableau-de-bord',
            'format' => 'pdf',
            'filtres' => ['periode' => Periode::SEPT_JOURS],
        ]);

        $reponse->assertOk();
        $this->assertStringStartsWith('%PDF-', $reponse->streamedContent());

        $archive = \App\Shared\ReportEngine\Models\EtatGenere::sole();
        $this->assertSame('M11', $archive->module);
        $this->assertSame(Periode::SEPT_JOURS, $archive->filtres_appliques['periode']);
    }

    // ------------------------------------------------------------- Helpers

    private function facture(string $montant): string
    {
        $id = (string) Str::uuid();

        DB::table('factures')->insert([
            'id' => $id,
            'client_id' => $this->client->id,
            'date_emission' => now()->subDays(3)->toDateString(),
            'montant_ht' => $montant, 'montant_tva' => '0.00', 'montant_ttc' => $montant,
            'statut' => 'certifiee',
            'numero_mecef' => 'MECEF-TEST-' . Str::random(6),
            'utilisateur_creation_id' => $this->gerant->id,
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    /**
     * `paiements.session_id` est NOT NULL au schéma : un encaissement
     * appartient toujours à une session de caisse ouverte. La contrainte est
     * respectée telle quelle, jamais contournée pour arranger un test.
     */
    private function sessionCaisse(): string
    {
        if ($this->sessionCaisseId === null) {
            $this->sessionCaisseId = (string) Str::uuid();

            DB::table('sessions_caisse')->insert([
                'id' => $this->sessionCaisseId,
                'point_vente' => 'reception',
                'utilisateur_ouverture_id' => $this->gerant->id,
                'date_ouverture' => now()->subDays(60),
                'montant_fond' => '10000.00',
            ]);
        }

        return $this->sessionCaisseId;
    }

    private function paiement(string $factureId, string $montant, ?\Illuminate\Support\Carbon $date = null): void
    {
        DB::table('paiements')->insert([
            'id' => (string) Str::uuid(),
            'facture_id' => $factureId,
            'session_id' => $this->sessionCaisse(),
            'mode_paiement' => 'especes',
            'montant' => $montant,
            'date_paiement' => $date ?? now()->subDays(2),
            'utilisateur_creation_id' => $this->gerant->id,
            'date_creation' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    // ------------------------------------------------------- SERIES (EF-M11-01)

    /**
     * Chaque point de la série est calculé **comme le KPI**, pas comme un
     * agrégat parallèle.
     *
     * C'est la garantie qui justifie deux requêtes par mois plutôt qu'un
     * `GROUP BY` unique : la courbe et la bande d'indicateurs ne peuvent pas
     * se contredire sur le même écran, puisqu'elles exécutent le même code.
     */
    #[Test]
    public function la_serie_mensuelle_donne_le_meme_chiffre_que_le_kpi(): void
    {
        $facture = $this->facture('50000.00');
        // ⚠ `now()` et jamais `subDays(2)` : exécuté un 1er ou un 2 du mois,
        // le paiement tombait dans le mois PRÉCÉDENT et le cas rougissait —
        // le piège de bord de mois de `SerieMensuelleFinDeMoisTest`, côté
        // données de test cette fois (constaté le 01/09/2026).
        $this->paiement($facture, '50000.00', now());

        $serie = $this->service()->serieMensuelle(3);
        $moisCourant = end($serie);

        self::assertSame(now()->format('Y-m'), $moisCourant['mois']);

        // Le KPI du mois courant, calcule par le meme chemin.
        $kpiDuMois = $this->service()->chiffreAffairesEncaisse(
            Periode::mois(\Carbon\CarbonImmutable::now()),
        );
        self::assertSame($kpiDuMois, $moisCourant['chiffre_affaires_encaisse']);
        self::assertSame('50000.00', $moisCourant['chiffre_affaires_encaisse']);
    }

    /**
     * Un mois sans mouvement rend « 0.00 », **jamais rien**.
     *
     * Un point absent ferait un trou dans la courbe, que le tracé relierait
     * en ligne droite d'un mois à l'autre : le creux disparaîtrait de l'écran
     * exactement là où il y a une information.
     */
    #[Test]
    public function un_mois_sans_mouvement_rend_zero_et_non_un_trou(): void
    {
        $serie = $this->service()->serieMensuelle(6);

        self::assertCount(6, $serie);
        foreach ($serie as $point) {
            self::assertSame('0.00', $point['depenses']);
            self::assertArrayHasKey('chiffre_affaires_encaisse', $point);
        }
    }

    /**
     * La série est ORDONNÉE du plus ancien au plus récent.
     *
     * Un graphique dont l'axe des temps remonte se lit à l'envers : une
     * hausse y ressemble à une baisse, et personne ne relit l'ordre des
     * étiquettes avant de conclure.
     */
    #[Test]
    public function la_serie_va_du_plus_ancien_au_plus_recent(): void
    {
        $serie = $this->service()->serieMensuelle(4);
        $mois = array_column($serie, 'mois');

        $trie = $mois;
        sort($trie);
        self::assertSame($trie, $mois);
        self::assertSame(now()->format('Y-m'), end($mois));
    }

    /**
     * Le nombre de mois est BORNÉ, des deux côtés.
     *
     * Sans borne haute, `?mois=600` ferait exécuter 1 200 requêtes depuis une
     * URL que n'importe qui peut composer.
     */
    #[Test]
    public function le_nombre_de_mois_est_borne(): void
    {
        self::assertCount(1, $this->service()->serieMensuelle(0));
        self::assertCount(1, $this->service()->serieMensuelle(-5));
        self::assertCount(
            TableauDeBordService::MOIS_MAX,
            $this->service()->serieMensuelle(600),
        );
    }

    /**
     * La ventilation par activité somme des MONTANTS FACTURÉS.
     *
     * Ce n'est pas la mesure du prototype, qui compte les réservations par
     * service : le schéma serveur ne porte aucun service sur `reservations`,
     * et la compter reviendrait à l'inventer.
     */
    #[Test]
    public function la_ventilation_par_activite_somme_les_montants_factures(): void
    {
        $facture = $this->facture('30000.00');
        $this->ligneFacture($facture, 'hebergement', '25000.00');
        $this->ligneFacture($facture, 'bar', '5000.00');

        $ventilation = $this->service()->ventilationParActivite($this->periode());
        $parModule = array_column($ventilation, 'montant', 'module');

        self::assertSame('25000.00', $parModule['hebergement']);
        self::assertSame('5000.00', $parModule['bar']);
        // Une activite sans ligne n'apparait pas : afficher « restaurant :
        // 0 F » sur un doughnut ajouterait une part invisible et une entree
        // de legende qui ne correspond a rien.
        self::assertArrayNotHasKey('restaurant', $parModule);
    }

    /**
     * L'activité la plus lourde vient EN TÊTE.
     *
     * Un doughnut se lit par sa légende : l'ordre y remplace la comparaison
     * visuelle, que l'œil fait mal sur des parts proches.
     */
    #[Test]
    public function la_ventilation_est_ordonnee_par_montant_decroissant(): void
    {
        $facture = $this->facture('30000.00');
        $this->ligneFacture($facture, 'bar', '5000.00');
        $this->ligneFacture($facture, 'hebergement', '25000.00');

        $ventilation = $this->service()->ventilationParActivite($this->periode());

        self::assertSame('hebergement', $ventilation[0]['module']);
        self::assertSame('bar', $ventilation[1]['module']);
    }

    #[Test]
    public function l_api_expose_les_series(): void
    {
        $facture = $this->facture('30000.00');
        $this->ligneFacture($facture, 'tourisme', '30000.00');
        \Laravel\Sanctum\Sanctum::actingAs($this->gerant);

        $this->getJson('/api/v1/tableau-de-bord/series?mois=3')
            ->assertOk()
            ->assertJsonCount(3, 'data.mensuelle')
            ->assertJsonPath('data.ventilation_activite.0.module', 'tourisme')
            ->assertJsonStructure([
                'data' => [
                    'mensuelle' => [['mois', 'debut', 'chiffre_affaires_encaisse', 'depenses']],
                    'ventilation_activite' => [['module', 'montant']],
                    'periode' => ['code', 'libelle'],
                ],
            ]);
    }

    #[Test]
    public function l_api_des_series_refuse_un_nombre_de_mois_hors_borne(): void
    {
        \Laravel\Sanctum\Sanctum::actingAs($this->gerant);

        $this->getJson('/api/v1/tableau-de-bord/series?mois=600')
            ->assertStatus(422);
    }

    /**
     * Le rôle sans accès est CHERCHÉ dans la matrice, jamais nommé en dur.
     *
     * Première version : « barman ». Il a `M11 => 'L'`, et le test échouait en
     * 200 — sur un code parfaitement juste. Figer un nom de rôle, c'est
     * recopier la matrice à un second endroit, et c'est la copie qui se
     * trompe.
     */
    #[Test]
    public function l_api_des_series_est_refusee_sans_droit_sur_m11(): void
    {
        $sansAcces = Role::all()->first(fn (Role $role): bool => $role->niveauSurModule('M11') === '-');

        if ($sansAcces === null) {
            $this->markTestSkipped('Tous les rôles ont accès à M11 dans la matrice.');
        }

        \Laravel\Sanctum\Sanctum::actingAs($this->compteAvecRole($sansAcces));

        $this->getJson('/api/v1/tableau-de-bord/series')->assertStatus(403);
    }

    /**
     * Une ligne de facture, avec son activité d'origine (RG-04).
     */
    private function ligneFacture(string $factureId, string $module, string $montant): void
    {
        DB::table('lignes_facture')->insert([
            'id' => (string) Str::uuid(),
            'facture_id' => $factureId,
            'source_module' => $module,
            'source_id' => (string) Str::uuid(),
            'libelle' => 'Ligne ' . $module,
            'quantite' => '1.00',
            'prix_unitaire' => $montant,
            'montant' => $montant,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

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
