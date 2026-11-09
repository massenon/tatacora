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
 * La vue web du flux de trésorerie (TAFIRE) porte TOUTES les lignes qui entrent
 * dans ses totaux (10/11/2026) : produits des cessions, emprunts (variation des
 * dettes financières 16 à 19) et dividendes versés, en plus de la CAFG, du
 * capital et des acquisitions. Sans elles, « TOTAL RESSOURCES » et « TOTAL
 * EMPLOIS » ne s'additionnaient plus à l'écran.
 *
 * Le test lit le HTML RENDU (pas le read-model) : il extrait chaque montant
 * affiché par son libellé et refait les additions que lit un comptable.
 */
final class FluxTresorerieLignesTest extends TestCase
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
    }

    /** @param list<array{0: string, 1: string, 2: string}> $lignes [compte, débit, crédit] */
    private function piece(string $date, string $libelle, array $lignes): void
    {
        $structure = (string) CentreCout::query()->where('libelle', 'Structure')->value('id');
        app(PasserEcritureService::class)->passerEtValider([
            'journal' => 'OD', 'date' => $date, 'libelle' => $libelle,
            'lignes' => array_map(static fn (array $l): array => [
                'compte' => $l[0], 'debit' => $l[1], 'credit' => $l[2], 'centre_id' => $structure,
            ], $lignes),
        ]);
    }

    /** Capital, matériel, exploitation : ni cession, ni emprunt, ni dividende. */
    private function exploiter(): void
    {
        $this->piece('2026-01-02', 'Capital', [['5711', '5000000.00', '0.00'], ['1013', '0.00', '5000000.00']]);
        $this->piece('2026-02-01', 'Matériel', [['2311', '1200000.00', '0.00'], ['5711', '0.00', '1200000.00']]);
        $this->piece('2026-03-10', 'Ventes', [['5711', '110000.00', '0.00'], ['7011', '0.00', '110000.00']]);
        $this->piece('2026-03-11', 'Achats', [['6011', '30000.00', '0.00'], ['5711', '0.00', '30000.00']]);
        $this->piece('2026-04-01', 'Stock', [['3111', '20000.00', '0.00'], ['4011', '0.00', '20000.00']]);
    }

    /** Une cession (brut 100 000, amorti 60 000, prix 50 000), un emprunt de 1 M et des dividendes réglés 25 000. */
    private function ceder_emprunter_distribuer(): void
    {
        $this->piece('2026-05-01', 'Dotation', [['6813', '70000.00', '0.00'], ['2813', '0.00', '70000.00']]);
        $this->piece('2026-06-01', 'Cession', [
            ['5711', '50000.00', '0.00'], ['2813', '60000.00', '0.00'],
            ['811', '40000.00', '0.00'], ['2311', '0.00', '100000.00'], ['821', '0.00', '50000.00'],
        ]);
        $this->piece('2026-06-15', 'Emprunt', [['5711', '1000000.00', '0.00'], ['162', '0.00', '1000000.00']]);
        $this->piece('2026-07-01', 'Dividendes décidés', [['111', '40000.00', '0.00'], ['465', '0.00', '40000.00']]);
        $this->piece('2026-07-10', 'Règlement dividendes', [['465', '25000.00', '0.00'], ['5711', '0.00', '25000.00']]);
    }

    private function page(): string
    {
        $reponse = $this->get(route('pwa.comptabilite.flux-tresorerie', ['exercice' => $this->exercice->id]));
        $reponse->assertOk();

        return $reponse->getContent();
    }

    /** Le montant AFFICHÉ en face d'un libellé, en unités entières. */
    private function montant(string $html, string $libelle): int
    {
        $motif = '#<span class="[^"]*">' . '(?:' . preg_quote($libelle, '#') . '|' . preg_quote(e($libelle), '#') . ')' . '</span>\s*<span class="[^"]*">([^<]*)</span>#u';
        $this->assertSame(1, preg_match($motif, $html, $m), "ligne absente de la vue : « {$libelle} »");

        $texte = str_replace(["\u{00A0}", "\u{202F}", ' ', 'FCFA'], '', html_entity_decode($m[1]));
        $texte = str_replace(['−', '–'], '-', $texte);
        $this->assertMatchesRegularExpression('/^-?\d+$/', $texte, "montant illisible en face de « {$libelle} »");

        return (int) $texte;
    }

    /** @return array<string, string> les libellés lus de lang/fr, jamais recopiés. */
    private function libelles(): array
    {
        return [
            'cessions' => __('comptabilite_pwa.flux_produits_cessions'),
            'emprunts' => __('comptabilite_pwa.flux_variation_emprunts'),
            'dividendes' => __('comptabilite_pwa.flux_dividendes_verses'),
        ];
    }

    /** Les additions que lit un comptable, refaites sur ce que la vue AFFICHE. */
    private function assertLesTotauxSAdditionnent(string $html): void
    {
        $l = $this->libelles();

        $cafg = $this->montant($html, "Capacité d'Autofinancement Globale (CAFG)");
        $capital = $this->montant($html, 'Augmentation de capital');
        $totalRessources = $this->montant($html, 'TOTAL RESSOURCES');
        $this->assertSame(
            $cafg + $this->montant($html, $l['cessions']) + $capital + $this->montant($html, $l['emprunts']),
            $totalRessources,
            'les lignes de RESSOURCES ne somment pas TOTAL RESSOURCES',
        );

        $totalEmplois = $this->montant($html, 'TOTAL EMPLOIS');
        $this->assertSame(
            $this->montant($html, "Acquisitions d'immobilisations") + $this->montant($html, $l['dividendes']),
            $totalEmplois,
            'les lignes d\'EMPLOIS ne somment pas TOTAL EMPLOIS',
        );

        $bfr = $this->montant($html, 'Variation des stocks')
            + $this->montant($html, '+ Variation des créances')
            - $this->montant($html, '− Variation des dettes');
        $this->assertSame($bfr, $this->montant($html, '= VARIATION DU BFR'));

        $calculee = $this->montant($html, 'Total ressources − Total emplois − Variation BFR');
        $this->assertSame($totalRessources - $totalEmplois - $bfr, $calculee);
        $this->assertSame(
            $calculee,
            $this->montant($html, 'Variation réelle des comptes de trésorerie (521/522/571/572/573)'),
            'la somme des lignes affichées n\'est pas la variation de trésorerie affichée',
        );
    }

    #[Test]
    public function les_trois_lignes_sont_affichees_avec_leur_montant_quand_cession_emprunt_et_dividende_existent(): void
    {
        $this->exploiter();
        $this->ceder_emprunter_distribuer();
        $html = $this->page();
        $l = $this->libelles();

        $this->assertSame(50000, $this->montant($html, $l['cessions']));
        $this->assertSame(1000000, $this->montant($html, $l['emprunts']));
        $this->assertSame(25000, $this->montant($html, $l['dividendes']));
        $this->assertSame('Dividendes versés (affectation du résultat N-1)', $l['dividendes']);
        $this->assertStringContainsString('Contrôle de cohérence réussi', $html);

        $this->assertLesTotauxSAdditionnent($html);
    }

    #[Test]
    public function sans_cession_emprunt_ni_dividende_les_trois_lignes_sont_a_zero_et_les_totaux_s_additionnent(): void
    {
        $this->exploiter();
        $html = $this->page();
        $l = $this->libelles();

        $this->assertSame(0, $this->montant($html, $l['cessions']));
        $this->assertSame(0, $this->montant($html, $l['emprunts']));
        $this->assertSame(0, $this->montant($html, $l['dividendes']));

        $this->assertLesTotauxSAdditionnent($html);
    }

    #[Test]
    public function les_trois_libelles_viennent_de_lang_fr_et_ne_sont_pas_ecrits_en_dur_dans_la_vue(): void
    {
        $source = (string) file_get_contents(resource_path('views/pwa/comptabilite/flux-tresorerie.blade.php'));
        $sansCommentaires = (string) preg_replace('/\{\{--.*?--\}\}/s', '', $source);

        foreach (['flux_produits_cessions', 'flux_variation_emprunts', 'flux_dividendes_verses'] as $cle) {
            $this->assertStringContainsString("__('comptabilite_pwa.{$cle}')", $source);
            $this->assertNotSame("comptabilite_pwa.{$cle}", __("comptabilite_pwa.{$cle}"), "clé de langue absente : {$cle}");
        }
        foreach ($this->libelles() as $libelle) {
            $this->assertStringNotContainsString($libelle, $sansCommentaires, 'libellé écrit en dur dans la vue');
        }
    }
}
