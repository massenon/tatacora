<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
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
 * A5 (28/10/2026) : la PURGE définitive d'une unité d'hébergement ou d'un véhicule
 * archivé voyage par la synchronisation (`suppression`, registre fermé) et
 * redescend vers les autres postes. Le serveur REJOUE le service de parc : mêmes
 * verrous, mêmes phrases que l'écran « Archives » du web.
 */
final class PurgeSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $superAdmin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-28 08:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->superAdmin = $this->creerUtilisateur('super_admin');
    }

    private function unite(string $statut = 'hors_service'): UniteHebergement
    {
        $categorie = CategorieHebergement::firstOrCreate(['libelle' => 'Bungalow'], ['tarif_base' => '25000', 'capacite_max' => 2]);

        return UniteHebergement::create(['numero' => 'BNG-' . random_int(10, 99), 'categorie_id' => $categorie->id, 'statut' => $statut]);
    }

    private function vehicule(string $statut = 'hors_service'): Vehicule
    {
        return Vehicule::create(['immatriculation' => 'BJ-' . random_int(100, 999), 'categorie' => 'voiture', 'annee' => 2020, 'tarif_jour' => '25000', 'statut' => $statut]);
    }

    /** @return array<string, mixed> */
    private function purge(string $table, string $id): array
    {
        return $this->operation($table, 'suppression', $id, ['libelle' => 'x']);
    }

    private function reservationSur(UniteHebergement $unite, string $arrivee, string $depart, string $statut = 'confirmee'): void
    {
        $client = Client::create(['nom' => 'Sabi', 'telephone' => '9600' . random_int(1000, 9999), 'type_client' => 'particulier']);
        Reservation::create(['client_id' => $client->id, 'unite_id' => $unite->id, 'date_arrivee' => $arrivee, 'date_depart' => $depart, 'statut' => $statut]);
    }

    #[Test]
    public function une_unite_archivee_se_purge_et_le_rejeu_est_idempotent(): void
    {
        $unite = $this->unite();
        $operation = $this->purge('unites_hebergement', $unite->id);

        $this->pousser([$operation], $this->superAdmin)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertNull(UniteHebergement::find($unite->id));
        $this->assertTrue(DB::table('suppressions_synchronisation')->where('entite_id', $unite->id)->where('table_concernee', 'unites_hebergement')->exists());

        // Rejeu (même opération, puis une autre tentative sur l'élément disparu) : un accusé, rien d'écrit.
        $this->pousser([$operation], $this->superAdmin)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$this->purge('unites_hebergement', $unite->id)], $this->superAdmin)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.deja_supprime', true);
        $this->assertSame(1, DB::table('suppressions_synchronisation')->count());
    }

    #[Test]
    public function un_vehicule_archive_se_purge(): void
    {
        $vehicule = $this->vehicule();

        $this->pousser([$this->purge('vehicules', $vehicule->id)], $this->superAdmin)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertNull(Vehicule::find($vehicule->id));
    }

    #[Test]
    public function les_verrous_et_les_phrases_sont_ceux_du_service_de_parc(): void
    {
        $actif = $this->unite('libre');
        $this->pousser([$this->purge('unites_hebergement', $actif->id)], $this->superAdmin)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('pwa.import_export.purge_refusee_non_archive'));
        $this->assertNotNull(UniteHebergement::find($actif->id));

        $engagee = $this->unite();
        $this->reservationSur($engagee, '2026-11-02', '2026-11-05');
        $reponse = $this->pousser([$this->purge('unites_hebergement', $engagee->id)], $this->superAdmin);
        $reponse->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertStringContainsString('Élément engagé dans 1 opération(s)', (string) $reponse->json('resultats.0.motif'));

        $passee = $this->unite();
        $this->reservationSur($passee, '2026-09-02', '2026-09-05', 'terminee');
        $this->pousser([$this->purge('unites_hebergement', $passee->id)], $this->superAdmin)
            ->assertJsonPath('resultats.0.motif', __('pwa.import_export.purge_refusee_referencee'));
        $this->assertNotNull(UniteHebergement::find($passee->id));

        $vehicule = $this->vehicule();
        $client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'particulier']);
        ContratLocation::create(['vehicule_id' => $vehicule->id, 'client_id' => $client->id, 'date_debut' => '2026-09-01', 'date_fin' => '2026-09-03', 'piece_identite' => 'CNI', 'permis_conduire' => 'P']);
        $this->pousser([$this->purge('vehicules', $vehicule->id)], $this->superAdmin)
            ->assertJsonPath('resultats.0.motif', __('pwa.import_export.purge_refusee_referencee'));
        $this->assertNotNull(Vehicule::find($vehicule->id));
        $this->assertSame(0, DB::table('suppressions_synchronisation')->count());
    }

    #[Test]
    public function seul_le_super_administrateur_purge(): void
    {
        $unite = $this->unite();

        foreach (['administrateur', 'gerant'] as $role) {
            $this->pousser([$this->purge('unites_hebergement', $unite->id)], $this->creerUtilisateur($role))
                ->assertJsonPath('resultats.0.statut', 'rejete')
                ->assertJsonPath('resultats.0.code_motif', 'droit_manquant')
                ->assertJsonPath('resultats.0.motif', __('sync.suppression_reservee'));
        }

        $this->assertNotNull(UniteHebergement::find($unite->id));
    }

    #[Test]
    public function aucune_autre_table_ne_se_supprime(): void
    {
        $client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'particulier']);

        $this->pousser([$this->purge('clients', $client->id)], $this->superAdmin)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.code_motif', 'suppression_non_synchronisable');
        $this->assertNotNull(Client::find($client->id));
    }

    #[Test]
    public function la_purge_descend_vers_les_postes_apres_les_tables_et_son_curseur_avance(): void
    {
        $unite = $this->unite();
        $vehicule = $this->vehicule();
        $this->pousser([$this->purge('unites_hebergement', $unite->id), $this->purge('vehicules', $vehicule->id)], $this->superAdmin, 'poste-a');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();

        $elements = [];
        $curseur = null;
        do {
            Sanctum::actingAs($this->superAdmin);
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 1])))->assertOk();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        $supprimes = collect($elements)->where('supprime', true)->keyBy('id');
        $this->assertEqualsCanonicalizing([$unite->id, $vehicule->id], $supprimes->keys()->all());
        $this->assertSame('unites_hebergement', $supprimes[$unite->id]['table']);
        $this->assertFalse($supprimes[$unite->id]['actif']);
        $this->assertSame([], $supprimes[$unite->id]['donnees']);

        // Le curseur a avancé : plus rien à livrer.
        Sanctum::actingAs($this->superAdmin);
        $this->assertSame([], collect($this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-b', 'depuis' => $curseur]))->assertOk()->json('data.elements'))->where('supprime', true)->all());
    }

    #[Test]
    public function la_purge_de_l_ecran_web_laisse_la_meme_trace(): void
    {
        $unite = $this->unite();
        app(\App\Shared\ImportExport\Services\RegistreArchivesService::class)->purger('unite_hebergement', $unite->id);

        $this->assertTrue(DB::table('suppressions_synchronisation')->where('entite_id', $unite->id)->exists());
    }

    #[Test]
    public function un_poste_qui_ne_lit_pas_le_module_ne_recoit_pas_la_suppression(): void
    {
        $unite = $this->unite();
        $this->pousser([$this->purge('unites_hebergement', $unite->id)], $this->superAdmin);
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();

        $caissier = $this->creerUtilisateur('cuisine');
        Sanctum::actingAs($caissier);
        $elements = $this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-c', 'limite' => 500]))->assertOk()->json('data.elements');
        $this->assertSame([], collect($elements)->where('supprime', true)->all());
    }
}
