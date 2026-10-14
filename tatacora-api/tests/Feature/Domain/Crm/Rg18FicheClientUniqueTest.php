<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Crm;

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\DetectionDoublonService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * RG-18 — Fiche client unique.
 *
 * Le cas de test obligatoire de 07_TESTING_QA.md §2 est explicite :
 * « création de client avec nom/téléphone proches d'un existant →
 * avertissement affiché, création NON bloquée ».
 */
final class Rg18FicheClientUniqueTest extends TestCase
{
    use RefreshDatabase;

    private DetectionDoublonService $service;

    protected function setUp(): void
    {
        parent::setUp();
        $this->service = app(DetectionDoublonService::class);
    }

    #[Test]
    public function rg18_un_telephone_identique_est_signale(): void
    {
        Client::factory()->create(['nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '01 97 35 59 74']);

        $doublons = $this->service->rechercherDoublons('AMEGAN', '01 97 35 59 74');

        $this->assertCount(1, $doublons);
        $this->assertStringContainsString('téléphone', $doublons->first()['motif']);
    }

    #[Test]
    public function rg18_le_telephone_est_compare_sans_tenir_compte_du_formatage(): void
    {
        Client::factory()->create(['nom' => 'KORA', 'telephone' => '01 97 35 59 74']);

        // Même numéro, saisi sans espaces : un formatage différent ne doit pas
        // faire passer un doublon pour un nouveau client.
        $doublons = $this->service->rechercherDoublons('KORA', '0197355974');

        $this->assertCount(1, $doublons);
    }

    #[Test]
    public function rg18_un_nom_identique_seul_suffit_a_avertir(): void
    {
        Client::factory()->create(['nom' => 'KORA', 'telephone' => '01 11 11 11 11']);

        $doublons = $this->service->rechercherDoublons('kora', '01 22 22 22 22');

        $this->assertCount(1, $doublons);
        $this->assertStringContainsString('nom identique', $doublons->first()['motif']);
    }

    #[Test]
    public function rg18_une_faute_de_frappe_sur_le_nom_avec_le_meme_telephone_est_signalee(): void
    {
        Client::factory()->create(['nom' => 'KORA', 'telephone' => '01 97 35 59 74']);

        $doublons = $this->service->rechercherDoublons('KORRA', '01 97 35 59 74');

        $this->assertCount(1, $doublons);
    }

    #[Test]
    public function rg18_deux_clients_reellement_distincts_ne_sont_pas_signales(): void
    {
        Client::factory()->create(['nom' => 'KORA', 'telephone' => '01 11 11 11 11']);

        $doublons = $this->service->rechercherDoublons('MENSAH', '01 22 22 22 22');

        $this->assertCount(0, $doublons);
        $this->assertNull($this->service->messageAvertissement($doublons));
    }

    /**
     * Le point le plus important de RG-18 : l'avertissement ne bloque pas.
     */
    #[Test]
    public function rg18_la_creation_reste_possible_malgre_un_doublon_detecte(): void
    {
        Client::factory()->create(['nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '01 97 35 59 74']);

        $doublons = $this->service->rechercherDoublons('KORA', '01 97 35 59 74');
        $this->assertNotEmpty($doublons);
        $this->assertNotNull($this->service->messageAvertissement($doublons));

        // Deux personnes peuvent légitimement partager un numéro (famille,
        // structure) : le système avertit, l'utilisateur tranche.
        $homonyme = Client::factory()->create([
            'nom' => 'KORA',
            'prenom' => 'Awa',
            'telephone' => '01 97 35 59 74',
        ]);

        $this->assertDatabaseHas('clients', ['id' => $homonyme->id]);
        $this->assertSame(2, Client::count());
    }

    #[Test]
    public function rg18_une_fiche_ne_se_signale_pas_elle_meme_en_modification(): void
    {
        $client = Client::factory()->create(['nom' => 'KORA', 'telephone' => '01 97 35 59 74']);

        $doublons = $this->service->rechercherDoublons('KORA', '01 97 35 59 74', exclureId: $client->id);

        $this->assertCount(0, $doublons);
    }
}
