<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Facture;
use App\Models\User;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Pwa\Support\OrigineEtModeFacture;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * 10/11/2026 (constat du PO : le registre WEB disait « — » pour l'origine et le mode de paiement là où le
 * poste dit « POS au comptant » et « Mobile Money »). L'origine est lue sur `factures.origine` ; le mode,
 * là où il vit : le paiement actif, ou la vente d'un ticket du comptoir.
 */
final class RegistreOrigineEtModeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->actingAs(User::create([
            'login' => 'nabogou', 'mot_de_passe_hash' => Hash::make('x-mot-de-passe-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id, 'statut' => 'actif',
        ]));
    }

    private function facture(string $origine, string $montant): Facture
    {
        $client = Client::create(['nom' => 'Client de passage', 'prenom' => '', 'telephone' => '-', 'type_client' => 'particulier']);

        return Facture::create([
            'client_id' => $client->id, 'date_emission' => now()->toDateString(), 'origine' => $origine,
            'montant_ht' => $montant, 'montant_tva' => '0.00', 'montant_ttc' => $montant, 'statut' => 'certifiee',
        ]);
    }

    #[Test]
    public function l_origine_se_lit_sur_la_facture_et_le_mode_sur_la_vente_du_ticket(): void
    {
        $ticket = $this->facture('pos_comptant', '3700.00');
        $venteId = (string) Str::uuid();
        DB::table('ventes')->insert([
            'id' => $venteId, 'numero' => 'V-'.Str::random(5), 'point_vente' => 'bar', 'mode_paiement' => 'mobile_money',
            'montant_total' => '3700.00', 'statut' => 'validee', 'utilisateur_id' => auth()->id(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
        DB::table('lignes_facture')->insert([
            'id' => (string) Str::uuid(), 'facture_id' => $ticket->id, 'source_module' => 'M5', 'source_id' => $venteId,
            'libelle' => 'Café', 'quantite' => 1, 'prix_unitaire' => '3700.00', 'montant' => '3700.00',
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $directe = $this->facture('facture_directe', '90000.00');

        $this->assertSame('POS au comptant', OrigineEtModeFacture::origine($ticket->refresh()));
        $this->assertSame('Mobile Money', OrigineEtModeFacture::mode($ticket->load('lignes')));
        $this->assertSame('Facture directe', OrigineEtModeFacture::origine($directe));
        // Sans paiement ni vente : « — », jamais un mode inventé.
        $this->assertSame('—', OrigineEtModeFacture::mode($directe->load('lignes')));

        Livewire::test(Facturation::class)->assertSee('POS au comptant')->assertSee('Mobile Money')->assertSee('Facture directe');
    }
}
