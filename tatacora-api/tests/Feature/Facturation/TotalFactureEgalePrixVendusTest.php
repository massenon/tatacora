<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Shared\Parametres\Models\ParametreSysteme;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * 10/11/2026 (constat du PO : « Encaissements de factures — Le montant dépasse le reste dû (29999.99 F) »
 * pour une facture de 30 000 F). Tous les prix sont TTC : le TTC d'une facture est la SOMME des prix
 * vendus, au franc près, comme au poste. La ventilation HT/TVA ligne par ligne arrondit chaque HT au
 * centime : la somme des TTC reconstitués pouvait dériver de ±0,01 (deux lignes de 15 000 → 29 999,99),
 * et l'encaissement exact du poste était refusé. La TVA est le COMPLÉMENT (TTC − HT), jamais l'inverse.
 */
final class TotalFactureEgalePrixVendusTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        ParametreSysteme::updateOrCreate(['cle' => 'tva_active'], ['valeur' => '1']);
        ParametreSysteme::updateOrCreate(['cle' => 'taux_tva'], ['valeur' => '18']);
        ParametreSysteme::updateOrCreate(['cle' => 'convention_prix'], ['valeur' => 'ttc']);
    }

    /** @return array<string, array{0: list<array{0: int, 1: int}>, 1: string}> */
    public static function cas(): array
    {
        return [
            'deux lignes de 15 000' => [[[15000, 1], [15000, 1]], '30000.00'],
            'trois fois 10 000' => [[[10000, 3]], '30000.00'],
            'trois lignes de 10 000' => [[[10000, 1], [10000, 1], [10000, 1]], '30000.00'],
            'mélange du comptoir' => [[[3700, 1], [3500, 1], [1500, 2], [2000, 1]], '12200.00'],
            'une ligne' => [[[30000, 1]], '30000.00'],
        ];
    }

    /** @param list<array{0: int, 1: int}> $lignes */
    #[Test]
    #[DataProvider('cas')]
    public function le_ttc_de_la_facture_est_la_somme_des_prix_vendus(array $lignes, string $attendu): void
    {
        $service = app(EmissionFactureService::class);
        $client = Client::create(['nom' => 'KORA', 'prenom' => 'J', 'telephone' => '01 90 00 00 01', 'type_client' => 'particulier']);
        $facture = $service->emettreVide($client->id);

        foreach ($lignes as [$prix, $quantite]) {
            $service->ajouterLigne($facture, 'M4', $facture->id, 'Ligne', (string) $quantite, (string) $prix.'.00');
        }

        $facture->refresh();
        $this->assertSame($attendu, (string) $facture->montant_ttc);
        // La TVA est le complément : HT + TVA = TTC, au centime.
        $this->assertSame($attendu, bcadd((string) $facture->montant_ht, (string) $facture->montant_tva, 2));
    }
}
