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

    /**
     * Lot L3-S (27/10/2026) : places, année et transmission se saisissent au poste
     * comme au web, à la création ET à la modification, avec les mêmes bornes.
     */
    #[Test]
    public function places_annee_et_transmission_se_creent_et_se_modifient_avec_les_bornes_du_web(): void
    {
        $id = $this->uuid();
        $this->pousser([$this->creation('vehicules', $id, [
            'immatriculation' => 'BJ-77', 'categorie' => 'voiture', 'tarif_jour' => 25000,
            'annee' => 2021, 'capacite' => 5, 'transmission' => 'Manuelle',
        ])], $this->gerant, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');
        $v = Vehicule::findOrFail($id);
        $this->assertSame([2021, 5, 'Manuelle'], [$v->annee, $v->capacite, $v->transmission]);
        // Année donnée : aucun signalement « sans année ».
        $this->assertFalse(AnomalieSynchronisation::query()->where('entite_id', $id)->exists());

        $this->pousser([$this->operation('vehicules', 'modification', $id, ['annee' => 2023, 'capacite' => 7, 'transmission' => 'Automatique'])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $v = Vehicule::findOrFail($id);
        $this->assertSame([2023, 7, 'Automatique'], [$v->annee, $v->capacite, $v->transmission]);

        $this->pousser([$this->operation('vehicules', 'modification', $id, ['transmission' => null])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertNull(Vehicule::findOrFail($id)->transmission);

        // Les bornes de la vue : année de 1950 à l'an prochain, places de 1 à 99, jamais vides.
        $anneeMax = (int) date('Y') + 1;
        foreach ([
            ['annee' => 1949], ['annee' => $anneeMax + 1], ['annee' => null], ['annee' => 'abc'],
            ['capacite' => 0], ['capacite' => 100], ['capacite' => null],
        ] as $refuse) {
            $this->pousser([$this->operation('vehicules', 'modification', $id, $refuse)], $this->gerant)
                ->assertJsonPath('resultats.0.statut', 'rejete');
        }
        $this->pousser([$this->operation('vehicules', 'modification', $id, ['annee' => $anneeMax, 'capacite' => 99])], $this->gerant)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $v = Vehicule::findOrFail($id)->refresh();
        $this->assertSame([$anneeMax, 99], [$v->annee, $v->capacite]);

        // L'année hors bornes est aussi refusée à la création.
        $this->pousser([$this->creation('vehicules', $this->uuid(), [
            'immatriculation' => 'BJ-78', 'categorie' => 'voiture', 'tarif_jour' => 1, 'annee' => 1949,
        ])], $this->gerant)->assertJsonPath('resultats.0.statut', 'rejete');
        $this->assertSame(0, Vehicule::query()->where('immatriculation', 'BJ-78')->count());
    }

    /**
     * Remise et acompte d'un contrat du poste : le montant net, l'acompte et le reste
     * dû sont rangés comme `Locations::enregistrerContrat`, et les deux refus ont les
     * phrases `lte` de la vue.
     */
    #[Test]
    public function la_remise_et_l_acompte_d_un_contrat_du_poste_se_jugent_comme_au_web(): void
    {
        $v = Vehicule::create(['immatriculation' => 'BJ-R1', 'categorie' => 'voiture', 'annee' => 2020, 'tarif_jour' => '25000', 'statut' => 'disponible']);
        $avec = fn (string $id, array $plus): array => $this->creation('contrats_location', $id, [
            'vehicule_id' => $v->id, 'client_id' => $this->client->id, 'date_debut' => '2026-10-20', 'date_fin' => '2026-10-23',
            'piece_identite' => 'CNI-1', 'permis_conduire' => 'P-1', ...$plus,
        ]);

        // 3 jours x 25 000 = 75 000 brut ; remise 5 000 -> net 70 000 ; acompte 20 000 -> reste 50 000.
        $a = $this->uuid();
        $this->pousser([$avec($a, ['remise' => 5000, 'acompte' => 20000])], $this->gerant, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.montant', '70000.00');
        $c = ContratLocation::findOrFail($a);
        $this->assertSame(['70000.00', '20000.00', '50000.00'], [(string) $c->getAttribute('montant'), (string) $c->getAttribute('acompte'), (string) $c->getAttribute('reste_a_payer')]);
        $this->assertStringStartsWith('LOC', (string) $c->getAttribute('numero'));

        // Remise > brut, puis acompte > net : les phrases de la vue, avec la borne rendue.
        $this->pousser([$avec($this->uuid(), ['remise' => 75001])], $this->gerant, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('validation.lte.numeric', ['attribute' => __('vehicules.pwa.champ_remise'), 'value' => '75000.00']));
        $this->pousser([$avec($this->uuid(), ['remise' => 5000, 'acompte' => 70001])], $this->gerant, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('validation.lte.numeric', ['attribute' => __('vehicules.pwa.champ_acompte'), 'value' => '70000.00']));
        $this->pousser([$avec($this->uuid(), ['acompte' => -1])], $this->gerant, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'rejete');

        // Bornes incluses : remise = brut (contrat gratuit), acompte = net.
        $b = $this->uuid();
        $this->pousser([$avec($b, ['remise' => 75000, 'date_debut' => '2026-11-01', 'date_fin' => '2026-11-04'])], $this->gerant, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame(['0.00', '0.00'], [(string) ContratLocation::findOrFail($b)->getAttribute('montant'), (string) ContratLocation::findOrFail($b)->getAttribute('reste_a_payer')]);

        // Un poste d'avant la v41 n'en envoie pas : comportement d'avant (brut, acompte 0).
        $v2 = Vehicule::create(['immatriculation' => 'BJ-R2', 'categorie' => 'voiture', 'annee' => 2020, 'tarif_jour' => '10000', 'statut' => 'disponible']);
        $ancien = $this->uuid();
        $this->pousser([$this->creation('contrats_location', $ancien, [
            'vehicule_id' => $v2->id, 'client_id' => $this->client->id, 'date_debut' => '2026-10-20', 'date_fin' => '2026-10-22',
            'piece_identite' => 'CNI-1', 'permis_conduire' => 'P-1',
        ])], $this->gerant, 'poste-a')->assertJsonPath('resultats.0.statut', 'synchronise');
        $c = ContratLocation::findOrFail($ancien);
        $this->assertSame(['20000.00', '0.00', '20000.00'], [(string) $c->getAttribute('montant'), (string) $c->getAttribute('acompte'), (string) $c->getAttribute('reste_a_payer')]);
    }
}
