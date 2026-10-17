<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Caisse\Services\SessionCaisseService;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Paiement;
use App\Models\User;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Les encaissements de facture saisis sur un poste — lot F5d, 17/10/2026.
 * L'argent est déjà reçu au comptoir : le serveur l'écrit par
 * `EncaissementFactureService` (pièce comprise), et SIGNALE ce qu'il admet
 * hors de sa règle en ligne (facture non certifiée, caisse inconnue).
 */
final class PaiementsSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $receptionniste;

    private SessionCaisse $session;

    private string $facture;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-19 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->receptionniste = $this->creerUtilisateur('receptionniste');
        $this->session = app(SessionCaisseService::class)->ouvrir('bar', '10000', $this->receptionniste->id, now()->setTime(7, 0));
        Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'groupe']);

        $this->facture = $this->uuid();
        $this->pousser([$this->operationDatee('factures', 'creation', $this->facture, [
            'origine' => 'facture_directe',
            'date_emission' => '2026-10-19',
            'lignes' => [['module' => 'M8', 'libelle' => 'Location 4x4', 'prix_unitaire' => 30000, 'quantite' => 1]],
        ], '2026-10-19T08:00:00+00:00')], $this->receptionniste, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');
    }

    /**
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function paiement(string $id, array $surcharges = []): array
    {
        return $this->operationDatee('paiements', 'creation', $id, [
            'facture_id' => $this->facture,
            'session_id' => $this->session->id,
            'mode_paiement' => 'especes',
            'montant' => 1000000,
            'date_paiement' => '2026-10-19T09:15:00+00:00',
            ...$surcharges,
        ], '2026-10-19T09:15:00+00:00');
    }

    private function piecesDe(string $paiementId): int
    {
        return EcritureComptable::query()->where('libelle', 'like', '%' . $paiementId . '%')->count();
    }

    #[Test]
    public function l_encaissement_du_poste_est_ecrit_avec_sa_piece_dans_la_caisse_du_poste(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->paiement($id)], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.anomalies', [AnomalieSynchronisation::PAIEMENT_FACTURE_NON_CERTIFIEE]);

        $paiement = Paiement::findOrFail($id);
        $this->assertSame('10000.00', (string) $paiement->montant);
        $this->assertSame($this->session->id, $paiement->session_id);
        $this->assertSame('2026-10-19 09:15:00', $paiement->date_paiement->format('Y-m-d H:i:s'));
        // Dr caisse / Cr 4111 : deux lignes, une pièce.
        $this->assertSame(2, $this->piecesDe($id));
        $this->assertSame('20000.00', Paiement::findOrFail($id)->facture->resteDu());
    }

    #[Test]
    public function un_rejeu_apres_purge_ne_double_ni_le_paiement_ni_la_piece(): void
    {
        $id = $this->uuid();
        $op = $this->paiement($id);
        $this->pousser([$op], $this->receptionniste);
        $this->purgerLaMemoireDIdempotence();
        $this->pousser([$this->nouvelleTentative($op)], $this->receptionniste)->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(1, Paiement::count());
        $this->assertSame(2, $this->piecesDe($id));
    }

    #[Test]
    public function une_caisse_inconnue_du_serveur_rattache_a_la_caisse_ouverte_et_le_signale(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->paiement($id, ['session_id' => $this->uuid()])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame($this->session->id, Paiement::findOrFail($id)->session_id);
        $this->assertTrue(AnomalieSynchronisation::query()
            ->where('entite_id', $id)->where('type', AnomalieSynchronisation::PAIEMENT_SESSION_INCONNUE)->exists());
    }

    #[Test]
    public function les_refus_du_service_sont_rendus_avec_leur_phrase(): void
    {
        $this->pousser([$this->paiement($this->uuid(), ['montant' => 4000000])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('facturation.encaissement_superieur_au_reste', ['reste' => '30000.00']));

        $this->pousser([$this->paiement($this->uuid(), ['facture_id' => $this->uuid()])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.paiements.facture_inconnue'));

        $this->assertSame(0, Paiement::count());
    }

    #[Test]
    public function l_annulation_contre_passe_la_piece_une_seule_fois(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->paiement($id)], $this->receptionniste);
        $lignesAvant = EcritureComptable::count();

        $annulation = $this->operation('paiements', 'modification', $id, ['statut' => 'annule', 'motif' => 'Mauvaise facture']);
        $this->pousser([$annulation], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.statut_paiement', 'annule');
        $this->pousser([[...$annulation, 'uuid_operation' => $this->uuid(), 'horodatage_client' => now()->addMinute()->toIso8601String()]], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame('annule', Paiement::findOrFail($id)->statut);
        // La pièce entière contre-passée (deux lignes inverses), une fois.
        $this->assertSame($lignesAvant + 2, EcritureComptable::count());

        $this->pousser([$this->operation('paiements', 'modification', $id, ['montant' => 1])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.modification_non_synchronisable'));
    }

    #[Test]
    public function l_encaissement_descend_aux_autres_postes_avec_son_origine(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->paiement($id)], $this->receptionniste, 'poste-a');

        // Le flux ne sert que ce qui a passé l'horizon de cohérence.
        $this->travel(10)->seconds();
        Sanctum::actingAs($this->creerUtilisateur('super_admin'));
        $elements = [];
        $curseur = null;

        do {
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter(['poste_id' => 'poste-b', 'depuis' => $curseur, 'limite' => 500])))->assertOk();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        $elements = collect($elements)->keyBy('id');

        $this->assertSame('poste-a', $elements[$id]['poste_origine']);
        $this->assertSame('10000.00', $elements[$id]['donnees']['montant']);
        $this->assertSame($this->facture, $elements[$id]['donnees']['facture_id']);
    }
}
