<?php

declare(strict_types=1);

namespace Tests\Feature\Rbac;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Vérifie que les factories produisent réellement des enregistrements valides
 * contre le schéma MySQL.
 *
 * La factory User livrée par le squelette Laravel alimentait name/email/password,
 * colonnes absentes de `utilisateurs` : sans ce test, l'erreur ne serait apparue
 * qu'au premier sprint métier, sous forme d'erreur SQL peu lisible.
 */
final class FactoriesRbacTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function la_factory_role_cree_un_role_persistable(): void
    {
        $role = Role::factory()->create();

        $this->assertDatabaseHas('roles', ['id' => $role->id]);
        $this->assertNotEmpty($role->libelle);
    }

    #[Test]
    public function la_factory_utilisateur_cree_un_compte_rattache_a_un_role(): void
    {
        $utilisateur = User::factory()->create();

        $this->assertDatabaseHas('utilisateurs', ['id' => $utilisateur->id]);
        $this->assertNotNull($utilisateur->role);
        $this->assertTrue($utilisateur->estActif());
    }

    #[Test]
    public function le_mot_de_passe_est_hache_jamais_stocke_en_clair(): void
    {
        $utilisateur = User::factory()->create();

        $this->assertNotSame('mot-de-passe-de-test', $utilisateur->mot_de_passe_hash);
        $this->assertTrue(password_verify('mot-de-passe-de-test', $utilisateur->getAuthPassword()));
    }

    #[Test]
    public function un_compte_desactive_est_bien_marque_comme_inactif(): void
    {
        $utilisateur = User::factory()->desactive()->create();

        $this->assertFalse($utilisateur->estActif());
    }
}
