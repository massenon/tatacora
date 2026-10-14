<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Crm\Models\Client;
use App\Models\User;
use App\Pwa\Livewire\Transverse\RechercheGlobale;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\UtilisateurSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Recherche globale de la barre superieure (audit PO du 01/09/2026).
 *
 * Deux proprietes eprouvees : le lien profond retombe sur le filtre natif de
 * l'ecran (`?q=`), et le RBAC filtre chaque source par son module — la meme
 * source que le menu, jamais un second calcul de droits.
 */
final class RechercheGlobaleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(UtilisateurSeeder::class);

        Client::query()->create([
            'id' => (string) Str::uuid(),
            'nom' => 'Zinsou',
            'prenom' => 'Albertine',
            'type_client' => 'particulier',
            'telephone' => '+229 97 00 00 01',
        ]);
    }

    #[Test]
    public function un_client_se_trouve_et_le_lien_porte_le_terme(): void
    {
        $admin = User::query()->where('login', 'admin')->firstOrFail();

        $this->actingAs($admin);

        Livewire::test(RechercheGlobale::class)
            ->set('terme', 'Zinsou')
            ->assertSee('Albertine Zinsou')
            ->assertSee('q=Zinsou', false);
    }

    #[Test]
    public function un_compte_sans_le_module_ne_voit_pas_la_source(): void
    {
        // La cuisine a M8 = '-' (matrice RolePermissionSeeder) : le vehicule
        // n'apparait pas dans SES resultats, alors que l'admin le trouve.
        \App\Domain\Vehicules\Models\Vehicule::query()->create([
            'id' => (string) Str::uuid(),
            'categorie' => 'moto',
            'immatriculation' => 'BJ-7431-RB',
            'annee' => 2024,
            'tarif_jour' => '8000.00',
        ]);

        $admin = User::query()->where('login', 'admin')->firstOrFail();
        $this->actingAs($admin);

        Livewire::test(RechercheGlobale::class)
            ->set('terme', 'BJ-7431')
            ->assertSee('BJ-7431-RB');

        $cuisine = User::query()->where('login', 'cuisine')->firstOrFail();
        $this->actingAs($cuisine);

        Livewire::test(RechercheGlobale::class)
            ->set('terme', 'BJ-7431')
            ->assertDontSee('BJ-7431-RB');
    }

    #[Test]
    public function moins_de_deux_caracteres_ne_cherche_rien(): void
    {
        $admin = User::query()->where('login', 'admin')->firstOrFail();

        $this->actingAs($admin);

        Livewire::test(RechercheGlobale::class)
            ->set('terme', 'Z')
            ->assertSee(__('pwa.recherche_globale.trop_court'));
    }
}
