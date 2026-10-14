<?php

declare(strict_types=1);

namespace Tests\Feature\ProcessusMetiers;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Models\LigneCommandeAchat;
use App\Domain\Achats\Services\ControleTroisVoiesService;
use App\Domain\Achats\Services\ReceptionService;
use App\Domain\Stocks\Events\SeuilStockAtteint;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Processus métier n°2 — Cycle Achats-Stocks.
 *
 * « Détection de besoin ou seuil d'alerte (M6) → Commande d'achat (M7) →
 * Réception et contrôle → Mise à jour du stock (M6) → Rapprochement facture
 * fournisseur » (05_MODULE_SPECIFICATIONS.md §5).
 *
 * ## Pourquoi cette suite existe
 *
 * `07_TESTING_QA.md` §8 la désigne comme **suite de régression de référence,
 * exécutée avant chaque mise en production** — et donne la raison exacte :
 * « un changement dans M6 (Stocks) peut casser silencieusement le processus
 * Restauration ou Cycle Achats-Stocks **sans qu'aucun test unitaire du module
 * M6 lui-même ne le détecte** ».
 *
 * C'est le seul niveau de test qui traverse les frontières de domaine. Les
 * tests par module vérifient chacun leur part ; celui-ci vérifie que les
 * parts s'emboîtent.
 */
final class CycleAchatsStocksTest extends TestCase
{
    use RefreshDatabase;

    private PointStockage $magasin;

    private Article $riz;

    private User $acheteur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->acheteur = $this->utilisateur('achats');
        $this->actingAs($this->acheteur);

        ParametreSysteme::create([
            'cle' => ReceptionService::CLE_TOLERANCE,
            'valeur' => '2.00',
            'description' => 'Tolérance de réception en % (RG-10).',
        ]);

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $this->riz = Article::create([
            'libelle' => 'Riz parfumé 50kg', 'categorie' => 'denree', 'unite_mesure' => 'sac',
            'seuil_alerte' => '10.00', 'seuil_reappro' => '25.00', 'cout_moyen_pondere' => '18000.0000',
        ]);
    }

    /**
     * Le cycle complet, de l'alerte de seuil au rapprochement.
     */
    #[Test]
    public function le_cycle_va_de_l_alerte_de_seuil_au_rapprochement(): void
    {
        Event::fake([SeuilStockAtteint::class]);
        $mouvements = app(MouvementStockService::class);
        $stock = app(StockTheoriqueService::class);

        // --- 1. Stock initial, puis consommation jusque sous le seuil (M6)
        $mouvements->entree($this->riz->id, $this->magasin->id, '40.00', 'Stock initial');
        $mouvements->sortie($this->riz->id, $this->magasin->id, '32.00', 'Consommation cuisine');

        $this->assertSame('8.00', $stock->stock($this->riz->id, $this->magasin->id));

        // RG-07 : le franchissement du seuil (10) déclenche l'alerte qui, en
        // exploitation, informe le Magasinier qu'il faut commander.
        Event::assertDispatched(SeuilStockAtteint::class);

        // --- 2. Commande d'achat (M7)
        $fournisseur = Fournisseur::create(['raison_sociale' => 'SODIS Bénin']);
        $commande = CommandeAchat::create([
            'fournisseur_id' => $fournisseur->id,
            'date_commande' => '2026-08-16',
            'statut' => 'envoyee',
            'utilisateur_id' => $this->acheteur->id,
        ]);
        LigneCommandeAchat::create([
            'commande_id' => $commande->id,
            'article_id' => $this->riz->id,
            'quantite_commandee' => '30.00',
            'prix_unitaire' => '18000.00',
        ]);

        // --- 3. Réception et contrôle (M7 → M6)
        $bon = app(ReceptionService::class)->receptionner(
            $commande,
            [$this->riz->id => '30.00'],
            $this->magasin->id,
        );

        $this->assertSame('totale', $bon->conformite);

        // --- 4. Le stock est mis à jour PAR la réception, jamais saisi deux fois
        $this->assertSame('38.00', $stock->stock($this->riz->id, $this->magasin->id));

        // Un seul mouvement d'entrée pour cette réception : une double-saisie
        // manuelle aurait doublé le stock reçu (05_MODULE_SPECIFICATIONS.md §M7).
        $entrees = \App\Domain\Stocks\Models\MouvementStock::where('article_id', $this->riz->id)
            ->where('type_mouvement', 'entree')
            ->count();
        $this->assertSame(2, $entrees, 'Stock initial + réception, pas davantage.');

        // --- 5. Rapprochement (M7)
        $rapprochement = app(ControleTroisVoiesService::class)->rapprocher($commande->fresh());

        $this->assertSame('conforme', $rapprochement['concordance_globale']);
        $this->assertSame('30.00', $rapprochement['lignes'][0]['recue']);

        // --- 6. Clôture (RG-10)
        $this->assertSame('cloturee', app(ReceptionService::class)->cloturer($commande->fresh())->statut);
    }

    /**
     * La rupture de chaîne que ce niveau de test existe pour attraper : une
     * livraison partielle doit se propager jusqu'au rapprochement ET bloquer
     * la clôture, sans qu'aucun module ne masque l'écart au suivant.
     */
    #[Test]
    public function une_livraison_partielle_se_propage_jusqu_a_la_cloture(): void
    {
        $fournisseur = Fournisseur::create(['raison_sociale' => 'SODIS Bénin']);
        $commande = CommandeAchat::create([
            'fournisseur_id' => $fournisseur->id, 'date_commande' => '2026-08-16',
            'statut' => 'envoyee', 'utilisateur_id' => $this->acheteur->id,
        ]);
        LigneCommandeAchat::create([
            'commande_id' => $commande->id, 'article_id' => $this->riz->id,
            'quantite_commandee' => '30.00', 'prix_unitaire' => '18000.00',
        ]);

        // Le fournisseur ne livre que 25 sacs sur 30 (−16,7 %).
        $bon = app(ReceptionService::class)->receptionner(
            $commande,
            [$this->riz->id => '25.00'],
            $this->magasin->id,
        );

        // M7 constate l'écart...
        $this->assertSame('partielle', $bon->conformite);
        $this->assertSame('receptionnee_partiellement', $commande->fresh()->statut);

        // ...M6 n'a reçu que ce qui est arrivé...
        $this->assertSame('25.00', app(StockTheoriqueService::class)->stock($this->riz->id, $this->magasin->id));

        // ...le rapprochement le montre...
        $rapprochement = app(ControleTroisVoiesService::class)->rapprocher($commande->fresh());
        $this->assertSame('ecart_constate', $rapprochement['concordance_globale']);
        $this->assertSame('manquant', $rapprochement['lignes'][0]['concordance']);
        $this->assertSame('-5.00', $rapprochement['lignes'][0]['ecart']);

        // ...et la clôture reste impossible : clôturer perdrait la créance de
        // 5 sacs sur le fournisseur (RG-10).
        $this->expectException(\RuntimeException::class);
        app(ReceptionService::class)->cloturer($commande->fresh());
    }

    /**
     * Le rapprochement ne doit jamais se présenter comme complet : la facture
     * fournisseur n'a aucune table où exister (PA-40).
     */
    #[Test]
    public function le_rapprochement_signale_que_la_troisieme_voie_manque(): void
    {
        $fournisseur = Fournisseur::create(['raison_sociale' => 'SODIS Bénin']);
        $commande = CommandeAchat::create([
            'fournisseur_id' => $fournisseur->id, 'date_commande' => '2026-08-16',
            'statut' => 'envoyee', 'utilisateur_id' => $this->acheteur->id,
        ]);
        LigneCommandeAchat::create([
            'commande_id' => $commande->id, 'article_id' => $this->riz->id,
            'quantite_commandee' => '10.00', 'prix_unitaire' => '18000.00',
        ]);
        app(ReceptionService::class)->receptionner($commande, [$this->riz->id => '10.00'], $this->magasin->id);

        $rapprochement = app(ControleTroisVoiesService::class)->rapprocher($commande->fresh());

        $this->assertFalse($rapprochement['facture_verifiable']);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(5),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
