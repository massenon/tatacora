<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Achats;

use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Models\LigneCommandeAchat;
use App\Domain\Achats\Policies\CommandeAchatPolicy;
use App\Domain\Achats\Policies\FournisseurPolicy;
use App\Domain\Achats\Services\ReceptionService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Route as RouteFacade;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * API M7 — Achats & Fournisseurs. Routes consommées par `m7-achats.html` et
 * `m7-approvisionnement.html`.
 *
 * @see EF-M7-01 Référentiel fournisseurs
 * @see EF-M7-02 Émission de commandes d'achat
 * @see EF-M7-03 Réception avec bon et contrôle de conformité
 * @see EF-M7-04 Rapprochement à trois voies
 * @see RG-10 Clôture sous tolérance paramétrable
 * @see RG-16 RBAC de 2e niveau
 *
 * ## Ce que cette suite existe pour empêcher
 *
 * 1. **Qu'un montant calculé redevienne un champ saisi** (PA-24). Le
 *    formulaire du prototype porte « Montant estimé » en saisie libre ;
 *    l'accepter ici ferait diverger le total affiché de la somme des lignes
 *    dès la première correction, sans que rien ne le signale.
 * 2. **Qu'une route d'écriture perde sa garde RBAC** (PA-65). Les rôles sont
 *    dérivés de `RolePermissionSeeder::MATRICE`, jamais écrits en dur.
 * 3. **Qu'une réception soit enregistrée sans tolérance configurée.** RG-10
 *    veut un seuil paramétrable ; en son absence le service refuse de
 *    calculer, et ce refus doit remonter en 422 sans laisser derrière lui ni
 *    bon de réception, ni entrée de stock.
 * 4. **Que le rapprochement annonce une troisième voie qu'il n'a pas
 *    vérifiée.** `ControleTroisVoiesService` bascule `facture_verifiable` sur
 *    la simple PRÉSENCE d'un tableau de montants, qu'il ne compare à rien.
 *    L'API ne l'expose pas ; ce test le prouve.
 */
final class ApiAchatsTest extends TestCase
{
    use RefreshDatabase;

    private Fournisseur $fournisseur;

    private PointStockage $magasin;

    private Article $riz;

    private Article $huile;

    /** Mémoïsé : les fixtures en ont besoin avant que le test ne s'authentifie. */
    private ?User $acheteur = null;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        // Tolérance RG-10 — paramètre, jamais codée en dur. Le cas de son
        // absence a son propre test.
        ParametreSysteme::create([
            'cle' => ReceptionService::CLE_TOLERANCE,
            'valeur' => '2.00',
            'description' => 'Tolérance de réception en % (RG-10).',
        ]);

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $this->riz = $this->article('Riz parfumé 50kg', 'sac');
        $this->huile = $this->article('Huile végétale 5L', 'bidon');

        $this->fournisseur = Fournisseur::create([
            'raison_sociale' => 'Grand Marché Natitingou SARL',
            'contact' => '01 90 12 34 56',
            'categorie' => 'Denrées alimentaires',
            'conditions_paiement' => 'Comptant',
            'evaluation' => 'excellent',
        ]);
    }

    // ------------------------------------------------------- Authentification

    /**
     * Aucune des douze routes n'est publique. La liste est explicite : une
     * route ajoutée au groupe sans jeton passerait sinon inaperçue.
     */
    #[Test]
    public function aucune_route_d_achats_n_est_accessible_sans_jeton(): void
    {
        $commande = $this->commande();

        $this->getJson('/api/v1/achats/fournisseurs')->assertUnauthorized();
        $this->getJson("/api/v1/achats/fournisseurs/{$this->fournisseur->id}")->assertUnauthorized();
        $this->postJson('/api/v1/achats/fournisseurs', [])->assertUnauthorized();
        $this->putJson("/api/v1/achats/fournisseurs/{$this->fournisseur->id}", [])->assertUnauthorized();
        $this->getJson('/api/v1/achats/commandes')->assertUnauthorized();
        $this->postJson('/api/v1/achats/commandes', [])->assertUnauthorized();
        $this->getJson("/api/v1/achats/commandes/{$commande->id}")->assertUnauthorized();
        $this->patchJson("/api/v1/achats/commandes/{$commande->id}/envoi")->assertUnauthorized();
        $this->patchJson("/api/v1/achats/commandes/{$commande->id}/cloture")->assertUnauthorized();
        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", [])->assertUnauthorized();
        $this->getJson("/api/v1/achats/commandes/{$commande->id}/rapprochement")->assertUnauthorized();
        $this->getJson('/api/v1/achats/receptions')->assertUnauthorized();
    }

    // ------------------------------------------------------------------ RBAC

    /**
     * RG-16 — un rôle sans aucun accès à M7 est refusé, en lecture comme en
     * écriture. Le rôle est DÉRIVÉ de la matrice : l'écrire en dur ferait
     * passer la suite au vert le jour où la matrice changerait.
     */
    #[Test]
    public function rg16_un_role_sans_acces_a_m7_est_refuse_partout(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM7('-')));

        $this->getJson('/api/v1/achats/fournisseurs')->assertForbidden();
        $this->getJson('/api/v1/achats/commandes')->assertForbidden();
        $this->getJson('/api/v1/achats/receptions')->assertForbidden();
        $this->getJson("/api/v1/achats/commandes/{$commande->id}/rapprochement")->assertForbidden();
        $this->postJson('/api/v1/achats/fournisseurs', $this->fournisseurValide())->assertForbidden();
        $this->postJson('/api/v1/achats/commandes', $this->commandeValide())->assertForbidden();
        $this->postJson(
            "/api/v1/achats/commandes/{$commande->id}/receptions",
            $this->receptionValide(),
        )->assertForbidden();

        $this->assertSame(1, Fournisseur::count());
        $this->assertSame(1, CommandeAchat::count());
        $this->assertSame(0, BonReception::count());
        $this->assertSame(0, MouvementStock::count());
    }

    /**
     * RG-16 — un rôle en LECTURE seule consulte tout et n'écrit rien.
     */
    #[Test]
    public function rg16_un_role_en_lecture_seule_consulte_mais_n_ecrit_pas(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM7('L')));

        $this->getJson('/api/v1/achats/fournisseurs')->assertOk();
        $this->getJson("/api/v1/achats/fournisseurs/{$this->fournisseur->id}")->assertOk();
        $this->getJson('/api/v1/achats/commandes')->assertOk();
        $this->getJson("/api/v1/achats/commandes/{$commande->id}")->assertOk();
        $this->getJson('/api/v1/achats/receptions')->assertOk();
        $this->getJson("/api/v1/achats/commandes/{$commande->id}/rapprochement")->assertOk();

        $this->postJson('/api/v1/achats/fournisseurs', $this->fournisseurValide())->assertForbidden();
        $this->putJson(
            "/api/v1/achats/fournisseurs/{$this->fournisseur->id}",
            $this->fournisseurValide(),
        )->assertForbidden();
        $this->postJson('/api/v1/achats/commandes', $this->commandeValide())->assertForbidden();
        $this->patchJson("/api/v1/achats/commandes/{$commande->id}/envoi")->assertForbidden();
        $this->patchJson("/api/v1/achats/commandes/{$commande->id}/cloture")->assertForbidden();
        $this->postJson(
            "/api/v1/achats/commandes/{$commande->id}/receptions",
            $this->receptionValide(),
        )->assertForbidden();

        $this->assertSame(1, Fournisseur::count());
        $this->assertSame(1, CommandeAchat::count());
        $this->assertSame(0, BonReception::count());
    }

    /**
     * Le refus RBAC est traduit, jamais écrit en dur dans le middleware.
     */
    #[Test]
    public function rg16_le_refus_est_un_message_traduit(): void
    {
        Sanctum::actingAs($this->utilisateur($this->roleAvecNiveauM7('-')));

        $this->getJson('/api/v1/achats/commandes')
            ->assertForbidden()
            ->assertJsonPath('message', __('auth.module_refuse'));
    }

    /**
     * Garde STRUCTURELLE à liste fermée — chaque route du groupe `achats`
     * déclare le niveau RBAC qu'elle exige, et la suite échoue tant qu'une
     * route nouvelle n'y est pas inscrite.
     *
     * ## Pourquoi un test de structure en plus des tests de comportement
     *
     * Retirer `module:M7,C` de `POST /achats/commandes` ne fait rougir aucun
     * test de comportement : le `FormRequest` refuse aussi, en 3ᵉ niveau, et
     * le 403 reste un 403. La garde disparue serait donc invisible — jusqu'au
     * jour où quelqu'un ajouterait une route d'écriture sans `FormRequest`, et
     * où plus rien ne la tiendrait. C'est exactement la forme de PA-65.
     *
     * La liste ci-dessous est la spécification : une route ajoutée au groupe
     * sans y figurer fait échouer la suite, donc se fait relire.
     */
    #[Test]
    public function rg16_chaque_route_du_groupe_achats_porte_sa_garde_rbac(): void
    {
        $attendu = [
            'GET|HEAD api/v1/achats/fournisseurs' => 'M7,L',
            'GET|HEAD api/v1/achats/fournisseurs/{fournisseur}' => 'M7,L',
            'POST api/v1/achats/fournisseurs' => 'M7,C',
            'PUT api/v1/achats/fournisseurs/{fournisseur}' => 'M7,C',
            'GET|HEAD api/v1/achats/commandes' => 'M7,L',
            'POST api/v1/achats/commandes' => 'M7,C',
            'GET|HEAD api/v1/achats/commandes/{commande}' => 'M7,L',
            'PATCH api/v1/achats/commandes/{commande}/envoi' => 'M7,C',
            'PATCH api/v1/achats/commandes/{commande}/cloture' => 'M7,C',
            'POST api/v1/achats/commandes/{commande}/receptions' => 'M7,C',
            'GET|HEAD api/v1/achats/commandes/{commande}/rapprochement' => 'M7,L',
            'GET|HEAD api/v1/achats/receptions' => 'M7,L',
        ];

        $constate = [];

        foreach (RouteFacade::getRoutes()->getRoutes() as $route) {
            if (! str_starts_with($route->uri(), 'api/v1/achats/')) {
                continue;
            }

            $middlewares = $route->gatherMiddleware();

            $gardes = array_values(array_filter(
                $middlewares,
                fn (mixed $m): bool => is_string($m) && str_starts_with($m, 'module:'),
            ));

            $cle = implode('|', array_diff($route->methods(), ['HEAD'])) . ' ' . $route->uri();
            $cle = str_contains($cle, 'GET ') ? str_replace('GET ', 'GET|HEAD ', $cle) : $cle;

            $constate[$cle] = $gardes === []
                ? 'AUCUNE GARDE'
                : str_replace('module:', '', $gardes[0]);

            $this->assertContains(
                'auth:sanctum',
                $middlewares,
                "La route {$cle} est accessible sans authentification.",
            );
        }

        ksort($attendu);
        ksort($constate);

        $this->assertSame(
            $attendu,
            $constate,
            'Une route du groupe `achats` a perdu sa garde RBAC, ou une route nouvelle n\'est pas inscrite ici.',
        );
    }

    /**
     * Aucune suppression n'est exposée sur une table transactionnelle. Le
     * verbe non routé (405) est la seule preuve solide qu'elle n'existe pas ;
     * les Policy la refusent en second niveau.
     */
    #[Test]
    public function aucune_suppression_n_est_exposee(): void
    {
        $commande = $this->commande();
        $administrateur = $this->utilisateur($this->roleAvecNiveauM7('C'));
        Sanctum::actingAs($administrateur);

        $this->deleteJson("/api/v1/achats/fournisseurs/{$this->fournisseur->id}")
            ->assertMethodNotAllowed();
        $this->deleteJson("/api/v1/achats/commandes/{$commande->id}")
            ->assertMethodNotAllowed();

        $this->assertFalse((new FournisseurPolicy())->delete($administrateur));
        $this->assertFalse((new CommandeAchatPolicy())->delete($administrateur));
    }

    // ------------------------------------------------------ EF-M7-01 Fournisseurs

    #[Test]
    public function ef_m7_01_le_referentiel_rend_les_champs_de_la_fiche(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->getJson('/api/v1/achats/fournisseurs')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.raison_sociale', 'Grand Marché Natitingou SARL')
            ->assertJsonPath('data.0.contact', '01 90 12 34 56')
            ->assertJsonPath('data.0.categorie', 'Denrées alimentaires')
            ->assertJsonPath('data.0.conditions_paiement', 'Comptant')
            ->assertJsonPath('data.0.evaluation', 'excellent');
    }

    /**
     * `null` veut dire « pas encore évalué », ce qui n'est pas « à revoir ».
     * Les confondre reprocherait à un fournisseur neuf une mauvaise note que
     * personne ne lui a donnée.
     */
    #[Test]
    public function ef_m7_01_un_fournisseur_non_evalue_rend_null_et_non_a_revoir(): void
    {
        Fournisseur::create(['raison_sociale' => 'Atacora Carburants']);
        Sanctum::actingAs($this->acheteur());

        $reponse = $this->getJson('/api/v1/achats/fournisseurs?recherche=Atacora')->assertOk();

        $reponse->assertJsonCount(1, 'data');
        $reponse->assertJsonPath('data.0.evaluation', null);
    }

    #[Test]
    public function ef_m7_01_la_recherche_porte_sur_la_raison_sociale_et_le_contact(): void
    {
        Fournisseur::create(['raison_sociale' => 'Bénin Boissons', 'contact' => '01 91 22 33 44']);
        Sanctum::actingAs($this->acheteur());

        $this->getJson('/api/v1/achats/fournisseurs?recherche=Boissons')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.raison_sociale', 'Bénin Boissons');

        $this->getJson('/api/v1/achats/fournisseurs?recherche=01 90 12')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.raison_sociale', 'Grand Marché Natitingou SARL');
    }

    /**
     * Un filtre incompris se REFUSE, il ne se tait pas : ignoré, il rendrait
     * le référentiel entier sous un intitulé qui promet le contraire (PA-119).
     */
    #[Test]
    public function ef_m7_01_un_filtre_d_evaluation_inconnu_est_refuse(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->getJson('/api/v1/achats/fournisseurs?evaluation=Excellent')
            ->assertStatus(422)
            ->assertJsonPath('errors.evaluation.0', __('achats.validation.evaluation_inconnue'));
    }

    #[Test]
    public function ef_m7_01_la_creation_rend_201_et_la_fiche_complete(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->postJson('/api/v1/achats/fournisseurs', $this->fournisseurValide())
            ->assertCreated()
            ->assertJsonPath('data.raison_sociale', 'Coopérative Maraîchère Atacora')
            ->assertJsonPath('data.evaluation', 'bon');

        $this->assertSame(2, Fournisseur::count());
    }

    #[Test]
    public function ef_m7_01_la_modification_met_a_jour_l_evaluation(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->putJson("/api/v1/achats/fournisseurs/{$this->fournisseur->id}", [
            'raison_sociale' => 'Grand Marché Natitingou SARL',
            'contact' => '01 90 12 34 56',
            'evaluation' => 'a_revoir',
        ])
            ->assertOk()
            ->assertJsonPath('data.evaluation', 'a_revoir');

        $this->assertSame('a_revoir', $this->fournisseur->refresh()->evaluation);
    }

    /**
     * PA-24 — un encours fournisseur ne se saisit pas. Il n'a d'ailleurs
     * aucune table pour l'accueillir ; l'accepter laisserait croire qu'il a
     * été enregistré quelque part.
     */
    #[Test]
    public function pa24_un_encours_fournisseur_soumis_est_refuse(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->postJson('/api/v1/achats/fournisseurs', array_merge($this->fournisseurValide(), [
            'encours' => '125000.00',
        ]))
            ->assertStatus(422)
            ->assertJsonPath('errors.encours.0', __('achats.validation.valeur_calculee'));

        $this->assertSame(1, Fournisseur::count());
    }

    // ------------------------------------------------------ EF-M7-02 Commandes

    #[Test]
    public function ef_m7_02_la_creation_persiste_la_commande_et_ses_lignes(): void
    {
        Sanctum::actingAs($this->acheteur());

        $reponse = $this->postJson('/api/v1/achats/commandes', $this->commandeValide())
            ->assertCreated();

        $reponse->assertJsonPath('data.statut', 'envoyee');
        $reponse->assertJsonPath('data.fournisseur.raison_sociale', 'Grand Marché Natitingou SARL');
        $reponse->assertJsonCount(2, 'data.lignes');
        $reponse->assertJsonPath('data.lignes.0.article_libelle', 'Riz parfumé 50kg');
        $reponse->assertJsonPath('data.lignes.0.unite_mesure', 'sac');

        $this->assertSame(1, CommandeAchat::count());
        $this->assertSame(2, LigneCommandeAchat::count());
    }

    /**
     * Le montant total est CALCULÉ depuis les lignes, et il sort en CHAÎNE :
     * 100 × 800 + 20 × 6 500 = 210 000. Un float réarrondi côté client ferait
     * diverger l'affichage du chiffre réellement stocké (PA-55).
     */
    #[Test]
    public function ef_m7_02_le_montant_total_est_calcule_et_sort_en_chaine(): void
    {
        Sanctum::actingAs($this->acheteur());

        $reponse = $this->postJson('/api/v1/achats/commandes', $this->commandeValide())
            ->assertCreated();

        $reponse->assertJsonPath('data.montant_total', '210000.00');
        $reponse->assertJsonPath('data.montant_lecture_seule', true);
        $reponse->assertJsonPath('data.lignes.0.montant', '80000.00');
        $reponse->assertJsonPath('data.lignes.1.montant', '130000.00');

        $montant = $reponse->json('data.montant_total');
        $this->assertIsString($montant);
        $this->assertSame(0, bccomp($montant, '210000.00', 2));
    }

    /**
     * PA-24 — « Montant estimé » est un champ du formulaire du prototype.
     * L'accepter ne servirait qu'à laisser croire au client qu'il a compté.
     */
    #[Test]
    public function pa24_un_montant_total_soumis_est_refuse(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->postJson('/api/v1/achats/commandes', array_merge($this->commandeValide(), [
            'montant_total' => '999999.00',
        ]))
            ->assertStatus(422)
            ->assertJsonPath('errors.montant_total.0', __('achats.validation.valeur_calculee'));

        $this->postJson('/api/v1/achats/commandes', array_merge($this->commandeValide(), [
            'montant_estime' => '999999.00',
        ]))
            ->assertStatus(422);

        $this->assertSame(0, CommandeAchat::count());
    }

    /**
     * Trois des cinq statuts de l'enum sont produits par une réception réelle.
     * Les poser à la création afficherait une commande « Reçue » dont aucune
     * marchandise n'est entrée en stock — PA-59/60/61 sur un bon de commande.
     */
    #[Test]
    public function ef_m7_02_un_statut_de_reception_ne_se_saisit_pas(): void
    {
        Sanctum::actingAs($this->acheteur());

        foreach (['receptionnee', 'receptionnee_partiellement', 'cloturee'] as $statut) {
            $this->postJson('/api/v1/achats/commandes', array_merge($this->commandeValide(), [
                'statut' => $statut,
            ]))
                ->assertStatus(422)
                ->assertJsonPath('errors.statut.0', __('achats.validation.statut_non_saisissable'));
        }

        $this->assertSame(0, CommandeAchat::count());
    }

    /**
     * Le même article deux fois ferait écraser la première ligne par la
     * seconde au moment du contrôle RG-10 (`pluck` par `article_id`) : la
     * commande porterait 100 + 20 sacs, le contrôle n'en verrait que 20, et une
     * livraison complète serait déclarée en excédent hors tolérance.
     */
    #[Test]
    public function ef_m7_02_un_article_en_double_est_refuse(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->postJson('/api/v1/achats/commandes', [
            'fournisseur_id' => $this->fournisseur->id,
            'date_commande' => '2026-08-20',
            'lignes' => [
                ['article_id' => $this->riz->id, 'quantite_commandee' => '100', 'prix_unitaire' => '800'],
                ['article_id' => $this->riz->id, 'quantite_commandee' => '20', 'prix_unitaire' => '800'],
            ],
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors([
                'lignes.0.article_id' => __('achats.validation.article_en_double'),
            ]);

        $this->assertSame(0, CommandeAchat::count());
    }

    #[Test]
    public function ef_m7_02_une_commande_sans_ligne_est_refusee(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->postJson('/api/v1/achats/commandes', [
            'fournisseur_id' => $this->fournisseur->id,
            'date_commande' => '2026-08-20',
            'lignes' => [],
        ])
            ->assertStatus(422)
            ->assertJsonPath('errors.lignes.0', __('achats.validation.lignes_obligatoires'));

        $this->assertSame(0, CommandeAchat::count());
    }

    /**
     * Le fournisseur est une VRAIE clé étrangère : l'anti-pattern « texte
     * libre » du prototype casserait silencieusement le rapprochement.
     */
    #[Test]
    public function ef_m7_02_un_fournisseur_inconnu_est_refuse_en_clair(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->postJson('/api/v1/achats/commandes', array_merge($this->commandeValide(), [
            'fournisseur_id' => (string) Str::uuid(),
        ]))
            ->assertStatus(422)
            ->assertJsonPath('errors.fournisseur_id.0', __('achats.validation.fournisseur_inexistant'));
    }

    /**
     * L'auteur vient du jeton (RG-15). L'accepter dans le corps permettrait
     * d'attribuer une commande à quelqu'un d'autre.
     */
    #[Test]
    public function rg15_l_auteur_vient_du_jeton_et_ne_se_soumet_pas(): void
    {
        $acheteur = $this->acheteur();
        $autre = $this->utilisateur($this->roleAvecNiveauM7('C'));
        Sanctum::actingAs($acheteur);

        $this->postJson('/api/v1/achats/commandes', array_merge($this->commandeValide(), [
            'utilisateur_id' => $autre->id,
        ]))->assertStatus(422);

        $this->postJson('/api/v1/achats/commandes', $this->commandeValide())->assertCreated();

        $commande = CommandeAchat::firstOrFail();
        $this->assertSame($acheteur->id, $commande->utilisateur_id);
    }

    #[Test]
    public function ef_m7_02_le_registre_filtre_par_statut_et_rend_son_total(): void
    {
        $this->commande('envoyee');
        $this->commande('brouillon');
        Sanctum::actingAs($this->acheteur());

        $this->getJson('/api/v1/achats/commandes')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('meta.total', 2);

        // C'est ainsi que le KPI « Commandes en attente » se lit : par le
        // total du registre filtré, jamais en additionnant une page.
        $this->getJson('/api/v1/achats/commandes?statut=envoyee&par_page=1')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.statut', 'envoyee');
    }

    #[Test]
    public function ef_m7_02_un_filtre_de_statut_inconnu_est_refuse(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->getJson('/api/v1/achats/commandes?statut=Envoyée')
            ->assertStatus(422)
            ->assertJsonPath('errors.statut.0', __('achats.validation.statut_inconnu'));
    }

    #[Test]
    public function ef_m7_02_un_brouillon_s_emet_une_seule_fois(): void
    {
        $commande = $this->commande('brouillon');
        Sanctum::actingAs($this->acheteur());

        $this->patchJson("/api/v1/achats/commandes/{$commande->id}/envoi")
            ->assertOk()
            ->assertJsonPath('data.statut', 'envoyee');

        $this->patchJson("/api/v1/achats/commandes/{$commande->id}/envoi")
            ->assertStatus(422)
            ->assertJsonPath('message', __('achats.envoi_impossible'));

        $this->assertSame('envoyee', $commande->refresh()->statut);
    }

    // ------------------------------------------------------ EF-M7-03 Réception

    /**
     * « EF-M7-03 déclenche `mouvements_stock` (entrée) — jamais de
     * double-saisie manuelle du stock après réception. »
     */
    #[Test]
    public function ef_m7_03_la_reception_genere_l_entree_de_stock_et_avance_la_commande(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", $this->receptionValide())
            ->assertCreated()
            ->assertJsonPath('data.conformite', 'totale')
            ->assertJsonPath('data.commande_id', $commande->id)
            ->assertJsonPath('data.lignes_non_stockees', true)
            ->assertJsonPath('data.fournisseur.raison_sociale', 'Grand Marché Natitingou SARL');

        $stock = app(StockTheoriqueService::class);
        $this->assertSame('100.00', $stock->stock($this->riz->id, $this->magasin->id));
        $this->assertSame('20.00', $stock->stock($this->huile->id, $this->magasin->id));
        $this->assertSame('receptionnee', $commande->refresh()->statut);
    }

    /**
     * RG-10 — 95 sur 100, soit −5 %, au-delà de la tolérance de 2 % : la
     * livraison est partielle, et la commande le dit.
     */
    #[Test]
    public function rg10_un_ecart_hors_tolerance_rend_la_reception_partielle(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", [
            'point_stockage_id' => $this->magasin->id,
            'lignes' => [
                ['article_id' => $this->riz->id, 'quantite_recue' => '95'],
                ['article_id' => $this->huile->id, 'quantite_recue' => '20'],
            ],
        ])
            ->assertCreated()
            ->assertJsonPath('data.conformite', 'partielle');

        $this->assertSame('receptionnee_partiellement', $commande->refresh()->statut);
    }

    /**
     * Le refus de calculer EST le livrable. Sans tolérance configurée, aucune
     * conformité ne peut être évaluée : le service refuse, et il ne doit rien
     * laisser derrière lui — ni bon de réception, ni entrée de stock. Une
     * réception à moitié écrite serait pire qu'un refus.
     */
    #[Test]
    public function rg10_sans_tolerance_configuree_la_reception_est_refusee_sans_rien_ecrire(): void
    {
        ParametreSysteme::where('cle', ReceptionService::CLE_TOLERANCE)->delete();

        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", $this->receptionValide())
            ->assertStatus(422)
            ->assertJsonPath('message', __('achats.tolerance_absente', [
                'cle' => ReceptionService::CLE_TOLERANCE,
            ]));

        $this->assertSame(0, BonReception::count());
        $this->assertSame(0, MouvementStock::count());
        $this->assertSame('envoyee', $commande->refresh()->statut);
    }

    /**
     * Une commande clôturée ne se réceptionne plus : une entrée de stock sans
     * commande en face ferait entrer de la marchandise que personne n'a
     * commandée.
     */
    #[Test]
    public function ef_m7_03_une_commande_deja_receptionnee_refuse_une_seconde_reception(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", $this->receptionValide())
            ->assertCreated();

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", $this->receptionValide())
            ->assertStatus(422)
            ->assertJsonPath('message', __('achats.commande_cloturee'));

        $this->assertSame(1, BonReception::count());
    }

    /**
     * Une quantité reçue à zéro n'est pas une réception, c'est une saisie
     * inachevée : le service l'ignorerait pour le stock mais la compterait
     * dans le verdict. Deux comportements pour une même saisie finissent
     * toujours par surprendre quelqu'un.
     */
    #[Test]
    public function ef_m7_03_une_quantite_recue_a_zero_est_refusee(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", [
            'point_stockage_id' => $this->magasin->id,
            'lignes' => [['article_id' => $this->riz->id, 'quantite_recue' => '0']],
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors([
                'lignes.0.quantite_recue' => __('achats.validation.quantite_positive'),
            ]);

        $this->assertSame(0, BonReception::count());
    }

    /**
     * PA-24 — le verdict RG-10 ne se saisit pas. L'accepter permettrait de
     * déclarer « totale » une livraison amputée de moitié, et la créance sur
     * le fournisseur serait perdue sans trace.
     */
    #[Test]
    public function pa24_une_conformite_soumise_est_refusee(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", array_merge(
            $this->receptionValide(),
            ['conformite' => 'totale'],
        ))
            ->assertStatus(422)
            ->assertJsonPath('errors.conformite.0', __('achats.validation.valeur_calculee'));

        $this->assertSame(0, BonReception::count());
    }

    /**
     * RG-10 impose une tolérance PARAMÉTRABLE. La passer dans la requête
     * ferait de chaque réception sa propre règle — c'est-à-dire qu'il n'y
     * aurait plus de règle.
     */
    #[Test]
    public function rg10_une_tolerance_soumise_dans_la_requete_est_refusee(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", array_merge(
            $this->receptionValide(),
            ['tolerance_pct' => '50.00'],
        ))
            ->assertStatus(422)
            ->assertJsonPath('errors.tolerance_pct.0', __('achats.validation.valeur_calculee'));

        $this->assertSame(0, BonReception::count());
    }

    /**
     * Le « déjà reçu » du détail vient des mouvements de stock (PA-39). Sans
     * lui, la modale de réception repartirait de la quantité commandée entière
     * et ferait entrer la marchandise deux fois.
     */
    #[Test]
    public function ef_m7_03_le_detail_rend_le_deja_recu_et_le_reste_a_recevoir(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", [
            'point_stockage_id' => $this->magasin->id,
            'lignes' => [['article_id' => $this->riz->id, 'quantite_recue' => '60']],
        ])->assertCreated();

        $reponse = $this->getJson("/api/v1/achats/commandes/{$commande->id}")->assertOk();

        $reponse->assertJsonPath('data.recu_reconstitue', true);
        $reponse->assertJsonPath('data.lignes.0.quantite_recue', '60.00');
        $reponse->assertJsonPath('data.lignes.0.reste_a_recevoir', '40.00');
        // L'huile n'a rien reçu : zéro, et non une absence de clé.
        $reponse->assertJsonPath('data.lignes.1.quantite_recue', '0.00');
        $reponse->assertJsonPath('data.lignes.1.reste_a_recevoir', '20.00');
        $reponse->assertJsonCount(1, 'data.receptions');
    }

    /**
     * Un excédent ne devient jamais un reste NÉGATIF à recevoir : la modale
     * poserait une quantité négative par défaut, que le formulaire refuserait
     * sans expliquer pourquoi.
     */
    #[Test]
    public function ef_m7_03_un_excedent_ne_rend_pas_un_reste_negatif(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", [
            'point_stockage_id' => $this->magasin->id,
            'lignes' => [['article_id' => $this->riz->id, 'quantite_recue' => '120']],
        ])->assertCreated();

        $this->getJson("/api/v1/achats/commandes/{$commande->id}")
            ->assertOk()
            ->assertJsonPath('data.lignes.0.quantite_recue', '120.00')
            ->assertJsonPath('data.lignes.0.reste_a_recevoir', '0.00');
    }

    #[Test]
    public function ef_m7_03_le_registre_des_receptions_filtre_par_conformite(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", [
            'point_stockage_id' => $this->magasin->id,
            'lignes' => [['article_id' => $this->riz->id, 'quantite_recue' => '95']],
        ])->assertCreated();

        $this->getJson('/api/v1/achats/receptions?conformite=partielle')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.conformite', 'partielle');

        $this->getJson('/api/v1/achats/receptions?conformite=totale')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    #[Test]
    public function ef_m7_03_un_filtre_de_conformite_inconnu_est_refuse(): void
    {
        Sanctum::actingAs($this->acheteur());

        $this->getJson('/api/v1/achats/receptions?conformite=avec_ecart')
            ->assertStatus(422)
            ->assertJsonPath('errors.conformite.0', __('achats.validation.conformite_inconnue'));
    }

    // ------------------------------------------------------------ RG-10 Clôture

    #[Test]
    public function rg10_une_commande_conforme_se_cloture(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", $this->receptionValide())
            ->assertCreated();

        $this->patchJson("/api/v1/achats/commandes/{$commande->id}/cloture")
            ->assertOk()
            ->assertJsonPath('data.statut', 'cloturee')
            ->assertJsonPath('data.receptionnable', false);

        $this->assertSame('cloturee', $commande->refresh()->statut);
    }

    /**
     * Le refus est le livrable : clôturer une livraison incomplète ferait
     * perdre la créance sur le fournisseur.
     */
    #[Test]
    public function rg10_une_commande_partiellement_recue_ne_se_cloture_pas(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", [
            'point_stockage_id' => $this->magasin->id,
            'lignes' => [['article_id' => $this->riz->id, 'quantite_recue' => '50']],
        ])->assertCreated();

        $this->patchJson("/api/v1/achats/commandes/{$commande->id}/cloture")
            ->assertStatus(422)
            ->assertJsonPath('message', __('achats.cloture_impossible'));

        $this->assertSame('receptionnee_partiellement', $commande->refresh()->statut);
    }

    // ------------------------------------------------- EF-M7-04 Rapprochement

    #[Test]
    public function ef_m7_04_le_rapprochement_compare_commande_et_reception(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $this->postJson("/api/v1/achats/commandes/{$commande->id}/receptions", [
            'point_stockage_id' => $this->magasin->id,
            'lignes' => [['article_id' => $this->riz->id, 'quantite_recue' => '90']],
        ])->assertCreated();

        $reponse = $this->getJson("/api/v1/achats/commandes/{$commande->id}/rapprochement")->assertOk();

        $reponse->assertJsonPath('data.concordance_globale', 'ecart_constate');
        $reponse->assertJsonPath('data.lignes.0.article_id', $this->riz->id);
        $reponse->assertJsonPath('data.lignes.0.commandee', '100.00');
        $reponse->assertJsonPath('data.lignes.0.recue', '90.00');
        $reponse->assertJsonPath('data.lignes.0.ecart', '-10.00');
        $reponse->assertJsonPath('data.lignes.0.concordance', 'manquant');
        $reponse->assertJsonPath('data.lignes.1.concordance', 'manquant');
    }

    /**
     * `ControleTroisVoiesService` bascule `facture_verifiable` sur la seule
     * PRÉSENCE d'un tableau de montants, qu'il ne compare à rien. Exposer ce
     * paramètre donnerait à un écran le moyen d'annoncer un rapprochement à
     * trois voies conforme sans qu'aucun montant n'ait été confronté — la forme
     * exacte de PA-59/60/61. La route ne l'accepte donc pas, et aucun montant
     * passé en requête ne doit pouvoir le faire basculer.
     */
    #[Test]
    public function ef_m7_04_la_troisieme_voie_n_est_jamais_annoncee_comme_verifiee(): void
    {
        $commande = $this->commande();
        Sanctum::actingAs($this->acheteur());

        $reponse = $this->getJson(
            "/api/v1/achats/commandes/{$commande->id}/rapprochement"
                . '?montants_factures[' . $this->riz->id . ']=80000',
        )->assertOk();

        $reponse->assertJsonPath('data.facture_verifiable', false);
        $reponse->assertJsonPath('data.voies_verifiees', ['commande', 'reception']);

        $avertissements = $reponse->json('data.avertissements');
        $this->assertIsArray($avertissements);
        $this->assertContains(__('achats.rapprochement.facture_absente'), $avertissements);
        $this->assertContains(__('achats.rapprochement.reconstitution'), $avertissements);
    }

    // --------------------------------------------------------------- Fixtures

    private function commande(string $statut = 'envoyee'): CommandeAchat
    {
        $commande = CommandeAchat::create([
            'fournisseur_id' => $this->fournisseur->id,
            'date_commande' => '2026-08-20',
            'statut' => $statut,
            'utilisateur_id' => $this->acheteur()->id,
        ]);

        LigneCommandeAchat::create([
            'commande_id' => $commande->id,
            'article_id' => $this->riz->id,
            'quantite_commandee' => '100.00',
            'prix_unitaire' => '800.00',
        ]);

        LigneCommandeAchat::create([
            'commande_id' => $commande->id,
            'article_id' => $this->huile->id,
            'quantite_commandee' => '20.00',
            'prix_unitaire' => '6500.00',
        ]);

        return $commande;
    }

    /**
     * @return array<string, mixed>
     */
    private function fournisseurValide(): array
    {
        return [
            'raison_sociale' => 'Coopérative Maraîchère Atacora',
            'contact' => '01 94 55 66 77',
            'categorie' => 'Denrées alimentaires',
            'conditions_paiement' => '30 jours',
            'evaluation' => 'bon',
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function commandeValide(): array
    {
        return [
            'fournisseur_id' => $this->fournisseur->id,
            'date_commande' => '2026-08-20',
            'statut' => 'envoyee',
            'lignes' => [
                ['article_id' => $this->riz->id, 'quantite_commandee' => '100', 'prix_unitaire' => '800'],
                ['article_id' => $this->huile->id, 'quantite_commandee' => '20', 'prix_unitaire' => '6500'],
            ],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function receptionValide(): array
    {
        return [
            'point_stockage_id' => $this->magasin->id,
            'lignes' => [
                ['article_id' => $this->riz->id, 'quantite_recue' => '100'],
                ['article_id' => $this->huile->id, 'quantite_recue' => '20'],
            ],
        ];
    }

    private function article(string $libelle, string $unite): Article
    {
        return Article::create([
            'libelle' => $libelle,
            'categorie' => 'denree',
            'unite_mesure' => $unite,
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '12.00',
            'cout_moyen_pondere' => '0.0000',
        ]);
    }

    /**
     * Le rôle est DÉRIVÉ de la matrice, jamais écrit en dur : le jour où elle
     * change, la suite suit — ou échoue en le disant.
     */
    private function roleAvecNiveauM7(string $niveau): string
    {
        foreach (RolePermissionSeeder::MATRICE as $role => $droits) {
            if ($droits['M7'] === $niveau) {
                return $role;
            }
        }

        $this->fail("Aucun rôle de la matrice ne porte M7 = '{$niveau}'.");
    }

    private function acheteur(): User
    {
        return $this->acheteur ??= $this->utilisateur($this->roleAvecNiveauM7('C'));
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(8),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
