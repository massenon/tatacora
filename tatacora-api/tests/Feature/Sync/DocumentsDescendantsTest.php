<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Lot F4 — décision du Product Owner du 17/10/2026 : « on doit avoir aussi
 * les ventes, dépenses, caisses, commandes et réceptions … des autres postes.
 * NE PLUS LIMITER. » Le poste A pousse sa journée par le VRAI moteur ; le
 * flux du poste B la rend entière, avec le poste d'origine ; le flux du
 * poste A ne lui renvoie pas les entrées de stock de SA réception (il les a
 * écrites lui-même), et les rend au poste B.
 */
final class DocumentsDescendantsTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $admin;

    /** @var array<string, string> */
    private array $ids = [];

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerLeDecor();
        $this->toleranceDeReception('2');
        $this->admin = $this->creerUtilisateur('administrateur');
        $fournisseur = Fournisseur::create(['raison_sociale' => 'SOBEBRA']);

        $this->ids = [
            'session' => $this->uuid(), 'vente' => $this->uuid(), 'depense' => $this->uuid(),
            'commande' => $this->uuid(), 'bon' => $this->uuid(),
        ];

        $this->pousser([
            $this->operationDatee('sessions_caisse', 'creation', $this->ids['session'], [
                'point_vente' => 'bar', 'date_ouverture' => '2026-10-15 07:00:00', 'montant_fond_centimes' => 1000000,
            ], '2026-10-15T07:00:00+00:00'),
            $this->operationDatee('ventes', 'creation', $this->ids['vente'], [
                'type_vente' => 'comptant', 'mode_paiement' => 'especes', 'session_encaissement_id' => $this->ids['session'],
                'cloture_le' => '2026-10-15 09:30:00', 'point_vente' => 'Bar',
                'lignes' => [[
                    'module_source' => 'M5', 'code_article' => $this->biere->id, 'libelle' => 'Béninoise 65cl',
                    'prix_unitaire' => 1000, 'quantite' => 3,
                ]],
            ], '2026-10-15T09:30:00+00:00'),
            $this->operationDatee('depenses', 'creation', $this->ids['depense'], [
                'date_transaction' => '2026-10-15', 'tresorerie' => 'caisse', 'libelle' => 'Marché du matin',
                'centre_id' => CentreCout::where('libelle', 'Structure')->firstOrFail()->id, 'centre_libelle' => 'Structure',
                'lignes' => [['libelle' => 'Tomates', 'compte_charge' => '6011', 'nature' => 'Tomate', 'famille' => 'Marché', 'montant' => 12500]],
            ], '2026-10-15T08:00:00+00:00'),
            $this->operationDatee('commandes_achat', 'creation', $this->ids['commande'], [
                'fournisseur_id' => $fournisseur->id, 'date_commande' => '2026-10-15', 'statut' => 'envoyee',
                'lignes' => [[
                    'article_id' => $this->articleBiere->id, 'article_libelle' => 'Bière 65cl', 'unite_mesure' => 'bouteille',
                    'quantite_centiemes' => 2400, 'prix_unitaire_centimes' => 100000, 'rang' => 1,
                ]],
            ], '2026-10-15T08:10:00+00:00'),
            $this->operationDatee('bons_reception', 'creation', $this->ids['bon'], [
                'commande_id' => $this->ids['commande'], 'date_reception' => '2026-10-15', 'point_stockage_id' => $this->bar->id,
                'lignes' => [['article_id' => $this->articleBiere->id, 'quantite_centiemes' => 2400]],
            ], '2026-10-15T10:00:00+00:00'),
        ], $this->admin, 'poste-a');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
    }

    #[Test]
    public function la_journee_du_poste_a_descend_entiere_au_poste_b_avec_son_origine(): void
    {
        $elements = collect($this->tout('poste-b'))->keyBy('id');

        foreach ($this->ids as $cle => $id) {
            $this->assertTrue($elements->has($id), "« {$cle} » du poste A absent du flux du poste B");
            $this->assertSame('poste-a', $elements[$id]['poste_origine'], $cle);
        }

        $vente = $elements[$this->ids['vente']]['donnees'];
        $this->assertSame($this->ids['session'], $vente['session_id']);
        $this->assertSame('3000.00', $vente['montant_total']);
        $this->assertSame('especes', $vente['mode_paiement']);
        // 26/10/2026 : le NUMÉRO `V-` du serveur et le LOGIN de l'auteur descendent
        // (jamais l'identifiant du compte) — le poste B les affiche dans les ventes.
        $this->assertMatchesRegularExpression('/^V-\d{4}-\d{5}$/', (string) $vente['numero']);
        $this->assertSame($this->admin->login, $vente['par']);
        $this->assertArrayNotHasKey('utilisateur_id', $vente);
        $this->assertSame([[
            'code' => $this->biere->id, 'nom' => 'Béninoise 65cl', 'categorie' => $vente['lignes'][0]['categorie'],
            'module' => 'M5', 'prix_unitaire' => '1000.00', 'quantite' => 3, 'montant' => '3000.00',
        ]], $vente['lignes']);

        $depense = $elements[$this->ids['depense']]['donnees'];
        $this->assertSame('12500.00', $depense['montant_total']);
        $this->assertSame('6011', $depense['lignes'][0]['compte_charge']);
        // Jamais la pièce : le poste ne tient pas les écritures du serveur.
        $this->assertArrayNotHasKey('ecriture_id', $depense);

        $commande = $elements[$this->ids['commande']]['donnees'];
        $this->assertSame([['article_id' => $this->articleBiere->id, 'quantite_commandee' => '24.00', 'prix_unitaire' => '1000.00']], $commande['lignes']);

        // Les lignes du bon : les entrées de stock que le service a écrites.
        $this->assertSame(
            [['article_id' => $this->articleBiere->id, 'point_id' => $this->bar->id, 'quantite' => '24.00']],
            $elements[$this->ids['bon']]['donnees']['lignes'],
        );

        // Les tables arrivent dans l'ordre des clés étrangères.
        $ordre = array_keys(CatalogueDescendantService::COLONNES);
        $this->assertLessThan(array_search('ventes', $ordre, true), array_search('sessions_caisse', $ordre, true));
        $this->assertLessThan(array_search('bons_reception', $ordre, true), array_search('commandes_achat', $ordre, true));
        $this->assertLessThan(array_search('mouvements_stock', $ordre, true), array_search('bons_reception', $ordre, true));
    }

    /**
     * Le piège du double comptage : A a déjà écrit les entrées de SA
     * réception. Le serveur en écrit d'autres (ses identifiants) — elles
     * descendent vers B, jamais vers A. Les sorties de la vente, que A ne
     * tient pas localement (RG-05 non portée sur le poste), descendent vers
     * les deux.
     */
    #[Test]
    public function les_entrees_de_la_reception_ne_redescendent_pas_au_poste_qui_les_a_deja(): void
    {
        $entreesDuBon = DB::table('mouvements_stock')->where('type_mouvement', 'entree')
            ->where('motif', 'like', '%' . $this->ids['bon'] . '%')->pluck('id')->all();
        $this->assertCount(1, $entreesDuBon);

        $mouvementsVus = static fn (array $elements): array => array_column(
            array_filter($elements, static fn (array $e): bool => $e['table'] === 'mouvements_stock'),
            'id',
        );

        $pourA = $mouvementsVus($this->tout('poste-a'));
        $pourB = $mouvementsVus($this->tout('poste-b'));

        $this->assertNotContains($entreesDuBon[0], $pourA, 'A compterait sa réception deux fois');
        $this->assertContains($entreesDuBon[0], $pourB);

        $sortiesDeLaVente = DB::table('origines_synchronisation')
            ->where('table_concernee', 'mouvements_stock')->where('exclu_pour_poste', false)->pluck('entite_id')->all();
        // Plancher : la vente a bien produit ses sorties (sinon la boucle
        // ci-dessous serait vide, donc verte).
        $this->assertNotEmpty($sortiesDeLaVente, 'la vente n\'a produit aucune sortie de stock');
        foreach ($sortiesDeLaVente as $id) {
            $this->assertContains($id, $pourA);
            $this->assertContains($id, $pourB);
        }

        // Le document lui-même, lui, redescend à A (ses changements d'état).
        $this->assertContains($this->ids['bon'], array_column($this->tout('poste-a'), 'id'));
    }

    #[Test]
    public function un_document_saisi_au_serveur_n_a_pas_de_poste_d_origine(): void
    {
        $this->actingAs($this->admin);
        $mouvement = app(MouvementStockService::class)->entree($this->articleRiz->id, $this->cuisine->id, '5.00', 'Inventaire PWA');
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();

        $element = collect($this->tout('poste-b'))->firstWhere('id', $mouvement->id);
        $this->assertNotNull($element);
        $this->assertNull($element['poste_origine']);
        $this->assertSame('5.00', $element['donnees']['quantite']);
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function tout(string $poste): array
    {
        $elements = [];
        $curseur = null;

        do {
            $reponse = $this->telecharger($poste, $curseur);
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        return $elements;
    }

    /**
     * @return TestResponse<\Illuminate\Http\JsonResponse>
     */
    private function telecharger(string $poste, ?string $depuis): TestResponse
    {
        Sanctum::actingAs($this->admin);
        $parametres = array_filter(['poste_id' => $poste, 'depuis' => $depuis, 'limite' => 500], static fn ($v): bool => $v !== null);

        return $this->getJson('/api/v1/referentiels?' . http_build_query($parametres))->assertOk();
    }
}
