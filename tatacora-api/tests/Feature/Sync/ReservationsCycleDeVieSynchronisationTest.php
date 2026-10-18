<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Models\User;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Le cycle de vie d'une réservation en synchronisation — lot F6, 17/10/2026.
 * Annulation par `AnnulationReservationService` (commission, remboursement et
 * sa pièce), déplacement par `ReservationService::modifier` (RG-01) ; la
 * réservation d'un autre poste ne s'annule que par l'administration ou le
 * comptable (Q3).
 */
final class ReservationsCycleDeVieSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $receptionniste;

    private UniteHebergement $b1;

    private UniteHebergement $b2;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-19 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->receptionniste = $this->creerUtilisateur('receptionniste');
        $categorie = CategorieHebergement::create(['libelle' => 'Bungalow', 'capacite_max' => 2, 'tarif_base' => '25000.00']);
        $this->b1 = UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'B-01', 'statut' => 'libre']);
        $this->b2 = UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'B-02', 'statut' => 'libre']);
        $this->client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'groupe']);
    }

    private function reserver(string $id, string $uniteId, string $arrivee, string $depart, string $poste = 'poste-a'): void
    {
        $this->pousser([$this->creation('reservations', $id, [
            'client_id' => $this->client->id, 'unite_id' => $uniteId,
            'date_arrivee' => $arrivee, 'date_depart' => $depart,
            'acompte' => '20000.00', 'mode_paiement' => 'especes', 'tarif_nuit' => '25000.00',
        ])], $this->receptionniste, $poste)->assertJsonPath('resultats.0.statut', 'synchronise');
    }

    /**
     * @return array<string, mixed>
     */
    private function annulation(string $id, string $taux = '20', string $mode = 'montant', string $valeur = '15000'): array
    {
        return $this->operation('reservations', 'modification', $id, [
            'statut' => 'annulee', 'taux' => $taux, 'mode_remboursement' => $mode, 'valeur_remboursement' => $valeur,
        ]);
    }

    #[Test]
    public function l_annulation_applique_les_conditions_du_service_une_seule_fois(): void
    {
        $id = $this->uuid();
        $this->reserver($id, $this->b1->id, '2026-10-25', '2026-10-27');

        $this->pousser([$this->annulation($id)], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $r = Reservation::findOrFail($id);
        $this->assertSame('annulee', $r->statut);
        $this->assertSame('50000.00', (string) $r->montant_total_annulation);
        $this->assertSame('10000.00', (string) $r->montant_commission_annulation);
        $this->assertSame('15000.00', (string) $r->montant_rembourse_annulation);
        $this->assertNotNull($r->ecriture_remboursement_id);

        // Rejeu : rendu tel quel, aucune seconde pièce.
        $this->travel(1)->minutes();
        $this->pousser([$this->annulation($id)], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame($r->ecriture_remboursement_id, Reservation::findOrFail($id)->ecriture_remboursement_id);
    }

    #[Test]
    public function les_refus_du_service_et_la_regle_des_autres_postes(): void
    {
        $id = $this->uuid();
        $this->reserver($id, $this->b1->id, '2026-10-25', '2026-10-27');

        $this->pousser([$this->annulation($id, valeur: '30000')], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('hebergement.annulation_remboursement_superieur_acompte'));

        $this->pousser([$this->annulation($id)], $this->receptionniste, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.annulation_autre_poste'));
        $this->assertSame('en_attente', Reservation::findOrFail($id)->statut);

        $this->pousser([$this->annulation($id)], $this->creerUtilisateur('administrateur'), 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('annulee', Reservation::findOrFail($id)->statut);
    }

    #[Test]
    public function le_deplacement_passe_par_rg_01(): void
    {
        [$a, $b] = [$this->uuid(), $this->uuid()];
        $this->reserver($a, $this->b1->id, '2026-10-25', '2026-10-27');
        $this->reserver($b, $this->b2->id, '2026-10-25', '2026-10-27', 'poste-b');

        // Vers une chambre prise : refusé (chevauchement).
        $this->pousser([$this->operation('reservations', 'modification', $a, ['unite_id' => $this->b2->id])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('hebergement.chevauchement'));

        $this->pousser([$this->operation('reservations', 'modification', $a, ['date_arrivee' => '2026-10-28', 'date_depart' => '2026-10-30', 'unite_id' => $this->b2->id])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $r = Reservation::findOrFail($a);
        $this->assertSame([$this->b2->id, '2026-10-28', '2026-10-30'], [$r->unite_id, $r->date_arrivee->toDateString(), $r->date_depart->toDateString()]);

        $this->pousser([$this->operation('reservations', 'modification', $a, ['acompte' => '0'])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.reservations.champ_non_modifiable', ['champs' => 'acompte']));
    }

    /**
     * Le cas du poste réel : création, déplacement puis annulation saisis
     * hors connexion AVANT la réception par le serveur, arrivés dans le même
     * lot — la suite du même document, par le même poste, jamais un conflit.
     */
    #[Test]
    public function creation_deplacement_et_annulation_hors_connexion_du_meme_poste(): void
    {
        $id = $this->uuid();
        $this->pousser([
            $this->operationDatee('reservations', 'creation', $id, [
                'client_id' => $this->client->id, 'unite_id' => $this->b1->id,
                'date_arrivee' => '2026-10-25', 'date_depart' => '2026-10-27',
                'acompte' => '8000.00', 'mode_paiement' => 'especes', 'tarif_nuit' => '25000.00',
            ], '2026-10-19T07:00:00+00:00'),
            $this->operationDatee('reservations', 'modification', $id, ['date_arrivee' => '2026-10-27', 'date_depart' => '2026-10-29'], '2026-10-19T07:05:00+00:00'),
            $this->operationDatee('reservations', 'modification', $id, [
                'statut' => 'annulee', 'taux' => '20.00', 'mode_remboursement' => 'montant', 'valeur_remboursement' => '4000.00',
            ], '2026-10-19T07:10:00+00:00'),
        ], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.2.statut', 'synchronise');

        $this->assertSame('annulee', Reservation::findOrFail($id)->statut);
    }

    /** Audit de couverture (18/10/2026) : les services descendent avec la réservation. */
    #[Test]
    public function les_services_d_une_reservation_descendent_avec_elle(): void
    {
        $id = $this->uuid();
        $this->reserver($id, $this->b1->id, '2026-10-25', '2026-10-27');
        $circuit = \App\Domain\Tourisme\Models\Circuit::create(['nom' => 'Kota', 'theme' => 'nature', 'zone' => 'Atacora', 'duree' => '1 jour', 'prix' => '15000', 'capacite_max' => 8]);
        app(\App\Domain\Hebergement\Services\ReservationService::class)
            ->remplacerLignes(Reservation::findOrFail($id), [['service' => 'tourisme', 'source_id' => $circuit->id, 'quantite' => '2']]);

        $this->travel(\App\Shared\Sync\Services\CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        \Laravel\Sanctum\Sanctum::actingAs($this->creerUtilisateur('administrateur'));
        $elements = [];
        $curseur = null;

        do {
            $r = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$r->json('data.elements')];
            $curseur = $r->json('meta.curseur');
        } while (! $r->json('meta.complet'));

        $resa = collect($elements)->firstWhere('id', $id);
        $this->assertSame([[
            'service' => 'tourisme', 'source_id' => $circuit->id, 'libelle' => 'Kota',
            'quantite' => '2.00', 'prix_unitaire' => '15000.00', 'montant' => '30000.00',
        ]], $resa['donnees']['lignes']);
    }
}
