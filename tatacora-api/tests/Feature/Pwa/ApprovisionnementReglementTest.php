<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Models\LigneCommandeAchat;
use App\Domain\Achats\Models\ReglementFournisseur;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Pwa\Livewire\Achats\Approvisionnement;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * LE RÈGLEMENT FOURNISSEUR RÉEL DEPUIS L'ÉCRAN APPROVISIONNEMENT — PA-165,
 * 02/09/2026.
 *
 * ## Ce que ce fichier prouve, et le défaut qu'il a trouvé EN L'EXÉCUTANT
 *
 * `AchatsCyclePwaTest` tenait déjà l'émission de commande et la réception.
 * Ce fichier tient le TROISIÈME geste — « Régler », `ReglementFournisseurService`
 * — et il a fallu, pour le faire réellement fonctionner, corriger une
 * conséquence d'un writer manquant (voir le docblock de
 * `Approvisionnement::enregistrerCommande()`) : `commandes_achat.montant_total`
 * n'était écrit par AUCUN chemin de ce dépôt, alors que
 * `ReglementFournisseurService::resteDu()` LIT cette colonne pour refuser un
 * sur-règlement. Sans correctif, `regler()` aurait refusé TOUT montant
 * positif sur CHAQUE commande, quel que soit son vrai reste dû — trouvé en
 * rejouant réellement le geste, pas en relisant le Service (PA-59/60/61).
 * Le Service lui-même n'est PAS modifié : la commande synchronise sa propre
 * colonne à la création et à l'ouverture de la modale de règlement.
 *
 * @see EF-M7-04 Dettes fournisseurs
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-165
 */
final class ApprovisionnementReglementTest extends TestCase
{
    use RefreshDatabase;

    private Fournisseur $fournisseur;

    private CommandeAchat $commande;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->seed(ComptabiliteReferentielSeeder::class);

        $this->actingAs($this->utilisateurQuiEcrit());

        $magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        $sucre = Article::create([
            'libelle' => 'Sucre en poudre',
            'categorie' => 'Denrées',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '4.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '0.0000',
        ]);
        app(MouvementStockService::class)
            ->entree($sucre->id, $magasin->id, '2.00', 'Réception initiale', '500.00');

        $this->fournisseur = Fournisseur::create([
            'raison_sociale' => 'Grand Marché Natitingou SARL',
            'contact' => '01 90 12 34 56',
            'categorie' => 'Denrées alimentaires',
            'conditions_paiement' => 'Comptant',
            'evaluation' => 'bon',
        ]);

        $this->commande = CommandeAchat::create([
            'fournisseur_id' => $this->fournisseur->id,
            'date_commande' => now()->toDateString(),
            'statut' => 'envoyee',
            'utilisateur_id' => auth()->id(),
        ]);

        LigneCommandeAchat::create([
            'commande_id' => $this->commande->id,
            'article_id' => $sucre->id,
            'quantite_commandee' => '4.00',
            'prix_unitaire' => '1000.00',
        ]);
        // Montant total réel : 4 000 F, jamais réglé.

        // Simule le SYNCHRONISME que `enregistrerCommande()` applique en
        // production (voir son docblock) : sans lui, `montant_total` resterait
        // à 0.00 et `ReglementFournisseurService::regler()` refuserait TOUT
        // règlement positif comme un sur-paiement, y compris via
        // `ouvrirFormulaireReglement()` qui l'aurait de toute façon réparé au
        // premier appel — ce bloc reproduit un état de production réaliste.
        $this->commande->setAttribute('montant_total', $this->commande->montantTotal());
        $this->commande->save();
        $this->commande->refresh();
    }

    #[Test]
    public function un_reglement_partiel_reel_reduit_le_reste_du(): void
    {
        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireReglement', $this->commande->id)
            ->assertSet('etatFormulaire', 'reglement')
            ->assertSet('regMontant', '4000.00')
            ->set('regMontant', '1500')
            ->set('regTresorerie', 'caisse')
            ->call('enregistrerReglement')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame(1, ReglementFournisseur::query()->count());
        $reglement = ReglementFournisseur::query()->firstOrFail();
        $this->assertSame($this->commande->id, $reglement->commande_id);
        $this->assertSame('1500.00', (string) $reglement->montant);
        $this->assertSame('caisse', $reglement->tresorerie);

        // `montant_regle` RECALCULÉ par le Service depuis les lignes.
        $this->assertSame('1500.00', (string) $this->commande->fresh()->montant_regle);

        // La pièce comptable RÉELLE est passée — DÉBIT 4011 Fournisseurs,
        // CRÉDIT trésorerie caisse (571000), même transaction.
        $compteFournisseurs = CompteComptable::where('numero_compte', '4011')->firstOrFail();
        $this->assertDatabaseHas('ecritures_comptables', [
            'compte_id' => $compteFournisseurs->id,
            'debit' => '1500.00',
            'statut' => 'validee',
        ]);
    }

    /**
     * Un second règlement, jusqu'au solde intégral — prouve que le reste dû
     * réellement chiffré (pas le montant commandé) borne le second geste.
     */
    #[Test]
    public function deux_reglements_successifs_soldent_la_commande(): void
    {
        app(\App\Domain\Achats\Services\ReglementFournisseurService::class)
            ->regler($this->commande, '1500.00', 'caisse');

        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireReglement', $this->commande->id)
            ->assertSet('regMontant', '2500.00')
            ->set('regMontant', '2500')
            ->call('enregistrerReglement')
            ->assertHasNoErrors();

        $this->assertSame('4000.00', (string) $this->commande->fresh()->montant_regle);
        $this->assertSame(2, ReglementFournisseur::query()->count());
    }

    /**
     * Un sur-règlement est REFUSÉ, et le refus reste LISIBLE — la modale NE
     * SE FERME PAS (PA-59/60/61).
     */
    #[Test]
    public function un_sur_reglement_est_refuse_et_la_modale_reste_ouverte(): void
    {
        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireReglement', $this->commande->id)
            ->set('regMontant', '9000')
            ->call('enregistrerReglement')
            ->assertHasErrors('regMontant')
            ->assertSet('etatFormulaire', 'reglement');

        $this->assertSame(0, ReglementFournisseur::query()->count());
    }

    /**
     * Une commande déjà soldée ne rouvre pas la modale : « Régler » n'a plus
     * lieu d'être une fois le reste dû à zéro.
     */
    #[Test]
    public function une_commande_soldee_refuse_d_ouvrir_le_reglement(): void
    {
        app(\App\Domain\Achats\Services\ReglementFournisseurService::class)
            ->regler($this->commande, '4000.00', 'caisse');

        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireReglement', $this->commande->id)
            ->assertSet('etatFormulaire', null)
            ->assertHasErrors('selection');

        $this->assertSame(1, ReglementFournisseur::query()->count());
    }

    #[Test]
    public function un_role_en_lecture_ne_peut_pas_ouvrir_le_reglement(): void
    {
        // `comptable` porte M7 = 'L' : la lecture, jamais l'écriture.
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M7'));

        $refusAvant = JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->count();
        $this->actingAs($comptable);

        Livewire::test(Approvisionnement::class)
            ->call('ouvrirFormulaireReglement', $this->commande->id)
            ->assertSet('etatFormulaire', null)
            ->assertForbidden();

        $this->assertSame(0, ReglementFournisseur::query()->count());
        $this->assertSame(
            $refusAvant + 1,
            JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->count(),
        );
    }

    // ----------------------------------------------------------- auxiliaires

    /** Le rôle qui porte `M7 = C`, lu du référentiel plutôt que supposé. */
    private function utilisateurQuiEcrit(): User
    {
        foreach (['achats', 'gerant', 'administrateur'] as $role) {
            $modele = Role::where('libelle', $role)->first();
            if ($modele !== null && $modele->niveauSurModule('M7') === 'C') {
                return $this->utilisateur($role);
            }
        }

        $this->fail('Aucun rôle du référentiel ne porte M7 = C.');
    }

    private function utilisateur(string $role): User
    {
        $existant = User::where('login', 'compte.'.$role)->first();

        if ($existant instanceof User) {
            return $existant;
        }

        return User::create([
            'login' => 'compte.'.$role,
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
