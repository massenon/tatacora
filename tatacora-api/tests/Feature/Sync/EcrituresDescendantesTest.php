<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Services\CatalogueDescendantService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les écritures VALIDÉES descendent aux postes (21/10/2026, « compte de
 * résultat et bilan sur le poste ») : validées seules, avec leur compte, leur
 * journal et l'année de leur exercice déjà résolus, sous le droit M10.
 */
final class EcrituresDescendantesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-21 08:00:00');
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->actingAs($this->utilisateur('comptable'));
    }

    private function passer(string $libelle, bool $valider): void
    {
        $donnees = [
            'journal' => 'OD',
            'date' => '2026-10-20',
            'libelle' => $libelle,
            'lignes' => [
                ['compte' => '5711', 'debit' => '12500.50'],
                ['compte' => '7011', 'credit' => '12500.50', 'centre_id' => CentreCout::query()->value('id')],
            ],
        ];
        $service = app(PasserEcritureService::class);
        $valider ? $service->passerEtValider($donnees) : $service->passer($donnees);
    }

    /**
     * @return list<array<string, mixed>>
     */
    private function ecrituresDuFlux(User $utilisateur): array
    {
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($utilisateur);
        $elements = [];
        $curseur = null;

        do {
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter([
                'poste_id' => 'poste-1', 'depuis' => $curseur, 'limite' => 5,
            ], static fn ($v): bool => $v !== null)))->assertOk();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        return array_values(array_filter($elements, static fn (array $e): bool => $e['table'] === 'ecritures_comptables'));
    }

    #[Test]
    public function seules_les_ecritures_validees_descendent_avec_compte_journal_et_annee(): void
    {
        $this->passer('Brouillon qui ne descend pas', false);
        $this->passer('Vente validée', true);

        $ecritures = $this->ecrituresDuFlux($this->utilisateur('comptable'));

        // Une pièce validée = DEUX lignes ; le brouillon n'en donne aucune.
        $this->assertCount(2, $ecritures);
        foreach ($ecritures as $e) {
            $this->assertSame('Vente validée', $e['donnees']['libelle']);
            $this->assertSame(2026, $e['donnees']['annee']);
            $this->assertSame('OD', $e['donnees']['code_journal']);
            $this->assertSame('2026-10-20', substr((string) $e['donnees']['date_ecriture'], 0, 10));
        }

        $parCompte = collect($ecritures)->keyBy(static fn (array $e): string => $e['donnees']['numero_compte']);
        $this->assertSame('12500.50', $parCompte['5711']['donnees']['debit']);
        $this->assertSame('0.00', $parCompte['5711']['donnees']['credit']);
        $this->assertSame('12500.50', $parCompte['7011']['donnees']['credit']);
        $this->assertSame('7', $parCompte['7011']['donnees']['classe']);
        $this->assertNotSame('', $parCompte['7011']['donnees']['libelle_compte']);
        $this->assertNotNull($parCompte['5711']['donnees']['numero_piece']);
    }

    #[Test]
    public function une_piece_validee_plus_tard_descend_alors_et_pas_avant(): void
    {
        $this->passer('Pièce en brouillon', false);
        $this->assertSame([], $this->ecrituresDuFlux($this->utilisateur('comptable')));

        // La validation fait avancer `updated_at` : la pièce passe sous le
        // curseur suivant, sans que rien n'ait à être rejoué.
        $piece = \App\Domain\Comptabilite\Models\EcritureComptable::query()->where('libelle', 'Pièce en brouillon')->get();
        app(\App\Domain\Comptabilite\Services\EcritureComptableService::class)->valider($piece);

        $this->assertCount(2, $this->ecrituresDuFlux($this->utilisateur('comptable')));
    }

    #[Test]
    public function sans_droit_sur_m10_aucune_ecriture_ne_descend(): void
    {
        $this->passer('Vente validée', true);

        $this->assertSame([], $this->ecrituresDuFlux($this->utilisateur('guide')));
        $this->assertCount(2, $this->ecrituresDuFlux($this->utilisateur('comptable')));
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    #[Test]
    public function le_plan_comptable_descend_avant_les_ecritures_et_la_piece_d_un_poste_porte_son_origine(): void
    {
        $this->actingAs($this->utilisateur('comptable'));
        $origine = (string) Str::uuid();
        $poste = $this->utilisateur('comptable');
        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        Sanctum::actingAs($poste);
        $piece = app(PasserEcritureService::class)->passer([
            'journal' => 'OD', 'date' => '2026-10-20', 'libelle' => 'Saisie poste', 'lignes' => [
                ['compte' => '5711', 'debit' => '10.00'],
                ['compte' => '7011', 'credit' => '10.00', 'centre_id' => CentreCout::query()->value('id')],
            ],
        ]);
        \Illuminate\Support\Facades\DB::table('ecritures_comptables')->whereIn('id', $piece->pluck('id'))->update(['piece_origine_id' => $origine]);
        app(\App\Domain\Comptabilite\Services\EcritureComptableService::class)->valider($piece);

        $this->travel(CatalogueDescendantService::HORIZON_SECONDES + 1)->seconds();
        $elements = [];
        $curseur = null;
        do {
            $reponse = $this->getJson('/api/v1/referentiels?' . http_build_query(array_filter([
                'poste_id' => 'poste-1', 'depuis' => $curseur, 'limite' => 200,
            ], static fn ($v): bool => $v !== null)))->assertOk();
            $elements = [...$elements, ...$reponse->json('data.elements')];
            $curseur = $reponse->json('meta.curseur');
        } while (! $reponse->json('meta.complet'));

        $tables = array_column($elements, 'table');
        $this->assertContains('plan_comptable', $tables);
        // Le plan arrive AVANT toute écriture : un compte cité existe déjà au poste.
        $this->assertLessThan(array_search('ecritures_comptables', $tables, true), array_search('plan_comptable', $tables, true));
        $compte = collect($elements)->first(static fn (array $e): bool => $e['table'] === 'plan_comptable' && $e['donnees']['numero_compte'] === '5711');
        $this->assertSame(['numero_compte', 'libelle', 'classe', 'nature'], array_keys($compte['donnees']));
        $ecritures = array_filter($elements, static fn (array $e): bool => $e['table'] === 'ecritures_comptables');
        $this->assertNotEmpty($ecritures);
        foreach ($ecritures as $e) {
            $this->assertSame($origine, $e['donnees']['piece_origine_id']);
        }
    }
}
