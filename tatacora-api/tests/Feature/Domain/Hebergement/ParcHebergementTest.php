<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Hebergement;

use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le référentiel de parc — `GET /api/v1/hebergement/parc` (PA-128).
 *
 * ## Ce que ces cas protègent
 *
 * **Que le parc descende ENTIER.** Le client Flutter calcule la disponibilité
 * en local : une unité manquante y apparaîtrait comme inexistante, et une unité
 * `hors_service` filtrée ici deviendrait indiscernable d'une unité supprimée.
 * C'est aussi la seule route qui alimente ses tables de parc — sans elle, un
 * poste neuf ne peut prendre aucune réservation.
 */
final class ParcHebergementTest extends TestCase
{
    use RefreshDatabase;

    private User $receptionniste;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->receptionniste = $this->compteAvecRole(
            Role::where('libelle', 'receptionniste')->firstOrFail(),
        );
    }

    #[Test]
    public function le_parc_descend_avec_ses_categories_et_ses_tarifs(): void
    {
        $categorie = CategorieHebergement::create([
            'libelle' => 'Bungalow',
            'capacite_max' => 2,
            'tarif_base' => '28000.00',
        ]);
        UniteHebergement::create([
            'categorie_id' => $categorie->id,
            'numero' => 'BNG-01',
            'statut' => 'libre',
        ]);

        Sanctum::actingAs($this->receptionniste);
        $reponse = $this->getJson('/api/v1/hebergement/parc')->assertOk();

        $this->assertSame('Bungalow', $reponse->json('data.categories.0.libelle'));
        $this->assertSame(2, $reponse->json('data.categories.0.capacite_max'));
        // Chaîne, jamais un float : réarrondi côté client, le tarif divergerait
        // de celui figé sur la réservation (PA-55).
        $this->assertSame('28000.00', $reponse->json('data.categories.0.tarif_base'));
        $this->assertSame('BNG-01', $reponse->json('data.unites.0.numero'));
        $this->assertSame($categorie->id, $reponse->json('data.unites.0.categorie_id'));
    }

    #[Test]
    public function une_unite_hors_service_descend_AUSSI(): void
    {
        // La filtrer la ferait disparaître du parc local, et le client ne
        // pourrait plus dire POURQUOI elle n'est pas proposée : il la
        // présenterait comme inexistante.
        $categorie = CategorieHebergement::create([
            'libelle' => 'Chambre',
            'capacite_max' => 2,
            'tarif_base' => '15000.00',
        ]);
        UniteHebergement::create([
            'categorie_id' => $categorie->id,
            'numero' => 'CH-09',
            'statut' => 'hors_service',
        ]);

        Sanctum::actingAs($this->receptionniste);
        $reponse = $this->getJson('/api/v1/hebergement/parc')->assertOk();

        $this->assertCount(1, $reponse->json('data.unites'));
        $this->assertSame('hors_service', $reponse->json('data.unites.0.statut'));
    }

    #[Test]
    public function le_parc_n_est_PAS_pagine(): void
    {
        // Le client a besoin du parc ENTIER pour calculer une disponibilité :
        // une page manquante ferait apparaître libre une chambre déjà prise.
        $categorie = CategorieHebergement::create([
            'libelle' => 'Chambre',
            'capacite_max' => 2,
            'tarif_base' => '15000.00',
        ]);
        for ($i = 1; $i <= 60; $i++) {
            UniteHebergement::create([
                'categorie_id' => $categorie->id,
                'numero' => sprintf('CH-%02d', $i),
                'statut' => 'libre',
            ]);
        }

        Sanctum::actingAs($this->receptionniste);
        $reponse = $this->getJson('/api/v1/hebergement/parc')->assertOk();

        $this->assertCount(60, $reponse->json('data.unites'));
        $this->assertNull($reponse->json('meta'));
    }

    #[Test]
    public function un_role_sans_acces_a_M1_est_refuse(): void
    {
        $sansAcces = Role::all()->first(
            fn (Role $r): bool => $r->niveauSurModule('M1') === '-',
        );
        $this->assertNotNull($sansAcces, 'Aucun role sans acces a M1 dans la matrice.');

        Sanctum::actingAs($this->compteAvecRole($sansAcces));

        $this->getJson('/api/v1/hebergement/parc')->assertForbidden();
    }

    #[Test]
    public function aucune_ecriture_n_est_exposee_sur_le_parc(): void
    {
        // Le parc DESCEND, il ne remonte jamais : `unites_hebergement` n'est
        // pas au registre synchronisable, et une unité créée au comptoir ne
        // partirait nulle part (PA-118). Exposer une écriture ici la ferait
        // exister sur un seul poste, en silence.
        Sanctum::actingAs($this->receptionniste);

        $this->postJson('/api/v1/hebergement/parc', [])->assertStatus(405);
        $this->putJson('/api/v1/hebergement/parc', [])->assertStatus(405);
        $this->deleteJson('/api/v1/hebergement/parc')->assertStatus(405);
    }

    private function compteAvecRole(Role $role): User
    {
        return User::create([
            'login' => $role->libelle . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => $role->id,
            'statut' => 'actif',
        ]);
    }
}
