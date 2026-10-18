<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Rh\Models\BulletinPaie;
use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Service;
use App\Models\User;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Domain\Rh\Concerns\PoseLeReferentielDePaie;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le dossier RH et la paie (M13) en synchronisation — audit de couverture du
 * 18/10/2026. Le serveur attribue le matricule et le numéro de bulletin, et
 * recalcule la paie avec SON barème ; un écart de net est signalé.
 */
final class RhSynchronisationTest extends TestCase
{
    use PoseLeReferentielDePaie;
    use PousseDesOperations;
    use RefreshDatabase;

    private User $rh;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-18 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->rh = $this->creerUtilisateur('rh');
        Service::firstOrCreate(['libelle' => 'Hébergement']);
    }

    /**
     * @param  array<string, mixed>  $surcharges
     * @return array<string, mixed>
     */
    private function employe(string $id, array $surcharges = []): array
    {
        return $this->creation('employes', $id, [
            'nom' => 'HOUNSOU', 'prenom' => 'Marceline', 'poste' => 'Réceptionniste',
            'service_id' => $this->uuid(), 'service_libelle' => 'Hébergement',
            'date_embauche' => '2023-02-01', 'salaire_base' => 150000, 'type_contrat' => 'CDI',
            ...$surcharges,
        ]);
    }

    #[Test]
    public function l_employe_du_poste_recoit_le_matricule_du_serveur_et_s_archive(): void
    {
        $id = $this->uuid();

        $reponse = $this->pousser([$this->employe($id)], $this->rh, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $e = Employe::findOrFail($id);
        $this->assertSame($e->matricule, $reponse->json('resultats.0.matricule'));
        $this->assertSame(['Hébergement', '150000.00'], [$e->service->libelle, (string) $e->salaire_base]);

        $this->pousser([$this->operation('employes', 'modification', $id, ['poste' => 'Chef de réception', 'salaire_base' => 175000])], $this->rh)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(['Chef de réception', '175000.00'], [Employe::findOrFail($id)->poste, (string) Employe::findOrFail($id)->salaire_base]);

        $this->pousser([$this->operation('employes', 'modification', $id, ['statut' => 'parti'])], $this->rh)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('parti', Employe::findOrFail($id)->statut);

        // Un service absent du serveur est créé par son libellé, une fois.
        $this->pousser([$this->employe($this->uuid(), ['service_libelle' => 'Spa'])], $this->rh)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->pousser([$this->employe($this->uuid(), ['service_libelle' => 'Spa'])], $this->rh)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(1, Service::query()->where('libelle', 'Spa')->count());
    }

    #[Test]
    public function le_bulletin_est_recalcule_au_serveur_un_ecart_est_signale_un_doublon_fusionne(): void
    {
        $this->poserLeReferentielDePaie();
        $employe = $this->uuid();
        $this->pousser([$this->employe($employe)], $this->rh);
        $b = $this->uuid();

        $this->pousser([$this->creation('bulletins_paie', $b, ['employe_id' => $employe, 'periode' => '2026-10', 'net_a_payer' => 1])], $this->rh, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $bulletin = BulletinPaie::findOrFail($b);
        $this->assertNotSame('1.00', (string) $bulletin->net_a_payer);
        $this->assertTrue(AnomalieSynchronisation::query()->where('entite_id', $b)->where('type', AnomalieSynchronisation::BULLETIN_ECART_NET)->exists());

        $this->pousser([$this->creation('bulletins_paie', $this->uuid(), ['employe_id' => $employe, 'periode' => '2026-10'])], $this->rh, 'poste-b')
            ->assertJsonPath('resultats.0.fusionne_avec', $b);
        $this->assertSame(1, BulletinPaie::count());

        $this->pousser([$this->operation('bulletins_paie', 'modification', $b, ['statut' => 'annulee', 'motif' => 'Erreur de mois'])], $this->rh)
            ->assertJsonPath('resultats.0.statut_bulletin', 'annulee');
    }
}
