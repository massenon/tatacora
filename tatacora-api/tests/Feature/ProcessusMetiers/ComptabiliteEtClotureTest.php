<?php

declare(strict_types=1);

namespace Tests\Feature\ProcessusMetiers;

use App\Domain\Comptabilite\Exceptions\EcritureImmuableException;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Comptabilite\Services\DeclarationTvaService;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\TvaReferentielSeeder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Processus métier n°5 — Comptabilité et clôture périodique.
 *
 * « Validation des pièces du mois → Génération automatique des écritures par
 * centre de coût (M10) → Rapprochement bancaire → Contrôle budgétaire → États
 * SYSCOHADA → Clôture/verrouillage »
 * (`05_MODULE_SPECIFICATIONS.md` §Processus transverses).
 *
 * ## Périmètre réellement couvert — trois maillons sur six
 *
 * Nommer ce qui manque évite de laisser croire qu'une clôture d'exercice est
 * validée de bout en bout :
 *
 * - **Génération automatique des écritures** depuis une facture ou un
 *   encaissement : aucun `Listener` ne l'implémente. Les pièces sont ici
 *   saisies explicitement.
 * - **Rapprochement bancaire** : `releves_bancaires` et `comptes_bancaires`
 *   existent au schéma, aucun service ne les exploite.
 * - **Contrôle budgétaire** : la table `budgets` existe, sans service.
 * - **États SYSCOHADA** (bilan, compte de résultat) : non implémentés — le
 *   taux d'IS reste délibérément non fixé (PA-19).
 *
 * Sont exercés : la validation des pièces, la TVA (PA-36/37), le verrouillage
 * de clôture, et l'immutabilité qui en découle (RG-11).
 */
final class ComptabiliteEtClotureTest extends TestCase
{
    use RefreshDatabase;

    private string $exerciceId;

    private string $journalId;

    private string $centreHebergement;

    private string $centreRestaurant;

    private CompteComptable $banque;

    private CompteComptable $ventes;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        // Comptes de TVA du fichier du PO (plus semés par TvaReferentielSeeder).
        foreach ([['4431', 'T.V.A. facturée sur ventes'], ['4432', 'T.V.A. facturée sur prestations de services'], ['4452', 'T.V.A. récupérable sur achats']] as [$n, $l]) {
            \App\Domain\Comptabilite\Models\CompteComptable::firstOrCreate(['numero_compte' => $n], ['libelle' => $l, 'classe' => '4', 'nature' => 'passif']);
        }
        $this->seed(TvaReferentielSeeder::class);
        $this->actingAs($this->utilisateur('comptable'));

        $this->exerciceId = $this->exercice('ouvert', 2026);

        $this->journalId = (string) Str::uuid();
        DB::table('journaux_comptables')->insert([
            'id' => $this->journalId, 'code' => 'VE', 'libelle' => 'Ventes',
            'created_at' => now(), 'updated_at' => now(),
        ]);

        // RG-12 — chaque écriture porte son centre de coût. En avoir deux
        // permet de vérifier que l'analytique sépare réellement les activités.
        $this->centreHebergement = $this->centre('Hébergement');
        $this->centreRestaurant = $this->centre('Restaurant');

        $this->banque = CompteComptable::create([
            'numero_compte' => '521000', 'libelle' => 'Banque', 'classe' => '5', 'nature' => 'actif',
        ]);
        $this->ventes = CompteComptable::create([
            'numero_compte' => '701000', 'libelle' => 'Ventes', 'classe' => '7', 'nature' => 'produit',
        ]);
    }

    private function service(): EcritureComptableService
    {
        return app(EcritureComptableService::class);
    }

    /**
     * Le cycle du mois : saisie → validation → verrouillage par la clôture.
     */
    #[Test]
    public function le_cycle_va_de_la_saisie_du_mois_au_verrouillage_de_l_exercice(): void
    {
        // --- 1. Deux pièces du mois, sur deux centres de coût distincts
        $hebergement = $this->piece('118000.00', $this->centreHebergement, 'Nuitées août');
        $restaurant = $this->piece('59000.00', $this->centreRestaurant, 'Restauration août');

        $this->assertSame(4, EcritureComptable::count());
        // Tout naît en brouillon : la validation est un acte distinct.
        $this->assertSame(4, EcritureComptable::where('statut', 'brouillon')->count());

        // --- 2. Un brouillon n'est pas opposable : il ne pèse sur aucun solde
        $this->assertSame('0.00', $this->soldeBanque());

        // --- 3. Validation des pièces du mois
        $this->service()->valider($hebergement);
        $this->service()->valider($restaurant);

        $this->assertSame('177000.00', $this->soldeBanque());

        // --- 4. Analytique par centre de coût (RG-12) : les deux activités
        // restent séparables, ce qui est tout l'intérêt du centre obligatoire.
        $this->assertSame('118000.00', $this->soldeCentre($this->centreHebergement));
        $this->assertSame('59000.00', $this->soldeCentre($this->centreRestaurant));

        // --- 5. Clôture de l'exercice : verrouillage
        DB::table('exercices_comptables')->where('id', $this->exerciceId)->update([
            'statut' => 'cloture',
            'date_cloture' => now(),
        ]);

        // Plus aucune écriture nouvelle...
        $this->assertThrows(
            fn () => $this->piece('10000.00', $this->centreHebergement, 'Écriture tardive'),
            EcritureImmuableException::class,
        );

        // ...et les écritures validées restent figées.
        $this->assertThrows(
            fn () => $hebergement->first()->update(['libelle' => 'Retouche après clôture']),
            EcritureImmuableException::class,
        );

        $this->assertSame('177000.00', $this->soldeBanque());
    }

    /**
     * **La rupture de chaîne que ce niveau doit attraper.**
     *
     * Une correction après clôture ne doit pas être possible « par la bande » :
     * ni par modification, ni par suppression, ni même par contre-passation —
     * celle-ci créerait une écriture nouvelle sur un exercice verrouillé.
     */
    #[Test]
    public function aucune_correction_ne_franchit_la_cloture_pas_meme_une_contrepassation(): void
    {
        $piece = $this->service()->valider($this->piece('118000.00', $this->centreHebergement));
        $ecriture = $piece->first();

        DB::table('exercices_comptables')->where('id', $this->exerciceId)->update(['statut' => 'cloture']);

        $this->assertThrows(fn () => $ecriture->update(['debit' => '1.00']), EcritureImmuableException::class);
        $this->assertThrows(fn () => $ecriture->delete(), EcritureImmuableException::class);

        // Le chemin de correction légitime est lui aussi fermé : une
        // contre-passation ajouterait une écriture à un exercice signé.
        $this->assertThrows(
            fn () => $this->service()->contrepasser($ecriture->fresh()),
            EcritureImmuableException::class,
        );

        $this->assertSame(2, EcritureComptable::count());
    }

    /**
     * Avant clôture, la correction reste possible — et laisse les deux traces.
     */
    #[Test]
    public function avant_cloture_la_correction_par_contrepassation_reste_ouverte(): void
    {
        $ecriture = $this->service()->valider($this->piece('118000.00', $this->centreHebergement))->first();

        $this->assertSame('118000.00', $this->soldeBanque());

        $this->service()->contrepasser($ecriture);

        // Solde neutralisé, mais les DEUX mouvements figurent au grand livre :
        // c'est ce que SYSCOHADA exige, et ce qu'un audit vérifie.
        $this->assertSame('0.00', $this->soldeBanque());
        $this->assertSame(3, EcritureComptable::count());
    }

    /**
     * La TVA traverse le processus : la déclaration lit les mêmes écritures
     * validées que le grand livre, jamais un calcul parallèle (PA-36).
     */
    #[Test]
    public function la_declaration_de_tva_lit_les_ecritures_validees_du_grand_livre(): void
    {
        $tvaCollectee = CompteComptable::where('numero_compte', DeclarationTvaService::COMPTE_TVA_COLLECTEE)->sole();

        // Pièce avec TVA : 100 000 HT + 18 000 de TVA = 118 000 encaissés.
        $piece = $this->service()->enregistrerPiece(
            [
                'exercice_id' => $this->exerciceId,
                'journal_id' => $this->journalId,
                'date_ecriture' => '2026-08-16',
                'libelle' => 'Vente avec TVA',
            ],
            [
                ['compte_id' => $this->banque->id, 'centre_id' => $this->centreHebergement, 'debit' => '118000.00'],
                ['compte_id' => $this->ventes->id, 'centre_id' => $this->centreHebergement, 'credit' => '100000.00'],
                ['compte_id' => $tvaCollectee->id, 'centre_id' => $this->centreHebergement, 'credit' => '18000.00'],
            ],
        );

        // Tant que la pièce est en brouillon, elle ne se déclare pas : une
        // déclaration bâtie sur des brouillons serait fausse dès la première
        // correction.
        $declarationAvant = app(DeclarationTvaService::class)->pourPeriode('2026-08-01', '2026-08-31');
        $this->assertSame('0.00', $declarationAvant['tva_collectee']);
        $this->assertSame('neant', $declarationAvant['sens']);

        $this->service()->valider($piece);

        $declaration = app(DeclarationTvaService::class)->pourPeriode('2026-08-01', '2026-08-31');
        $this->assertSame('18000.00', $declaration['tva_collectee']);
        // Aucune TVA deductible saisie : le solde est integralement a payer.
        $this->assertSame('a_payer', $declaration['sens']);
        $this->assertSame('18000.00', $declaration['montant_a_payer']);

        // Cohérence avec le taux paramétré, jamais un 18 % codé en dur.
        $this->assertSame('18000.00', app(CalculTvaService::class)->depuisHt('100000.00'));
    }

    /**
     * Une pièce déséquilibrée n'atteint jamais le grand livre — et n'y laisse
     * aucune ligne partielle.
     */
    #[Test]
    public function une_piece_desequilibree_n_entre_pas_dans_le_grand_livre(): void
    {
        $this->assertThrows(
            fn () => $this->service()->enregistrerPiece(
                [
                    'exercice_id' => $this->exerciceId,
                    'journal_id' => $this->journalId,
                    'date_ecriture' => '2026-08-16',
                    'libelle' => 'Pièce fautive',
                ],
                [
                    ['compte_id' => $this->banque->id, 'centre_id' => $this->centreHebergement, 'debit' => '118000.00'],
                    ['compte_id' => $this->ventes->id, 'centre_id' => $this->centreHebergement, 'credit' => '100000.00'],
                ],
            ),
            \RuntimeException::class,
        );

        $this->assertSame(0, EcritureComptable::count());
    }

    // ------------------------------------------------------------- Helpers

    /**
     * @return Collection<int, EcritureComptable>
     */
    private function piece(string $montant, string $centreId, string $libelle = 'Vente comptant'): Collection
    {
        return $this->service()->enregistrerPiece(
            [
                'exercice_id' => $this->exerciceId,
                'journal_id' => $this->journalId,
                'date_ecriture' => '2026-08-16',
                'libelle' => $libelle,
            ],
            [
                ['compte_id' => $this->banque->id, 'centre_id' => $centreId, 'debit' => $montant],
                ['compte_id' => $this->ventes->id, 'centre_id' => $centreId, 'credit' => $montant],
            ],
        );
    }

    private function soldeBanque(): string
    {
        return $this->service()->soldeCompte($this->banque->id, '2026-01-01', '2026-12-31');
    }

    private function soldeCentre(string $centreId): string
    {
        $solde = EcritureComptable::query()
            ->where('centre_id', $centreId)
            ->where('compte_id', $this->banque->id)
            ->where('statut', 'validee')
            ->selectRaw('COALESCE(SUM(debit) - SUM(credit), 0) AS solde')
            ->value('solde');

        return bcadd((string) ($solde ?? '0'), '0', 2);
    }

    private function centre(string $libelle): string
    {
        $id = (string) Str::uuid();

        DB::table('centres_cout')->insert([
            'id' => $id, 'libelle' => $libelle,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    private function exercice(string $statut, int $annee): string
    {
        $id = (string) Str::uuid();

        DB::table('exercices_comptables')->insert([
            'id' => $id, 'annee' => $annee,
            'date_debut' => "{$annee}-01-01", 'date_fin' => "{$annee}-12-31",
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
