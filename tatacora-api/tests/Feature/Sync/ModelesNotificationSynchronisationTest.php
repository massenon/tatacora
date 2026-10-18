<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Notifications\Models\ModeleNotification;
use App\Models\User;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Les modèles de notification (M12) en synchronisation — lot 10f. Par
 * `ModeleNotificationService` ; le couple (événement, canal) fusionne.
 */
final class ModelesNotificationSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $gerant;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-18 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->gerant = $this->creerUtilisateur('administrateur');
    }

    /** @return array<string, mixed> */
    private function modele(array $surcharges = []): array
    {
        return [
            'evenement' => 'sejour_demain', 'canal' => 'whatsapp', 'objet' => null,
            'contenu_template' => 'Bonjour {client}, votre réservation est confirmée.', 'actif' => true,
            ...$surcharges,
        ];
    }

    #[Test]
    public function le_modele_du_poste_nait_au_serveur_se_modifie_et_fusionne_par_son_couple(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('modeles_notification', $id, $this->modele())], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('whatsapp', ModeleNotification::findOrFail($id)->canal);

        $this->travel(1)->minutes();
        $this->pousser([$this->operation('modeles_notification', 'modification', $id, $this->modele(['actif' => false, 'contenu_template' => 'Texte relu']))], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame([false, 'Texte relu'], [(bool) ModeleNotification::findOrFail($id)->actif, ModeleNotification::findOrFail($id)->contenu_template]);

        // Le même couple saisi sur un autre poste : fusion, rien n'est doublé.
        $this->pousser([$this->creation('modeles_notification', $this->uuid(), $this->modele())], $this->gerant, 'poste-b')
            ->assertJsonPath('resultats.0.fusionne_avec', $id);
        $this->assertSame(1, ModeleNotification::count());

        // Un canal hors registre est refusé avec la phrase du service.
        $this->pousser([$this->creation('modeles_notification', $this->uuid(), $this->modele(['canal' => 'fax']))], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'rejete');
    }
}
