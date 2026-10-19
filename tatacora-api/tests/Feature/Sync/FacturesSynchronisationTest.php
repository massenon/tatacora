<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\ReservationService;
use App\Models\User;
use App\Shared\Sync\Gestionnaires\GestionnaireFactures;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Les factures émises sur un poste — lot F5c, décisions du PO du 17/10/2026
 * (Q2 : facture PROVISOIRE au poste, numéro continu attribué par le serveur,
 * régularisation ; « F-AAAA-NNNNN au serveur »).
 */
final class FacturesSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $receptionniste;

    private Reservation $reservation;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-19 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->receptionniste = $this->creerUtilisateur('receptionniste');
        $categorie = CategorieHebergement::create(['libelle' => 'Bungalow', 'capacite_max' => 2, 'tarif_base' => '25000.00']);
        $unite = UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre']);
        $client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'groupe']);
        $this->reservation = app(ReservationService::class)->creer([
            'client_id' => $client->id, 'unite_id' => $unite->id, 'date_arrivee' => '2026-10-17', 'date_depart' => '2026-10-19',
        ]);
    }

    /**
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function facture(string $id, array $surcharges = []): array
    {
        return $this->operationDatee('factures', 'creation', $id, [
            'origine' => 'pos_sejour',
            'numero_provisoire' => 'PROV-2026-00001',
            'date_emission' => '2026-10-19',
            'reservation_id' => $this->reservation->id,
            'lignes' => [
                ['module' => 'M1', 'libelle' => 'Hébergement — 2 nuit(s)', 'prix_unitaire' => 25000, 'quantite' => 2],
                ['module' => 'M4', 'libelle' => 'Riz sauce', 'prix_unitaire' => 2500, 'quantite' => 1],
            ],
            ...$surcharges,
        ], '2026-10-19T09:00:00+00:00');
    }

    #[Test]
    public function le_serveur_attribue_le_numero_continu_et_le_rend_au_poste(): void
    {
        [$a, $b] = [$this->uuid(), $this->uuid()];

        $reponse = $this->pousser([$this->facture($a), $this->facture($b, ['origine' => 'facture_directe', 'reservation_id' => null])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero', 'F-2026-00001')
            ->assertJsonPath('resultats.1.numero', 'F-2026-00002');

        $facture = Facture::with('lignes')->findOrFail($a);
        $this->assertSame('F-2026-00001', $facture->numero);
        $this->assertSame('pos_sejour', $facture->origine);
        $this->assertSame($this->reservation->client_id, $facture->client_id);
        $this->assertSame('2026-10-19', $facture->date_emission->toDateString());
        // Le PRIX VENDU est gardé ; le service a calculé les totaux.
        $this->assertSame(['25000.00', '2500.00'], $facture->lignes->sortBy('source_module')->pluck('prix_catalogue')->map(fn ($v) => (string) $v)->values()->all());
        $this->assertSame($this->reservation->id, $facture->lignes->firstWhere('source_module', 'M1')->source_id);
        $this->assertSame((string) $facture->montant_ttc, $reponse->json('resultats.0.montant_ttc'));
    }

    #[Test]
    public function une_facture_de_passage_porte_le_client_de_passage_unique(): void
    {
        $this->pousser([
            $this->facture($this->uuid(), ['origine' => 'pos_comptant', 'reservation_id' => null, 'lignes' => [['module' => 'M5', 'libelle' => 'Bière', 'prix_unitaire' => 1000, 'quantite' => 2]]]),
            $this->facture($this->uuid(), ['origine' => 'pos_comptant', 'reservation_id' => null, 'lignes' => [['module' => 'M5', 'libelle' => 'Bière', 'prix_unitaire' => 1000, 'quantite' => 1]]]),
        ], $this->receptionniste)->assertJsonPath('resultats.1.statut', 'synchronise');

        $this->assertSame(1, Client::query()->where('nom', GestionnaireFactures::CLIENT_DE_PASSAGE['nom'])->count());
    }

    #[Test]
    public function un_rejeu_rend_le_meme_numero_sans_en_bruler_un(): void
    {
        $op = $this->facture($this->uuid());
        $this->pousser([$op], $this->receptionniste);
        $this->pousser([[...$op, 'uuid_operation' => $this->uuid()]], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero', 'F-2026-00001');

        $this->assertSame(1, Facture::count());
        $this->assertSame('F-2026-00002', app(EmissionFactureService::class)->emettreVide((string) $this->reservation->client_id)->numero);
    }

    #[Test]
    public function l_annulation_emet_l_avoir_numerote_une_seule_fois(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->facture($id)], $this->receptionniste);

        $annulation = $this->operation('factures', 'modification', $id, ['statut' => 'annulee', 'motif' => 'Erreur de chambre']);
        $this->pousser([$annulation], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero_avoir', 'AV-2026-00001');
        $this->pousser([[...$annulation, 'uuid_operation' => $this->uuid(), 'horodatage_client' => now()->addMinute()->toIso8601String()]], $this->receptionniste)
            ->assertJsonPath('resultats.0.numero_avoir', 'AV-2026-00001');

        $avoir = Avoir::query()->where('facture_id', $id)->sole();
        $this->assertSame((string) Facture::findOrFail($id)->montant_ttc, (string) $avoir->montant);
        $this->assertSame('Erreur de chambre', $avoir->motif);
    }

    #[Test]
    public function une_facture_emise_sur_la_pwa_est_numerotee_par_la_meme_sequence(): void
    {
        $this->pousser([$this->facture($this->uuid())], $this->receptionniste);
        $pwa = app(EmissionFactureService::class)->emettrePourConsommations($this->reservation);

        $this->assertSame('F-2026-00002', $pwa->numero);
    }

    #[Test]
    public function une_reservation_inconnue_refuse_la_facture_avec_sa_phrase(): void
    {
        $this->pousser([$this->facture($this->uuid(), ['reservation_id' => $this->uuid()])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.factures.reservation_inconnue'));

        $this->assertSame(0, Facture::count());
    }

    #[Test]
    public function la_facture_et_son_avoir_descendent_aux_autres_postes_avec_leur_numero(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->facture($id)], $this->receptionniste, 'poste-a');
        $this->pousser([$this->operation('factures', 'modification', $id, ['statut' => 'annulee', 'motif' => 'Erreur'])], $this->receptionniste, 'poste-a');
        $this->travel(\App\Shared\Sync\Services\CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();

        \Laravel\Sanctum\Sanctum::actingAs($this->receptionniste);
        $elements = collect($this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-b', 'limite' => 500]))
            ->assertOk()->json('data.elements'));

        $facture = $elements->firstWhere('id', $id);
        $this->assertSame('poste-a', $facture['poste_origine']);
        $this->assertSame('F-2026-00001', $facture['donnees']['numero']);
        $this->assertSame('pos_sejour', $facture['donnees']['origine']);
        $this->assertSame(['25000.00', '2500.00'], array_column($facture['donnees']['lignes'], 'prix_catalogue'));

        $avoir = $elements->first(fn (array $e): bool => $e['table'] === 'avoirs');
        $this->assertSame($id, $avoir['donnees']['facture_id']);
        $this->assertSame('AV-2026-00001', $avoir['donnees']['numero']);
    }
}
