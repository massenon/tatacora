<?php

declare(strict_types=1);

namespace Tests\Feature\ProcessusMetiers;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Bar\Services\VenteBarService;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\ClientHistoriqueService;
use App\Domain\Facturation\Exceptions\FactureImmuableException;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\DisponibiliteService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\TvaReferentielSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Processus métier n°1 — Cycle de séjour client.
 *
 * « Réservation → Confirmation (M12) → Check-in → Consommation de services
 * annexes (M4/M5/M9/M8) → Check-out → Facturation consolidée (M2) →
 * Encaissement » (05_MODULE_SPECIFICATIONS.md §5).
 *
 * ## Périmètre réellement couvert
 *
 * Trois maillons de la chaîne documentée ne sont pas implémentés et ne sont
 * donc pas exercés ici — les nommer explicitement évite de laisser croire que
 * le processus est validé de bout en bout :
 *
 * - **Confirmation (M12)** : domaine Notifications vide, canal WhatsApp absent.
 * - **Check-in / Check-out** : `CheckInService` et `CheckOutService` ne sont pas
 *   écrits ; le modèle `Sejour` existe mais n'est alimenté par rien.
 * - **Encaissement** : ni modèle `Paiement`, ni `SessionCaisse` (PA-21).
 *
 * Ce test couvre donc : réservation (M1) → consommation bar (M5 → M6) →
 * facturation consolidée (M2 → RG-04) → historique client (M3).
 */
final class CycleSejourClientTest extends TestCase
{
    use RefreshDatabase;

    private Client $client;

    private UniteHebergement $unite;

    private CarteBoisson $biere;

    private Article $articleBiere;

    private PointStockage $bar;

    private string $sessionCaisseId;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        // Comptes de TVA du fichier du PO (plus semés par TvaReferentielSeeder).
        foreach ([['4431', 'T.V.A. facturée sur ventes'], ['4432', 'T.V.A. facturée sur prestations de services'], ['4452', 'T.V.A. récupérable sur achats']] as [$n, $l]) {
            \App\Domain\Comptabilite\Models\CompteComptable::firstOrCreate(['numero_compte' => $n], ['libelle' => $l, 'classe' => '4', 'nature' => 'passif']);
        }
        $this->seed(TvaReferentielSeeder::class);

        $utilisateur = $this->utilisateur('receptionniste');
        $this->actingAs($utilisateur);

        $this->client = Client::factory()->create(['type_client' => 'particulier']);

        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow', 'capacite_max' => 4, 'tarif_base' => '25000.00',
        ]);
        $this->unite = UniteHebergement::create([
            'categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre',
        ]);

        $this->bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $this->articleBiere = Article::create([
            'libelle' => 'Bière 65cl', 'categorie' => 'boisson', 'unite_mesure' => 'bouteille',
            'seuil_alerte' => '10.00', 'seuil_reappro' => '24.00', 'cout_moyen_pondere' => '450.0000',
        ]);
        $this->biere = CarteBoisson::create([
            'article_id' => $this->articleBiere->id, 'libelle' => 'Bière 65cl',
            'categorie' => 'locale', 'prix_vente' => '1000.00',
        ]);
        app(MouvementStockService::class)->entree($this->articleBiere->id, $this->bar->id, '48.00', 'Réception');

        $this->sessionCaisseId = (string) Str::uuid();
        DB::table('sessions_caisse')->insert([
            'id' => $this->sessionCaisseId, 'point_vente' => 'bar',
            'utilisateur_ouverture_id' => $utilisateur->id,
            'date_ouverture' => now(), 'montant_fond' => '10000.00',
        ]);
    }

    #[Test]
    public function le_sejour_va_de_la_reservation_a_la_facture_consolidee(): void
    {
        $disponibilite = app(DisponibiliteService::class);
        $reservations = app(ReservationService::class);

        // --- 1. L'unité est disponible avant réservation (M1, RG-02)
        $this->assertTrue($disponibilite->uniteEstDisponible($this->unite->id, '2026-09-01', '2026-09-04'));

        $reservation = $reservations->creer([
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01', 'date_depart' => '2026-09-04',
            'statut' => 'confirmee', 'acompte' => '25000.00',
        ]);

        // --- 2. Elle ne l'est plus (RG-01), et c'est calculé, pas stocké
        $this->assertFalse($disponibilite->uniteEstDisponible($this->unite->id, '2026-09-02', '2026-09-03'));
        $this->assertSame('libre', $this->unite->fresh()->statut, 'Le statut opérationnel n\'est pas la disponibilité.');

        // --- 3. Consommation annexe au bar pendant le séjour (M5 → M6)
        $vente = app(VenteBarService::class)->enregistrer(
            $this->sessionCaisseId,
            [['boisson_id' => $this->biere->id, 'quantite' => 6]],
            clientId: $this->client->id,
        );

        $this->assertSame('42.00', app(StockTheoriqueService::class)->stock($this->articleBiere->id, $this->bar->id));
        $this->assertSame('6000.00', $vente->montant);

        // --- 4. Facturation consolidée (M2, RG-04) : hébergement + bar
        $emission = app(EmissionFactureService::class);
        $facture = $emission->emettrePourReservation($reservation, '25000.00');
        $emission->ajouterLigne($facture, 'M5', $vente->id, 'Consommations bar', '6.00', '1000.00');

        $facture->refresh();

        $this->assertCount(2, $facture->lignes()->get());
        $this->assertEqualsCanonicalizing(
            ['M1', 'M5'],
            $facture->lignes()->pluck('source_module')->all(),
        );
        // 3 nuitées × 25 000 + 6 bières × 1 000 — TVA inactive par défaut.
        $this->assertSame('81000.00', $facture->montant_ttc);

        // --- 5. Certification puis immutabilité (RG-03)
        $certifiee = $emission->certifier($facture);
        $this->assertTrue($certifiee->estCertificationDemonstration());

        $this->assertThrows(
            fn () => $certifiee->update(['montant_ttc' => '1.00']),
            FactureImmuableException::class,
        );

        // --- 6. Le séjour apparaît dans l'historique client (M3, EF-M3-02)
        $historique = app(ClientHistoriqueService::class)->pourClient($this->client->id);
        $this->assertCount(1, $historique['sejours']);
        $this->assertSame(3, app(ClientHistoriqueService::class)->statistiques($this->client->id)['nb_nuitees_totales']);

        // ...mais l'historique se déclare INCOMPLET : la facture émise plus haut
        // n'y figure pas, car M2 n'est pas encore une source branchée.
        $this->assertFalse($historique['complet']);
    }

    /**
     * RG-02 de bout en bout : une annulation doit rendre l'unité réservable
     * immédiatement, sans traitement intermédiaire.
     */
    #[Test]
    public function une_annulation_libere_l_unite_pour_un_autre_client(): void
    {
        $reservations = app(ReservationService::class);
        $disponibilite = app(DisponibiliteService::class);

        $premiere = $reservations->creer([
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01', 'date_depart' => '2026-09-04',
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);

        $reservations->annuler($premiere);

        // Aucun job, aucun cache : un second client réserve la même période.
        $autreClient = Client::factory()->create();
        $seconde = $reservations->creer([
            'client_id' => $autreClient->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01', 'date_depart' => '2026-09-04',
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);

        $this->assertTrue($disponibilite->uniteEstDisponible($this->unite->id, '2026-09-05', '2026-09-06'));
        $this->assertSame($autreClient->id, $seconde->client_id);
        $this->assertSame('annulee', $premiere->fresh()->statut);
    }

    /**
     * Chaîne complète avec TVA active : le paramétrage doit traverser tous les
     * modules sans qu'aucun ne recalcule la taxe à sa façon.
     */
    #[Test]
    public function la_tva_activee_traverse_toute_la_chaine_de_facturation(): void
    {
        \App\Shared\Parametres\Models\ParametreSysteme::where('cle', CalculTvaService::CLE_PARAMETRE_ACTIVE)
            ->update(['valeur' => 'true']);

        $reservation = app(ReservationService::class)->creer([
            'client_id' => $this->client->id, 'unite_id' => $this->unite->id,
            'date_arrivee' => '2026-09-01', 'date_depart' => '2026-09-02',
            'statut' => 'confirmee', 'acompte' => '0.00',
        ]);

        $facture = app(EmissionFactureService::class)->emettrePourReservation($reservation, '25000.00');

        // Convention TTC depuis la décision du PO (01/09/2026) : le tarif
        // du catalogue INCLUT la taxe — elle s'extrait, ne s'ajoute pas, et
        // le prix affiché au client reste exactement 25 000.
        $this->assertSame('21186.44', $facture->montant_ht);
        $this->assertSame('3813.56', $facture->montant_tva);
        $this->assertSame('25000.00', $facture->montant_ttc);

        // Cohérence arithmétique vérifiée par bccomp, jamais en flottant.
        $this->assertSame(
            0,
            bccomp(bcadd($facture->montant_ht, $facture->montant_tva, 2), $facture->montant_ttc, 2),
        );
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
