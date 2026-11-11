<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Models\User;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * L'AVOIR PARTIEL émis sur un poste (21/10/2026) — `emettreAvoir($facture,
 * $montant, $motif)` de la PWA : la règle est celle du service (un avoir
 * n'excède jamais le TTC de sa facture), l'avoir naît sous l'identifiant du poste,
 * son rejeu ne le double pas, et l'annulation (TTC entier) reste distincte.
 */
final class AvoirPartielSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $receptionniste;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-21 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->receptionniste = $this->creerUtilisateur('receptionniste');
        Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'groupe']);
    }

    /** Une facture de 10 000 F (2 × 5 000), poussée par le poste A. */
    private function factureDe10000(): string
    {
        $id = $this->uuid();
        $this->pousser([$this->operationDatee('factures', 'creation', $id, [
            'origine' => 'facture_directe', 'date_emission' => '2026-10-21',
            'lignes' => [['module' => 'M5', 'libelle' => 'Bière', 'prix_unitaire' => 5000, 'quantite' => 2]],
        ], '2026-10-21T09:00:00+00:00')], $this->receptionniste, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');

        return $id;
    }

    #[Test]
    public function l_avoir_partiel_naît_sous_l_identifiant_du_poste_et_rend_son_numero(): void
    {
        $facture = $this->factureDe10000();
        $avoir = $this->uuid();

        $this->pousser([$this->operation('factures', 'modification', $facture, [
            'montant' => 3000, 'motif' => 'Bière tiède', 'avoir_id' => $avoir,
        ])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero_avoir', 'AV-2026-00001')
            ->assertJsonPath('resultats.0.avoir_id', $avoir);

        $a = Avoir::findOrFail($avoir);
        $this->assertSame([$facture, '3000.00', 'Bière tiède'], [$a->facture_id, (string) $a->montant, $a->motif]);
        // La facture d'origine reste inchangée (RG-03).
        $this->assertSame('10000.00', (string) Facture::findOrFail($facture)->montant_ttc);
    }

    #[Test]
    public function le_rejeu_d_un_avoir_partiel_ne_le_double_pas_et_rend_le_meme_numero(): void
    {
        $facture = $this->factureDe10000();
        $avoir = $this->uuid();
        $payload = ['montant' => 3000, 'motif' => 'Bière tiède', 'avoir_id' => $avoir];

        $this->pousser([$this->operation('factures', 'modification', $facture, $payload)], $this->receptionniste);
        $this->pousser([$this->operation('factures', 'modification', $facture, $payload)], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero_avoir', 'AV-2026-00001');

        $this->assertSame(1, Avoir::query()->where('facture_id', $facture)->count());
    }

    #[Test]
    public function le_plafond_du_service_refuse_un_avoir_superieur_au_ttc_avec_sa_phrase(): void
    {
        $facture = $this->factureDe10000();

        $this->pousser([$this->operation('factures', 'modification', $facture, ['montant' => 10001, 'motif' => 'Trop'])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('facturation.avoir_montant_excessif'));

        // Le TTC exact passe : le service ne refuse que ce qui le dépasse.
        $this->pousser([$this->operation('factures', 'modification', $facture, ['montant' => 10000, 'motif' => 'Tout'])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
    }

    #[Test]
    public function un_montant_nul_negatif_ou_decimal_est_refuse_et_un_champ_etranger_aussi(): void
    {
        $facture = $this->factureDe10000();

        foreach ([0, -5, 12.5, 'abc'] as $montant) {
            $this->pousser([$this->operation('factures', 'modification', $facture, ['montant' => $montant, 'motif' => 'x'])], $this->receptionniste)
                ->assertJsonPath('resultats.0.statut', 'rejete');
        }

        $this->pousser([$this->operation('factures', 'modification', $facture, ['montant' => 100, 'motif' => 'x', 'numero' => 'F-1'])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.modification_non_synchronisable'));

        $this->assertSame(0, Avoir::query()->count());
    }

    #[Test]
    public function un_avoir_partiel_n_annule_pas_la_facture_et_l_annulation_emet_ensuite_le_ttc_entier(): void
    {
        $facture = $this->factureDe10000();
        $this->pousser([$this->operation('factures', 'modification', $facture, ['montant' => 3000, 'motif' => 'Geste', 'avoir_id' => $this->uuid()])], $this->receptionniste, 'poste-a');

        $this->pousser([$this->operation('factures', 'modification', $facture, ['statut' => 'annulee', 'motif' => 'Erreur'])], $this->receptionniste, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.numero_avoir', 'AV-2026-00002');

        $this->assertEqualsCanonicalizing(['3000.00', '10000.00'], Avoir::query()->where('facture_id', $facture)->get()->map(fn (Avoir $a): string => (string) $a->montant)->all());
    }

    #[Test]
    public function le_montant_sans_statut_et_le_statut_avec_montant_sont_les_deux_seuls_gestes(): void
    {
        $facture = $this->factureDe10000();

        $this->pousser([$this->operation('factures', 'modification', $facture, ['statut' => 'annulee', 'montant' => 100, 'motif' => 'x'])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->pousser([$this->operation('factures', 'modification', $facture, ['motif' => 'x'])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame(0, Avoir::query()->count());
    }

    #[Test]
    public function l_avoir_partiel_descend_aux_autres_postes_sous_le_meme_identifiant(): void
    {
        $facture = $this->factureDe10000();
        $avoir = $this->uuid();
        $this->pousser([$this->operation('factures', 'modification', $facture, ['montant' => 3000, 'motif' => 'Geste', 'avoir_id' => $avoir])], $this->receptionniste, 'poste-a');

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($this->receptionniste);
        $elements = collect($this->getJson('/api/v1/referentiels?' . http_build_query(['poste_id' => 'poste-a', 'limite' => 500]))
            ->assertOk()->json('data.elements'));

        $ligne = $elements->firstWhere('table', 'avoirs');
        $this->assertSame($avoir, $ligne['id']);
        $this->assertSame(['3000.00', 'AV-2026-00001', $facture], [$ligne['donnees']['montant'], $ligne['donnees']['numero'], $ligne['donnees']['facture_id']]);
    }
}
