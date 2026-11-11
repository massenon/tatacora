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

    /**
     * Un actif (3 jours) et un annulé (3 jours) à 10 000 FCFA/jour.
     */
    private function deuxContrats(): void
    {
        $client = Client::factory()->create();
        $vehicule = Vehicule::create([
            'categorie' => 'voiture', 'immatriculation' => 'AB 1', 'annee' => 2020,
            'tarif_jour' => '10000.00', 'statut' => 'disponible',
        ]);

        foreach ([['2026-10-10', '2026-10-12', 'annule'], ['2026-10-01', '2026-10-03', 'actif']] as [$debut, $fin, $statut]) {
            $contrat = ContratLocation::create([
                'vehicule_id' => $vehicule->id, 'client_id' => $client->id,
                'date_debut' => $debut, 'date_fin' => $fin,
            ]);
            $contrat->forceFill(['statut' => $statut])->save();
        }
    }

    #[Test]
    public function case_cochee_les_annules_sont_listes_a_part_avec_leur_statut_et_jamais_comptes(): void
    {
        $this->deuxContrats();
        $etat = new EtatLocations();

        $decoche = $etat->calculer([]);
        $coche = $etat->calculer(['inclure_annules' => '1']);

        // Les totaux sont IDENTIQUES : un annulé n'est jamais du chiffre d'affaires.
        $this->assertSame($decoche->kpis, $coche->kpis);
        $jours = ContratLocation::query()->where('statut', 'actif')->first()->nombreJours();
        $this->assertSame(['1', bcmul('10000.00', (string) $jours, 2)], array_values($coche->kpis));

        // Décochée : six colonnes, pas de statut, un seul contrat.
        $this->assertCount(6, $decoche->entetes);
        $this->assertCount(1, $decoche->lignes);

        // Cochée : colonne « Statut », l'annulé vient APRÈS l'actif, montant vide.
        $this->assertCount(7, $coche->entetes);
        $this->assertSame('Statut', $coche->entetes[6]);
        $this->assertCount(2, $coche->lignes);
        $this->assertSame(['Actif', 'Annulé'], array_column($coche->lignes, 6));
        $this->assertNotSame('', $coche->lignes[0][5]);
        $this->assertSame('', $coche->lignes[1][5]);
        $this->assertSame(['inclure_annules' => '1'], $coche->filtresAppliques);
    }

    #[Test]
    public function la_periode_dit_si_les_annules_sont_exclus_ou_inclus(): void
    {
        $etat = new EtatLocations();

        $this->assertSame('Toutes dates · contrats annulés exclus', $etat->periode([]));
        $this->assertStringContainsString('inclus, non comptés dans les totaux', $etat->periode(['inclure_annules' => '1']));
        $this->assertStringEndsWith('contrats annulés exclus', $etat->periode(['date_debut' => '2026-01-01', 'date_fin' => '2026-12-31']));
    }

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
