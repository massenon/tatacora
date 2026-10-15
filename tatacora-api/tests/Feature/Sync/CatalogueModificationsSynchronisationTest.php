<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Models\User;
use App\Shared\Sync\Models\ConflitSynchronisation;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PousseDesOperations;
use Tests\TestCase;

/**
 * Modifications du CATALOGUE faites hors connexion — décision du Product
 * Owner du 15/10/2026 (« offline-first total »), qui remplace le refus du
 * lot S2 (« le serveur est maître, modification refusée »).
 *
 * La cible est identifiée par son id (traduit par les correspondances), la
 * modification est PARTIELLE, validée par les règles de modification de
 * l'API, écrite par le service, et arbitrée en DERNIER ÉCRIT GAGNANT sur
 * l'horodatage de SAISIE — sans arbitrage manuel (le catalogue n'est pas
 * financier), mais avec la ligne de conflit.
 *
 * L'horloge est figée : le catalogue serveur naît à 08 h, les postes
 * synchronisent à midi des saisies faites entre 09 h et 11 h.
 */
final class CatalogueModificationsSynchronisationTest extends TestCase
{
    use PousseDesOperations;
    use RefreshDatabase;

    private User $magasinier;

    private Article $huile;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo('2026-10-15 08:00:00');
        $this->seed(RolePermissionSeeder::class);

        // `magasinier` : M6 = C, hors administration (archivage soumis à la bascule).
        $this->magasinier = $this->creerUtilisateur('magasinier');
        $this->huile = app(ReferentielArticleService::class)->creer([
            'libelle' => 'Huile', 'categorie' => 'Épicerie', 'unite_mesure' => 'litre', 'seuil_alerte' => '3.00',
        ]);

        $this->travelTo('2026-10-15 12:00:00');
    }

    // ------------------------------------------------------- Correspondance

    /**
     * Un article créé sur le poste a été FUSIONNÉ avec l'article serveur ; le
     * poste le modifie ensuite sous SON uuid : la modification atteint
     * l'élément serveur, et le poste apprend l'uuid serveur.
     */
    #[Test]
    public function une_modification_sous_l_uuid_du_poste_atteint_l_element_fusionne(): void
    {
        $idPoste = $this->uuid();

        $this->pousser([$this->a('articles', 'creation', $idPoste, '09:00', [
            'libelle' => 'HUILE', 'categorie' => 'Épicerie', 'unite_mesure' => 'Litre', 'seuil_alerte' => '3',
        ])], $this->magasinier)->assertJsonPath('resultats.0.fusionne_avec', $this->huile->id);

        $this->pousser([$this->a('articles', 'modification', $idPoste, '10:00', ['seuil_alerte' => '7'])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $this->huile->id)
            ->assertJsonPath('resultats.0.fusionne_avec', $this->huile->id);

        $this->assertSame('7.00', (string) $this->huile->fresh()->seuil_alerte);
        $this->assertSame(1, Article::count());
    }

    /**
     * Les identifiants CITÉS dans une modification passent aussi par les
     * correspondances : un plat rattaché à un menu créé sur le poste puis
     * fusionné.
     */
    #[Test]
    public function les_references_citees_par_une_modification_sont_traduites(): void
    {
        $cuisinier = $this->creerUtilisateur('cuisine');
        $carte = app(CartePlatMenuService::class);
        [$menuServeur, $plat] = $this->aHuitHeures(function () use ($carte): array {
            $menuServeur = $carte->creerMenu(['libelle' => 'Carte du soir', 'type' => 'local']);
            $autreMenu = $carte->creerMenu(['libelle' => 'Carte du midi', 'type' => 'local']);
            $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Poulet DG']);

            return [$menuServeur, $carte->creerPlat([
                'libelle' => 'Poulet DG', 'menu_id' => $autreMenu->id, 'recette_id' => $fiche->id, 'prix_vente' => '4500',
            ])];
        });
        $menuPoste = $this->uuid();

        $this->pousser([
            $this->a('menus', 'creation', $menuPoste, '09:00', ['libelle' => 'carte du SOIR', 'type' => 'local']),
            $this->a('plats', 'modification', $plat->id, '10:00', ['menu_id' => $menuPoste, 'prix_vente' => '5000']),
        ], $cuisinier)
            ->assertJsonPath('resultats.0.fusionne_avec', $menuServeur->id)
            ->assertJsonPath('resultats.1.statut', 'synchronise');

        $plat->refresh();
        $this->assertSame([$menuServeur->id, '5000.00', 'Poulet DG'], [$plat->menu_id, (string) $plat->prix_vente, $plat->libelle]);
    }

    // ------------------------------------------------- Dernier écrit gagnant

    /**
     * Poste A (saisie 10 h) puis poste B : sa saisie de 9 h est plus ANCIENNE
     * que la dernière appliquée → elle perd, la ligne de conflit est résolue
     * côté serveur ; sa saisie de 11 h est plus RÉCENTE → elle gagne. Aucun
     * arbitrage manuel : le catalogue n'est pas financier.
     */
    #[Test]
    public function une_modification_plus_ancienne_perd_une_plus_recente_gagne(): void
    {
        $this->pousser([$this->a('articles', 'modification', $this->huile->id, '10:00', ['seuil_alerte' => '5'])], $this->magasinier, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonMissingPath('resultats.0.resolution');

        $this->travelTo('2026-10-15 12:01:00');
        $ancienne = $this->pousser([$this->a('articles', 'modification', $this->huile->id, '09:00', ['seuil_alerte' => '1'])], $this->magasinier, 'poste-b');

        $ancienne->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.resolution', 'version_serveur_conservee');
        $this->assertSame('5.00', (string) $this->huile->fresh()->seuil_alerte);
        $this->assertDatabaseHas('conflits_synchronisation', [
            'id' => $ancienne->json('resultats.0.conflit_id'), 'table_concernee' => 'articles', 'statut' => 'resolu_serveur',
        ]);

        $this->travelTo('2026-10-15 12:02:00');
        $this->pousser([$this->a('articles', 'modification', $this->huile->id, '11:00', ['seuil_alerte' => '9'])], $this->magasinier, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.resolution', 'version_locale_conservee');

        $this->assertSame('9.00', (string) $this->huile->fresh()->seuil_alerte);
        $this->assertSame(0, ConflitSynchronisation::where('statut', 'en_attente_arbitrage')->count());
    }

    /**
     * Deux postes modifient la même boisson ; le plus RÉCENT en saisie gagne,
     * quel que soit l'ordre d'arrivée — et chacun reçoit son résultat. Un
     * même poste qui renvoie une saisie plus ancienne après une plus récente
     * perd aussi : on juge la saisie, jamais l'arrivée.
     */
    #[Test]
    public function deux_postes_modifiant_la_meme_boisson_le_plus_recent_gagne_et_chacun_a_son_resultat(): void
    {
        $barman = $this->creerUtilisateur('barman');
        $boisson = $this->aHuitHeures(fn (): CarteBoisson => CarteBoisson::create([
            'article_id' => $this->huile->id, 'libelle' => 'Béninoise', 'categorie' => 'locale', 'prix_vente' => '1000.00',
        ]));

        // Le plus récent (B, 11 h) arrive le PREMIER...
        $this->pousser([$this->a('cartes_boisson', 'modification', $boisson->id, '11:00', ['prix_vente' => '1200'])], $barman, 'poste-b')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        // ... le plus ancien (A, 10 h) ensuite : il perd, et le sait.
        $this->travelTo('2026-10-15 12:05:00');
        $this->pousser([$this->a('cartes_boisson', 'modification', $boisson->id, '10:00', ['prix_vente' => '900', 'libelle' => 'Béninoise 65cl'])], $barman, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.resolution', 'version_serveur_conservee');

        // Le même poste B renvoie une saisie antérieure à la sienne : perdue.
        $this->pousser([$this->a('cartes_boisson', 'modification', $boisson->id, '10:30', ['prix_vente' => '1100'])], $barman, 'poste-b')
            ->assertJsonPath('resultats.0.resolution', 'version_serveur_conservee');

        $boisson->refresh();
        $this->assertSame(['1200.00', 'Béninoise'], [(string) $boisson->prix_vente, $boisson->libelle]);
        $this->assertSame(2, ConflitSynchronisation::where('table_concernee', 'cartes_boisson')->count());
    }

    /**
     * La correction faite À L'ÉCRAN par le gérant (hors synchronisation)
     * compte dans l'arbitrage : une saisie de poste antérieure à elle perd,
     * même si une saisie de poste encore plus ancienne avait été appliquée.
     */
    #[Test]
    public function une_correction_en_ligne_posterieure_n_est_pas_ecrasee_par_une_saisie_plus_ancienne(): void
    {
        $this->travelTo('2026-10-15 10:00:00');
        $this->pousser([$this->a('articles', 'modification', $this->huile->id, '09:00', ['seuil_alerte' => '4'])], $this->magasinier, 'poste-a')
            ->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->travelTo('2026-10-15 11:00:00');
        app(ReferentielArticleService::class)->modifier($this->huile->fresh(), ['seuil_alerte' => '6']);

        $this->travelTo('2026-10-15 12:00:00');
        $this->pousser([$this->a('articles', 'modification', $this->huile->id, '10:30', ['seuil_alerte' => '2'])], $this->magasinier, 'poste-b')
            ->assertJsonPath('resultats.0.resolution', 'version_serveur_conservee');

        $this->assertSame('6.00', (string) $this->huile->fresh()->seuil_alerte);
    }

    // ---------------------------------------------------------- Archivage

    #[Test]
    public function l_archivage_par_la_synchronisation_suit_la_regle_de_droits_de_l_ecran(): void
    {
        // Hors administration, bascule fermée : refusé, l'article reste actif.
        $this->pousser([$this->a('articles', 'modification', $this->huile->id, '10:00', ['actif' => false])], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('pwa.archivage.refus_bascule'));
        $this->assertTrue((bool) $this->huile->fresh()->actif);

        // L'administrateur archive puis restaure, par le service.
        $admin = $this->creerUtilisateur('administrateur');
        $this->pousser([$this->a('articles', 'modification', $this->huile->id, '10:05', ['actif' => false])], $admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertFalse((bool) $this->huile->fresh()->actif);

        $this->pousser([$this->a('articles', 'modification', $this->huile->id, '10:10', ['actif' => true])], $admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertTrue((bool) $this->huile->fresh()->actif);

        // Une unité d'hébergement s'archive en `hors_service`, se restaure `libre`.
        $unite = $this->aHuitHeures(function (): UniteHebergement {
            $categorie = CategorieHebergement::create(['libelle' => 'Chambre', 'capacite_max' => 2, 'tarif_base' => '20000.00']);

            return UniteHebergement::create(['categorie_id' => $categorie->id, 'numero' => 'C-01', 'statut' => 'libre']);
        });

        $this->pousser([$this->a('unites_hebergement', 'modification', $unite->id, '10:15', ['actif' => false, 'statut' => 'occupee'])], $admin)
            ->assertJsonPath('resultats.0.statut', 'synchronise');
        $this->assertSame('hors_service', $unite->fresh()->statut);

        $this->pousser([$this->a('unites_hebergement', 'modification', $unite->id, '10:20', ['actif' => true])], $admin);
        $this->assertSame('libre', $unite->fresh()->statut);

        // Une table qui ne s'archive pas le dit, plutôt que d'ignorer la demande.
        $point = $this->aHuitHeures(fn (): PointStockage => PointStockage::create(['libelle' => 'Cave', 'type' => 'magasin']));
        $this->pousser([$this->a('points_stockage', 'modification', $point->id, '10:25', ['libelle' => 'Cave 2', 'actif' => false])], $admin)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.motif', __('sync.archivage_non_disponible'));
        $this->assertSame('Cave', $point->fresh()->libelle);
    }

    // --------------------------------------------------- Valeurs calculées

    /**
     * Stock, CMP, prix d'achat, coût matière : refusés par la synchronisation
     * EXACTEMENT comme par la route de modification — mêmes phrases.
     */
    #[Test]
    public function les_valeurs_calculees_restent_refusees_comme_a_l_api(): void
    {
        $cuisinier = $this->creerUtilisateur('cuisine');
        [$fiche, $plat] = $this->aHuitHeures(function (): array {
            $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Riz sauce']);
            $menu = app(CartePlatMenuService::class)->creerMenu(['libelle' => 'Carte', 'type' => 'local']);

            return [$fiche, app(CartePlatMenuService::class)->creerPlat([
                'libelle' => 'Riz sauce', 'menu_id' => $menu->id, 'recette_id' => $fiche->id, 'prix_vente' => '2500',
            ])];
        });

        $this->pousser([
            $this->a('articles', 'modification', $this->huile->id, '09:00', ['prix_achat' => '100', 'libelle' => 'Huile X']),
            $this->a('articles', 'modification', $this->huile->id, '09:01', ['stock' => '40']),
        ], $this->magasinier)
            ->assertJsonPath('resultats.0.statut', 'rejete')
            ->assertJsonPath('resultats.0.erreurs.prix_achat.0', __('stocks.validation.valeur_calculee'))
            ->assertJsonPath('resultats.1.erreurs.stock.0', __('stocks.validation.valeur_calculee'));

        $this->pousser([
            $this->a('plats', 'modification', $plat->id, '09:00', ['cout_matiere' => '10']),
            $this->a('recettes', 'modification', $fiche->id, '09:00', ['cout_matiere_calcule' => '10']),
        ], $cuisinier)
            ->assertJsonPath('resultats.0.motif', __('restaurant.validation.valeur_calculee'))
            ->assertJsonPath('resultats.1.motif', __('restaurant.validation.cout_matiere_calcule'));

        $this->assertSame('Huile', $this->huile->fresh()->libelle);
    }

    /**
     * La composition d'une fiche se remplace par la synchronisation, par
     * `CompositionRecetteService` — coût matière recalculé, jamais reçu.
     */
    #[Test]
    public function la_composition_d_une_fiche_se_remplace_par_le_service(): void
    {
        $cuisinier = $this->creerUtilisateur('cuisine');
        [$riz, $fiche] = $this->aHuitHeures(function (): array {
            $riz = app(ReferentielArticleService::class)->creer([
                'libelle' => 'Riz', 'categorie' => 'Épicerie', 'unite_mesure' => 'kg', 'seuil_alerte' => '1',
            ]);
            $fiche = app(ReferentielRecetteService::class)->creer(['libelle' => 'Riz sauce']);
            app(CompositionRecetteService::class)->remplacerComposition($fiche, [
                ['article_id' => $this->huile->id, 'quantite_unitaire' => '0.050'],
            ]);

            return [$riz, $fiche];
        });

        $this->pousser([$this->a('recettes', 'modification', $fiche->id, '10:00', [
            'lignes' => [['article_id' => $riz->id, 'quantite_unitaire' => '0.25']],
        ])], $cuisinier)->assertJsonPath('resultats.0.statut', 'synchronise');

        $this->assertSame(
            [$riz->id],
            DB::table('ingredients_recette')->where('recette_id', $fiche->id)->pluck('article_id')->all(),
        );
        $this->assertSame('Riz sauce', Recette::findOrFail($fiche->id)->libelle);
    }

    // ------------------------------------- Modification d'un id inconnu

    /**
     * La création s'est perdue en route : une modification COMPLÈTE crée
     * l'élément sous l'UUID du poste ; une modification qui RECOUPE un élément
     * serveur (clé naturelle) y fusionne ; une modification INCOMPLÈTE est
     * rejetée avec son motif et ses erreurs par champ.
     */
    #[Test]
    public function une_modification_d_un_id_inconnu_devient_une_creation_si_elle_est_complete(): void
    {
        [$complet, $recoupe, $incomplet] = [$this->uuid(), $this->uuid(), $this->uuid()];

        $reponse = $this->pousser([
            $this->a('articles', 'modification', $complet, '09:00', [
                'libelle' => 'Farine', 'categorie' => 'Épicerie', 'unite_mesure' => 'kg', 'seuil_alerte' => '2',
            ]),
            $this->a('articles', 'modification', $recoupe, '09:00', [
                'libelle' => 'huile', 'categorie' => 'Épicerie', 'unite_mesure' => 'LITRE', 'seuil_alerte' => '1',
            ]),
            $this->a('articles', 'modification', $incomplet, '09:00', ['seuil_alerte' => '2']),
        ], $this->magasinier);

        $reponse->assertJsonPath('resultats.0.statut', 'synchronise')
            ->assertJsonPath('resultats.0.entite_id', $complet)
            ->assertJsonPath('resultats.0.cree_depuis_modification', true)
            ->assertJsonPath('resultats.1.fusionne_avec', $this->huile->id)
            ->assertJsonPath('resultats.2.statut', 'rejete')
            ->assertJsonPath('resultats.2.motif', __('sync.modification_inconnue_incomplete', [
                'raison' => __('stocks.validation.libelle_obligatoire'),
            ]))
            ->assertJsonStructure(['resultats' => [2 => ['erreurs' => ['libelle', 'unite_mesure']]]]);

        $this->assertSame('Farine', Article::findOrFail($complet)->libelle);
        $this->assertDatabaseHas('correspondances_synchronisation', [
            'table_concernee' => 'articles', 'id_poste' => $recoupe, 'id_serveur' => $this->huile->id,
        ]);
        // Rien n'est écrasé sur la cible de fusion, rien n'est créé pour l'incomplet.
        $this->assertSame('3.00', (string) $this->huile->fresh()->seuil_alerte);
        $this->assertNull(Article::find($incomplet));

        // Même règle pour un fournisseur, référentiel M7.
        $idFournisseur = $this->uuid();
        $this->pousser([$this->a('fournisseurs', 'modification', $idFournisseur, '09:00', ['raison_sociale' => 'Glacier du Port'])], $this->magasinier)
            ->assertJsonPath('resultats.0.cree_depuis_modification', true);
        $this->assertSame('Glacier du Port', Fournisseur::findOrFail($idFournisseur)->raison_sociale);
    }

    // ----------------------------------------------------------- Helpers

    /**
     * Le décor serveur posé à 08 h, AVANT les saisies des postes : sinon il
     * serait la version la plus récente, et gagnerait à bon droit.
     *
     * @template T
     *
     * @param  callable(): T  $decor
     * @return T
     */
    private function aHuitHeures(callable $decor): mixed
    {
        $this->travelTo('2026-10-15 08:00:00');
        $resultat = $decor();
        $this->travelTo('2026-10-15 12:00:00');

        return $resultat;
    }

    /**
     * Une opération saisie au poste le 15/10/2026 à `$heure`.
     *
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function a(string $table, string $type, string $id, string $heure, array $payload): array
    {
        return [...$this->operation($table, $type, $id, $payload), 'horodatage_client' => '2026-10-15T' . $heure . ':00+00:00'];
    }
}
