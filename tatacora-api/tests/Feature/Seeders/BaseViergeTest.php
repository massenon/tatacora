<?php

declare(strict_types=1);

namespace Tests\Feature\Seeders;

use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Database\Seeders\DatabaseSeeder;
use Database\Seeders\ParametresEtablissementSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * `php artisan migrate:fresh --seed` rend une base VIERGE (directive PO du
 * 14/10/2026) : référentiels indispensables et paramètres du PO, AUCUNE donnée
 * de démonstration, AUCUN compte.
 */
final class BaseViergeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
    }

    #[Test]
    public function aucune_donnee_de_demonstration_ni_aucun_compte(): void
    {
        foreach ([
            'utilisateurs', 'articles', 'cartes_boisson', 'plats', 'menus', 'recettes',
            'clients', 'fournisseurs', 'employes', 'unites_hebergement', 'vehicules',
            'circuits', 'tables_salle', 'reservations', 'ventes', 'depenses', 'ecritures_comptables',
        ] as $table) {
            $this->assertSame(0, DB::table($table)->count(), "La table {$table} devrait etre vide.");
        }

        foreach ([
            'roles', 'canaux_reservation', 'plan_comptable', 'journaux_comptables',
            'centres_cout', 'exercices_comptables', 'modeles_notification',
        ] as $table) {
            $this->assertGreaterThan(0, DB::table($table)->count(), "Le referentiel {$table} manque.");
        }
    }

    #[Test]
    public function les_vingt_parametres_du_po_sont_semes_et_tous_au_registre(): void
    {
        $this->assertCount(20, ParametresEtablissementSeeder::PARAMETRES);

        foreach (ParametresEtablissementSeeder::PARAMETRES as [$cle, $valeur, $description]) {
            $this->assertNotNull(RegistreParametres::definition($cle), "{$cle} absente du registre.");
            $ligne = ParametreSysteme::query()->where('cle', $cle)->first();
            $this->assertNotNull($ligne, "{$cle} non semee.");
            $this->assertSame($valeur, (string) $ligne->valeur, $cle);
            $this->assertSame($description, $ligne->description, $cle);
        }

        // Le taux non confirme reste absent (PA-53).
        $this->assertFalse(ParametreSysteme::query()->where('cle', 'taux_cnss_risques_professionnels')->exists());
    }

    #[Test]
    public function l_en_tete_des_etats_lit_l_identite_du_po(): void
    {
        $entete = app(ReportHeaderService::class)->genererEnTete('Essai', 'Periode', null);

        $this->assertSame('0202011344660', $entete->ifu);
        $this->assertSame('RB/NAT/2020-A-137', $entete->rccm);
        $this->assertSame('TATACORA AFRIQUE Gîte Chez Noël', $entete->raisonSociale);
        $this->assertSame('NABOGOU Noel', $entete->promoteur);
        $this->assertSame('0197355974', $entete->whatsapp);
        $this->assertSame('https://tatacora.com/', $entete->siteWeb);
    }
}
