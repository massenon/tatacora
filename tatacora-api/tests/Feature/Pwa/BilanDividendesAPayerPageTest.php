<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le compte 465 (associés, dividendes à payer) est au PASSIF CIRCULANT du bilan
 * (avis de l'expert-comptable, 10/11/2026) : les trois vues web du bilan écrivent
 * la ligne « dont dividendes à payer » sous le poste, avec le mot de lang/fr (le
 * poste le relit), et le montant n'est jamais additionné une seconde fois.
 */
final class BilanDividendesAPayerPageTest extends TestCase
{
    use RefreshDatabase;

    private ExerciceComptable $exercice;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-20 10:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->actingAs(User::create([
            'login' => 'comptable.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'comptable')->firstOrFail()->id,
            'statut' => 'actif',
        ]));
        $this->exercice = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();

        $structure = (string) CentreCout::query()->where('libelle', 'Structure')->value('id');
        app(PasserEcritureService::class)->passerEtValider([
            'journal' => 'OD', 'date' => '2026-03-01', 'libelle' => 'Capital',
            'lignes' => [
                ['compte' => '5711', 'debit' => '100000.00', 'credit' => '0.00', 'centre_id' => $structure],
                ['compte' => '131', 'debit' => '0.00', 'credit' => '100000.00', 'centre_id' => $structure],
            ],
        ]);
        app(PasserEcritureService::class)->passerEtValider([
            'journal' => 'OD', 'date' => '2026-05-10', 'libelle' => 'Dividendes décidés',
            'lignes' => [
                ['compte' => '131', 'debit' => '40000.00', 'credit' => '0.00', 'centre_id' => $structure],
                ['compte' => '465', 'debit' => '0.00', 'credit' => '40000.00', 'centre_id' => $structure],
            ],
        ]);
    }

    private function sousLigne(string $html): string
    {
        $mot = __('comptabilite_pwa.bilan_dont_dividendes_a_payer');
        $this->assertSame('dont dividendes à payer', $mot);
        $this->assertStringContainsString($mot, $html, 'la ligne « dont dividendes à payer » manque à la vue');

        return $mot;
    }

    #[Test]
    public function la_page_du_bilan_porte_le_dont_dividendes_a_payer_sous_le_passif_circulant(): void
    {
        $html = (string) $this->get(route('pwa.comptabilite.bilan', ['exercice' => $this->exercice->id]))->assertOk()->getContent();
        $this->sousLigne($html);
        $this->assertMatchesRegularExpression('#dont dividendes à payer</span>\s*<span[^>]*>\s*40\D*000#u', $html);
        $this->assertStringContainsString('Bilan équilibré', $html);
    }

    #[Test]
    public function l_onglet_bilan_du_hub_porte_le_dont_avec_le_montant_et_sans_le_compter_deux_fois(): void
    {
        $html = (string) $this->get(route('pwa.comptabilite.hub', ['exercice' => $this->exercice->id, 'onglet' => 'bilan']))->assertOk()->getContent();
        $this->sousLigne($html);
        $this->assertMatchesRegularExpression('#dont dividendes à payer</td>\s*<td[^>]*>\s*40\D*000#u', $html);
        // Le total du passif ne compte le 465 qu'une fois : 60 000 de capitaux propres + 40 000.
        $this->assertMatchesRegularExpression('#TOTAL PASSIF</td>\s*<td[^>]*>\s*100\D*000#u', $html);
    }

    #[Test]
    public function la_vue_des_etats_financiers_porte_aussi_le_dont(): void
    {
        $html = (string) $this->get(route('pwa.comptabilite.etats-financiers', ['exercice' => $this->exercice->id]))->assertOk()->getContent();
        $this->sousLigne($html);
    }
}
