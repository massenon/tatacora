<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Depenses;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Domain\Depenses\Models\Depense;
use App\Domain\Depenses\Services\DepenseService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;
use Throwable;

/**
 * Une dépense produit une écriture comptable — PA-159 lot 0b, T4.
 *
 * ## Le défaut couvert ici
 *
 * `DepenseService` importait `PasserEcritureService`, **une classe qui
 * n'existait nulle part**, derrière un `class_exists()` qui rendait `false`
 * pour toujours. Sans erreur, sans journal, sans un mot à l'écran : cinq
 * dépenses en base, zéro écriture, un bandeau vert à chaque saisie, et un
 * grand livre qui ne voyait jamais l'argent sortir.
 *
 * Le premier test de ce fichier est donc littéral : la classe existe. Il paraît
 * trivial, et c'est exactement le contrôle qui manquait — un import mort n'est
 * visible d'aucune suite verte.
 *
 * @see EF-M10-02 Saisie des écritures comptables
 * @see RG-11 Immutabilité — correction par contre-passation
 * @see RG-12 Centre de coût obligatoire
 */
final class ComptabilisationDepenseTest extends TestCase
{
    use RefreshDatabase;

    private DepenseService $depenses;

    private User $comptable;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);
        // Le fichier du PO ne porte aucun centre : on en pose un sur 6011, comme le ferait l'Administrateur.
        \App\Domain\Comptabilite\Models\CompteComptable::where('numero_compte', '6011')->update([
            'centre_cout_defaut_id' => \App\Domain\Comptabilite\Models\CentreCout::where('libelle', 'Restaurant')->value('id'),
        ]);

        $this->depenses = app(DepenseService::class);
        $this->comptable = $this->utilisateur('comptable');
        $this->actingAs($this->comptable);
    }

    // ------------------------------------------------------- L'import mort

    #[Test]
    public function le_service_de_passage_d_ecriture_existe_reellement(): void
    {
        $this->assertTrue(
            class_exists(\App\Domain\Comptabilite\Services\PasserEcritureService::class),
            'La classe était importée par DepenseService et par le composant PWA, '
            .'et elle n\'existait nulle part. Le garde-fou `class_exists()` rendait `false` '
            .'pour toujours, en silence.',
        );

        // Sur le CODE, pas sur le texte : ce fichier commente le défaut qu'il
        // corrige, et le mot y figure entre guillemets. Une recherche
        // littérale échouerait sur son propre docblock — et l'aurait fait
        // supprimer, effaçant l'explication.
        $appels = $this->appelsDeFonction(app_path('Domain/Depenses/Services/DepenseService.php'));

        $this->assertNotContains(
            'class_exists',
            $appels,
            'Un `class_exists()` laissé en place rétablirait le silence au premier renommage.',
        );

        $this->assertContains(
            'bcadd',
            $appels,
            'Ancrage de la mesure : sans lui, un tokenizeur cassé rendrait une liste vide, '
            .'donc un test vert qui ne mesure rien.',
        );
    }

    /**
     * Noms de fonctions réellement APPELÉES dans un fichier — commentaires et
     * chaînes exclus par le tokenizeur de PHP lui-même.
     *
     * @return list<string>
     */
    private function appelsDeFonction(string $chemin): array
    {
        $jetons = token_get_all((string) file_get_contents($chemin));
        $appels = [];

        foreach ($jetons as $index => $jeton) {
            if (! is_array($jeton) || $jeton[0] !== T_STRING) {
                continue;
            }

            for ($suivant = $index + 1; $suivant < count($jetons); $suivant++) {
                $candidat = $jetons[$suivant];

                if (is_array($candidat) && in_array($candidat[0], [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true)) {
                    continue;
                }

                if ($candidat === '(') {
                    $appels[] = $jeton[1];
                }

                break;
            }
        }

        return array_values(array_unique($appels));
    }

    // ------------------------------------------------------- Le chemin réel

    #[Test]
    public function une_depense_produit_une_piece_equilibree_et_validee(): void
    {
        $depense = $this->depenseDeMarche();

        $this->assertTrue($depense->estComptabilisee());
        $this->assertNull($depense->ecriture_refus);

        $lignes = EcritureComptable::all();

        // Deux charges au débit + une trésorerie au crédit.
        $this->assertCount(3, $lignes);
        $this->assertSame('23500.00', $this->somme($lignes, 'debit'));
        $this->assertSame('23500.00', $this->somme($lignes, 'credit'));

        // Validée, sans quoi le grand livre, la balance et le tableau de bord
        // — qui filtrent tous `statut = validee` — continueraient de ne pas
        // voir l'argent sortir.
        $this->assertSame(['validee'], $lignes->pluck('statut')->unique()->values()->all());
    }

    #[Test]
    public function la_depense_pointe_la_LIGNE_DE_TRESORERIE_de_sa_piece(): void
    {
        $depense = $this->depenseDeMarche();

        $ecriture = EcritureComptable::findOrFail($depense->ecriture_id);
        $compte = CompteComptable::findOrFail($ecriture->compte_id);

        $this->assertSame('5711', $compte->numero_compte);
        $this->assertSame('23500.00', (string) $ecriture->credit);
        $this->assertSame('0.00', (string) $ecriture->debit);
    }

    #[Test]
    public function rg12_chaque_ligne_porte_un_centre_de_cout_venu_du_plan(): void
    {
        $this->depenseDeMarche();

        $lignes = EcritureComptable::all();

        // Ancrage : sans lui, une pièce vide rendrait cette boucle muette,
        // donc le test vert sans avoir rien mesuré.
        $this->assertCount(3, $lignes);

        foreach ($lignes as $ecriture) {
            // Le centre existe VRAIMENT au référentiel. La colonne étant NOT
            // NULL (RG-12), constater qu'elle n'est pas nulle ne prouve rien.
            $this->assertTrue(
                CentreCout::whereKey($ecriture->centre_id)->exists(),
                'Le centre imputé doit exister au référentiel.',
            );

            $compte = CompteComptable::findOrFail($ecriture->compte_id);
            $this->assertSame(
                $compte->centre_cout_defaut_id,
                $ecriture->centre_id,
                'Le centre vient du plan comptable, jamais d\'une déduction sur le numéro.',
            );
        }
    }

    // ----------------------------------------------------------- Les refus

    #[Test]
    public function une_depense_dont_la_piece_est_refusee_n_est_PAS_enregistree(): void
    {
        try {
            $this->depenses->enregistrer([
                'tresorerie' => 'caisse',
                'libelle' => 'Achat imputé à un compte inexistant',
                'lignes' => [
                    // « 601 » est le numéro que le composant PWA écrivait en
                    // dur : il n'existe dans aucun plan comptable du dépôt.
                    ['compte_charge' => '601', 'nature' => 'Oignon', 'famille' => 'Marché', 'montant' => '15000.00'],
                ],
            ]);
            $this->fail('Un compte inconnu aurait dû être refusé.');
        } catch (RuntimeException $refus) {
            $this->assertStringContainsString('601', $refus->getMessage());
        }

        // Rien n'est écrit : ni la dépense, ni ses lignes, ni la pièce. Un
        // enregistrement muet reproduirait le défaut sous une forme plus douce.
        $this->assertSame(0, Depense::count());
        $this->assertDatabaseCount('lignes_depense', 0);
        $this->assertSame(0, EcritureComptable::count());
    }

    #[Test]
    public function un_exercice_clos_refuse_l_ecriture_et_le_dit_autrement_qu_un_exercice_absent(): void
    {
        ExerciceComptable::query()->update(['statut' => 'cloture']);

        try {
            $this->depenseDeMarche();
            $this->fail('Un exercice clos aurait dû refuser.');
        } catch (RuntimeException $refus) {
            $this->assertStringContainsString('cloture', $refus->getMessage());
        }

        // Absence d'exercice : message distinct, parce que la correction
        // s'applique à un autre endroit.
        ExerciceComptable::query()->delete();

        try {
            $this->depenseDeMarche();
            $this->fail('Une date hors exercice aurait dû refuser.');
        } catch (RuntimeException $refus) {
            $this->assertStringContainsString('Aucun exercice', $refus->getMessage());
        }
    }

    #[Test]
    public function une_tresorerie_inconnue_est_refusee(): void
    {
        $this->expectException(RuntimeException::class);

        $this->depenses->enregistrer([
            'tresorerie' => 'crypto',
            'libelle' => 'Paiement exotique',
            'lignes' => [['compte_charge' => '6011', 'montant' => '1000.00']],
        ]);
    }

    #[Test]
    public function une_depense_sans_ligne_ou_a_montant_nul_est_refusee(): void
    {
        foreach ([[], [['compte_charge' => '6011', 'montant' => '0.00']]] as $lignes) {
            try {
                $this->depenses->enregistrer(['libelle' => 'Vide', 'lignes' => $lignes]);
                $this->fail('Aurait dû être refusée.');
            } catch (RuntimeException) {
                $this->addToAssertionCount(1);
            }
        }
    }

    // ------------------------------------------------------- Numérotation

    #[Test]
    public function la_numerotation_est_sequentielle_et_ne_recule_pas_avec_le_decompte(): void
    {
        $annee = now()->format('Y');

        $this->assertSame("DEP-{$annee}-00001", $this->depenseDeMarche()->numero);
        $this->assertSame("DEP-{$annee}-00002", $this->depenseDeMarche()->numero);
        $this->assertSame("DEP-{$annee}-00003", $this->depenseDeMarche()->numero);
    }

    // ---------------------------------------------------------- Rattrapage

    #[Test]
    public function une_depense_heritee_sans_ecriture_se_rattrape_et_son_echec_se_voit(): void
    {
        // Une dépense telle que l'ancien service en produisait : écrite, sans
        // pièce, avec un numéro de compte qui n'existe pas.
        $depense = Depense::create([
            'numero' => 'DEP-2026-90001',
            'date_transaction' => now()->toDateString(),
            'tresorerie' => 'caisse',
            'compte_tresorerie' => '5711',
            'montant_total' => '15000.00',
            'libelle' => 'Dépense héritée',
            'utilisateur_id' => $this->comptable->id,
        ]);

        $depense->lignes()->create([
            'compte_charge' => '601',
            'nature' => 'Oignon',
            'famille' => 'Marché',
            'montant' => '15000.00',
        ]);

        // Aucun centre par défaut sur les comptes : seul le geste en porte un.
        \App\Domain\Comptabilite\Models\CompteComptable::query()->update(['centre_cout_defaut_id' => null]);
        $centre = \App\Domain\Comptabilite\Models\CentreCout::where('libelle', 'Structure')->value('id');

        $this->assertFalse($depense->estComptabilisee());

        // Le refus est capturé PUIS asserté hors du try : un fail() posé dans le
        // try serait avalé par le catch (AssertionFailedError est un Throwable).
        $refus = null;
        try {
            $this->depenses->comptabiliser($depense, $centre);
        } catch (Throwable $erreur) {
            $refus = $erreur;
        }
        $this->assertNotNull($refus, 'Le compte 601 n\'existe pas : le rattrapage aurait dû échouer.');
        $this->assertStringContainsString('601', $refus->getMessage());

        // La raison est PERSISTÉE — pas avalée : la liste des dépenses doit
        // pouvoir montrer ce qui bloque.
        $depense->refresh();
        $this->assertNotNull($depense->ecriture_refus);
        $this->assertStringContainsString('601', $depense->ecriture_refus);
        $this->assertFalse($depense->estComptabilisee());

        // Compte corrigé mais SANS centre : refusé par RG-12 (phrase exacte), rien d'écrit.
        $depense->lignes()->first()->update(['compte_charge' => '6011']);
        $refusSansCentre = null;
        try {
            $this->depenses->comptabiliser($depense->refresh(), '');
        } catch (Throwable $erreur) {
            $refusSansCentre = $erreur;
        }
        $this->assertNotNull($refusSansCentre, 'Sans centre, le rattrapage doit être refusé (RG-12).');
        $this->assertSame(__('depenses.centre_absent', ['numero' => '6011']), $refusSansCentre->getMessage());
        $this->assertSame(0, EcritureComptable::count());
        $this->assertNotNull($depense->refresh()->ecriture_refus);
        $this->assertFalse($depense->estComptabilisee());

        // Avec un centre explicite, le rattrapage aboutit : pièce équilibrée, ecriture_id posé.
        $rattrapee = $this->depenses->comptabiliser($depense->refresh(), $centre);
        $this->assertNotNull($rattrapee->ecriture_id);
        $this->assertSame(2, EcritureComptable::count());
        $this->assertSame(
            0,
            bccomp((string) EcritureComptable::sum('debit'), (string) EcritureComptable::sum('credit'), 2),
        );
        $this->assertSame([$centre], EcritureComptable::pluck('centre_id')->unique()->values()->all());

        $this->assertTrue($rattrapee->estComptabilisee());
        $this->assertNull($rattrapee->ecriture_refus);

        // Et il est idempotent : repasser ne crée pas une seconde pièce.
        $avant = EcritureComptable::count();
        $this->depenses->comptabiliser($rattrapee, $centre);
        $this->assertSame($avant, EcritureComptable::count());
    }

    #[Test]
    public function le_filtre_nomme_les_depenses_non_comptabilisees(): void
    {
        $this->depenseDeMarche();

        Depense::create([
            'numero' => 'DEP-2026-90002',
            'date_transaction' => now()->toDateString(),
            'tresorerie' => 'caisse',
            'compte_tresorerie' => '5711',
            'montant_total' => '1000.00',
            'libelle' => 'Héritée',
            'utilisateur_id' => $this->comptable->id,
        ]);

        $this->assertCount(2, $this->depenses->filtrer()->get());
        $this->assertCount(1, $this->depenses->filtrer(['non_comptabilisees' => true])->get());
    }

    // ------------------------------------- Le compte n'est plus écrit en dur

    #[Test]
    public function le_plan_comptable_sert_la_liste_des_comptes_de_charge(): void
    {
        $comptes = app(PlanComptableService::class)->comptesDeCharge();

        $this->assertGreaterThan(0, $comptes->count());
        $this->assertSame(['6'], $comptes->pluck('classe')->unique()->values()->all());
        $this->assertContains('6011', $comptes->pluck('numero_compte')->all());

        // « 601 », le numéro écrit en dur dans le composant, n'y est pas.
        $this->assertNotContains('6010', $comptes->pluck('numero_compte')->all());
    }

    // ------------------------------------------------------------ Fixtures

    private function depenseDeMarche(): Depense
    {
        return $this->depenses->enregistrer([
            'date_transaction' => now()->toDateString(),
            'tresorerie' => 'caisse',
            'libelle' => 'Marché du matin',
            'lignes' => [
                ['compte_charge' => '6011', 'libelle' => 'Oignons', 'nature' => 'Oignon', 'famille' => 'Marché', 'montant' => '15000.00'],
                ['compte_charge' => '6011', 'libelle' => 'Tomates', 'nature' => 'Tomate', 'famille' => 'Marché', 'montant' => '8500.00'],
            ],
        ], $this->comptable);
    }

    /**
     * @param  \Illuminate\Support\Collection<int, EcritureComptable>  $lignes
     */
    private function somme(\Illuminate\Support\Collection $lignes, string $colonne): string
    {
        $total = '0.00';

        foreach ($lignes as $ligne) {
            $total = bcadd($total, (string) $ligne->{$colonne}, 2);
        }

        return $total;
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
