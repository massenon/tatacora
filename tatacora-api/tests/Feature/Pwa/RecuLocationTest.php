<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ContratLocationService;
use App\Models\User;
use App\Pwa\Livewire\Vehicules\Locations;
use App\Pwa\Support\MontantFcfa;
use App\Shared\Rbac\Models\Role;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le REÇU de location (PDF d'un contrat, M8) — web, jumeau du poste.
 *
 * Le HTML qui précède dompdf porte les mentions à vérifier : la vue est rendue
 * avec EXACTEMENT les variables que le composant lui passe
 * (`ContratLocationService::donneesRecu()`).
 */
final class RecuLocationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function compte(string $role): User
    {
        return User::create([
            'login' => $role.'.recu.'.bin2hex(random_bytes(3)),
            'mot_de_passe_hash' => Hash::make('MotDePasseTresLong!2026'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    private function contrat(string $statut = 'actif', string $tarif = '70000.00'): ContratLocation
    {
        $vehicule = Vehicule::create([
            'immatriculation' => 'AB 1234 RB', 'categorie' => '4x4', 'annee' => 2022,
            'transmission' => 'Manuelle', 'capacite' => 5, 'tarif_jour' => $tarif,
            'statut' => 'disponible',
        ]);
        $client = Client::create(['nom' => 'Agence Bénin Tour', 'telephone' => '+229 01 97 00 00', 'type_client' => 'structure']);

        $contrat = ContratLocation::create([
            'vehicule_id' => $vehicule->id, 'client_id' => $client->id,
            'date_debut' => '2026-09-01', 'date_fin' => '2026-09-04',
        ]);
        $contrat->forceFill([
            'numero' => 'LOC-2026-00007', 'statut' => $statut,
            'montant' => '210000.00', 'acompte' => '50000.00', 'reste_a_payer' => '160000.00',
        ])->save();

        return $contrat->fresh(['vehicule', 'client']);
    }

    private function html(ContratLocation $contrat): string
    {
        return view('pdf.location-recu', [
            'contrat' => $contrat,
            ...app(ContratLocationService::class)->donneesRecu($contrat),
            'entete' => app(ReportHeaderService::class)->genererEnTete(
                typeRapport: (string) __('vehicules.pwa.recu_titre'),
                periode: '',
                auteur: null,
            ),
        ])->render();
    }

    #[Test]
    public function un_contrat_actif_porte_ses_montants_et_ne_vaut_pas_facture(): void
    {
        $html = $this->html($this->contrat());

        foreach (['LOC-2026-00007', 'Agence Bénin Tour', 'AB 1234 RB', '01/09/2026', '04/09/2026', '3 jour(s)'] as $attendu) {
            $this->assertStringContainsString($attendu, $html);
        }
        $this->assertStringContainsString(MontantFcfa::format('210000'), $html);
        $this->assertStringContainsString(MontantFcfa::format('50000'), $html);
        $this->assertStringContainsString(MontantFcfa::format('160000'), $html);
        $this->assertStringContainsString(MontantFcfa::format('70000'), $html, 'tarif journalier');
        $this->assertStringContainsString(e((string) __('vehicules.pwa.recu_mention')), $html);
        $this->assertStringNotContainsString('ANNULÉ', $html);
        $this->assertStringContainsString('TATACORA', $html, 'en-tête entreprise');
    }

    #[Test]
    public function un_contrat_annule_porte_le_bandeau_et_aucun_montant(): void
    {
        $html = $this->html($this->contrat('annule'));

        $this->assertStringContainsString('ANNULÉ', $html);
        $this->assertStringContainsString(e((string) __('vehicules.pwa.recu_annule_mention')), $html);
        foreach ([MontantFcfa::format('210000'), MontantFcfa::format('50000'), MontantFcfa::format('160000'), (string) __('vehicules.pwa.recu_reste'), (string) __('vehicules.pwa.recu_montant')] as $interdit) {
            $this->assertStringNotContainsString($interdit, $html);
        }
    }

    #[Test]
    public function le_tarif_n_est_rendu_que_s_il_explique_le_montant_fige(): void
    {
        // Le tarif du véhicule a changé depuis la signature : 80 000 x 3 != 210 000.
        $html = $this->html($this->contrat('actif', '80000.00'));

        $this->assertStringNotContainsString(MontantFcfa::format('80000'), $html);
        $this->assertStringContainsString(MontantFcfa::format('210000'), $html);
    }

    #[Test]
    public function l_action_rend_un_pdf_pour_un_role_en_lecture_seule(): void
    {
        $contrat = $this->contrat();
        $this->actingAs($this->compte('receptionniste'));

        $reponse = Livewire::test(Locations::class)
            ->call('imprimerRecu', $contrat->id)
            ->assertFileDownloaded('recu_location_LOC-2026-00007.pdf');

        $this->assertNotNull($reponse);
    }
}
