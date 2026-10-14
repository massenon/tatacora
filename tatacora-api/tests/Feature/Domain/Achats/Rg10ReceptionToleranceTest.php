<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Achats;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Models\LigneCommandeAchat;
use App\Domain\Achats\Services\ControleTroisVoiesService;
use App\Domain\Achats\Services\ReceptionService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * M7 Achats — réception (EF-M7-03), tolérance (RG-10) et rapprochement à trois
 * voies (EF-M7-04).
 */
final class Rg10ReceptionToleranceTest extends TestCase
{
    use RefreshDatabase;

    private ReceptionService $reception;

    private StockTheoriqueService $stock;

    private PointStockage $magasin;

    private Article $riz;

    private CommandeAchat $commande;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->reception = app(ReceptionService::class);
        $this->stock = app(StockTheoriqueService::class);
        $utilisateur = $this->utilisateur('achats');
        $this->actingAs($utilisateur);

        // Tolérance de 2 % — paramètre, jamais codé en dur (RG-10).
        ParametreSysteme::create([
            'cle' => ReceptionService::CLE_TOLERANCE,
            'valeur' => '2.00',
            'description' => 'Tolérance de réception en % (RG-10).',
        ]);

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);
        $this->riz = $this->article('Riz parfumé');

        $fournisseur = Fournisseur::create(['raison_sociale' => 'SODIS Bénin']);

        $this->commande = CommandeAchat::create([
            'fournisseur_id' => $fournisseur->id,
            'date_commande' => '2026-08-01',
            'statut' => 'envoyee',
            'utilisateur_id' => $utilisateur->id,
        ]);

        LigneCommandeAchat::create([
            'commande_id' => $this->commande->id,
            'article_id' => $this->riz->id,
            'quantite_commandee' => '100.00',
            'prix_unitaire' => '800.00',
        ]);
    }

    // ------------------------------------------------------------- Réception

    #[Test]
    public function ef_m7_03_la_reception_genere_l_entree_de_stock(): void
    {
        $this->reception->receptionner($this->commande, [$this->riz->id => '100.00'], $this->magasin->id);

        // Jamais de double-saisie manuelle : l'entrée vient de la réception.
        $this->assertSame('100.00', $this->stock->stock($this->riz->id, $this->magasin->id));
        $this->assertSame('receptionnee', $this->commande->fresh()->statut);
    }

    #[Test]
    public function rg10_une_livraison_exacte_est_totalement_conforme(): void
    {
        $bon = $this->reception->receptionner($this->commande, [$this->riz->id => '100.00'], $this->magasin->id);

        $this->assertSame('totale', $bon->conformite);
    }

    #[Test]
    public function rg10_un_ecart_dans_la_tolerance_reste_conforme(): void
    {
        // 98,5 sur 100 = −1,5 %, sous la tolérance de 2 %.
        $bon = $this->reception->receptionner($this->commande, [$this->riz->id => '98.50'], $this->magasin->id);

        $this->assertSame('totale', $bon->conformite);
        $this->assertSame('receptionnee', $this->commande->fresh()->statut);
    }

    #[Test]
    public function rg10_un_ecart_hors_tolerance_rend_la_reception_partielle(): void
    {
        // 95 sur 100 = −5 %, au-delà de la tolérance.
        $bon = $this->reception->receptionner($this->commande, [$this->riz->id => '95.00'], $this->magasin->id);

        $this->assertSame('partielle', $bon->conformite);
        $this->assertSame('receptionnee_partiellement', $this->commande->fresh()->statut);
    }

    /**
     * Recevoir plus que commandé n'est pas une bonne nouvelle : c'est une
     * facture plus élevée que prévu.
     */
    #[Test]
    public function rg10_un_excedent_hors_tolerance_est_non_conforme(): void
    {
        $bon = $this->reception->receptionner($this->commande, [$this->riz->id => '120.00'], $this->magasin->id);

        $this->assertSame('non_conforme', $bon->conformite);
    }

    #[Test]
    public function un_article_hors_commande_rend_la_reception_non_conforme(): void
    {
        $autre = $this->article('Huile');

        $bon = $this->reception->receptionner(
            $this->commande,
            [$this->riz->id => '100.00', $autre->id => '10.00'],
            $this->magasin->id,
        );

        $this->assertSame('non_conforme', $bon->conformite);
    }

    // --------------------------------------------------------------- RG-10

    #[Test]
    public function rg10_la_tolerance_vient_du_parametre_jamais_du_code(): void
    {
        $this->assertSame('2.00', $this->reception->tolerancePourcentage());

        ParametreSysteme::where('cle', ReceptionService::CLE_TOLERANCE)->update(['valeur' => '10.00']);

        // Avec 10 % de tolérance, 95 sur 100 redevient conforme.
        $bon = app(ReceptionService::class)
            ->receptionner($this->commande, [$this->riz->id => '95.00'], $this->magasin->id);

        $this->assertSame('totale', $bon->conformite);
    }

    #[Test]
    public function rg10_sans_tolerance_configuree_aucune_conformite_n_est_evaluee(): void
    {
        ParametreSysteme::where('cle', ReceptionService::CLE_TOLERANCE)->delete();

        // Refus explicite plutôt qu'une valeur par défaut arbitraire.
        $this->expectException(RuntimeException::class);
        app(ReceptionService::class)
            ->receptionner($this->commande, [$this->riz->id => '100.00'], $this->magasin->id);
    }

    #[Test]
    public function rg10_une_commande_partiellement_receptionnee_ne_se_cloture_pas(): void
    {
        $this->reception->receptionner($this->commande, [$this->riz->id => '95.00'], $this->magasin->id);

        // Clôturer perdrait la créance sur le fournisseur.
        $this->expectException(RuntimeException::class);
        $this->reception->cloturer($this->commande->fresh());
    }

    #[Test]
    public function rg10_une_commande_conforme_se_cloture(): void
    {
        $this->reception->receptionner($this->commande, [$this->riz->id => '100.00'], $this->magasin->id);

        $cloturee = $this->reception->cloturer($this->commande->fresh());

        $this->assertSame('cloturee', $cloturee->statut);
    }

    #[Test]
    public function une_commande_cloturee_n_accepte_plus_de_reception(): void
    {
        $this->reception->receptionner($this->commande, [$this->riz->id => '100.00'], $this->magasin->id);
        $this->reception->cloturer($this->commande->fresh());

        // Sinon on créerait une entrée de stock sans commande en face.
        $this->expectException(RuntimeException::class);
        $this->reception->receptionner($this->commande->fresh(), [$this->riz->id => '10.00'], $this->magasin->id);
    }

    // ----------------------------------------------- Rapprochement 3 voies

    #[Test]
    public function ef_m7_04_le_rapprochement_confronte_commande_et_reception(): void
    {
        $this->reception->receptionner($this->commande, [$this->riz->id => '95.00'], $this->magasin->id);

        $rapprochement = app(ControleTroisVoiesService::class)->rapprocher($this->commande->fresh());

        $this->assertSame('ecart_constate', $rapprochement['concordance_globale']);
        $this->assertSame('manquant', $rapprochement['lignes'][0]['concordance']);
        $this->assertSame('-5.00', $rapprochement['lignes'][0]['ecart']);
    }

    #[Test]
    public function ef_m7_04_une_reception_conforme_donne_un_rapprochement_conforme(): void
    {
        $this->reception->receptionner($this->commande, [$this->riz->id => '100.00'], $this->magasin->id);

        $rapprochement = app(ControleTroisVoiesService::class)->rapprocher($this->commande->fresh());

        $this->assertSame('conforme', $rapprochement['concordance_globale']);
        $this->assertSame('100.00', $rapprochement['lignes'][0]['recue']);
    }

    /**
     * Le point le plus important : ne jamais présenter comme complet un
     * rapprochement qui ne porte que sur deux voies.
     */
    #[Test]
    public function ef_m7_04_le_rapprochement_signale_que_la_facture_n_est_pas_verifiable(): void
    {
        $this->reception->receptionner($this->commande, [$this->riz->id => '100.00'], $this->magasin->id);

        $rapprochement = app(ControleTroisVoiesService::class)->rapprocher($this->commande->fresh());

        $this->assertFalse($rapprochement['facture_verifiable']);
        $this->assertNotEmpty($rapprochement['avertissements']);

        $texte = implode(' ', $rapprochement['avertissements']);
        // Article 8 (02/09/2026, PA-171) : la reference PA-39 vit dans le
        // fichier de langue en commentaire, plus dans le texte affiche — le
        // test verifie la phrase lue par l'operateur.
        $this->assertStringContainsString('Facture fournisseur non fournie', $texte);
    }

    #[Test]
    public function une_commande_sans_reception_montre_tout_en_manquant(): void
    {
        $rapprochement = app(ControleTroisVoiesService::class)->rapprocher($this->commande);

        $this->assertSame('manquant', $rapprochement['lignes'][0]['concordance']);
        $this->assertSame('0.00', $rapprochement['lignes'][0]['recue']);
    }

    private function article(string $libelle): Article
    {
        return Article::create([
            'libelle' => $libelle,
            'categorie' => 'denree',
            'unite_mesure' => 'kg',
            'seuil_alerte' => '10.00',
            'seuil_reappro' => '25.00',
            'cout_moyen_pondere' => '800.0000',
        ]);
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
