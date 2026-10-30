<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Achats\Services\ReferentielFournisseurService;
use App\Domain\Bar\Services\CarteBoissonService;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\EnregistrementClientService;
use App\Domain\Crm\Services\ReferentielClientService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\AnnulationReservationService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le catalogue que les postes téléchargent — `GET /api/v1/referentiels`
 * (décision du Product Owner du 15/10/2026 : le serveur est maître).
 *
 * Ce que ces cas tiennent : un curseur qui ne perd ni ne double aucun élément
 * d'une page à l'autre (même quand tout le catalogue partage la même seconde),
 * un élément modifié après le curseur qui repasse, les archivés marqués et
 * jamais retirés, aucune valeur calculée descendue, le filtrage par module,
 * et les seules correspondances du poste demandeur.
 */
final class ReferentielsDescendantsTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $admin;

    /** @var array<string, string> */
    private array $ids = [];

    protected function setUp(): void
    {
        parent::setUp();
        // Horloge FIGÉE : tout le catalogue ci-dessous naît dans la même
        // seconde — le cas où seul l'`id` départage, et où un curseur sur
        // l'horodatage seul perdrait ou doublerait des éléments.
        $this->travelTo('2026-10-15 08:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->admin = $this->creerUtilisateur('administrateur');
        $this->semerCatalogue();
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
    }

    #[Test]
    public function la_pagination_rend_chaque_element_une_fois_et_une_seule(): void
    {
        $vus = [];
        $pages = 0;
        $curseur = null;

        do {
            $reponse = $this->telecharger($this->admin, depuis: $curseur, limite: 3)->assertOk();
            $this->assertLessThanOrEqual(3, count($reponse->json('data.elements')));

            foreach ($reponse->json('data.elements') as $element) {
                $vus[] = $element['table'] . ':' . $element['id'];
            }

            $curseur = $reponse->json('meta.curseur');
            $pages++;
        } while (! $reponse->json('meta.complet') && $pages < 50);

        $attendus = $this->tousLesElements();
        $this->assertCount(count($attendus), $vus, 'Un élément perdu ou doublé.');
        $this->assertSame([], array_diff_assoc(array_count_values($vus), array_fill_keys($vus, 1)));
        $this->assertEqualsCanonicalizing($attendus, $vus);
        $this->assertGreaterThanOrEqual(intdiv(count($attendus), 3), $pages);

        // L'ordre des tables : un élément cité descend avant celui qui le cite.
        $tables = array_values(array_unique(array_map(static fn (string $v): string => explode(':', $v)[0], $vus)));
        // (Les tables vides de ce jeu — les documents du lot F4 — n'y sont pas :
        // `DocumentsDescendantsTest` les sème.)
        $this->assertSame(
            array_values(array_filter(
                array_keys(CatalogueDescendantService::COLONNES),
                static fn (string $t): bool => DB::table($t)->exists(),
            )),
            $tables,
        );

        // À jour : le même curseur ne rend plus rien.
        $this->telecharger($this->admin, depuis: $curseur)
            ->assertJsonCount(0, 'data.elements')
            ->assertJsonPath('meta.complet', true);
    }

    /**
     * Un élément modifié APRÈS le passage du curseur repasse — et lui seul. La
     * composition d'une fiche aussi : elle vit dans `ingredients_recette`, que
     * rien ne date, et `remplacerComposition()` touche la fiche pour cela.
     */
    #[Test]
    public function un_element_modifie_apres_le_curseur_repasse_seul(): void
    {
        $curseur = $this->toutTelecharger($this->admin);

        $this->travel(60)->seconds();
        app(ReferentielArticleService::class)->modifier(Article::findOrFail($this->ids['riz']), ['seuil_alerte' => '7.50']);
        app(CompositionRecetteService::class)->remplacerComposition(Recette::findOrFail($this->ids['recette']), [
            ['article_id' => $this->ids['riz'], 'quantite_unitaire' => '0.200'],
        ]);

        // Dans l'horizon : pas encore servi (seconde non close).
        $this->telecharger($this->admin, depuis: $curseur)->assertJsonCount(0, 'data.elements');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        $reponse = $this->telecharger($this->admin, depuis: $curseur)->assertOk();

        $this->assertSame(
            ['articles:' . $this->ids['riz'], 'recettes:' . $this->ids['recette']],
            array_map(static fn (array $e): string => $e['table'] . ':' . $e['id'], $reponse->json('data.elements')),
        );
        $this->assertSame('7.50', $reponse->json('data.elements.0.donnees.seuil_alerte'));
        $this->assertSame(
            [['article_id' => $this->ids['riz'], 'quantite_unitaire' => '0.200']],
            $reponse->json('data.elements.1.donnees.lignes'),
        );
    }

    /**
     * Des DÉFINITIONS (leçon PA-129) : ni stock, ni coût moyen, ni dernier
     * prix d'achat, ni coût matière. Les archivés descendent, marqués.
     */
    #[Test]
    public function seules_les_definitions_descendent_et_les_archives_sont_marques(): void
    {
        $elements = collect($this->tousLesElementsDe($this->admin))->keyBy('id');

        $riz = $elements[$this->ids['riz']];
        $this->assertSame(
            ['libelle', 'categorie', 'unite_mesure', 'point_stockage_id', 'suivi', 'seuil_alerte', 'seuil_reappro'],
            array_keys($riz['donnees']),
        );
        $this->assertTrue($riz['actif']);
        $this->assertSame('2.00', $riz['donnees']['seuil_alerte']);

        $this->assertFalse($elements[$this->ids['archive']]['actif']);

        // 30/10/2026 (poste v47) : la description facultative d'un plat descend avec lui.
        $plat = $elements->first(static fn (array $e): bool => $e['table'] === 'plats' && $e['donnees']['libelle'] === 'Riz sauté');
        $this->assertSame('Riz, oignon, poivron', $plat['donnees']['description']);

        // Lot F3 : un client archivé descend marqué, son solde (calcul) non.
        $client = $elements[$this->ids['client']];
        $this->assertSame(['nom', 'prenom', 'telephone', 'email', 'type_client'], array_keys($client['donnees']));
        $this->assertTrue($client['actif']);
        $this->assertFalse($elements[$this->ids['client_archive']]['actif']);

        $reservation = $elements[$this->ids['reservation']];
        $this->assertSame('reservations', $reservation['table']);
        $this->assertSame($this->ids['client'], $reservation['donnees']['client_id']);
        $this->assertSame('2026-10-20', $reservation['donnees']['date_arrivee']);
        // Le tarif figé par le service (tarif de base de la catégorie), en
        // chaîne décimale ; ni le canal, ni l'écriture de remboursement.
        $this->assertSame('25000.00', $reservation['donnees']['tarif_nuit']);
        $this->assertSame('0.00', $reservation['donnees']['acompte']);
        $this->assertArrayNotHasKey('canal_id', $reservation['donnees']);
        $this->assertArrayNotHasKey('ecriture_remboursement_id', $reservation['donnees']);
        $this->assertFalse($elements[$this->ids['unite_hs']]['actif']);
        $this->assertTrue($elements[$this->ids['unite']]['actif']);

        $recette = $elements[$this->ids['recette']]['donnees'];
        $this->assertArrayNotHasKey('cout_matiere_calcule', $recette);
        $this->assertSame([['article_id' => $this->ids['riz'], 'quantite_unitaire' => '0.150']], $recette['lignes']);

        foreach ($elements as $element) {
            foreach (['cout_moyen_pondere', 'prix_achat', 'stock', 'cout_matiere_calcule', 'utilisateur_creation_id', 'solde', 'utilisateur_annulation_id'] as $interdit) {
                $this->assertArrayNotHasKey($interdit, $element['donnees'], $element['table']);
            }
        }
    }

    /**
     * Lot F3 — la question du Product Owner (16/10/2026) : « le poste B
     * aura-t-il ce que le poste A a enregistré ? ». Le client et la
     * réservation POUSSÉS par le poste A descendent au poste B ; la chambre
     * qu'il croyait libre ne l'est plus.
     */
    #[Test]
    public function ce_que_le_poste_a_pousse_descend_au_poste_b(): void
    {
        $curseurB = $this->toutTelecharger($this->admin);

        $this->travel(60)->seconds();
        $client = $this->uuid();
        $reservation = $this->uuid();
        $this->pousser([
            $this->creation('clients', $client, ['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'groupe']),
            $this->creation('reservations', $reservation, [
                'client_id' => $client, 'unite_id' => $this->ids['unite'],
                'date_arrivee' => '2026-11-02', 'date_depart' => '2026-11-04',
                'acompte' => '0.00', 'tarif_nuit' => '24000.00',
            ]),
        ], $this->admin, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise')->assertJsonPath('resultats.1.statut', 'synchronise');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        $elements = $this->tousLesElementsDe($this->admin, $curseurB);

        $this->assertSame(
            ['clients:' . $client, 'reservations:' . $reservation],
            array_map(static fn (array $e): string => $e['table'] . ':' . $e['id'], $elements),
        );
        $this->assertSame('24000.00', $elements[1]['donnees']['tarif_nuit']);
        $this->assertSame('2026-11-04', $elements[1]['donnees']['date_depart']);
    }

    /**
     * Une réservation annulée AU SERVEUR repasse, avec son statut et ses
     * conditions : le poste qui l'a prise libère la chambre.
     */
    #[Test]
    public function une_reservation_annulee_au_serveur_repasse_avec_ses_conditions(): void
    {
        $curseur = $this->toutTelecharger($this->admin);

        $this->travel(60)->seconds();
        app(AnnulationReservationService::class)->annuler(
            Reservation::findOrFail($this->ids['reservation']),
            ['taux' => '10', 'mode_remboursement' => 'montant', 'valeur_remboursement' => '0'],
            $this->admin,
        );

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        $reponse = $this->telecharger($this->admin, depuis: $curseur)->assertJsonCount(1, 'data.elements');

        $this->assertSame($this->ids['reservation'], $reponse->json('data.elements.0.id'));
        $this->assertSame('annulee', $reponse->json('data.elements.0.donnees.statut'));
        $this->assertSame('10.00', $reponse->json('data.elements.0.donnees.taux_annulation'));
        // 3 nuits × 25 000 = 75 000 ; 10 % = 7 500.
        $this->assertSame('75000.00', $reponse->json('data.elements.0.donnees.montant_total_annulation'));
        $this->assertSame('7500.00', $reponse->json('data.elements.0.donnees.montant_commission_annulation'));
        $this->assertNotNull($reponse->json('data.elements.0.donnees.date_annulation'));
    }

    /**
     * Un élément créé à l'instant n'est pas servi tant que sa seconde n'est
     * pas close (horizon de stabilité) — il l'est au téléchargement suivant.
     */
    #[Test]
    public function un_element_trop_recent_attend_le_telechargement_suivant(): void
    {
        $curseur = $this->toutTelecharger($this->admin);

        $nouveau = PointStockage::create(['libelle' => 'Garage annexe', 'type' => 'garage']);

        $this->telecharger($this->admin, depuis: $curseur)->assertJsonCount(0, 'data.elements');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        $this->telecharger($this->admin, depuis: $curseur)
            ->assertJsonCount(1, 'data.elements')
            ->assertJsonPath('data.elements.0.id', $nouveau->id);
    }

    /**
     * Une table ne descend que si l'utilisateur LIT son module. `barman` :
     * M3, M5 et M6 (parmi les tables descendues). Le curseur d'une table refusée n'avance pas : le
     * même curseur, présenté par un utilisateur qui lit tout, rend ces tables
     * depuis le début — et pas celles déjà servies.
     */
    #[Test]
    public function seules_les_tables_lisibles_descendent_et_leur_curseur_seul_avance(): void
    {
        $barman = $this->creerUtilisateur('barman');
        $curseur = null;
        $tables = [];

        do {
            $reponse = $this->telecharger($barman, depuis: $curseur, limite: 4);
            $tables = [...$tables, ...array_column($reponse->json('data.elements'), 'table')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        // `barman` lit aussi M3 (clients) ; pas M1 (réservations). Les rôles
        // (semés) descendent vers tout compte (lot 10e, `LECTURE_LIBRE`).
        $this->assertSame(['points_stockage', 'articles', 'cartes_boisson', 'clients', 'roles'], array_values(array_unique($tables)));

        $suite = array_values(array_unique(array_column(
            $this->tousLesElementsDe($this->admin, $curseur),
            'table',
        )));
        $this->assertSame(
            ['menus', 'recettes', 'plats', 'categories_hebergement', 'unites_hebergement', 'fournisseurs', 'reservations', 'centres_cout'],
            $suite,
        );
    }

    /**
     * Les correspondances de CE poste seulement, et seulement pour les tables
     * que l'utilisateur lit.
     */
    #[Test]
    public function seules_les_correspondances_du_poste_et_des_tables_lisibles_descendent(): void
    {
        $this->travel(-10)->seconds();
        $resolveur = app(ResolveurCorrespondances::class);
        $resolveur->enregistrer('poste-a', 'articles', $idArticleA = $this->uuid(), $this->ids['riz']);
        $resolveur->enregistrer('poste-a', 'fournisseurs', $this->uuid(), $this->ids['fournisseur']);
        $resolveur->enregistrer('poste-b', 'articles', $this->uuid(), $this->ids['riz']);
        $this->travel(10)->seconds();

        $barman = $this->creerUtilisateur('barman');
        $reponse = $this->telecharger($barman, poste: 'poste-a', limite: 500)->assertJsonPath('meta.complet', true);

        $this->assertSame(
            [['table' => 'articles', 'id_poste' => $idArticleA, 'id_serveur' => $this->ids['riz']]],
            $reponse->json('data.correspondances'),
        );

        $this->assertCount(2, $this->telecharger($this->admin, poste: 'poste-a', limite: 500)->json('data.correspondances'));
        $this->assertCount(1, $this->telecharger($this->admin, poste: 'poste-b', limite: 500)->json('data.correspondances'));

        // Déjà servies : le curseur ne les rend plus.
        $this->telecharger($barman, poste: 'poste-a', depuis: $reponse->json('meta.curseur'))
            ->assertJsonCount(0, 'data.correspondances');
    }

    /**
     * Le poste déclaré doit être celui du jeton — vérifié avec un jeton RÉEL
     * (`Sanctum::actingAs` court-circuite le nom du jeton, PA-54).
     */
    #[Test]
    public function le_poste_doit_etre_celui_du_jeton_et_les_parametres_sont_controles(): void
    {
        $jeton = $this->admin->createToken('poste-a')->plainTextToken;

        $this->withHeader('Authorization', 'Bearer ' . $jeton)
            ->getJson('/api/v1/referentiels?poste_id=poste-b')
            ->assertForbidden()
            ->assertJsonPath('message', __('sync.poste_non_reconnu'));

        $this->withHeader('Authorization', 'Bearer ' . $jeton)
            ->getJson('/api/v1/referentiels?poste_id=poste-a&limite=2')
            ->assertOk()
            ->assertJsonCount(2, 'data.elements');

        Sanctum::actingAs($this->admin);
        $this->getJson('/api/v1/referentiels?poste_id=poste-a&depuis=nimporte-quoi')
            ->assertUnprocessable()
            ->assertJsonPath('errors.depuis.0', __('sync.referentiels.curseur_invalide'));
        $this->getJson('/api/v1/referentiels?poste_id=poste-a&limite=501')->assertUnprocessable();
        $this->getJson('/api/v1/referentiels')->assertUnprocessable()->assertJsonValidationErrors('poste_id');
    }

    #[Test]
    public function sans_jeton_rien_ne_descend(): void
    {
        $this->getJson('/api/v1/referentiels?poste_id=poste-a')->assertUnauthorized();
    }

    // ---------------------------------------------------------------- Helpers

    private function semerCatalogue(): void
    {
        $point = PointStockage::create(['libelle' => 'Magasin', 'type' => 'magasin']);
        PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);

        $articles = app(ReferentielArticleService::class);
        $riz = $articles->creer([
            'libelle' => 'Riz', 'categorie' => 'Épicerie', 'unite_mesure' => 'kg', 'seuil_alerte' => '2', 'point_stockage_id' => $point->id,
        ]);
        $biere = $articles->creer(['libelle' => 'Bière', 'categorie' => 'Boissons', 'unite_mesure' => 'bouteille', 'seuil_alerte' => '24']);
        $archive = $articles->creer(['libelle' => 'Ancien savon', 'categorie' => 'Entretien', 'unite_mesure' => 'pièce', 'seuil_alerte' => '0']);
        $articles->archiver($archive);
        // Un coût moyen et un dernier prix d'achat existent en base : ils ne
        // doivent pas descendre.
        DB::table('articles')->where('id', $riz->id)->update(['cout_moyen_pondere' => '812.5000', 'prix_achat' => '800.00']);

        app(CarteBoissonService::class)->creer([
            'libelle' => 'Bière pression', 'article_id' => $biere->id, 'categorie' => 'locale', 'prix_vente' => '800',
        ]);

        $carte = app(CartePlatMenuService::class);
        $menu = $carte->creerMenu(['libelle' => 'Carte', 'type' => 'local']);
        $recette = app(ReferentielRecetteService::class)->creer(['libelle' => 'Riz sauté']);
        app(CompositionRecetteService::class)->remplacerComposition($recette, [
            ['article_id' => $riz->id, 'quantite_unitaire' => '0.150'],
        ]);
        $carte->creerPlat(['libelle' => 'Riz sauté', 'description' => 'Riz, oignon, poivron', 'menu_id' => $menu->id, 'recette_id' => $recette->id, 'prix_vente' => '2500']);

        $categorie = CategorieHebergement::create(['libelle' => 'Bungalow', 'capacite_max' => 2, 'tarif_base' => '25000.00']);
        $unite = UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre']);
        $uniteHs = UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'B-02', 'statut' => 'hors_service']);

        $fournisseur = app(ReferentielFournisseurService::class)->creer(['raison_sociale' => 'SOBEBRA']);
        CentreCout::create(['libelle' => 'Bar', 'type' => 'exploitation']);

        // Lot F3 : les tiers et les séjours descendent aussi.
        $clients = app(EnregistrementClientService::class);
        $client = Client::query()->findOrFail($clients->creer([
            'nom' => 'Kora', 'prenom' => 'Awa', 'telephone' => '97000001', 'type_client' => 'particulier',
        ])['client']->id);
        $clientArchive = Client::query()->findOrFail($clients->creer([
            'nom' => 'Ancien', 'telephone' => '97000002', 'type_client' => 'agence',
        ])['client']->id);
        app(ReferentielClientService::class)->archiver($clientArchive);
        DB::table('clients')->where('id', $client->id)->update(['solde' => '15000.00']);
        $reservation = app(ReservationService::class)->creer([
            'client_id' => $client->id, 'unite_id' => $unite->id,
            'date_arrivee' => '2026-10-20', 'date_depart' => '2026-10-23',
        ]);

        $this->ids = [
            'riz' => $riz->id, 'archive' => $archive->id, 'recette' => $recette->id,
            'unite' => $unite->id, 'unite_hs' => $uniteHs->id, 'fournisseur' => $fournisseur->id,
            'client' => $client->id, 'client_archive' => $clientArchive->id, 'reservation' => $reservation->id,
        ];
    }

    /**
     * @return list<string>
     */
    private function tousLesElements(): array
    {
        $tous = [];

        foreach (array_keys(CatalogueDescendantService::COLONNES) as $table) {
            foreach (DB::table($table)->pluck('id') as $id) {
                $tous[] = $table . ':' . $id;
            }
        }

        return $tous;
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function tousLesElementsDe(User $utilisateur, ?string $curseur = null): array
    {
        $elements = [];

        do {
            $reponse = $this->telecharger($utilisateur, depuis: $curseur, limite: 500);
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        return $elements;
    }

    private function toutTelecharger(User $utilisateur): string
    {
        $curseur = null;

        do {
            $reponse = $this->telecharger($utilisateur, depuis: $curseur, limite: 500);
            $curseur = (string) $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        return $curseur;
    }

    /**
     * @return TestResponse<\Illuminate\Http\JsonResponse>
     */
    private function telecharger(User $utilisateur, string $poste = 'poste-windows-1', ?string $depuis = null, ?int $limite = null): TestResponse
    {
        Sanctum::actingAs($utilisateur);

        $parametres = array_filter(['poste_id' => $poste, 'depuis' => $depuis, 'limite' => $limite], static fn ($v): bool => $v !== null);

        return $this->getJson('/api/v1/referentiels?' . http_build_query($parametres))->assertOk();
    }
}
