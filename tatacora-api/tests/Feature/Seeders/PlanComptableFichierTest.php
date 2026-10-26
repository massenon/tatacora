<?php

declare(strict_types=1);

namespace Tests\Feature\Seeders;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Services\DeclarationTvaService;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Hebergement\Services\AnnulationReservationService;
use App\Domain\Ventes\Services\VenteService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use ReflectionClass;
use Tests\TestCase;

/**
 * Le plan comptable du Product Owner est l'UNIQUE source de `plan_comptable`
 * (décision du 10/10/2026, lot 0 — le serveur est la référence, le client
 * Flutter desktop le réplique).
 *
 * Deux garanties : la table EST le fichier, et aucun compte écrit en dur dans
 * le code du serveur n'est absent du fichier.
 *
 * @see ComptabiliteReferentielSeeder
 */
class PlanComptableFichierTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Comptes mouvementés en dur par le code mais ABSENTS du fichier, en
     * attente d'un arbitrage du PO (choix d'une feuille parmi plusieurs
     * candidates — voir la décision du 10/10/2026). Une entrée qui deviendrait
     * présente dans le fichier, ou qui disparaîtrait du code, fait échouer le
     * test : la liste ne peut que se réduire.
     *
     * @var list<string>
     */
    private const DECISIONS_OUVERTES = [];

    #[Test]
    public function la_table_reproduit_exactement_le_fichier_du_po(): void
    {
        $this->seed(ComptabiliteReferentielSeeder::class);

        $fichier = ComptabiliteReferentielSeeder::lireFichier();
        $this->assertCount(1332, $fichier, 'Le fichier du PO compte 1332 comptes.');

        $attendu = [];
        foreach ($fichier as [$numero, $libelle]) {
            $attendu[$numero] = $libelle;
        }
        $this->assertCount(1332, $attendu, 'Aucun numéro en double dans le fichier.');

        $this->assertSame(1332, CompteComptable::query()->count());
        $table = CompteComptable::query()->pluck('libelle', 'numero_compte')->all();
        ksort($attendu, SORT_STRING);
        ksort($table, SORT_STRING);
        $this->assertSame($attendu, $table);
        $this->assertSame(
            0,
            CompteComptable::query()->whereRaw('classe != LEFT(numero_compte, 1)')->count(),
        );
    }

    #[Test]
    public function l_import_est_idempotent(): void
    {
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        $this->assertSame(1332, CompteComptable::query()->count());
    }

    #[Test]
    public function aucun_compte_en_dur_du_code_n_est_absent_du_fichier(): void
    {
        $fichier = array_column(ComptabiliteReferentielSeeder::lireFichier(), 0);

        $absents = array_values(array_diff($this->comptesEnDur(), $fichier));
        sort($absents);
        $attendus = self::DECISIONS_OUVERTES;
        sort($attendus);

        $this->assertSame(
            $attendus,
            $absents,
            'Compte en dur absent du fichier du PO (ou décision ouverte devenue sans objet).',
        );
    }

    #[Test]
    public function une_division_du_plan_ne_recoit_aucun_mouvement_une_feuille_oui(): void
    {
        $this->seed(ComptabiliteReferentielSeeder::class);
        $centre = \App\Domain\Comptabilite\Models\CentreCout::query()->where('libelle', 'Structure')->value('id');
        $service = app(\App\Domain\Comptabilite\Services\PasserEcritureService::class);
        $piece = fn (string $debit, string $credit): array => [
            'journal' => 'OD',
            'date' => now()->toDateString(),
            'libelle' => 'Test',
            'lignes' => [
                ['compte' => $debit, 'debit' => '100.00', 'credit' => '0', 'centre_id' => $centre],
                ['compte' => $credit, 'debit' => '0', 'credit' => '100.00', 'centre_id' => $centre],
            ],
        ];

        // 60, 601 et 4 (divisions) refusés avec la clé de langue exacte ; 552
        // (feuille à 3 chiffres) et 6011 acceptés. Aucun try/catch : un fail()
        // y serait avalé (AssertionFailedError dérive de RuntimeException).
        foreach (['60', '601', '4'] as $division) {
            try {
                $service->passer($piece($division, '5711'));
            } catch (\RuntimeException $refus) {
                $this->assertSame(__('comptabilite.compte_division', ['numero' => $division]), $refus->getMessage());

                continue;
            }
            $this->fail("La division {$division} a reçu un mouvement.");
        }

        $this->assertCount(2, $service->passer($piece('6011', '552')));
    }

    #[Test]
    public function creer_un_compte_accepte_2_3_4_chiffres_et_refuse_1_et_5(): void
    {
        $service = app(\App\Domain\Comptabilite\Services\PlanComptableService::class);

        foreach (['98', '987', '9876'] as $numero) {
            $this->assertSame($numero, $service->creerCompte($numero, 'Compte de test', 'actif')->numero_compte);
        }

        foreach (['9', '98765'] as $numero) {
            try {
                $service->creerCompte($numero, 'Compte de test', 'actif');
            } catch (\RuntimeException $refus) {
                $this->assertSame(__('comptabilite.compte_numero_invalide', ['numero' => $numero]), $refus->getMessage());

                continue;
            }
            $this->fail("Le numéro {$numero} aurait dû être refusé.");
        }
    }

    #[Test]
    public function une_depense_porte_un_centre_explicite_sans_centre_par_defaut_sur_le_compte(): void
    {
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->assertNull(CompteComptable::where('numero_compte', '6052')->value('centre_cout_defaut_id'));
        $centre = \App\Domain\Comptabilite\Models\CentreCout::query()->where('libelle', 'Structure')->value('id');
        $depenses = app(DepenseService::class);
        $donnees = [
            'tresorerie' => 'caisse',
            'libelle' => 'Électricité',
            'lignes' => [['compte_charge' => '6052', 'montant' => '1000.00', 'libelle' => 'SBEE']],
        ];

        try {
            $depenses->enregistrer($donnees);
            $this->fail('Sans centre explicite, la dépense aurait dû être refusée (RG-12).');
        } catch (\RuntimeException $refus) {
            $this->assertStringContainsString('6052', $refus->getMessage());
        }

        $depense = $depenses->enregistrer($donnees + ['centre_id' => $centre]);
        $this->assertSame('1000.00', (string) $depense->montant_total);
    }

    /**
     * @return list<string>
     */
    private function comptesEnDur(): array
    {
        // Tous les DÉFAUTS de la correspondance (26/10/2026) : les constantes de
        // `ComptesSyscohada` (charges comprises) et les défauts par trésorerie.
        $comptes = [
            AnnulationReservationService::COMPTE_AVANCES_CLIENTS,
            DeclarationTvaService::COMPTE_TVA_COLLECTEE,
            DeclarationTvaService::COMPTE_TVA_DEDUCTIBLE,
            DeclarationTvaService::COMPTE_TVA_COLLECTEE_PRESTATIONS,
            ...array_map(
                static fn (string $role): string => \App\Domain\Comptabilite\Support\RolesCorrespondance::defaut($role),
                array_values(VenteService::ROLES_PRODUIT),
            ),
            ...array_map(
                static fn (string $role): string => \App\Domain\Comptabilite\Support\RolesCorrespondance::defaut($role),
                array_values(VenteService::ROLES_TVA),
            ),
            ...array_values((new ReflectionClass(\App\Domain\Comptabilite\Support\ComptesSyscohada::class))->getConstants()),
            ...array_column(DepenseService::TRESORERIES, 'compte'),
        ];

        // Balayage du code : tout littéral `'compte' => 'NNN…'` d'une ligne de pièce.
        $racines = [app_path(), database_path('seeders')];
        $fichiers = [];
        foreach ($racines as $racine) {
            foreach (new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine)) as $f) {
                $fichiers[] = $f;
            }
        }
        foreach ($fichiers as $fichier) {
            if (! $fichier->isFile() || $fichier->getExtension() !== 'php') {
                continue;
            }
            $source = (string) file_get_contents($fichier->getPathname());
            if (preg_match_all("/'compte(?:_charge|_tresorerie)?'\s*=>\s*'([1-9][0-9]{2,5})'/", $source, $m) > 0) {
                array_push($comptes, ...$m[1]);
            }
            if (preg_match_all("/const\s+COMPTE_\w+\s*=\s*'([1-9][0-9]*)'/", $source, $m) > 0) {
                array_push($comptes, ...$m[1]);
            }
        }

        $comptes = array_values(array_unique($comptes));
        $this->assertGreaterThanOrEqual(8, count($comptes), 'Le balayage ne doit pas être vide.');

        return $comptes;
    }
}
