<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Crm\Models\Client;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use App\Models\User;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Le parc M8 et ses contrats en synchronisation — audit de couverture du
 * 18/10/2026. Deux postes ne louent jamais le même véhicule sur la même
 * période (RG-08, sous verrou).
 */
final class VehiculesSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $gerant;

    private Client $client;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-18 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->gerant = $this->creerUtilisateur('gerant');
        $this->client = Client::create(['nom' => 'Sabi', 'telephone' => '96000003', 'type_client' => 'particulier']);
    }

    /**
     * @return array<string, mixed>
     */
    private function contrat(string $id, string $vehicule, string $debut, string $fin): array
    {
        return $this->creation('contrats_location', $id, [
            'vehicule_id' => $vehicule, 'client_id' => $this->client->id,
            'date_debut' => $debut, 'date_fin' => $fin, 'piece_identite' => 'CNI-123', 'permis_conduire' => 'P-9',
        ]);
    }

    #[Test]
    public function le_vehicule_du_poste_entre_au_parc_signale_sans_annee_et_une_plaque_connue_fusionne(): void
    {
        $id = $this->uuid();

        $this->pousser([$this->creation('vehicules', $id, ['immatriculation' => 'BJ-1234-RB', 'categorie' => '4x4', 'tarif_jour' => 30000])], $this->gerant, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $v = Vehicule::findOrFail($id);
        $this->assertSame(['disponible', 0, '30000.00'], [$v->statut, $v->annee, (string) $v->tarif_jour]);
        $this->assertTrue(AnomalieSynchronisation::query()->where('entite_id', $id)->where('type', AnomalieSynchronisation::VEHICULE_SANS_ANNEE)->exists());

        $this->pousser([$this->creation('vehicules', $this->uuid(), ['immatriculation' => 'BJ-1234-RB', 'categorie' => '4x4', 'tarif_jour' => 1])], $this->gerant, 'poste-b')
            ->assertJsonPath('resultats.0.fusionne_avec', $id);

        $this->pousser([$this->operation('vehicules', 'modification', $id, ['statut' => 'entretien', 'tarif_jour' => 32000])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(['entretien', '32000.00'], [Vehicule::findOrFail($id)->statut, (string) Vehicule::findOrFail($id)->tarif_jour]);

        $this->pousser([$this->operation('vehicules', 'modification', $id, ['statut' => 'loue'])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'rejete');
    }

    #[Test]
    public function deux_postes_ne_louent_jamais_le_meme_vehicule_sur_la_meme_periode(): void
    {
        $v = Vehicule::create(['immatriculation' => 'BJ-9', 'categorie' => 'voiture', 'annee' => 2020, 'tarif_jour' => '25000', 'statut' => 'disponible']);
        $a = $this->uuid();

        $this->pousser([$this->contrat($a, $v->id, '2026-10-20', '2026-10-23')], $this->gerant, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.montant', '75000.00');
        $c = ContratLocation::findOrFail($a);
        $this->assertSame(['actif', '75000.00'], [$c->getAttribute('statut'), (string) $c->getAttribute('montant')]);
        $this->assertStringStartsWith('LOC', (string) $c->getAttribute('numero'));

        $this->pousser([$this->contrat($this->uuid(), $v->id, '2026-10-22', '2026-10-24')], $this->gerant, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('vehicules.chevauchement'));
    }

    #[Test]
    public function l_annulation_d_un_contrat_du_poste_libere_le_vehicule_et_se_rejoue_sans_effet(): void
    {
        $v = Vehicule::create(['immatriculation' => 'BJ-7', 'categorie' => 'voiture', 'annee' => 2020, 'tarif_jour' => '25000', 'statut' => 'disponible']);
        $a = $this->uuid();
        $this->pousser([$this->contrat($a, $v->id, '2026-10-20', '2026-10-23')], $this->gerant, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        // Le contrat annulé libère la plage : un autre poste peut louer.
        $this->pousser([$this->operation('contrats_location', 'modification', $a, ['statut' => 'annule'])], $this->gerant, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('annule', ContratLocation::findOrFail($a)->statut);
        $this->pousser([$this->contrat($this->uuid(), $v->id, '2026-10-21', '2026-10-22')], $this->gerant, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        // Rejeu (un autre poste, ou la PWA, l'avait déjà annulé) : accepté.
        $this->pousser([$this->operation('contrats_location', 'modification', $a, ['statut' => 'annule'])], $this->gerant, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(2, ContratLocation::query()->count());
    }

    #[Test]
    public function un_contrat_ne_se_modifie_que_par_son_annulation(): void
    {
        $v = Vehicule::create(['immatriculation' => 'BJ-8', 'categorie' => 'voiture', 'annee' => 2020, 'tarif_jour' => '25000', 'statut' => 'disponible']);
        $a = $this->uuid();
        $this->pousser([$this->contrat($a, $v->id, '2026-10-20', '2026-10-23')], $this->gerant, 'poste-a');

        foreach ([
            ['statut' => 'actif'],
            ['statut' => 'loue'],
            ['date_fin' => '2026-10-30'],
            ['statut' => 'annule', 'montant' => '1.00'],
        ] as $payload) {
            $this->pousser([$this->operation('contrats_location', 'modification', $a, $payload)], $this->gerant, 'poste-a')
                ->assertJsonPath('resultats.0.statut', 'rejete');
        }

        $contrat = ContratLocation::findOrFail($a);
        $this->assertSame(['actif', '2026-10-23', '75000.00'], [$contrat->statut, $contrat->date_fin->toDateString(), (string) $contrat->montant]);

        $this->pousser([$this->operation('contrats_location', 'modification', $a, ['statut' => 'actif'])], $this->gerant, 'poste-a')
            ->assertJsonPath('resultats.0.motif', __('sync.vehicules.contrat_statut_refuse', ['statut' => 'actif']));
        $this->pousser([$this->operation('contrats_location', 'modification', $a, ['date_fin' => '2026-10-30'])], $this->gerant, 'poste-a')
            ->assertJsonPath('resultats.0.motif', __('sync.vehicules.contrat_champ_non_modifiable', ['champs' => 'date_fin']));
    }

    #[Test]
    public function l_annulation_exige_le_droit_ecriture_de_la_location(): void
    {
        $v = Vehicule::create(['immatriculation' => 'BJ-9X', 'categorie' => 'voiture', 'annee' => 2020, 'tarif_jour' => '25000', 'statut' => 'disponible']);
        $a = $this->uuid();
        $this->pousser([$this->contrat($a, $v->id, '2026-10-20', '2026-10-23')], $this->gerant, 'poste-a');

        $this->pousser([$this->operation('contrats_location', 'modification', $a, ['statut' => 'annule'])], $this->creerUtilisateur('cuisine'), 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame('actif', ContratLocation::findOrFail($a)->statut);
    }
}
