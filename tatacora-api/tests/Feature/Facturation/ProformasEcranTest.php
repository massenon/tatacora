<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Proforma;
use App\Models\User;
use App\Pwa\Livewire\Facturation\Proformas;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/** L'écran « Proformas » (M2) : droits, saisie libre, prérempli depuis les modules, conversion. */
final class ProformasEcranTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    private function utilisateur(string $niveau): User
    {
        // Le rôle qui porte M2 au niveau demandé, lu du référentiel plutôt que supposé.
        foreach (Role::all() as $role) {
            if ($role->niveauSurModule('M2') === $niveau) {
                return User::create(['login' => 'compte.'.$role->libelle, 'mot_de_passe_hash' => Hash::make('x-mot-de-passe-test'), 'role_id' => $role->id, 'statut' => 'actif']);
            }
        }
        $this->fail('Aucun rôle M2 = '.$niveau);
    }

    #[Test]
    public function la_saisie_libre_cree_emet_et_convertit(): void
    {
        $this->actingAs($this->utilisateur('C'));

        Livewire::test(Proformas::class)
            ->call('ouvrirCreation')
            ->set('clientNom', 'SARL KORA')->set('clientTelephone', '0190123456')->set('objet', 'Atelier')
            ->set('lignes', [['designation' => 'Salle', 'quantite' => '2', 'prix_unitaire' => '50000']])
            ->call('enregistrer', true)
            ->assertSet('etatFormulaire', null)
            ->assertSee('N°0001 FP-GCN/'.now()->year);

        $proforma = Proforma::query()->firstOrFail();
        $this->assertSame(100000, $proforma->total);

        Livewire::test(Proformas::class)
            ->call('ouvrirConversion', $proforma->id)->assertSet('etatFormulaire', 'conversion')
            ->call('confirmerConversion');

        $this->assertSame(1, Facture::query()->where('proforma_id', $proforma->id)->count());
        $this->assertSame('convertie', $proforma->refresh()->statut);
    }

    #[Test]
    public function un_role_en_lecture_ne_peut_rien_ecrire(): void
    {
        $role = Role::all()->first(fn (Role $r): bool => $r->niveauSurModule('M2') === 'L');

        if ($role === null) {
            $this->markTestSkipped('Aucun rôle M2 = L dans le référentiel.');
        }

        $this->actingAs(User::create(['login' => 'lecteur', 'mot_de_passe_hash' => Hash::make('x-mot-de-passe-test'), 'role_id' => $role->id, 'statut' => 'actif']));

        Livewire::test(Proformas::class)->call('ouvrirCreation')->assertForbidden();
        $this->assertSame(0, Proforma::query()->count());
    }

    #[Test]
    public function un_circuit_prerempli_client_objet_et_lignes(): void
    {
        $this->actingAs($this->utilisateur('C'));
        $client = Client::create(['nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '0190123456', 'type_client' => 'particulier', 'ifu' => '0202011344660']);
        $circuit = \App\Domain\Tourisme\Models\Circuit::create(['nom' => 'Pendjari', 'theme' => 'Nature', 'zone' => 'Nord', 'duree' => 3, 'prix' => '75000.00', 'capacite_max' => 10]);
        $guide = \App\Domain\Tourisme\Models\Guide::create(['nom' => 'Guide Test', 'certification' => 'Officielle', 'zone_competence' => 'Nord', 'tarif_jour' => '10000.00']);
        $r = \App\Domain\Tourisme\Models\ReservationTour::create(['circuit_id' => $circuit->id, 'client_id' => $client->id, 'guide_id' => $guide->id, 'date_circuit' => '2026-12-01', 'nb_participants' => 4, 'statut' => 'reservee']);

        Livewire::withQueryParams(['flux' => 'tourisme', 'source' => $r->id])->test(Proformas::class)
            ->assertSet('etatFormulaire', 'proforma')
            ->assertSet('clientNom', 'Jean KORA')->assertSet('clientIfu', '0202011344660')
            ->assertSet('sourceModule', 'tourisme')
            ->assertSet('lignes.0.quantite', '4')->assertSet('lignes.0.prix_unitaire', '75000');
    }

    #[Test]
    public function un_evenement_ouvre_une_proforma_vide(): void
    {
        $this->actingAs($this->utilisateur('C'));

        Livewire::withQueryParams(['flux' => 'evenement'])->test(Proformas::class)
            ->assertSet('etatFormulaire', 'proforma')->assertSet('sourceModule', 'evenement')
            ->assertSet('clientNom', '')->assertCount('lignes', 1);
    }
}
