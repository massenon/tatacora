<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Comptabilite;

use App\Domain\Comptabilite\Exceptions\EcritureImmuableException;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Immutabilité et intégrité des écritures comptables — RG-11, RG-12.
 *
 * `07_TESTING_QA.md` §2 rend obligatoire, pour RG-11, le même cas que RG-03 :
 * tentative d'`UPDATE`/`DELETE` sur une écriture validée → exception ;
 * correction par contre-passation → écriture d'origine inchangée.
 *
 * `06_DEVELOPMENT_STANDARDS.md` classe **automatiquement Bloquante** toute
 * anomalie touchant une table financière : c'est le niveau de garantie visé
 * ici, et la raison pour laquelle le contrôle vit dans un Observer plutôt que
 * dans un service.
 */
final class Rg11Rg12EcrituresTest extends TestCase
{
    use RefreshDatabase;

    private string $exerciceId;

    private string $journalId;

    private string $centreId;

    private CompteComptable $banque;

    private CompteComptable $vente;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->actingAs($this->utilisateur('comptable'));

        $this->exerciceId = $this->exercice('ouvert', 2026);

        $this->journalId = (string) Str::uuid();
        DB::table('journaux_comptables')->insert([
            'id' => $this->journalId, 'code' => 'OD', 'libelle' => 'Opérations diverses',
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $this->centreId = (string) Str::uuid();
        DB::table('centres_cout')->insert([
            'id' => $this->centreId, 'libelle' => 'Structure',
            'created_at' => now(), 'updated_at' => now(),
        ]);

        $this->banque = CompteComptable::create([
            'numero_compte' => '521000', 'libelle' => 'Banque', 'classe' => '5', 'nature' => 'actif',
        ]);
        $this->vente = CompteComptable::create([
            'numero_compte' => '701000', 'libelle' => 'Ventes', 'classe' => '7', 'nature' => 'produit',
        ]);
    }

    private function service(): EcritureComptableService
    {
        return app(EcritureComptableService::class);
    }

    // -------------------------------------------------------- Équilibre

    #[Test]
    public function une_piece_desequilibree_est_refusee(): void
    {
        $this->assertThrows(
            fn () => $this->piece(debit: '100000.00', credit: '90000.00'),
            RuntimeException::class,
        );

        // Rien n'a été écrit : le contrôle a lieu AVANT la transaction.
        $this->assertSame(0, EcritureComptable::count());
    }

    #[Test]
    public function une_piece_a_zero_est_refusee_bien_qu_equilibree(): void
    {
        $this->assertThrows(
            fn () => $this->piece(debit: '0.00', credit: '0.00'),
            RuntimeException::class,
        );
    }

    #[Test]
    public function une_piece_equilibree_est_ecrite_en_brouillon(): void
    {
        $piece = $this->piece();

        $this->assertCount(2, $piece);
        // Toute pièce naît en brouillon : la validation est un acte distinct.
        $this->assertTrue($piece->every(fn (EcritureComptable $e): bool => $e->statut === 'brouillon'));
    }

    /**
     * Un écart au centime doit être détecté : c'est précisément l'erreur
     * qu'une comparaison flottante laisserait passer.
     */
    #[Test]
    public function un_ecart_d_un_centime_est_detecte(): void
    {
        $this->assertThrows(
            fn () => $this->piece(debit: '100000.00', credit: '99999.99'),
            RuntimeException::class,
        );
    }

    // ------------------------------------------------------------- RG-11

    #[Test]
    public function rg11_une_ecriture_validee_ne_peut_plus_etre_modifiee(): void
    {
        $piece = $this->service()->valider($this->piece());
        $ecriture = $piece->first();

        $this->assertThrows(
            fn () => $ecriture->update(['libelle' => 'Libellé corrigé']),
            EcritureImmuableException::class,
        );

        $this->assertThrows(
            fn () => $ecriture->update(['debit' => '1.00']),
            EcritureImmuableException::class,
        );

        $this->assertSame('Vente comptant', $ecriture->fresh()->libelle);
    }

    /**
     * L'Observer couvre TOUS les chemins d'écriture : le vérifier depuis un
     * `update()` de modèle direct, sans passer par le service, est le seul
     * moyen de le prouver.
     */
    #[Test]
    public function rg11_une_ecriture_validee_ne_peut_pas_etre_supprimee(): void
    {
        $ecriture = $this->service()->valider($this->piece())->first();

        $this->assertThrows(fn () => $ecriture->delete(), EcritureImmuableException::class);
        $this->assertDatabaseHas('ecritures_comptables', ['id' => $ecriture->id]);
    }

    /**
     * Même en brouillon : un trou dans la séquence est précisément ce qu'un
     * contrôle fiscal recherche.
     */
    #[Test]
    public function rg11_une_ecriture_en_brouillon_ne_peut_pas_non_plus_etre_supprimee(): void
    {
        $ecriture = $this->piece()->first();

        $this->assertSame('brouillon', $ecriture->statut);
        $this->assertThrows(fn () => $ecriture->delete(), EcritureImmuableException::class);
    }

    /**
     * Le passage brouillon → validée doit rester possible : c'est la seule
     * modification légitime d'une écriture non encore validée.
     */
    #[Test]
    public function rg11_la_validation_elle_meme_n_est_pas_bloquee(): void
    {
        $piece = $this->service()->valider($this->piece());

        $this->assertTrue($piece->every(fn (EcritureComptable $e): bool => $e->statut === 'validee'));
    }

    #[Test]
    public function rg11_une_ecriture_en_brouillon_reste_modifiable(): void
    {
        $ecriture = $this->piece()->first();

        $ecriture->update(['libelle' => 'Libellé corrigé avant validation']);

        $this->assertSame('Libellé corrigé avant validation', $ecriture->fresh()->libelle);
    }

    // ------------------------------------------------- Contre-passation

    /**
     * Le cœur de RG-11 : la correction ajoute un mouvement inverse, elle
     * n'efface rien. Le grand livre montre les deux — une correction sans
     * trace serait indétectable à l'audit.
     */
    #[Test]
    public function rg11_la_contrepassation_inverse_sans_toucher_l_ecriture_d_origine(): void
    {
        $ecriture = $this->service()->valider($this->piece())->first();
        $debitOrigine = $ecriture->debit;
        $creditOrigine = $ecriture->credit;

        $contrepassee = $this->service()->contrepasser($ecriture);

        // Débit et crédit inversés.
        $this->assertSame($creditOrigine, $contrepassee->debit);
        $this->assertSame($debitOrigine, $contrepassee->credit);
        $this->assertSame($ecriture->id, $contrepassee->ecriture_contrepassee_id);
        // Validée d'emblée : en brouillon, le grand livre resterait faux.
        $this->assertSame('validee', $contrepassee->statut);

        // L'originale n'a pas bougé d'un centime.
        $ecriture->refresh();
        $this->assertSame($debitOrigine, $ecriture->debit);
        $this->assertSame($creditOrigine, $ecriture->credit);
        $this->assertSame('validee', $ecriture->statut);
    }

    #[Test]
    public function rg11_le_solde_du_compte_revient_a_zero_apres_contrepassation(): void
    {
        $piece = $this->service()->valider($this->piece());
        $ecritureBanque = $piece->firstOrFail(fn (EcritureComptable $e): bool => $e->compte_id === $this->banque->id);

        $this->assertSame('100000.00', $this->soldeBanque());

        $this->service()->contrepasser($ecritureBanque);

        $this->assertSame('0.00', $this->soldeBanque());
    }

    #[Test]
    public function rg11_une_ecriture_en_brouillon_ne_se_contrepasse_pas(): void
    {
        $this->assertThrows(
            fn () => $this->service()->contrepasser($this->piece()->first()),
            EcritureImmuableException::class,
        );
    }

    /**
     * Une double contre-passation rétablirait l'écriture d'origine tout en
     * laissant croire à une annulation.
     */
    #[Test]
    public function rg11_une_ecriture_ne_se_contrepasse_pas_deux_fois(): void
    {
        $ecriture = $this->service()->valider($this->piece())->first();

        $this->service()->contrepasser($ecriture);

        $this->assertThrows(
            fn () => $this->service()->contrepasser($ecriture->fresh()),
            EcritureImmuableException::class,
        );
    }

    // ------------------------------------------------------ Exercice clos

    #[Test]
    public function aucune_ecriture_ne_s_ajoute_a_un_exercice_cloture(): void
    {
        $clos = $this->exercice('cloture', 2025);

        $this->assertThrows(
            fn () => $this->piece(exerciceId: $clos, dateEcriture: '2025-08-16'),
            EcritureImmuableException::class,
        );

        $this->assertSame(0, EcritureComptable::count());
    }

    /**
     * Un exercice `en_cloture` accepte encore les écritures d'ajustement :
     * c'est précisément la période où elles se passent.
     */
    #[Test]
    public function un_exercice_en_cloture_accepte_encore_les_ajustements(): void
    {
        $enCloture = $this->exercice('en_cloture', 2024);

        $this->assertCount(2, $this->piece(exerciceId: $enCloture, dateEcriture: '2024-12-31'));
    }

    // ------------------------------------------------------------- RG-12

    /**
     * « Chaque écriture comptable est obligatoirement rattachée à un centre de
     * coût. » La garantie est portée par la **base** (`centre_id` NOT NULL),
     * pas seulement par du code applicatif contournable.
     */
    #[Test]
    public function rg12_le_centre_de_cout_est_impose_par_le_schema(): void
    {
        $colonne = DB::selectOne('SHOW COLUMNS FROM ecritures_comptables LIKE "centre_id"');

        $this->assertSame('NO', $colonne->Null, 'RG-12 exige une FK NOT NULL sur centre_id.');

        // Et une tentative directe échoue bien, contrainte à l'appui.
        $this->expectException(\Illuminate\Database\QueryException::class);
        DB::table('ecritures_comptables')->insert([
            'id' => (string) Str::uuid(),
            'exercice_id' => $this->exerciceId,
            'journal_id' => $this->journalId,
            'compte_id' => $this->banque->id,
            'date_ecriture' => '2026-08-16',
            'libelle' => 'Sans centre de coût',
            'debit' => '1000.00', 'credit' => '0.00', 'statut' => 'brouillon',
            'date_creation' => now(),
        ]);
    }

    // ------------------------------------------------------------- Helpers

    /**
     * @return \Illuminate\Database\Eloquent\Collection<int, EcritureComptable>
     */
    private function piece(
        string $debit = '100000.00',
        string $credit = '100000.00',
        ?string $exerciceId = null,
        string $dateEcriture = '2026-08-16',
    ): \Illuminate\Database\Eloquent\Collection {
        return $this->service()->enregistrerPiece(
            [
                'exercice_id' => $exerciceId ?? $this->exerciceId,
                'journal_id' => $this->journalId,
                'date_ecriture' => $dateEcriture,
                'libelle' => 'Vente comptant',
            ],
            [
                ['compte_id' => $this->banque->id, 'centre_id' => $this->centreId, 'debit' => $debit],
                ['compte_id' => $this->vente->id, 'centre_id' => $this->centreId, 'credit' => $credit],
            ],
        );
    }

    private function soldeBanque(): string
    {
        return $this->service()->soldeCompte($this->banque->id, '2026-01-01', '2026-12-31');
    }

    /**
     * `exercices_comptables.annee` est UNIQUE — un seul exercice par annee.
     * Chaque exercice de test porte donc sa propre annee, et l'ecriture qu'on
     * y rattache est datee dans ses bornes : une ecriture hors de son exercice
     * serait elle-meme une anomalie.
     */
    private function exercice(string $statut, int $annee): string
    {
        $id = (string) Str::uuid();

        DB::table('exercices_comptables')->insert([
            'id' => $id,
            'annee' => $annee,
            'date_debut' => "{$annee}-01-01",
            'date_fin' => "{$annee}-12-31",
            'statut' => $statut,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
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
}
