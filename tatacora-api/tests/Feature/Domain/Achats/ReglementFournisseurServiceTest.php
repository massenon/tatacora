<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Achats;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Models\ReglementFournisseur;
use App\Domain\Achats\Services\ReglementFournisseurService;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Règlement fournisseur — le décaissement de PA-165, symétrique de
 * l'encaissement client.
 *
 * ## Mutation vérifiée (01/09/2026)
 *
 * Le recalcul remplacé par un incrément (`montant_regle + montant`) SUR UNE
 * BASE FAUSSÉE (un règlement préexistant hors service) rend le cas
 * « montant_regle est recalculé » rouge — c'est précisément la divergence
 * cumul/lignes que le recalcul empêche.
 */
final class ReglementFournisseurServiceTest extends TestCase
{
    use RefreshDatabase;

    private CommandeAchat $commande;

    private ReglementFournisseurService $service;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        $gerant = User::create([
            'login' => 'gerant.test',
            'mot_de_passe_hash' => Hash::make('x'),
            'role_id' => Role::where('libelle', 'gerant')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
        $this->actingAs($gerant);

        $fournisseur = Fournisseur::create([
            'raison_sociale' => 'SOBEBRA',
            'contact' => '01 21 30 30 30',
        ]);

        $this->commande = CommandeAchat::create([
            'fournisseur_id' => $fournisseur->id,
            'date_commande' => now()->toDateString(),
            'statut' => 'envoyee',
            'utilisateur_id' => $gerant->id,
        ]);

        // `montant_total` n'est pas fillable (il se calcule des lignes en
        // production) : pose directe pour le decor du test.
        \Illuminate\Support\Facades\DB::table('commandes_achat')
            ->where('id', $this->commande->id)
            ->update(['montant_total' => '80000.00']);
        $this->commande->refresh();

        $this->service = app(ReglementFournisseurService::class);
    }

    #[Test]
    public function un_reglement_ecrit_sa_piece_comptable_et_recalcule_montant_regle(): void
    {
        $reglement = $this->service->regler($this->commande, '50000.00', 'banque');

        $this->assertSame('banque', $reglement->tresorerie);
        $this->assertNotNull($reglement->utilisateur_creation_id, 'RG-15 : le règlement porte son auteur.');

        // montant_regle est recalculé — la colonne du schéma dit la somme des lignes.
        $this->assertSame(0, bccomp((string) $this->commande->refresh()->montant_regle, '50000.00', 2));
        $this->assertSame(0, bccomp($this->service->resteDu($this->commande), '30000.00', 2));

        // La pièce : débit 4011, crédit trésorerie, équilibrée.
        $lignes = EcritureComptable::query()
            ->where('libelle', 'like', 'Règlement fournisseur SOBEBRA%')
            ->get();

        $this->assertCount(2, $lignes);

        $debit = '0.00';
        $credit = '0.00';

        foreach ($lignes as $ligne) {
            $debit = bcadd($debit, (string) $ligne->debit, 2);
            $credit = bcadd($credit, (string) $ligne->credit, 2);
        }

        $this->assertSame(0, bccomp($debit, $credit, 2));
        $this->assertSame(0, bccomp($debit, '50000.00', 2));
    }

    #[Test]
    public function un_sur_reglement_refuse_et_rien_n_est_ecrit(): void
    {
        $this->service->regler($this->commande, '70000.00', 'caisse');

        try {
            $this->service->regler($this->commande->refresh(), '20000.00', 'caisse');
            $this->fail('Un sur-règlement aurait dû refuser.');
        } catch (RuntimeException $refus) {
            $this->assertStringContainsString('10000.00', $refus->getMessage());
        }

        $this->assertSame(1, ReglementFournisseur::count());
        $this->assertSame(0, bccomp((string) $this->commande->refresh()->montant_regle, '70000.00', 2));
    }

    /**
     * `montant_regle` = somme des lignes, même quand la colonne a été faussée
     * ailleurs : le recalcul RÉPARE, un incrément aurait entériné l'écart.
     */
    #[Test]
    public function montant_regle_est_recalcule_depuis_les_lignes_jamais_incremente(): void
    {
        // Colonne faussée hors service (le défaut que le recalcul absorbe).
        $this->commande->update(['montant_regle' => '99999.00']);

        $this->service->regler($this->commande->refresh(), '10000.00', 'momo');

        $this->assertSame(
            0,
            bccomp((string) $this->commande->refresh()->montant_regle, '10000.00', 2),
            'montant_regle est recalculé depuis les règlements, jamais incrémenté.',
        );
    }
}
