<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Domain\Tourisme\Models\Guide;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Lot L3-S (27/10/2026) : ce que le poste PORTE désormais descend aussi — la catégorie
 * d'un plat, l'année, les places et la transmission d'un véhicule, l'acompte, le
 * montant net et le N° `LOC-` d'un contrat, la certification et le tarif d'un guide.
 * Sans la descente, un poste ne verrait jamais ce qu'un autre poste ou le web a saisi.
 */
final class ChampsPosteDescendantsTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    #[Test]
    public function les_champs_portes_par_le_poste_descendent(): void
    {
        $this->travelTo('2026-10-27 08:00:00');
        $this->seed(RolePermissionSeeder::class);
        $admin = $this->creerUtilisateur('administrateur');

        $menu = app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Carte', 'type' => 'local']);
        $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Riz gras']);
        $plat = app(CartePlatMenuService::class)->creerPlat([
            'libelle' => 'Riz gras', 'menu_id' => $menu->id, 'recette_id' => $fiche->id,
            'prix_vente' => '2500', 'categorie' => 'sandwicherie',
        ]);
        $vehicule = Vehicule::create([
            'immatriculation' => 'BJ-D1', 'categorie' => 'voiture', 'annee' => 2022, 'capacite' => 5,
            'transmission' => 'Automatique', 'tarif_jour' => '25000', 'statut' => 'disponible',
        ]);
        $client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'particulier']);
        $contrat = ContratLocation::create([
            'vehicule_id' => $vehicule->id, 'client_id' => $client->id, 'date_debut' => '2026-11-01',
            'date_fin' => '2026-11-04', 'piece_identite' => 'CNI', 'permis_conduire' => 'P',
        ]);
        $contrat->forceFill(['numero' => 'LOC-0001', 'statut' => 'actif', 'montant' => '70000.00', 'acompte' => '20000.00', 'reste_a_payer' => '50000.00'])->save();
        $guide = Guide::create(['nom' => 'Moussa', 'certification' => 'Guide diplômé', 'zone_competence' => 'Atacora', 'tarif_jour' => '15000']);

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();

        $elements = [];
        $curseur = null;
        do {
            Sanctum::actingAs($admin);
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-1', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        $parId = collect($elements)->keyBy(static fn (array $e): string => $e['table'] . ':' . $e['id']);

        $this->assertSame('sandwicherie', $parId['plats:' . $plat->id]['donnees']['categorie']);
        $v = $parId['vehicules:' . $vehicule->id]['donnees'];
        $this->assertEquals([2022, 5, 'Automatique'], [$v['annee'], $v['capacite'], $v['transmission']]);
        $c = $parId['contrats_location:' . $contrat->id]['donnees'];
        $this->assertSame(['LOC-0001', '70000.00', '20000.00'], [$c['numero'], $c['montant'], $c['acompte']]);
        $g = $parId['guides:' . $guide->id]['donnees'];
        $this->assertSame(['Guide diplômé', '15000.00'], [$g['certification'], $g['tarif_jour']]);
    }
}
