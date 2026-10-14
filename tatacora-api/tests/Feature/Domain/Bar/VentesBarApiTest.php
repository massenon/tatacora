<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Bar;

use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Carbon\CarbonImmutable;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * `GET /api/v1/bar/ventes` — « Ventes du Bar » par l'API (11/09/2026, PA-197).
 *
 * ## Ce que ces cas protègent
 *
 * La route rend les lignes du rayon M5 par `LignesVenteDuRayonService`, le
 * MÊME service que l'onglet de la PWA : filtre de module sur la LIGNE (un
 * ticket mixte ne fait pas apparaître son plat au bar), bornes de dates
 * INCLUSES, total des SEULES lignes validées, porté sur le jeu filtré ENTIER
 * et jamais sur la page.
 *
 * ## Pourquoi les ventes sont écrites en direct
 *
 * Même arbitrage, avec les mêmes mots, que `BarPwaTest` et `VentesSeeder` :
 * `VenteService::enregistrer()` sort le stock, exige une session de caisse et
 * passe sa pièce comptable. Ces cas éprouvent une LECTURE ; le chemin réel
 * d'écriture est prouvé par `tests/Feature/Domain/Ventes/VenteServiceTest.php`.
 *
 * @see EF-M5 — carte du bar, onglet des ventes
 */
final class VentesBarApiTest extends TestCase
{
    use RefreshDatabase;

    private const URL = '/api/v1/bar/ventes';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    #[Test]
    public function un_ticket_mixte_ne_rend_que_sa_ligne_du_bar(): void
    {
        $barman = $this->utilisateur('barman');
        $this->vente('V-TEST-00001', now()->subDay(), $barman, [
            ['code' => 'boisson-1', 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 3],
            ['code' => 'plat-1', 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);
        Sanctum::actingAs($barman);

        $reponse = $this->getJson(self::URL)->assertOk();

        $reponse->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.nom', 'Béninoise 66 cl')
            // Le code FIGÉ de l'article de carte : c'est par lui que le client
            // retrouve le stock du jour, jamais par le libellé.
            ->assertJsonPath('data.0.code', 'boisson-1')
            ->assertJsonPath('data.0.numero', 'V-TEST-00001')
            ->assertJsonPath('data.0.quantite', 3)
            // Valeurs BRUTES, jamais mises en forme par le serveur.
            ->assertJsonPath('data.0.prix_unitaire', '800.00')
            ->assertJsonPath('data.0.montant', '2400.00')
            ->assertJsonPath('data.0.annulee', false)
            // RG-15 — le login de qui a encaissé.
            ->assertJsonPath('data.0.utilisateur', $barman->login)
            ->assertJsonPath('totaux.lignes', 1)
            ->assertJsonPath('totaux.total_valide', '2400.00');
    }

    #[Test]
    public function le_total_exclut_les_annulations_et_porte_sur_tout_le_filtre(): void
    {
        $barman = $this->utilisateur('barman');

        // DOUZE lignes validées de 1 000 : la page en rend dix, le total
        // doit en compter douze — un total calculé sur la page dirait 10 000.
        for ($i = 1; $i <= 12; $i++) {
            $this->vente(sprintf('V-TEST-%05d', $i), now()->subMinutes($i), $barman, [
                ['code' => 'boisson-1', 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '1000.00', 'qte' => 1],
            ]);
        }
        // Et une annulée : listée, jamais additionnée (RG-02).
        $this->vente('V-TEST-ANNULEE', now()->subHours(2), $barman, [
            ['code' => 'boisson-1', 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '5000.00', 'qte' => 1],
        ], 'annulee', 'Erreur de saisie');
        Sanctum::actingAs($barman);

        $this->getJson(self::URL)->assertOk()
            ->assertJsonCount(10, 'data')
            ->assertJsonPath('totaux.lignes', 13)
            ->assertJsonPath('totaux.annulees', 1)
            ->assertJsonPath('totaux.total_valide', '12000.00')
            ->assertJsonPath('meta.total', 13);

        $annulee = $this->getJson(self::URL.'?statut=annulee')->assertOk();
        $annulee->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.annulee', true)
            ->assertJsonPath('data.0.motif_annulation', 'Erreur de saisie')
            ->assertJsonPath('totaux.total_valide', '0.00');
    }

    #[Test]
    public function la_borne_haute_inclut_la_journee_entiere(): void
    {
        $barman = $this->utilisateur('barman');
        $jour = CarbonImmutable::parse('2026-08-20 19:40:00');
        $ligne = [['code' => 'boisson-1', 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1]];

        $this->vente('V-TEST-DERNIERJOUR', $jour, $barman, $ligne);
        // HORS bornes des deux côtés : une plage qui ne rejetterait rien
        // serait verte à vide.
        $this->vente('V-TEST-TROPTOT', $jour->subDays(5), $barman, $ligne);
        $this->vente('V-TEST-TROPTARD', $jour->addDays(2), $barman, $ligne);
        Sanctum::actingAs($barman);

        $donnees = $this->getJson(self::URL.'?du=2026-08-18&au=2026-08-20')->assertOk()->json('data');
        $this->assertIsArray($donnees);
        $numeros = collect($donnees)->pluck('numero')->all();

        $this->assertSame(['V-TEST-DERNIERJOUR'], $numeros);
    }

    #[Test]
    public function la_recherche_porte_sur_le_ticket_l_article_et_le_login(): void
    {
        $barman = $this->utilisateur('barman');
        $autre = $this->utilisateur('gerant');
        $this->vente('V-TEST-AAAAA', now()->subHour(), $barman, [
            ['code' => 'boisson-1', 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);
        $this->vente('V-TEST-BBBBB', now()->subHour(), $autre, [
            ['code' => 'boisson-2', 'nom' => 'Coca-Cola 33 cl', 'module' => 'M5', 'prix' => '500.00', 'qte' => 1],
        ]);
        Sanctum::actingAs($barman);

        foreach (['V-TEST-BBBBB', 'Coca', $autre->login] as $terme) {
            $this->getJson(self::URL.'?recherche='.urlencode($terme))->assertOk()
                ->assertJsonCount(1, 'data')
                ->assertJsonPath('data.0.numero', 'V-TEST-BBBBB');
        }
    }

    #[Test]
    public function une_date_illisible_ou_une_plage_inversee_est_refusee(): void
    {
        Sanctum::actingAs($this->utilisateur('barman'));

        // L'écran PWA ignore une borne illisible venue de l'URL ; l'API la
        // REFUSE : un client qui envoie « hier » a un défaut à corriger.
        $this->getJson(self::URL.'?du=hier')->assertStatus(422)->assertJsonValidationErrors('du');
        $this->getJson(self::URL.'?du=2026-08-20&au=2026-08-18')->assertStatus(422)->assertJsonValidationErrors('au');
        $this->getJson(self::URL.'?statut=perdue')->assertStatus(422)->assertJsonValidationErrors('statut');
    }

    #[Test]
    public function la_lecture_suffit_et_un_role_sans_acces_au_bar_est_refuse(): void
    {
        // `receptionniste` porte `M5 = 'L'` : consulter ne demande pas d'écrire.
        $lecteur = $this->utilisateur('receptionniste');
        $this->assertSame('L', $lecteur->niveauSurModule('M5'));
        Sanctum::actingAs($lecteur);
        $this->getJson(self::URL)->assertOk();

        $sansAcces = $this->utilisateur('cuisine');
        $this->assertSame('-', $sansAcces->niveauSurModule('M5'));
        Sanctum::actingAs($sansAcces);
        $this->getJson(self::URL)->assertForbidden();
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.ventes.'.Str::random(4),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * Une vente et ses lignes, écrites en direct (voir l'en-tête).
     * `created_at` passe par `forceFill()` : la colonne n'est pas dans
     * `$fillable`, et la plage de dates serait sinon éprouvée à vide.
     *
     * @param  list<array{code: string, nom: string, module: string, prix: string, qte: int}>  $lignes
     */
    private function vente(
        string $numero,
        \DateTimeInterface $quand,
        User $auteur,
        array $lignes,
        string $statut = 'validee',
        string $motif = '',
    ): Vente {
        $total = '0.00';
        foreach ($lignes as $ligne) {
            $total = bcadd($total, bcmul($ligne['prix'], (string) $ligne['qte'], 2), 2);
        }

        $vente = Vente::create([
            'numero' => $numero,
            'point_vente' => 'bar',
            'montant_total' => $total,
            'mode_paiement' => 'especes',
            'encaisse' => true,
            'statut' => $statut,
            'motif_annulation' => $motif === '' ? null : $motif,
            'annulee_at' => $statut === 'annulee' ? $quand : null,
            'utilisateur_id' => $auteur->id,
        ]);
        $vente->forceFill(['created_at' => $quand])->save();

        foreach ($lignes as $ligne) {
            LigneVente::create([
                'vente_id' => $vente->id,
                'code' => $ligne['code'],
                'nom' => $ligne['nom'],
                'categorie' => 'locale',
                'module' => $ligne['module'],
                'prix_unitaire' => $ligne['prix'],
                'quantite' => $ligne['qte'],
                'montant' => bcmul($ligne['prix'], (string) $ligne['qte'], 2),
            ]);
        }

        return $vente->refresh();
    }
}
