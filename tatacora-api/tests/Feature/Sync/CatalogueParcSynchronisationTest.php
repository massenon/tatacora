<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Models\User;
use App\Shared\Sync\Services\ResolveurCentresCout;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Parc d'hébergement créé hors connexion — lot S2 (décision du Product Owner
 * du 15/10/2026) — et centres de coût, semés par le serveur, retrouvés par
 * libellé sans jamais être créés par un poste.
 */
final class CatalogueParcSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $receptionniste;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        // `receptionniste` : M1 = C.
        $this->receptionniste = $this->creerUtilisateur('receptionniste');
    }

    /**
     * L'unité naît `libre` quel que soit le statut reçu, et cite la catégorie
     * créée dans le même lot sous l'UUID du poste.
     */
    #[Test]
    public function une_categorie_et_son_unite_sont_creees_l_unite_toujours_libre(): void
    {
        [$categorie, $unite] = [$this->uuid(), $this->uuid()];

        $this->pousser([
            $this->creation('categories_hebergement', $categorie, ['libelle' => 'Suite', 'capacite_max' => 3, 'tarif_base' => 45000]),
            $this->creation('unites_hebergement', $unite, ['numero' => 'S-01', 'categorie_id' => $categorie, 'statut' => 'occupee']),
        ], $this->receptionniste)
            ->assertJsonPath('resultats.0.entite_id', $categorie)
            ->assertJsonPath('resultats.1.entite_id', $unite);

        $creee = UniteHebergement::findOrFail($unite);
        $this->assertSame('libre', $creee->statut);
        $this->assertSame($categorie, $creee->categorie_id);
        $this->assertSame('45000.00', (string) CategorieHebergement::findOrFail($categorie)->tarif_base);
        $this->assertDatabaseHas('journal_audit', ['entite_concernee' => 'unites_hebergement', 'entite_id' => $unite]);
    }

    /**
     * À l'écran, un libellé de catégorie pris est REFUSÉ (`unique`) ; par la
     * synchronisation, il FUSIONNE — c'est la décision du 15/10/2026. Les
     * autres règles de l'écran restent : un tarif nul est refusé.
     */
    #[Test]
    public function un_libelle_de_categorie_deja_pris_fusionne_au_lieu_d_etre_refuse(): void
    {
        $serveur = CategorieHebergement::create(['libelle' => 'Bungalow', 'capacite_max' => 4, 'tarif_base' => '25000.00']);
        [$categoriePoste, $unite] = [$this->uuid(), $this->uuid()];

        $this->pousser([
            $this->creation('categories_hebergement', $categoriePoste, ['libelle' => 'Bungalow', 'capacite_max' => 2, 'tarif_base' => 1000]),
            $this->creation('unites_hebergement', $unite, ['numero' => 'B-07', 'categorie_id' => $categoriePoste]),
            $this->creation('categories_hebergement', $this->uuid(), ['libelle' => 'Tente', 'capacite_max' => 2, 'tarif_base' => 0]),
        ], $this->receptionniste)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id)
            ->assertJsonPath('resultats.1.statut', 'synchronise')
            ->assertJsonPath('resultats.2.statut', 'rejete')
            ->assertJsonPath('resultats.2.motif', __('hebergement.validation.categorie_tarif_positif'));

        $this->assertSame(1, CategorieHebergement::count());
        $this->assertSame('25000.00', (string) $serveur->fresh()->tarif_base);
        $this->assertSame($serveur->id, UniteHebergement::findOrFail($unite)->categorie_id);
    }

    /**
     * Le numéro est l'identité de l'unité sur tout le parc ; une unité
     * archivée (`hors_service`) reste la même chambre, et le poste en est
     * averti.
     */
    #[Test]
    public function une_unite_fusionne_sur_son_numero_y_compris_archivee(): void
    {
        $categorie = CategorieHebergement::create(['libelle' => 'Chambre', 'capacite_max' => 2, 'tarif_base' => '20000.00']);
        $autre = CategorieHebergement::create(['libelle' => 'Suite', 'capacite_max' => 3, 'tarif_base' => '40000.00']);
        $serveur = UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'C-12', 'statut' => 'hors_service']);

        $this->pousser([$this->creation('unites_hebergement', $this->uuid(), ['numero' => ' c-12 ', 'categorie_id' => $autre->id])], $this->receptionniste)
            ->assertJsonPath('resultats.0.fusionne_avec', $serveur->id)
            ->assertJsonPath('resultats.0.cible_archivee', true);

        $this->assertSame(1, UniteHebergement::count());
        // Le serveur est maître : ni la catégorie ni le statut ne bougent.
        $this->assertSame([$categorie->id, 'hors_service'], [$serveur->fresh()->categorie_id, $serveur->fresh()->statut]);
    }

    /**
     * Adapté le 15/10/2026 (décision PO « offline-first total ») : la
     * modification du parc n'est plus refusée par principe — elle l'est SANS
     * le droit d'écriture sur M1, et appliquée par le service avec lui.
     */
    #[Test]
    public function sans_ecriture_sur_m1_le_parc_ne_remonte_pas_et_ne_se_modifie_pas(): void
    {
        $categorie = CategorieHebergement::create(['libelle' => 'Chambre', 'capacite_max' => 2, 'tarif_base' => '20000.00']);

        // `cuisine` : M1 = '-' ; `comptable` : M1 = 'L'.
        foreach (['cuisine', 'comptable'] as $role) {
            $this->pousser([
                $this->creation('unites_hebergement', $this->uuid(), ['numero' => 'X-' . $role, 'categorie_id' => $categorie->id]),
                $this->operation('categories_hebergement', 'modification', $categorie->id, ['tarif_base' => 1]),
            ], $this->creerUtilisateur($role))
                ->assertJsonPath('resultats.0.motif', __('auth.module_refuse'))
                ->assertJsonPath('resultats.1.motif', __('auth.module_refuse'));
        }

        $this->assertSame(0, UniteHebergement::count());
        $this->assertSame('20000.00', (string) $categorie->fresh()->tarif_base);

        // Avec le droit : appliquée, partielle — la capacité ne bouge pas.
        $this->pousser([$this->operation('categories_hebergement', 'modification', $categorie->id, ['tarif_base' => 25000])], $this->receptionniste)
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(['25000.00', 2], [(string) $categorie->fresh()->tarif_base, (int) $categorie->fresh()->capacite_max]);
    }

    // ---------------------------------------------------------- Centres de coût

    /**
     * Semés par le serveur, installés à l'identique par le poste sous d'autres
     * UUID : jamais créés par la synchronisation, retrouvés par libellé.
     */
    #[Test]
    public function un_centre_de_cout_se_resout_par_son_id_ou_son_libelle_et_ne_se_cree_jamais(): void
    {
        $bar = CentreCout::create(['libelle' => 'Bar', 'type' => 'exploitation']);
        CentreCout::create(['libelle' => 'Hébergement', 'type' => 'exploitation']);
        $resolveur = app(ResolveurCentresCout::class);

        $this->assertSame($bar->id, $resolveur->resoudre($bar->id, null));
        $this->assertSame($bar->id, $resolveur->resoudre($this->uuid(), '  BAR '));
        $this->assertSame(
            CentreCout::where('libelle', 'Hébergement')->value('id'),
            $resolveur->resoudre(null, 'hebergement'),
        );
        // Inconnu : `null`, jamais un centre deviné.
        $this->assertNull($resolveur->resoudre($this->uuid(), 'Spa'));
        $this->assertNull($resolveur->resoudre(null, null));

        $this->pousser([$this->creation('centres_cout', $this->uuid(), ['libelle' => 'Spa'])], $this->creerUtilisateur('administrateur'))
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.table_non_synchronisable', ['table' => 'centres_cout']));

        $this->assertSame(2, CentreCout::count());
    }
}
