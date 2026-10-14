<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Bar;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * `POST /api/v1/bar/boissons/{boisson}/retrait` et `…/remise` — « Retirer de
 * la carte du jour » et « Remettre » par l'API (11/09/2026).
 *
 * ## Ce que ces cas protègent
 *
 * **Que le retrait soit une donnée partagée et imputable**, pas un état de
 * poste : c'est le défaut que `DisponibiliteCarteService` a fermé (la PWA
 * écrivait en session — le plat revenait seul, aucun autre poste ne le voyait
 * retiré, personne n'en répondait).
 *
 * **Que remettre LÈVE, jamais n'efface** : l'historique des ruptures est ce
 * sur quoi se décide un réapprovisionnement.
 *
 * @see EF-M5-02 Carte des boissons
 * @see RG-15 Journalisation — la décision porte son auteur
 */
final class DisponibiliteBoissonApiTest extends TestCase
{
    use RefreshDatabase;

    private CarteBoisson $biere;

    private CarteBoisson $sodabi;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $article = Article::create([
            'libelle' => 'Béninoise 66 cl — bouteille',
            'categorie' => 'boisson',
            'unite_mesure' => 'bouteille',
            'seuil_alerte' => '10.00',
            'cout_moyen_pondere' => '450.0000',
        ]);

        $this->biere = CarteBoisson::create([
            'article_id' => $article->id,
            'libelle' => 'Béninoise 66 cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
        ]);
        $this->sodabi = CarteBoisson::create([
            'article_id' => $article->id,
            'libelle' => 'Sodabi',
            'categorie' => 'maison',
            'prix_vente' => '500.00',
        ]);
    }

    #[Test]
    public function le_retrait_est_ecrit_motive_et_impute(): void
    {
        $barman = $this->utilisateur('barman');
        Sanctum::actingAs($barman);

        $this->postJson($this->url('retrait'), [
            'motif' => 'rupture',
            'commentaire' => 'Livraison attendue jeudi',
        ])
            ->assertOk()
            ->assertJsonPath('data.indisponibilite.motif', 'rupture')
            ->assertJsonPath('data.indisponibilite.libelle', 'Rupture du jour')
            ->assertJsonPath('data.indisponibilite.temporaire', true)
            ->assertJsonPath('data.indisponibilite.commentaire', 'Livraison attendue jeudi');

        $ligne = IndisponibiliteCarte::where('boisson_id', $this->biere->id)->sole();
        $this->assertSame($barman->id, $ligne->utilisateur_id);
        $this->assertNull($ligne->date_retour_disponibilite);
    }

    #[Test]
    public function la_liste_dit_quelle_boisson_est_retiree(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));
        $this->postJson($this->url('retrait'), ['motif' => 'retire'])->assertOk();

        $donnees = $this->getJson('/api/v1/bar/boissons')->assertOk()->json('data');
        $this->assertIsArray($donnees);
        $parId = collect($donnees)->keyBy('id');

        $this->assertSame('retire', $parId[$this->biere->id]['indisponibilite']['motif']);
        // Un retrait est une DÉCISION, pas un aléa : il ne revient pas seul.
        $this->assertFalse($parId[$this->biere->id]['indisponibilite']['temporaire']);
        $this->assertNull($parId[$this->sodabi->id]['indisponibilite']);
    }

    #[Test]
    public function retirer_ce_qui_est_deja_retire_est_refuse_sur_le_motif(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));
        $this->postJson($this->url('retrait'), ['motif' => 'rupture'])->assertOk();

        $this->postJson($this->url('retrait'), ['motif' => 'saison'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('motif');

        // Toujours UNE seule indisponibilité ouverte : deux lignes ouvertes
        // laisseraient l'article retiré après en avoir levé une.
        $this->assertSame(1, IndisponibiliteCarte::where('boisson_id', $this->biere->id)->enCours()->count());
    }

    #[Test]
    public function un_motif_hors_registre_est_refuse(): void
    {
        // `hors_saison` est l'ancien code de la PWA, celui qui avait divergé.
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->postJson($this->url('retrait'), ['motif' => 'hors_saison'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('motif');
    }

    #[Test]
    public function remettre_leve_l_indisponibilite_sans_l_effacer(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));
        $this->postJson($this->url('retrait'), ['motif' => 'rupture'])->assertOk();

        $this->postJson($this->url('remise'))
            ->assertOk()
            ->assertJsonPath('data.indisponibilite', null);

        $ligne = IndisponibiliteCarte::where('boisson_id', $this->biere->id)->sole();
        $this->assertNotNull($ligne->date_retour_disponibilite);
        $this->assertNotNull($ligne->utilisateur_retour_id);
    }

    #[Test]
    public function remettre_ce_qui_est_a_la_carte_est_refuse_pas_ignore(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        $this->postJson($this->url('remise'))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('etat');
    }

    #[Test]
    public function rg16_un_role_en_lecture_sur_m5_ne_retire_ni_ne_remet(): void
    {
        Sanctum::actingAs($this->utilisateur('receptionniste'));

        $this->postJson($this->url('retrait'), ['motif' => 'rupture'])->assertForbidden();
        $this->postJson($this->url('remise'))->assertForbidden();

        $this->assertSame(0, IndisponibiliteCarte::count());
    }

    private function url(string $geste): string
    {
        return '/api/v1/bar/boissons/' . $this->biere->id . '/' . $geste;
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
