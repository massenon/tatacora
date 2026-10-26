<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Ventes;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Crm\Models\Client;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Ventes\Models\LignePanier;
use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Services\PanierService;
use App\Domain\Ventes\Services\VenteService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Le panier des deux points de vente — PA-161, arbitrage (f) du 31/08/2026.
 *
 * ## Ce que ce fichier couvre, defaut par defaut
 *
 * | Cas | Le defaut qu'il ferme |
 * |---|---|
 * | `un_seul_panier_ouvert…` | R-a : deux paniers ouverts scindent les consommations, et la facture finale en oublie la moitie. L'ecart n'apparait qu'a la reclamation du client. |
 * | `l_ouverture_d_un_panier_de_sejour_prend…` | La lecture-puis-ecriture sans verrou laisse passer DEUX paniers quand deux caissiers cliquent en meme temps. C'est le patron de `VerificationChevauchementService`, et sans le verrou il ne reste qu'une lecture optimiste. |
 * | `l_index…_n_est_pas_unique` | Un index unique sur `(reservation_id, statut)` semblerait exprimer R-a et interdirait en fait un second panier CLOTURE — donc un client qui reconsomme apres sa facture. MySQL n'a pas d'index partiel : la garantie ne PEUT pas descendre en base sous cette forme. |
 * | `le_prix_vient_du_catalogue…` | Le maitre porte le montant dans le DOM et le renvoie : n'importe qui appellerait l'action avec le sien. Le service ne l'accepte pas et relit le catalogue. |
 * | `un_panier_cloture_refuse…` | R-b : sans cela, le panier devient le chemin par lequel on modifie une facture emise. |
 * | `une_quantite_a_zero…` | PA-98 : une quantite saisie a zero ne devient jamais une unite facturee — et elle ne cree pas non plus une ligne a zero franc. |
 * | `un_panier_ne_se_supprime_pas` | RG-02 et le « D » de CRUD, qui n'existe nulle part. |
 * | `vider_ne_libere_pas_la_table` | Le troisieme etat du maitre (`ouverte`) n'existe QUE si un panier vide se distingue d'une absence de panier. |
 *
 * ## Preuves par mutation — reellement executees le 31/08/2026
 *
 * Chaque mutation a ete appliquee, le rouge constate, puis le fichier restaure.
 *
 * 1. `un_seul_panier_ouvert…` — retirer le controle d'existence de
 *    `PanierService::ouvrirPourSejour()` (creer sans relire). ROUGE : deux
 *    paniers en base, et deux identifiants differents.
 * 2. `l_ouverture_d_un_panier_de_sejour_prend…` — retirer `lockForUpdate()`
 *    de la meme methode. ROUGE : aucune requete `for update` sur
 *    `reservations`.
 * 3. `le_prix_vient_du_catalogue…` — faire accepter a `ajouterLigne()` un
 *    prix fourni par l'appelant. ROUGE : la ligne porte 1 F au lieu de
 *    1 000 F.
 * 4. `un_panier_cloture_refuse…` — retirer `exigerOuvert()` de
 *    `ajouterLigne()`. **VERT.** Ce n'est pas un echec de la mutation, c'est
 *    la mesure du point de PA-100 : la garde du service est REDONDANTE, et
 *    c'est `LignePanierObserver` qui protege reellement. Retirer les DEUX
 *    (garde du service ET Observer) rend le cas ROUGE : « Un panier cloture a
 *    accepte une modification de ses lignes. » Ne jamais conclure d'un vert
 *    sous mutation que la garde mutee ne sert a rien — conclure qu'elle n'est
 *    pas celle qui tient.
 * 5. `le_motif_de_detection…` de `SessionSansDonneeMetierTest` — remplacer
 *    `Session::put` par `Session::putX` dans son motif. ROUGE, alors que le
 *    cas principal reste VERT : c'est exactement pour cela qu'il existe,
 *    depuis que le plancher d'ecritures est tombe a zero.
 *
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §5 (R-a a R-d), §8 (Q1, Q2)
 * @see RG-02 Aucune suppression — un panier se cloture
 */
final class PanierServiceTest extends TestCase
{
    use RefreshDatabase;

    private PanierService $paniers;

    private CarteBoisson $biere;

    private Plat $plat;

    private Client $client;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        // La clôture d'un panier produit une VENTE, et une vente sans pièce
        // comptable n'est plus enregistrée depuis le 31/08/2026 : le
        // référentiel comptable fait partie du décor minimal.
        $this->seed(ComptabiliteReferentielSeeder::class);

        $this->paniers = app(PanierService::class);

        $this->caissier = $this->utilisateur('gerant');
        // `mouvements_stock.utilisateur_id` est NOT NULL : RG-15 exige qu'un
        // mouvement nomme qui l'a fait, y compris les receptions du montage.
        $this->actingAs($this->caissier);

        $bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);

        $articleBiere = $this->article('Bière 65cl', 'bouteille');
        $articleRiz = $this->article('Riz', 'kg');

        $this->biere = CarteBoisson::create([
            'article_id' => $articleBiere->id,
            'libelle' => 'Béninoise 65cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
            'unites_vendables_par_unite_stock' => '1.0000',
        ]);

        $recette = Recette::create(['libelle' => 'Riz sauce', 'cout_matiere_calcule' => '0.00']);
        $recette->ingredients()->attach([$articleRiz->id => ['quantite_unitaire' => '0.250']]);

        $menu = Menu::create(['libelle' => 'Carte principale', 'type' => 'local']);
        $this->plat = Plat::create([
            'menu_id' => $menu->id,
            'recette_id' => $recette->id,
            'libelle' => 'Riz sauce arachide',
            'categorie' => 'plat',
            'prix_vente' => '2500.00',
        ]);

        $this->client = Client::create([
            'nom' => 'ADJOVI',
            'prenom' => 'Paul',
            'telephone' => '+229 01 00 00 00 00',
            'type_client' => 'particulier',
        ]);

        app(MouvementStockService::class)->entree($articleBiere->id, $bar->id, '48.00', 'Réception');
        app(MouvementStockService::class)->entree($articleRiz->id, $cuisine->id, '20.00', 'Réception');
    }

    // =====================================================================
    // R-a — un seul panier ouvert, et la garantie est dans le SERVICE
    // =====================================================================

    #[Test]
    public function un_seul_panier_ouvert_par_sejour_meme_apres_deux_ouvertures(): void
    {
        $reservation = $this->reservationEnCours();

        $premier = $this->paniers->ouvrirPourSejour($reservation->id, 'Hébergement');
        $second = $this->paniers->ouvrirPourSejour($reservation->id, 'Hébergement');

        // Le SECOND caissier retombe sur le panier du premier, jamais sur un
        // second : deux paniers ouverts scinderaient les consommations, et la
        // facture finale en oublierait la moitie.
        $this->assertSame($premier->id, $second->id);
        $this->assertSame(1, Panier::where('reservation_id', $reservation->id)->count());
    }

    #[Test]
    public function un_seul_panier_ouvert_par_poste_et_par_table(): void
    {
        $comptoir = $this->paniers->ouvrirPourPoste('Bar', null);
        $memeComptoir = $this->paniers->ouvrirPourPoste('Bar', null);
        $table = $this->paniers->ouvrirPourPoste('Restaurant', 'tab-r1');

        $this->assertSame($comptoir->id, $memeComptoir->id);
        // Une table est un AUTRE panier : c'est ce qui fait tenir deux
        // commandes en parallele dans la meme salle.
        $this->assertNotSame($comptoir->id, $table->id);
        $this->assertSame(2, Panier::count());
    }

    /**
     * Le comptoir n'a pas de table, et `table_id` y vaut NULL.
     *
     * `where('table_id', null)` produit `= NULL` en SQL, qui n'est JAMAIS vrai :
     * le comptoir n'aurait jamais retrouve son propre panier et en aurait
     * ouvert un neuf a chaque article. Le cas le mesure plutot que de faire
     * confiance a la lecture du code.
     */
    #[Test]
    public function le_panier_du_comptoir_se_retrouve_malgre_sa_table_nulle(): void
    {
        $ouvert = $this->paniers->ouvrirPourPoste('Bar', null);

        $retrouve = $this->paniers->panierOuvertDuPoste('Bar', null);

        $this->assertNotNull($retrouve);
        $this->assertSame($ouvert->id, $retrouve->id);
    }

    /**
     * Le verrou pessimiste est PRIS — mesure, pas suppose.
     *
     * L'unicite du panier ouvert repose entierement sur lui : sans
     * `lockForUpdate()`, deux caissiers qui lisent en meme temps trouvent tous
     * deux « aucun panier » et en creent chacun un. C'est le patron de
     * `VerificationChevauchementService`, retenu par l'arbitrage Q2 faute
     * d'index partiel MySQL — et un patron dont on ne verifie que le resultat
     * a un poste reste une lecture optimiste deguisee.
     */
    #[Test]
    public function l_ouverture_d_un_panier_de_sejour_prend_un_verrou_pessimiste(): void
    {
        $reservation = $this->reservationEnCours();

        $requetes = [];
        DB::listen(function ($requete) use (&$requetes): void {
            $requetes[] = strtolower($requete->sql);
        });

        $this->paniers->ouvrirPourSejour($reservation->id, 'Hébergement');

        $verrous = array_filter(
            $requetes,
            static fn (string $sql): bool => str_contains($sql, 'for update')
                && str_contains($sql, 'reservations'),
        );

        $this->assertNotEmpty(
            $verrous,
            'Aucun SELECT ... FOR UPDATE sur `reservations` : l unicite du panier ouvert '
            .'n est plus tenue par rien, et deux caissiers simultanes ouvriraient chacun le leur.',
        );
    }

    /**
     * ⚠ L'index NE DOIT PAS etre unique, et c'est le coeur de l'arbitrage.
     *
     * Un index unique sur `(reservation_id, statut)` a l'air d'exprimer R-a.
     * Il interdirait en realite un second panier CLOTURE sur le meme sejour —
     * c'est-a-dire le cas normal d'un client qui consomme, se fait facturer,
     * puis reconsomme. MySQL n'ayant pas d'index partiel, « unique la ou
     * statut = ouvert » ne s'ecrit pas : la garantie vit dans le service.
     *
     * Ce cas le mesure CONTRE LA BASE, pas contre le fichier de migration : un
     * index ajoute plus tard par une autre migration serait invisible a une
     * relecture du seul `create_paniers`.
     */
    #[Test]
    public function l_index_du_panier_de_sejour_n_est_pas_unique(): void
    {
        $index = collect(DB::select('SHOW INDEX FROM paniers'))
            ->filter(static fn (object $ligne): bool => $ligne->Column_name === 'reservation_id')
            ->values();

        $this->assertNotEmpty($index, 'L index `(reservation_id, statut)` a disparu.');

        foreach ($index as $ligne) {
            $this->assertSame(
                1,
                (int) $ligne->Non_unique,
                "L index {$ligne->Key_name} est UNIQUE sur `reservation_id` : il interdit un "
                .'second panier CLOTURE sur le meme sejour, donc un client qui reconsomme '
                .'apres sa facture. MySQL n a pas d index partiel — la garantie est en service.',
            );
        }
    }

    #[Test]
    public function un_sejour_facture_peut_rouvrir_un_second_panier(): void
    {
        $reservation = $this->reservationEnCours();

        $premier = $this->paniers->ouvrirPourSejour($reservation->id, 'Hébergement');
        $this->paniers->ajouterLigne($premier, 'M5', $this->biere->id);
        $this->paniers->abandonner($premier);

        $second = $this->paniers->ouvrirPourSejour($reservation->id, 'Hébergement');

        $this->assertNotSame($premier->id, $second->id);
        $this->assertSame(2, Panier::where('reservation_id', $reservation->id)->count());
    }

    // =====================================================================
    // R-c — prix et libelle FIGES, et jamais transmis par l'appelant
    // =====================================================================

    #[Test]
    public function le_prix_vient_du_catalogue_et_reste_fige_apres_un_changement_de_carte(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);
        $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id);

        $ligne = $panier->lignes->firstOrFail();
        $this->assertSame('1000.00', (string) $ligne->prix_unitaire);
        $this->assertSame('Béninoise 65cl', $ligne->libelle);

        // La carte change, la ligne ne bouge pas : un panier de sejour vit
        // plusieurs jours, et le montant deja annonce au client ne doit pas
        // bouger sous lui (PA-55, PA-98).
        $this->biere->update(['prix_vente' => '1500.00', 'libelle' => 'Béninoise grand modèle']);

        $ligne->refresh();
        $this->assertSame('1000.00', (string) $ligne->prix_unitaire);
        $this->assertSame('Béninoise 65cl', $ligne->libelle);
        $this->assertSame('1000.00', $panier->refresh()->total());
    }

    /**
     * Le prix n'est PAS un parametre — la signature elle-meme le refuse.
     *
     * Le cas le mesure par reflexion plutot que par comportement : un contrat
     * qui n'accepte pas de prix ne peut pas en accepter un par erreur, et
     * c'est plus fort qu'un test qui verifierait qu'un prix transmis est
     * ignore.
     */
    #[Test]
    public function la_signature_d_ajout_n_accepte_aucun_prix_ni_libelle(): void
    {
        $parametres = array_map(
            static fn (\ReflectionParameter $p): string => $p->getName(),
            (new \ReflectionMethod(PanierService::class, 'ajouterLigne'))->getParameters(),
        );

        $this->assertSame(['panier', 'module', 'reference', 'quantite'], $parametres);
    }

    #[Test]
    public function une_seconde_unite_incremente_la_ligne_au_prix_deja_fige(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);
        $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id);

        $this->biere->update(['prix_vente' => '9000.00']);
        $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id);

        // UNE ligne, au prix du premier ajout : deux lignes du meme article a
        // deux prix differents seraient illisibles au ticket.
        $this->assertCount(1, $panier->refresh()->lignes);
        $this->assertSame(2, $panier->lignes->firstOrFail()->quantite);
        $this->assertSame('2000.00', $panier->total());
    }

    #[Test]
    public function bar_et_restaurant_partagent_le_meme_panier(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);
        $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id);
        $this->paniers->ajouterLigne($panier, 'M4', $this->plat->id);

        $this->assertEqualsCanonicalizing(['M4', 'M5'], $panier->refresh()->modules());
        $this->assertSame('3500.00', $panier->total());
        // L'ordre de la ventilation suit celui des lignes du panier, pas
        // l'alphabet : le comparer a la cle et non a l'ordre.
        $this->assertEquals(
            ['M4' => '2500.00', 'M5' => '1000.00'],
            $panier->ventilationParModule(),
        );
    }

    // =====================================================================
    // Les refus — chacun ferme un etat que rien d'autre n'interdirait
    // =====================================================================

    #[Test]
    public function une_quantite_a_zero_ne_cree_aucune_ligne(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('ventes.quantite_minimale'));

        try {
            $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id, 0);
        } finally {
            // Elle ne cree pas non plus une ligne a zero franc : elle ne cree
            // rien du tout (PA-98, `QuantiteSaisie`).
            $this->assertSame(0, LignePanier::count());
        }
    }

    #[Test]
    public function une_reference_absente_du_catalogue_est_refusee(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);

        $this->expectException(RuntimeException::class);

        try {
            $this->paniers->ajouterLigne($panier, 'M5', (string) Str::uuid());
        } finally {
            $this->assertSame(0, LignePanier::count());
        }
    }

    #[Test]
    public function un_module_sans_catalogue_encaissable_est_refuse(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);

        $this->expectException(RuntimeException::class);
        // PA-24 : l'hebergement (M1) n'a pas de catalogue d'ou FIGER un prix.
        // Le tourisme (M9) et la location (M8) en ont un depuis le 22/10/2026.
        $this->assertNotContains('M1', VenteService::MODULES_ENCAISSABLES);
        $this->assertContains('M9', VenteService::MODULES_ENCAISSABLES);
        $this->assertContains('M8', VenteService::MODULES_ENCAISSABLES);

        $this->paniers->ajouterLigne($panier, 'M1', (string) Str::uuid());
    }

    #[Test]
    public function un_article_sans_prix_ne_se_porte_pas_au_panier(): void
    {
        $this->biere->update(['prix_vente' => '0.00']);
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);

        $this->expectException(RuntimeException::class);

        try {
            $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id);
        } finally {
            $this->assertSame(0, LignePanier::count());
        }
    }

    // =====================================================================
    // R-b — un panier cloture est immuable
    // =====================================================================

    #[Test]
    public function un_panier_cloture_refuse_toute_ligne(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);
        $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id);
        $this->paniers->abandonner($panier);

        foreach ([
            fn (): mixed => $this->paniers->ajouterLigne($panier, 'M4', $this->plat->id),
            fn (): mixed => $this->paniers->changerQuantite($panier, $panier->lignes->firstOrFail()->id, 1),
            fn (): mixed => $this->paniers->retirerLigne($panier, $panier->lignes->firstOrFail()->id),
            fn (): mixed => $this->paniers->vider($panier),
        ] as $geste) {
            try {
                $geste();
                $this->fail('Un panier cloture a accepte une modification de ses lignes.');
            } catch (RuntimeException $refus) {
                $this->assertSame(__('ventes.panier_cloture_immuable'), $refus->getMessage());
            }
        }

        $this->assertCount(1, $panier->refresh()->lignes);
    }

    /**
     * L'OBSERVER protege, pas seulement le service (PA-100).
     *
     * Le service refuse, et son refus est ce que l'operateur lit. Mais il ne
     * couvre que le chemin qu'il porte : un job, un import ou un futur service
     * ecrirait sans passer par lui. Ce cas contourne DELIBEREMENT le service
     * pour montrer que la garantie tient quand meme.
     */
    #[Test]
    public function un_panier_cloture_refuse_une_ligne_ecrite_hors_du_service(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);
        $this->paniers->abandonner($panier);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('ventes.panier_cloture_immuable'));

        LignePanier::create([
            'panier_id' => $panier->id,
            'module' => 'M5',
            'reference_id' => $this->biere->id,
            'libelle' => 'Ligne posée par un import',
            'prix_unitaire' => '1000.00',
            'quantite' => 1,
        ]);
    }

    #[Test]
    public function un_panier_cloture_ne_se_rouvre_pas(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);
        $this->paniers->abandonner($panier);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('ventes.panier_cloture_immuable'));

        $panier->update(['statut' => Panier::STATUT_OUVERT]);
    }

    #[Test]
    public function un_panier_ne_se_supprime_pas(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage(__('ventes.panier_indestructible'));

        try {
            $panier->delete();
        } finally {
            $this->assertSame(1, Panier::count());
        }
    }

    // =====================================================================
    // Cloture, abandon, et le troisieme etat du maitre
    // =====================================================================

    #[Test]
    public function vider_ne_libere_pas_la_table_alors_qu_abandonner_la_libere(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Restaurant', 'tab-r1');
        $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id);

        $this->paniers->vider($panier);

        // « Vider » laisse la table OUVERTE : le client est toujours assis.
        // C'est le troisieme etat du maitre, et il n'existe QUE si un panier
        // vide se distingue d'une absence de panier.
        $encore = $this->paniers->panierOuvertDuPoste('Restaurant', 'tab-r1');
        $this->assertNotNull($encore);
        $this->assertCount(0, $encore->lignes);

        $this->paniers->abandonner($encore);

        // « Abandonner » la libere — et laisse la TRACE qu'elle a ete servie.
        $this->assertNull($this->paniers->panierOuvertDuPoste('Restaurant', 'tab-r1'));
        $this->assertTrue(Panier::findOrFail($panier->id)->estAbandonne());
    }

    #[Test]
    public function une_ligne_ramenee_a_zero_disparait_au_lieu_de_rester_a_zero_unite(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);
        $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id);

        $this->paniers->changerQuantite($panier, $panier->lignes->firstOrFail()->id, -1);

        $this->assertCount(0, $panier->refresh()->lignes);
        $this->assertSame('0.00', $panier->total());
        // Le panier, lui, reste OUVERT : vider n'est pas abandonner.
        $this->assertTrue($panier->estOuvert());
    }

    #[Test]
    public function la_cloture_sur_vente_porte_la_vente_et_son_horodatage(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);
        $this->paniers->ajouterLigne($panier, 'M5', $this->biere->id, 2);

        $vente = app(VenteService::class)->enregistrer([
            'point_vente' => 'Bar',
            'mode_paiement' => 'especes',
            'utilisateur_id' => $this->caissier->id,
            'lignes' => $this->paniers->lignesPourVente($panier),
        ]);

        $this->paniers->cloturerSurVente($panier, $vente);

        $panier->refresh();
        $this->assertTrue($panier->estCloture());
        $this->assertFalse($panier->estAbandonne());
        $this->assertSame($vente->id, $panier->vente_id);
        $this->assertNotNull($panier->cloture_at);
        $this->assertSame('2000.00', (string) $vente->montant_total);
    }

    // =====================================================================
    // Le schema dit ce que le code promet
    // =====================================================================

    #[Test]
    public function les_cles_de_rattachement_sont_de_vraies_cles_etrangeres_en_uuid(): void
    {
        foreach (['id', 'reservation_id', 'session_id', 'vente_id'] as $colonne) {
            $this->assertSame('char', Schema::getColumnType('paniers', $colonne));
        }

        $this->assertSame('char', Schema::getColumnType('lignes_panier', 'panier_id'));

        $regles = collect(DB::select(
            'SELECT rc.CONSTRAINT_NAME, rc.DELETE_RULE
             FROM information_schema.REFERENTIAL_CONSTRAINTS rc
             WHERE rc.CONSTRAINT_SCHEMA = DATABASE()
               AND rc.TABLE_NAME IN ("paniers", "lignes_panier")',
        ))->pluck('DELETE_RULE', 'CONSTRAINT_NAME');

        $this->assertNotEmpty($regles);

        foreach ($regles as $nom => $regle) {
            // `cascadeOnDelete` est interdit sur une table transactionnelle :
            // la suppression d'une vente ou d'une reservation emporterait le
            // panier sans laisser de trace. `SET NULL` reste admis sur les
            // seules colonnes d'audit.
            $this->assertContains(
                $regle,
                ['RESTRICT', 'NO ACTION', 'SET NULL'],
                "La contrainte {$nom} est en {$regle} : une cascade sur une table "
                .'transactionnelle efface des lignes sans trace.',
            );
        }
    }

    /**
     * La quantite minimale est tenue par la BASE, pas seulement par le service.
     *
     * Un import ou un job qui contournerait `PanierService` poserait sinon une
     * ligne a zero unite, invisible au total et pourtant presente au ticket.
     */
    #[Test]
    public function la_contrainte_de_quantite_tient_meme_hors_du_service(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);

        $this->expectException(\Illuminate\Database\QueryException::class);

        DB::table('lignes_panier')->insert([
            'id' => (string) Str::uuid(),
            'panier_id' => $panier->id,
            'module' => 'M5',
            'reference_id' => $this->biere->id,
            'libelle' => 'Ligne à zéro',
            'prix_unitaire' => '1000.00',
            'quantite' => 0,
        ]);
    }

    /**
     * Un panier OUVERT ne peut pas porter de vente — contrainte CHECK.
     *
     * Sans elle, un panier pourrait etre a la fois encaisse et encore
     * encaissable, et l'ecran afficherait un encours deja regle.
     */
    #[Test]
    public function un_panier_ouvert_ne_peut_pas_porter_de_vente(): void
    {
        $panier = $this->paniers->ouvrirPourPoste('Bar', null);

        $this->expectException(\Illuminate\Database\QueryException::class);

        DB::table('paniers')->where('id', $panier->id)->update(['cloture_at' => now()]);
    }

    // ------------------------------------------------------------------ outils

    private function reservationEnCours(): Reservation
    {
        $categorie = CategorieHebergement::create([
            'libelle' => 'Chambre standard',
            'capacite_max' => 2,
            'tarif_base' => '30000.00',
        ]);

        $unite = UniteHebergement::create([
            'categorie_id' => $categorie->id,
            'numero' => 'CH-'.Str::random(4),
            'statut' => 'occupee',
        ]);

        return Reservation::create([
            'client_id' => $this->client->id,
            'unite_id' => $unite->id,
            'date_arrivee' => now()->subDay()->toDateString(),
            'date_depart' => now()->addDay()->toDateString(),
            'statut' => 'en_cours',
            'acompte' => '0.00',
        ]);
    }

    private function article(string $libelle, string $unite): Article
    {
        return Article::create([
            'libelle' => $libelle,
            'categorie' => 'test',
            'unite_mesure' => $unite,
            'seuil_alerte' => '5.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '500.0000',
        ]);
    }

    private function utilisateur(string $role): User
    {
        return User::create([
            'login' => $role.'.'.Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
