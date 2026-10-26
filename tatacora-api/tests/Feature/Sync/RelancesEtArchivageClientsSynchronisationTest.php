<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Models\RelanceClient;
use App\Domain\Crm\Services\ReferentielClientService;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les relances de clients et l'archivage d'un client saisis sur un poste
 * (21/10/2026, « tout au complet ») :
 *
 * - une relance est un FAIT daté, écrit par `RelanceClientService`, rejoué sans
 *   doublon, jamais modifié, descendu vers les autres postes ;
 * - `actif` d'un client archive ou restaure par `ReferentielClientService` —
 *   les quatre verrous (séjour, location, circuit, facture non soldée) et la
 *   règle d'archivage de la directive du 03/09/2026.
 */
final class RelancesEtArchivageClientsSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $gerant;

    private User $admin;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-21 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->gerant = $this->creerUtilisateur('gerant');
        $this->admin = $this->creerUtilisateur('administrateur');
        $this->client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'particulier']);
    }

    /**
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function relance(array $surcharges = []): array
    {
        return [
            'client_id' => $this->client->id,
            'date_relance' => '2026-10-20',
            'canal' => 'telephone',
            'montant_reclame' => '15000.00',
            'promesse' => '2026-10-30',
            'commentaire' => 'Rappelle vendredi',
            ...$surcharges,
        ];
    }

    // ------------------------------------------------------------ Relances

    #[Test]
    public function la_relance_du_poste_est_ecrite_par_le_service_et_son_rejeu_ne_double_rien(): void
    {
        $id = $this->uuid();
        $operation = $this->creation('relances_clients', $id, $this->relance());

        $this->pousser([$operation], $this->gerant, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');

        $r = RelanceClient::findOrFail($id);
        $this->assertSame(
            [$this->client->id, '2026-10-20', 'telephone', '15000.00', '2026-10-30', 'Rappelle vendredi'],
            [$r->client_id, $r->date_relance->toDateString(), $r->canal, (string) $r->montant_reclame, $r->promesse->toDateString(), $r->commentaire],
        );
        $this->assertDatabaseHas('origines_synchronisation', ['table_concernee' => 'relances_clients', 'entite_id' => $id, 'poste_id' => 'poste-a']);

        $this->pousser([[...$operation, 'uuid_operation' => $this->uuid()]], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(1, RelanceClient::query()->count());
    }

    #[Test]
    public function la_promesse_et_le_commentaire_sont_facultatifs_et_le_montant_nul_est_admis(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('relances_clients', $id, $this->relance([
            'promesse' => null, 'commentaire' => null, 'montant_reclame' => '0.00', 'canal' => 'visite',
        ]))], $this->gerant)->assertJsonPath('resultats.0.statut', 'synchronise');

        $r = RelanceClient::findOrFail($id);
        $this->assertNull($r->promesse);
        $this->assertNull($r->commentaire);
        $this->assertSame('0.00', (string) $r->montant_reclame);
    }

    #[Test]
    public function les_cas_invalides_sont_refuses_avec_les_phrases_du_serveur(): void
    {
        $refus = $this->pousser([
            $this->creation('relances_clients', $this->uuid(), $this->relance(['canal' => 'pigeon'])),
            $this->creation('relances_clients', $this->uuid(), $this->relance(['montant_reclame' => '-1.00'])),
            $this->creation('relances_clients', $this->uuid(), $this->relance(['date_relance' => '20/10/2026'])),
            $this->creation('relances_clients', $this->uuid(), $this->relance(['client_id' => $this->uuid()])),
        ], $this->gerant);

        foreach ([0, 1, 2, 3] as $i) {
            $refus->assertJsonPath("resultats.{$i}.statut", 'rejete');
        }
        $refus->assertJsonPath('resultats.3.motif', __('sync.crm.client_inconnu_relance'));
        $this->assertSame(0, RelanceClient::query()->count());
    }

    #[Test]
    public function le_droit_est_celui_de_m3_et_une_relance_ne_se_modifie_pas(): void
    {
        $sansDroit = $this->creerUtilisateur('cuisine');
        $this->pousser([$this->creation('relances_clients', $this->uuid(), $this->relance())], $sansDroit)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame(0, RelanceClient::query()->count());

        $id = $this->uuid();
        $this->pousser([$this->creation('relances_clients', $id, $this->relance())], $this->gerant);
        $this->pousser([$this->operation('relances_clients', 'modification', $id, ['montant_reclame' => '1.00'])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame('15000.00', (string) RelanceClient::findOrFail($id)->montant_reclame);
    }

    #[Test]
    public function la_relance_descend_vers_les_autres_postes_apres_son_client(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('relances_clients', $id, $this->relance())], $this->gerant, 'poste-a');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($this->gerant);
        $elements = collect($this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-b', 'limite' => 500]))
            ->assertOk()->json('data.elements'));

        $ligne = $elements->firstWhere('table', 'relances_clients');
        $this->assertSame($id, $ligne['id']);
        $this->assertSame('poste-a', $ligne['poste_origine']);
        $this->assertSame(
            ['client_id' => $this->client->id, 'date_relance' => '2026-10-20', 'canal' => 'telephone', 'montant_reclame' => '15000.00', 'promesse' => '2026-10-30', 'commentaire' => 'Rappelle vendredi'],
            $ligne['donnees'],
        );

        // Le client avant la relance qui le cite.
        $tables = $elements->pluck('table')->all();
        $this->assertLessThan(array_search('relances_clients', $tables, true), array_search('clients', $tables, true));
    }

    // ------------------------------------------------------------ Archivage

    #[Test]
    public function l_administrateur_archive_et_restaure_un_client_et_l_archive_descend(): void
    {
        $this->pousser([$this->operation('clients', 'modification', $this->client->id, ['actif' => false])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertFalse((bool) $this->client->fresh()->actif);

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($this->admin);
        $element = collect($this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-b', 'limite' => 500]))
            ->assertOk()->json('data.elements'))->firstWhere('id', $this->client->id);
        $this->assertFalse($element['actif']);

        $this->pousser([$this->operation('clients', 'modification', $this->client->id, ['actif' => true])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue((bool) $this->client->fresh()->actif);
    }

    #[Test]
    public function un_role_sans_droit_d_archivage_ne_range_pas_un_client_mais_peut_le_restaurer(): void
    {
        $this->pousser([$this->operation('clients', 'modification', $this->client->id, ['actif' => false])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('pwa.archivage.refus_bascule'));
        $this->assertTrue((bool) $this->client->fresh()->actif);

        app(ReferentielClientService::class)->archiver($this->client);
        $this->pousser([$this->operation('clients', 'modification', $this->client->id, ['actif' => true])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue((bool) $this->client->fresh()->actif);
    }

    #[Test]
    public function chacun_des_quatre_verrous_refuse_l_archivage_avec_sa_phrase(): void
    {
        $archiver = fn (Client $c): \Illuminate\Testing\TestResponse => $this->pousser(
            [$this->operation('clients', 'modification', $c->id, ['actif' => false])],
            $this->admin,
        );

        // 1. Un séjour à venir.
        $categorie = CategorieHebergement::create(['libelle' => 'Bungalow', 'capacite_max' => 2, 'tarif_base' => '25000.00']);
        $unite = UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre']);
        $sejour = Client::create(['nom' => 'Sejour', 'telephone' => '1', 'type_client' => 'particulier']);
        app(ReservationService::class)->creer([
            'client_id' => $sejour->id, 'unite_id' => $unite->id, 'date_arrivee' => '2026-10-25', 'date_depart' => '2026-10-27',
        ]);
        $archiver($sejour)->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('crm.archivage.verrou_sejour', ['nombre' => 1]));

        // 2. Une location non terminée.
        $loueur = Client::create(['nom' => 'Loueur', 'telephone' => '2', 'type_client' => 'particulier']);
        DB::table('vehicules')->insert(['id' => $v = $this->uuid(), 'immatriculation' => 'BJ-1', 'categorie' => 'voiture', 'annee' => 2020, 'tarif_jour' => '25000', 'statut' => 'disponible']);
        DB::table('contrats_location')->insert([
            'id' => $this->uuid(), 'vehicule_id' => $v, 'client_id' => $loueur->id, 'date_debut' => '2026-10-20',
            'date_fin' => '2026-10-23', 'numero' => 'LOC-1', 'statut' => 'en_cours', 'montant' => '75000',
        ]);
        $archiver($loueur)->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('crm.archivage.verrou_location', ['nombre' => 1]));

        // 3. Un circuit à venir.
        $touriste = Client::create(['nom' => 'Touriste', 'telephone' => '3', 'type_client' => 'particulier']);
        DB::table('circuits')->insert(['id' => $c = $this->uuid(), 'nom' => 'Kota', 'theme' => 'nature', 'zone' => 'Atacora', 'duree' => '', 'prix' => '15000', 'capacite_max' => 8]);
        DB::table('guides')->insert(['id' => $g = $this->uuid(), 'nom' => 'Moussa', 'zone_competence' => 'Atacora', 'tarif_jour' => '0']);
        DB::table('reservations_tour')->insert([
            'id' => $this->uuid(), 'circuit_id' => $c, 'guide_id' => $g, 'client_id' => $touriste->id, 'date_circuit' => '2026-11-01',
            'nb_participants' => 2, 'statut' => 'reservee',
        ]);
        $archiver($touriste)->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('crm.archivage.verrou_circuit', ['nombre' => 1]));

        // 4. Une facture non soldée.
        $debiteur = Client::create(['nom' => 'Debiteur', 'telephone' => '4', 'type_client' => 'particulier']);
        $emission = app(EmissionFactureService::class);
        $facture = $emission->emettreVide($debiteur->id);
        $emission->ajouterLigne($facture, 'M5', $facture->id, 'Bière', '2', '1000.00');
        $emission->certifier($facture->refresh());
        $archiver($debiteur)->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('crm.archivage.verrou_creance', ['nombre' => 1]));

        foreach ([$sejour, $loueur, $touriste, $debiteur] as $c) {
            $this->assertTrue((bool) $c->fresh()->actif);
        }

        // Un client sans engagement s'archive.
        $libre = Client::create(['nom' => 'Libre', 'telephone' => '5', 'type_client' => 'particulier']);
        $archiver($libre)->assertJsonPath('resultats.0.statut', 'synchronise');
    }

    #[Test]
    public function la_modification_d_une_fiche_et_l_archivage_peuvent_voyager_ensemble_et_actif_n_est_pas_ecrit_en_brut(): void
    {
        $this->pousser([$this->operation('clients', 'modification', $this->client->id, ['nom' => 'Sabi-Gounou', 'actif' => false])], $this->admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $c = $this->client->fresh();
        $this->assertSame('Sabi-Gounou', $c->nom);
        $this->assertFalse((bool) $c->actif);

        // À la création, `actif` est ignoré : une fiche naît active.
        $id = $this->uuid();
        $this->pousser([$this->creation('clients', $id, ['nom' => 'Nouveau', 'telephone' => '9', 'type_client' => 'particulier', 'actif' => false])], $this->admin);
        $this->assertTrue((bool) Client::findOrFail($id)->actif);
    }
}
