<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Models\User;
use Database\Seeders\CanauxReservationSeeder;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Le cycle de vie d'une réservation en synchronisation — lot F6, 17/10/2026.
 * Annulation par `AnnulationReservationService` (commission, remboursement et
 * sa pièce), déplacement par `ReservationService::modifier` (RG-01). Le serveur ne juge
 * plus QUI annule (09/11/2026) : le contrôle est fait au poste (droit `ANNULATIONS`).
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

    private function reserver(string $id, string $uniteId, string $arrivee, string $depart, string $poste = 'poste-a', ?string $canal = null): void
    {
        $this->pousser([$this->creation('reservations', $id, [
            'client_id' => $this->client->id, 'unite_id' => $uniteId,
            'date_arrivee' => $arrivee, 'date_depart' => $depart,
            'acompte' => '20000.00', 'mode_paiement' => 'especes', 'tarif_nuit' => '25000.00',
            'canal' => $canal,
        ])], $this->receptionniste, $poste)->assertJsonPath('resultats.0.statut', 'synchronise');
    }

    #[Test]
    public function le_canal_monte_et_descend_par_son_nom_un_nom_inconnu_reste_sans_canal(): void
    {
        $this->seed(CanauxReservationSeeder::class);
        $booking = $this->uuid();
        $this->reserver($booking, $this->b1->id, '2026-10-25', '2026-10-27', canal: 'Booking.com');
        $this->reserver($inconnu = $this->uuid(), $this->b2->id, '2026-10-25', '2026-10-27', canal: 'Fax');

        $this->assertSame('Booking.com', Reservation::findOrFail($booking)->canal?->nom);
        $this->assertNull(Reservation::findOrFail($inconnu)->canal_id);

        $this->travel(10)->seconds();
        $elements = collect($this->getJson('/api/v1/referentiels?poste_id=poste-b&limite=500')->assertOk()->json('data.elements'))
            ->where('table', 'reservations')->keyBy('id');
        $this->assertSame('Booking.com', $elements[$booking]['donnees']['canal']);
        $this->assertNull($elements[$inconnu]['donnees']['canal']);
        $this->assertArrayNotHasKey('canal_id', $elements[$booking]['donnees']);
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
    public function les_refus_du_service_portent_sur_la_coherence_jamais_sur_le_poste(): void
    {
        $id = $this->uuid();
        $this->reserver($id, $this->b1->id, '2026-10-25', '2026-10-27');

        $this->pousser([$this->annulation($id, valeur: '30000')], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('hebergement.annulation_remboursement_superieur_acompte'));

        // 09/11/2026 (décision du PO : « aucune opération ne doit bloquer la synchronisation ») :
        // la réservation saisie sur le poste A est annulée par un AUTRE poste, avec le compte
        // d'un réceptionniste (ni administrateur ni comptable) : ACCEPTÉE. Le contrôle « qui peut
        // annuler » est fait au poste.
        $this->pousser([$this->annulation($id)], $this->receptionniste, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('annulee', Reservation::findOrFail($id)->statut);
    }

    #[Test]
    public function une_reservation_saisie_au_serveur_s_annule_depuis_un_poste_sans_droit_d_administration(): void
    {
        $web = Reservation::create([
            'id' => $this->uuid(), 'client_id' => $this->client->id, 'unite_id' => $this->b2->id,
            'date_arrivee' => '2026-10-25', 'date_depart' => '2026-10-27', 'statut' => 'en_attente',
            'acompte' => '0.00', 'tarif_nuit' => '25000.00',
        ]);

        $this->pousser([$this->annulation($web->id, valeur: '0')], $this->receptionniste, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('annulee', $web->fresh()->statut);
        $this->assertStringNotContainsString(
            'saisi sur un autre poste',
            (string) json_encode($this->getJson('/api/v1/referentiels?poste_id=poste-c&limite=500')->json()),
        );
    }

    #[Test]
    public function l_annulation_d_un_poste_garde_son_auteur_local_son_poste_et_sa_date_et_descend_complete(): void
    {
        $id = $this->uuid();
        $this->reserver($id, $this->b1->id, '2026-10-25', '2026-10-27');
        $this->travelTo('2026-10-19 11:30:00');

        $operation = $this->annulation($id, valeur: '0');
        $operation['payload']['auteur'] = 'barman.local';
        $this->pousser([$operation], $this->receptionniste, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $r = Reservation::findOrFail($id);
        $this->assertSame('barman.local', $r->annulee_par_login);
        $this->assertSame('poste-b', $r->annulee_depuis_poste);
        $this->assertSame($this->receptionniste->id, $r->utilisateur_annulation_id, 'le compte d\'appairage reste l\'auteur d\'enregistrement');
        $this->assertSame('2026-10-19 11:30:00', $r->date_annulation->format('Y-m-d H:i:s'));
        // La trace d'audit porte l'auteur local et le poste.
        $audit = \App\Shared\Audit\Models\JournalAudit::query()
            ->where('entite_concernee', 'reservations')->where('entite_id', $id)->latest('date_heure')->get()
            ->first(fn ($j) => isset($j->valeur_apres['annulee_par_login']));
        $this->assertNotNull($audit);
        $this->assertSame('poste-b', $audit->valeur_apres['annulee_depuis_poste']);

        // L'annulation DESCEND COMPLÈTE : taux, montants, date, mode, auteur local.
        $this->travel(10)->seconds();
        $element = collect($this->getJson('/api/v1/referentiels?poste_id=poste-c&limite=500')->assertOk()->json('data.elements'))
            ->where('table', 'reservations')->keyBy('id')[$id];
        $this->assertSame('barman.local', $element['donnees']['par']);
        $this->assertSame('montant', $element['donnees']['mode_saisie_remboursement']);
        $this->assertSame('20.00', $element['donnees']['taux_annulation']);
        $this->assertSame('50000.00', $element['donnees']['montant_total_annulation']);
        $this->assertSame('10000.00', $element['donnees']['montant_commission_annulation']);
        $this->assertSame('0.00', $element['donnees']['montant_rembourse_annulation']);
        $this->assertNotNull($element['donnees']['date_annulation']);
        $this->assertArrayNotHasKey('annulee_par_login', $element['donnees']);
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

        // Ce qui n'est PAS de la fiche reste refusé (la référence, le statut hors annulation).
        $this->pousser([$this->operation('reservations', 'modification', $a, ['statut' => 'terminee'])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.reservations.champ_non_modifiable', ['champs' => 'statut']));
    }

    private function circuit(string $prix = '15000'): \App\Domain\Tourisme\Models\Circuit
    {
        return \App\Domain\Tourisme\Models\Circuit::create(['nom' => 'Kota ' . $this->uuid(), 'theme' => 'nature', 'zone' => 'Atacora', 'duree' => '1 jour', 'prix' => $prix, 'capacite_max' => 8]);
    }

    /**
     * 09/11/2026 (PO) : la FICHE se modifie — tarif, acompte, remise, mode, services — et
     * arrive complète aux autres postes. Chaque champ est un geste, le dernier écrit gagne.
     */
    #[Test]
    public function la_fiche_se_modifie_champ_par_champ_et_les_services_se_remplacent_au_prix_fige_du_poste(): void
    {
        $id = $this->uuid();
        $this->reserver($id, $this->b1->id, '2026-10-25', '2026-10-27');
        $circuit = $this->circuit();

        $this->pousser([$this->operation('reservations', 'modification', $id, [
            'tarif_nuit' => '30000.00', 'acompte' => '45000.00', 'remise_type' => 'pourcentage', 'remise_valeur' => '10.00',
            'mode_paiement' => 'mobile_money',
            // Le prix du POSTE (figé à son ajout), pas celui du catalogue (15000).
            'lignes' => [['service' => 'tourisme', 'source_id' => $circuit->id, 'libelle' => 'Kota (poste)', 'quantite' => '2', 'prix_unitaire' => '12000.00']],
        ])], $this->receptionniste)->assertJsonPath('resultats.0.statut', 'synchronise');

        $r = Reservation::with('lignes')->findOrFail($id);
        $this->assertSame(['30000.00', '45000.00', 'pourcentage', '10.00', 'mobile_money'], [(string) $r->tarif_nuit, (string) $r->acompte, $r->remise_type, (string) $r->remise_valeur, $r->mode_paiement]);
        $this->assertCount(1, $r->lignes);
        $this->assertSame(['Kota (poste)', '12000.00', '24000.00'], [$r->lignes[0]->libelle, (string) $r->lignes[0]->prix_unitaire, (string) $r->lignes[0]->montant]);

        // Sans la clé `lignes`, les services restent ; avec une liste vide, ils sont retirés.
        $this->pousser([$this->operation('reservations', 'modification', $id, ['acompte' => '1000.00'])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertCount(1, Reservation::findOrFail($id)->lignes);
        $this->pousser([$this->operation('reservations', 'modification', $id, ['lignes' => []])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertCount(0, Reservation::findOrFail($id)->lignes);
    }

    #[Test]
    public function une_modification_de_la_fiche_descend_aux_autres_postes_meme_quand_seuls_les_services_changent(): void
    {
        $id = $this->uuid();
        $this->reserver($id, $this->b1->id, '2026-10-25', '2026-10-27');
        $circuit = $this->circuit();
        $this->travel(\App\Shared\Sync\Services\CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        $curseur = $this->getJson('/api/v1/referentiels?poste_id=poste-b&limite=500')->assertOk()->json('meta.curseur');

        // Ni date, ni prix, ni acompte : SEULS les services changent. La fiche doit quand même redescendre.
        $this->travel(10)->seconds();
        $this->pousser([$this->operation('reservations', 'modification', $id, [
            'lignes' => [['service' => 'tourisme', 'source_id' => $circuit->id, 'libelle' => 'Kota', 'quantite' => '1', 'prix_unitaire' => '15000.00']],
        ])], $this->receptionniste)->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->travel(\App\Shared\Sync\Services\CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        $page = $this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500]))->assertOk();
        $fiche = collect($page->json('data.elements'))->where('table', 'reservations')->where('id', $id)->first();
        $this->assertNotNull($fiche, 'la réservation redescend : ses lignes ont changé');
        $this->assertSame('tourisme', $fiche['donnees']['lignes'][0]['service']);
    }

    #[Test]
    public function la_creation_porte_ses_services_et_les_refus_sont_lisibles(): void
    {
        $circuit = $this->circuit();
        $id = $this->uuid();
        $this->pousser([$this->creation('reservations', $id, [
            'client_id' => $this->client->id, 'unite_id' => $this->b1->id,
            'date_arrivee' => '2026-10-25', 'date_depart' => '2026-10-27',
            'acompte' => '0.00', 'tarif_nuit' => '25000.00',
            'lignes' => [['service' => 'tourisme', 'source_id' => $circuit->id, 'libelle' => 'Kota', 'quantite' => '3', 'prix_unitaire' => '5000.00']],
        ])], $this->receptionniste)->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('15000.00', (string) Reservation::with('lignes')->findOrFail($id)->lignes[0]->montant);

        // Une source qui n'existe pas : la fiche entière est refusée, avec la phrase du service.
        $this->pousser([$this->operation('reservations', 'modification', $id, [
            'lignes' => [['service' => 'tourisme', 'source_id' => $this->uuid(), 'libelle' => 'Fantôme', 'quantite' => '1', 'prix_unitaire' => '1.00']],
        ])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('hebergement.ligne_source_inconnue', ['service' => 'tourisme']));
        $this->assertCount(1, Reservation::findOrFail($id)->lignes, 'rien n\'est écrit à moitié');
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
