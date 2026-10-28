<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Vehicules;

use App\Domain\Crm\Models\Client;
use App\Domain\Vehicules\Etats\EtatLocations;
use App\Domain\Vehicules\Models\ContratLocation;
use App\Domain\Vehicules\Models\Vehicule;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * État M14 « Locations » : un contrat ANNULÉ n'est ni une ligne, ni dans le
 * nombre, ni dans le montant (PRD corrections Locations, R1).
 */
final class EtatLocationsAnnulesTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function un_contrat_annule_est_exclu_des_lignes_du_nombre_et_du_montant(): void
    {
        $client = Client::factory()->create();
        $vehicule = Vehicule::create([
            'categorie' => 'voiture', 'immatriculation' => 'AB 1', 'annee' => 2020,
            'tarif_jour' => '10000.00', 'statut' => 'disponible',
        ]);

        $creer = static function (string $debut, string $fin, string $statut) use ($vehicule, $client): void {
            $contrat = ContratLocation::create([
                'vehicule_id' => $vehicule->id, 'client_id' => $client->id,
                'date_debut' => $debut, 'date_fin' => $fin,
            ]);
            $contrat->forceFill(['statut' => $statut])->save();
        };

        $creer('2026-10-01', '2026-10-03', 'actif');
        $creer('2026-10-10', '2026-10-12', 'annule');

        $etat = (new EtatLocations())->calculer([]);

        $this->assertCount(1, $etat->lignes);
        $valeurs = array_values($etat->kpis);
        $this->assertSame('1', $valeurs[0]);
        $this->assertSame(
            (string) bcmul('10000.00', (string) ContratLocation::query()->where('statut', 'actif')->first()->nombreJours(), 2),
            $valeurs[1],
        );
    }
}
