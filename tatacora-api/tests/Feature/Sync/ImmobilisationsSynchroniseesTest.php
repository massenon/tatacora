<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\Immobilisation;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les immobilisations saisies sur un poste (onglet « Immobilisations » du hub,
 * 21/10/2026) : créées par `ImmobilisationService` sous l'UUID du poste, le code
 * du serveur rendu à l'accusé, rejouées sans doublon, refusées aux phrases du
 * service, descendues vers les autres postes.
 */
final class ImmobilisationsSynchroniseesTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $comptable;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-21 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->comptable = $this->creerUtilisateur('comptable');
    }

    /**
     * @return array<string, mixed>
     */
    private function charge(array $surcharge = []): array
    {
        return [...[
            'libelle' => 'Toyota Land Cruiser Prado',
            'compte_immobilisation' => '231',
            'valeur_origine' => 1200000000,
            'date_mise_service' => '2026-03-20',
            'duree_annees' => 5,
        ], ...$surcharge];
    }

    #[Test]
    public function l_immobilisation_du_poste_est_creee_sous_son_uuid_et_le_code_du_serveur_revient(): void
    {
        $id = $this->uuid();
        $operation = $this->creation('immobilisations', $id, $this->charge());

        $reponse = $this->pousser([$operation], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.code', 'IMMO-2026-00001');

        $i = Immobilisation::findOrFail($id);
        $this->assertSame(['IMMO-2026-00001', '12000000.00', 5, '2026-03-20', '231'], [
            $i->code, (string) $i->valeur_origine, $i->duree_annees, $i->date_mise_service->toDateString(), $i->compte_immobilisation,
        ]);
        $this->assertNotNull($reponse);

        // Le rejeu du même document ne double rien et rend le même code.
        $this->pousser([$operation], $this->comptable)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(1, Immobilisation::query()->count());
    }

    #[Test]
    public function chaque_refus_porte_la_phrase_du_service(): void
    {
        $cas = [
            [['libelle' => '  '], 'immobilisation_libelle_requis'],
            [['valeur_origine' => 0], 'immobilisation_valeur_invalide'],
            [['valeur_origine' => -100], 'immobilisation_valeur_invalide'],
            [['duree_annees' => 0], 'immobilisation_duree_requise'],
            [['duree_annees' => null], 'immobilisation_duree_requise'],
            [['date_mise_service' => '20/03/2026'], 'immobilisation_date_invalide'],
            [['date_mise_service' => ''], 'immobilisation_date_invalide'],
        ];

        foreach ($cas as [$surcharge, $cle]) {
            $this->pousser([$this->creation('immobilisations', $this->uuid(), $this->charge($surcharge))], $this->comptable)
                ->assertJsonPath('resultats.0.statut', 'rejete')
                ->assertJsonPath('resultats.0.motif', __('comptabilite.' . $cle));
        }

        $this->pousser([$this->creation('immobilisations', $this->uuid(), $this->charge(['compte_immobilisation' => '9999']))], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('comptabilite.compte_inconnu', ['numero' => '9999']));

        $this->assertSame(0, Immobilisation::query()->count());
    }

    #[Test]
    public function une_modification_est_refusee_et_le_droit_est_celui_de_m10(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('immobilisations', $id, $this->charge())], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->pousser([$this->operation('immobilisations', 'modification', $id, ['libelle' => 'Autre'])], $this->comptable)
            ->assertJsonPath('resultats.0.statut', 'rejete');

        $sansDroit = $this->creerUtilisateur('cuisine');
        $this->pousser([$this->creation('immobilisations', $this->uuid(), $this->charge())], $sansDroit)
            ->assertJsonPath('resultats.0.statut', 'rejete');

        $this->assertSame(1, Immobilisation::query()->count());
        $this->assertSame('Toyota Land Cruiser Prado', Immobilisation::findOrFail($id)->libelle);
    }

    #[Test]
    public function l_immobilisation_descend_vers_les_autres_postes_sous_m10(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('immobilisations', $id, $this->charge())], $this->comptable, 'poste-a');

        $this->assertSame(
            ['code', 'libelle', 'compte_immobilisation', 'valeur_origine', 'date_mise_service', 'duree_annees'],
            CatalogueDescendantService::COLONNES['immobilisations'],
        );

        $ligne = collect($this->flux($this->comptable))->firstWhere('table', 'immobilisations');
        $this->assertSame($id, $ligne['id']);
        $this->assertSame('IMMO-2026-00001', $ligne['donnees']['code']);
        $this->assertSame('12000000.00', $ligne['donnees']['valeur_origine']);
        $this->assertSame('2026-03-20', substr((string) $ligne['donnees']['date_mise_service'], 0, 10));
        $this->assertSame(5, (int) $ligne['donnees']['duree_annees']);
        $this->assertSame('231', $ligne['donnees']['compte_immobilisation']);

        $this->assertNull(collect($this->flux($this->creerUtilisateur('guide')))->firstWhere('table', 'immobilisations'));
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function flux(User $utilisateur): array
    {
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($utilisateur);
        $elements = [];
        $curseur = null;

        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        return $elements;
    }
}
