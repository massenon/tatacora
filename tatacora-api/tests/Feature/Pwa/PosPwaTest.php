<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\Vente;
use App\Exports\VentesExport;
use App\Models\User;
use App\Pwa\Livewire\Pos\HistoriqueVentes;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Pwa\Livewire\Pos\PosHeberges;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\TablesSalleSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Maatwebsite\Excel\Facades\Excel;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les deux points de vente et le journal des ventes — le chemin de l'argent.
 *
 * ## Ce que couvre ce fichier, defaut par defaut
 *
 * | Cas | Le defaut qu'il ferme |
 * |---|---|
 * | `un_panier_mixte…` | P1 — les lignes de restauration etaient JETEES en silence pendant que le ticket totalisait le panier entier et que l'ecran disait « succes ». |
 * | `le_journal_affiche…` | P2 — l'ecran ecrivait `ventes_bar`, le journal lisait `ventes` : deux registres qui ne se rencontraient jamais. |
 * | `la_numerotation…` | P2 — le numero etait fabrique d'un prefixe d'UUID, ou d'un `date('YmdHis')` sans boisson : deux ventes de la meme seconde portaient le meme. |
 * | `un_echec_de_facturation…` | P3 — le `catch` vidait le panier du sejour PUIS notifiait « succes ». |
 * | `aucun_tarif_de_repli…` | P3bis — `?? 20000` facturait un tarif de nuit que personne n'avait decide. |
 * | `une_vente_s_annule…` | P5 — `$v->delete()` sur une table financiere. |
 * | `un_role_sans_droit…` | P6 — aucun des trois composants n'appelait `exigerEcriture()`. |
 * | `le_prix_ne_vient_jamais…` | L'ecran transmettait le montant depuis le DOM : n'importe qui pouvait appeler l'action avec le sien. |
 * | `le_panier_d_un_sejour_survit…` | P4 (PA-161) — le panier vivait dans la SESSION HTTP : 120 minutes, un seul navigateur, perdu a la deconnexion. Le comptoir voisin ne voyait rien pendant que l'ecran promettait un panier ouvert « de l'arrivee au depart ». |
 * | `l_etat_d_une_table…` | Le troisieme etat du maitre (`ouverte`) etait INRENDABLE tant que le panier vivait en memoire : un panier vide y etait indiscernable d'une table libre. |
 * | `afficher_les_deux_ecrans_n_ouvre_aucun_panier` | Ouvrir un panier a la LECTURE ferait passer toutes les tables a « ouverte » des qu'un role en `L` regarde la page — et le ferait ecrire en base sans droit d'ecriture. |
 * | `l_encaissement_clot_le_panier…` | Le panier etait une variable d'ecran videe a la main : il survivait dans l'autre onglet, et le meme panier repartait au registre des ventes. |
 * | `une_rupture_de_stock_laisse_le_panier…` | La vente et la cloture vivent dans UNE transaction : un panier clos sur une vente annulee serait perdu pour tout le monde. |
 *
 * ## Preuve par mutation — reellement executee le 31/08/2026
 *
 * Chaque cible a ete cassee, le rouge constate, puis le fichier restaure et
 * son empreinte MD5 reverifiee. Les mutations exactes :
 *
 * 1. `un_panier_mixte…` — remettre le filtre d'origine sur les lignes
 *    envoyees au service (`array_filter(… === 'M5')`) dans
 *    `PosComptant::encaissementReel()`. ROUGE : « two arrays are equal ».
 * 2. `un_echec_de_facturation…` — poser `Session::forget()` dans le
 *    `catch (RuntimeException)` de `PosHeberges::cloturerEtFacturer()`.
 *    ROUGE : « actual size 0 matches expected size 2 ».
 *    ⚠ CETTE MUTATION N'EST PLUS APPLICABLE depuis PA-161 : il n'y a plus de
 *    cle de session a oublier. Elle est REJOUEE sous sa forme nouvelle le
 *    31/08/2026 — clore le panier AVANT de savoir si la facture passe, par un
 *    `$paniers->abandonner($panier)` pose juste avant le `try`. ROUGE sur les
 *    DEUX cas (n° 2 et n° 6). C'est le meme defaut que le `Session::forget()`
 *    d'origine : detruire la commande du client avant de savoir si l'on a pu
 *    la facturer.
 *    ⚠ Une PREMIERE version de cette mutation n'a PAS mordu : elle inserait
 *    un appel inerte dans la fermeture de transaction, sans en sortir la
 *    cloture. Verte, elle aurait laisse croire que le cas tenait la
 *    transaction — alors qu'il ne l'avait pas encore eprouvee.
 * 3. `une_vente_s_annule…` — remplacer `VenteService::annuler()` par
 *    `$vente->delete()` dans `HistoriqueVentes`. ROUGE.
 * 4. `aucun_tarif_de_repli…` — remplacer le refus par le repli historique
 *    (`$tarif = '20000'`). ROUGE : « two strings are equal ».
 * 5. `le_prix_ne_vient_jamais…` — la cible a CHANGE de fichier avec PA-161 :
 *    `ComposePanier::ajouterLigne()` n'existe plus, le panier n'etant plus un
 *    tableau d'ecran. La mutation porte desormais sur
 *    `PanierService::ajouterLigne()`, a qui l'on fait ecrire un prix et un
 *    libelle qui ne viennent pas du catalogue. ROUGE.
 *    Elle est doublee, cote domaine, par
 *    `PanierServiceTest::la_signature_d_ajout_n_accepte_aucun_prix_ni_libelle`,
 *    qui refuse le prix a la SIGNATURE : un contrat qui n'accepte pas de prix
 *    ne peut pas en accepter un par erreur.
 * 6. `une_panne_technique…` — poser `notifier($erreur->getMessage())` dans le
 *    `catch (\Throwable)`. ROUGE (le message technique atteint l'ecran).
 *    Le second volet — la destruction du panier — n'a plus de forme possible
 *    dans ce `catch` : la transaction l'annule d'elle-meme, et c'est ce que le
 *    cas mesure en relisant le panier EN BASE, toujours ouvert avec ses deux
 *    lignes.
 * 7. `un_comptable_exporte…` — remettre `exigerEcriture(self::MODULE)` sur
 *    `HistoriqueVentes::genererExport()`. ROUGE : « status 200, received 403 ».
 *
 * ## ⚠ Une SECONDE lecon de la mutation, et elle vaut pour tout le depot
 *
 * La premiere version du cas n° 7 est restee VERTE sous sa mutation. La
 * raison : Livewire rend un `abort(403)` comme un STATUT de reponse, pas comme
 * une exception — ni `assertHasNoErrors()` ni `assertSet()` ne le voient. Un
 * cas qui affirme « ce role obtient bien X » doit donc dire
 * `assertStatus(200)`, sans quoi il reste vert alors meme que le role est
 * refuse. Les deux moities de la regle RBAC se prouvent avec la meme mesure :
 * `assertForbidden()` d'un cote, `assertStatus(200)` de l'autre.
 *
 * ## ⚠ Ce que la mutation a APPRIS, et qui n'aurait pas ete vu autrement
 *
 * La premiere version de la mutation n° 2 visait le `catch (\Throwable)` — et
 * elle N'A PAS MORDU : la suite est restee verte. La raison : le refus de TVA
 * de `CalculTvaService` remonte en `RuntimeException` et sort par l'AUTRE
 * branche. Le `catch` generique n'etait donc exerce par rien du tout, alors
 * que c'est lui qui decide si un message technique atteint le comptoir.
 * Le cas n° 6 a ete ecrit pour cela. Sans la mutation, deux lignes vertes
 * auraient laisse croire que les deux branches etaient tenues.
 *
 * ## ⚠ Le panier ne se lit plus dans la SESSION, et c'est mesurable
 *
 * Aucun cas de ce fichier n'interroge plus `Session::get('panier_sejour_…')`.
 * Ce n'est pas un detail de style : une assertion sur une cle de session
 * SUPPRIMEE reste verte pour toujours — `Session::get()` rend son defaut, et
 * `assertSame([], …)` passe. L'un de ces cas etait exactement dans cet etat
 * apres la bascule ; il relit desormais `paniers` en base. Une assertion qui
 * ne peut plus echouer est pire qu'une assertion absente : elle se compte.
 *
 * @see RG-02 Aucune suppression — une vente s'annule
 * @see RG-05 Sortie de stock automatique
 * @see PA-119 Un export porte sur ce qui est affiche, et il dit son filtre
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §5, §8 Q2 (PA-161)
 */
final class PosPwaTest extends TestCase
{
    use RefreshDatabase;

    private PointStockage $bar;

    private PointStockage $cuisine;

    private Article $articleBiere;

    private Article $articleRiz;

    private CarteBoisson $biere;

    private Plat $plat;

    private Client $client;

    private User $gerant;

    /**
     * Identifiants REELS des tables R1 et J1 du referentiel `tables_salle`
     * (02/09/2026) — les litteraux `tab-r1`/`tab-j1` de l'ancien registre
     * d'ecran `PLAN_DE_SALLE` n'existent plus : le plan du POS vient du
     * referentiel seme (`TablesSalleSeeder`), et l'identifiant est un UUID.
     */
    private string $tableR1;

    private string $tableJ1;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        /*
         * Le referentiel comptable fait partie du decor MINIMAL d'un point de
         * vente depuis le 02/09/2026, et ce n'est pas une commodite de test :
         * la regle du Product Owner du 31/08/2026 veut que tout mouvement
         * d'argent produise son ecriture comptable reelle, dans la MEME
         * transaction. `VenteService::enregistrer()` passe donc sa piece par
         * `PasserEcritureService`, qui exige un plan comptable, des journaux
         * et un exercice ouvert — et refuse l'encaissement sinon.
         *
         * Sans cette ligne, ces douze cas echouaient sur « Journal comptable
         * inconnu : VTE ». Ils ne decriraient alors plus un comptoir reel,
         * mais un Gite dont la comptabilite n'a jamais ete ouverte. Le refus
         * lui-meme est eprouve ailleurs, sur une base d'ou le referentiel est
         * RETIRE : `VenteServiceTest::sans_referentiel_comptable_aucune_vente_n_est_enregistree()`.
         *
         * Aucune attente n'a ete abaissee ici — c'est le DECOR qui a change.
         */
        $this->seed(ComptabiliteReferentielSeeder::class);

        // Le plan de salle vient du REFERENTIEL depuis le 02/09/2026 — sans
        // ce semis, le comptoir n'aurait aucune table a proposer.
        $this->seed(TablesSalleSeeder::class);
        $this->tableR1 = \App\Domain\Ventes\Models\TableSalle::where('libelle', 'R1')->firstOrFail()->id;
        $this->tableJ1 = \App\Domain\Ventes\Models\TableSalle::where('libelle', 'J1')->firstOrFail()->id;

        $this->gerant = $this->utilisateur('gerant');
        // `mouvements_stock.utilisateur_id` est NOT NULL : RG-15 exige qu'un
        // mouvement nomme qui l'a fait, y compris les receptions du montage.
        $this->actingAs($this->gerant);

        $this->bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $this->cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);

        $this->articleBiere = $this->article('Bière 65cl', 'bouteille');
        $this->articleRiz = $this->article('Riz', 'kg');

        $this->biere = CarteBoisson::create([
            'article_id' => $this->articleBiere->id,
            'libelle' => 'Béninoise 65cl',
            'categorie' => 'locale',
            'prix_vente' => '1000.00',
            'unites_vendables_par_unite_stock' => '1.0000',
        ]);

        $recette = Recette::create(['libelle' => 'Riz sauce', 'cout_matiere_calcule' => '0.00']);
        $recette->ingredients()->attach([$this->articleRiz->id => ['quantite_unitaire' => '0.250']]);

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

        app(MouvementStockService::class)->entree($this->articleBiere->id, $this->bar->id, '48.00', 'Réception');
        app(MouvementStockService::class)->entree($this->articleRiz->id, $this->cuisine->id, '20.00', 'Réception');
    }

    /**
     * Le panier OUVERT d'un sejour, relu en base.
     *
     * Il n'existe plus de cle de session a interroger : depuis PA-161 le
     * panier est une table, et c'est elle qui fait foi.
     */
    private function panierDuSejour(string $reservationId): Panier
    {
        return Panier::with('lignes')
            ->where('reservation_id', $reservationId)
            ->where('statut', Panier::STATUT_OUVERT)
            ->firstOrFail();
    }

    /** Le panier OUVERT du comptoir — celui qui n'a pas de table. */
    private function panierDuComptoir(): Panier
    {
        return Panier::with('lignes')
            ->where('point_vente', PosComptant::POSTE_COMPTOIR)
            ->whereNull('table_id')
            ->where('statut', Panier::STATUT_OUVERT)
            ->firstOrFail();
    }

    // =====================================================================
    // Les trois ecrans se chargent VRAIMENT
    // =====================================================================

    #[Test]
    public function les_trois_ecrans_repondent_200_et_portent_leur_propre_titre(): void
    {
        $attendus = [
            '/pwa/pos/comptant' => 'Point de vente comptant — TATACORA AFRIQUE',
            '/pwa/pos/heberges' => 'Point de vente — clients hébergés — TATACORA AFRIQUE',
            '/pwa/historique-ventes' => 'Historique des ventes — TATACORA AFRIQUE',
        ];

        foreach ($attendus as $url => $titre) {
            $reponse = $this->actingAs($this->gerant)->get($url);

            $reponse->assertOk();
            // Le titre est relu dans le HTML RENDU, jamais dans l'attribut PHP :
            // c'est la lecon exacte du defaut de la balise `<title>`.
            $reponse->assertSee('<title>'.$titre.'</title>', false);
        }
    }

    // =====================================================================
    // P1 — le panier mixte enregistre les DEUX rayons
    // =====================================================================

    #[Test]
    public function un_panier_mixte_bar_et_restaurant_enregistre_les_deux_rayons(): void
    {
        $this->ouvrirLaCaisse();
        $stocks = app(StockTheoriqueService::class);

        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M4', $this->plat->id)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M4', $this->plat->id)
            ->call('encaisser')
            ->assertSet('toastType', 'success');

        $vente = Vente::with('lignes')->firstOrFail();

        // Le repas n'est plus jete : les deux rayons sont au registre.
        $this->assertEqualsCanonicalizing(
            ['M4', 'M5'],
            $vente->lignes->pluck('module')->unique()->values()->all(),
        );
        $this->assertSame('6000.00', (string) $vente->montant_total);

        // Et RG-05 des deux cotes : le bar par mouvement direct, la cuisine par
        // la recette, via la commande transmise.
        $this->assertSame('47.00', $stocks->stock($this->articleBiere->id, $this->bar->id));
        $this->assertSame('19.50', $stocks->stock($this->articleRiz->id, $this->cuisine->id));
    }

    // =====================================================================
    // P2 — un seul registre, lu par le journal
    // =====================================================================

    #[Test]
    public function le_journal_affiche_ce_que_le_point_de_vente_vient_d_encaisser(): void
    {
        $this->ouvrirLaCaisse();

        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('encaisser');

        $numero = Vente::firstOrFail()->numero;

        $this->actingAs($this->gerant);

        Livewire::test(HistoriqueVentes::class)
            ->assertSee($numero)
            ->assertSet('venteDetailId', null);

        // Aucune ligne n'est partie dans `ventes_bar` : un meme argent compte
        // deux fois serait le defaut a l'envers.
        $this->assertSame(0, \DB::table('ventes_bar')->count());
    }

    /**
     * La pagination du journal — décision du Product Owner du 13/10/2026 :
     * dix ventes par page, comme le client Flutter. Les indicateurs portent
     * sur la liste ENTIÈRE, jamais sur la page ; un filtre changé ramène à la
     * page 1 ; une page hors bornes est ramenée.
     */
    #[Test]
    public function le_journal_pagine_dix_ventes_et_ses_indicateurs_portent_sur_toute_la_liste(): void
    {
        $this->ouvrirLaCaisse();
        $this->actingAs($this->gerant);

        for ($i = 0; $i < 12; $i++) {
            Livewire::test(PosComptant::class)
                ->set('comptoirChoisi', true)
                ->call('ajouterAuPanier', 'M5', $this->biere->id)
                ->call('encaisser');
        }

        $journal = Livewire::test(HistoriqueVentes::class);
        $this->assertSame(10, $journal->viewData('ventesPage')->count());
        $this->assertSame(12, $journal->viewData('totalVentes'));
        $this->assertSame(2, $journal->viewData('pagesVentes'));
        $this->assertSame(12, $journal->viewData('valideesCount'));
        $journal->assertSee('Page 1 / 2')
            ->assertSeeInOrder(['Affichage de', '1-10', 'sur', '12']);

        $journal->set('page', 2);
        $this->assertSame(2, $journal->viewData('ventesPage')->count());
        $journal->assertSee('Page 2 / 2')->assertSeeInOrder(['11-12', '12']);
        // Les indicateurs n'ont pas suivi la page.
        $this->assertSame(12, $journal->viewData('valideesCount'));

        // Aucune vente vue deux fois : les deux pages couvrent les douze.
        $journal->set('page', 1);
        $page1 = $journal->viewData('ventesPage')->pluck('id');
        $journal->set('page', 2);
        $page2 = $journal->viewData('ventesPage')->pluck('id');
        $this->assertCount(12, $page1->merge($page2)->unique());

        // Un filtre changé ramène à la page 1.
        $journal->set('statut', 'validee');
        $journal->assertSet('page', 1);

        // Une page hors bornes est ramenée à la dernière.
        $journal->set('page', 9);
        $journal->assertSet('page', 2);
    }

    /**
     * Sous pagination, le CHIFFRE D'AFFAIRES, l'ENCAISSÉ et l'EXPORT portent
     * sur la liste filtrée ENTIÈRE — sur chaque page (contrôle des lots B et
     * C, 13/10/2026). Le cas précédent ne vérifiait que les décomptes : un
     * montant calculé sur la page (10 ventes en page 1, 2 en page 2) y serait
     * passé inaperçu. Douze ventes de 1 000 : la liste vaut 12 000, aucune
     * page ne le vaut.
     */
    #[Test]
    public function sous_pagination_les_montants_et_l_export_portent_sur_les_douze_ventes(): void
    {
        $this->ouvrirLaCaisse();
        $this->actingAs($this->gerant);

        for ($i = 0; $i < 12; $i++) {
            Livewire::test(PosComptant::class)
                ->set('comptoirChoisi', true)
                ->call('ajouterAuPanier', 'M5', $this->biere->id)
                ->call('encaisser');
        }

        $total = '0.00';
        foreach (Vente::all() as $vente) {
            $total = bcadd($total, (string) $vente->montant_total, 2);
        }
        $this->assertSame('12000.00', $total);

        $journal = Livewire::test(HistoriqueVentes::class);

        foreach ([1, 2] as $page) {
            $journal->set('page', $page);
            $journal->assertSet('page', $page);

            $montantPage = '0.00';
            foreach ($journal->viewData('ventesPage') as $vente) {
                $montantPage = bcadd($montantPage, (string) $vente->montant_total, 2);
            }
            // La page ne vaut PAS la liste : sans quoi l'assertion suivante ne
            // distinguerait rien.
            $this->assertNotSame($total, $montantPage, "page {$page}");

            $this->assertSame($total, $journal->viewData('chiffreAffaires'), "page {$page}");
            $this->assertSame($total, $journal->viewData('encaisseTotal'), "page {$page}");
        }

        // L'export, demandé depuis la page 2, emporte les DOUZE ventes.
        Excel::fake();
        Excel::matchByRegex();
        $journal->call('ouvrirExport', 'excel')
            ->call('genererExport')
            ->assertHasNoErrors();

        Excel::assertDownloaded(
            '/\.xlsx$/',
            fn (VentesExport $export): bool => $export->collection()->count() === 12,
        );
    }

    #[Test]
    public function le_journal_vide_dit_zero_et_garde_ses_boutons_desactives(): void
    {
        $this->actingAs($this->gerant);

        Livewire::test(HistoriqueVentes::class)
            ->assertSee('Page 1 / 1')
            ->assertSeeInOrder(['Affichage de', '0-0', 'sur', '0'])
            ->assertSee(__('pos_pwa.journal.page_precedent'))
            ->assertSee(__('pos_pwa.journal.page_suivant'));
    }

    #[Test]
    public function la_numerotation_vient_de_la_sequence_et_jamais_d_un_uuid_ni_d_une_horloge(): void
    {
        $this->ouvrirLaCaisse();
        $annee = now()->format('Y');

        foreach ([1, 2] as $ignore) {
            $this->actingAs($this->gerant);

            Livewire::test(PosComptant::class)
                ->set('comptoirChoisi', true)
                ->call('ajouterAuPanier', 'M5', $this->biere->id)
                ->call('encaisser');
        }

        $this->assertSame(
            ["V-{$annee}-00001", "V-{$annee}-00002"],
            Vente::orderBy('numero')->pluck('numero')->all(),
        );
    }

    // =====================================================================
    // Le prix ne vient JAMAIS de l'ecran
    // =====================================================================

    #[Test]
    public function le_prix_ne_vient_jamais_de_l_ecran_et_reste_fige_apres_l_encaissement(): void
    {
        $this->ouvrirLaCaisse();

        $this->actingAs($this->gerant);

        $composant = Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id);

        /*
         * Le panier est relu EN BASE, pas dans une propriete de composant
         * (PA-161) : c'est la ligne persistee qui compte, et c'est elle qui
         * doit porter le prix du catalogue.
         */
        $ligne = $this->panierDuComptoir()->lignes->firstOrFail();

        // Le prix vient du catalogue, pas d'un parametre d'action.
        $this->assertSame('1000.00', (string) $ligne->prix_unitaire);
        $this->assertSame('Béninoise 65cl', $ligne->libelle);

        $composant->call('encaisser');

        // Puis il est FIGE : le catalogue peut changer, la vente ne bouge pas.
        $this->biere->update(['prix_vente' => '1500.00']);

        $this->assertSame('1000.00', (string) Vente::firstOrFail()->lignes()->first()->prix_unitaire);
    }

    // =====================================================================
    // La caisse — un seul chemin, sans repli
    // =====================================================================

    #[Test]
    public function aucun_encaissement_n_est_possible_sans_caisse_ouverte(): void
    {
        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('encaisser')
            ->assertSet('toastType', 'error');

        $this->assertSame(0, Vente::count());
    }

    #[Test]
    public function la_caisse_s_ouvre_par_le_modele_et_refuse_une_seconde_ouverture(): void
    {
        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->call('ouvrirFormulaireOuvertureCaisse')
            ->set('fondCaisseSaisi', '25000')
            ->call('ouvrirCaisse')
            ->assertHasNoErrors();

        $session = SessionCaisse::where('point_vente', 'bar')->firstOrFail();

        // Les colonnes d'ouverture sont RENSEIGNEES : les trois chemins
        // d'ecriture d'origine (dont deux contournaient le modele) les
        // laissaient a la discretion de l'insertion brute.
        $this->assertSame($this->gerant->id, $session->utilisateur_ouverture_id);
        $this->assertSame('25000.00', (string) $session->montant_fond);

        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->call('ouvrirFormulaireOuvertureCaisse')
            ->set('fondCaisseSaisi', '10000')
            ->call('ouvrirCaisse')
            ->assertHasErrors('fondCaisseSaisi');

        $this->assertSame(1, SessionCaisse::count());
    }

    #[Test]
    public function la_cloture_de_caisse_ne_compte_que_ce_qui_est_reellement_encaisse(): void
    {
        $this->ouvrirLaCaisse('10000');

        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('encaisser');

        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->call('ouvrirFormulaireClotureCaisse')
            ->set('montantConstateSaisi', '11000')
            ->call('cloturerCaisse')
            ->assertHasNoErrors();

        $session = SessionCaisse::firstOrFail();

        $this->assertSame('11000.00', (string) $session->montant_theorique);
        $this->assertNotNull($session->date_cloture);
    }

    // =====================================================================
    // P5 — une vente s'ANNULE, elle ne se supprime pas
    // =====================================================================

    #[Test]
    public function une_vente_s_annule_avec_son_motif_et_ne_se_supprime_jamais(): void
    {
        $this->ouvrirLaCaisse();
        $stocks = app(StockTheoriqueService::class);

        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('encaisser');

        $vente = Vente::firstOrFail();
        $this->assertSame('47.00', $stocks->stock($this->articleBiere->id, $this->bar->id));

        // Sans motif : refus, et la vente reste validee.
        $this->actingAs($this->gerant);

        Livewire::test(HistoriqueVentes::class)
            ->set('venteDetailId', $vente->id)
            ->call('annulerVente')
            ->assertHasErrors('motifAnnulation');

        $this->assertSame('validee', $vente->refresh()->statut);

        $this->actingAs($this->gerant);

        Livewire::test(HistoriqueVentes::class)
            ->set('venteDetailId', $vente->id)
            ->set('motifAnnulation', 'Erreur de saisie')
            ->call('annulerVente')
            ->assertHasNoErrors();

        // La vente EXISTE toujours, avec son numero : rien n'est efface.
        $this->assertDatabaseHas('ventes', [
            'id' => $vente->id,
            'numero' => $vente->numero,
            'statut' => 'annulee',
            'motif_annulation' => 'Erreur de saisie',
        ]);
        $this->assertSame('48.00', $stocks->stock($this->articleBiere->id, $this->bar->id));
    }

    // =====================================================================
    // P4 — le panier SURVIT au poste, au navigateur et a la releve (PA-161)
    // =====================================================================

    /**
     * La promesse que l'ecran affichait sans pouvoir la tenir.
     *
     * Le sous-titre du POS heberges dit le panier ouvert « de l'arrivee au
     * depart ». Il vivait dans la session HTTP : 120 minutes, un seul
     * navigateur, perdu a la deconnexion. Le serveur qui prenait la releve au
     * comptoir voisin ne voyait rien, et le client avait consomme sans que
     * rien ne le porte.
     *
     * Le cas reproduit LES DEUX moities de la perte : la session HTTP est
     * videe (`flushSession`), et le composant est recree de zero — deux
     * instances de `Livewire::test` ne partagent aucun etat. Ce qui reste
     * visible ne peut donc venir que de la base.
     */
    #[Test]
    public function le_panier_d_un_sejour_survit_a_une_nouvelle_session_et_a_un_autre_poste(): void
    {
        $reservation = $this->reservationEnCours();

        $this->actingAs($this->gerant);

        Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('ajouterAuPanier', 'M4', $this->plat->id);

        // La session HTTP disparait — expiration, deconnexion, autre poste.
        $this->flushSession();

        // Et c'est un AUTRE utilisateur, sur un composant neuf : la releve.
        $autrePoste = $this->utilisateur('gerant');

        $this->actingAs($autrePoste);

        $composant = Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id);

        $panier = $composant->viewData('panier');

        $this->assertNotNull($panier, 'Le panier a disparu avec la session : il ne vit pas en base.');
        $this->assertCount(2, $panier->lignes);
        $this->assertSame('3500.00', $composant->viewData('totalPanier'));
        $this->assertSame(1, $composant->viewData('paniersOuverts'));
        $this->assertSame('3500.00', $composant->viewData('encoursSejours'));
    }

    #[Test]
    public function le_panier_d_une_table_survit_a_une_nouvelle_session_et_a_un_autre_poste(): void
    {
        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('selectedTableId', $this->tableR1)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M4', $this->plat->id);

        $this->flushSession();

        $this->actingAs($this->utilisateur('gerant'));

        $composant = Livewire::test(PosComptant::class)
            ->set('selectedTableId', $this->tableR1);

        $this->assertNotNull($composant->viewData('panier'));
        $this->assertSame('2500.00', $composant->viewData('totalPanier'));

        // Le panier du comptoir, lui, est un AUTRE panier : la table n'est pas
        // la caisse (PA-79), et une commande de salle ne doit pas apparaitre
        // au comptoir.
        $this->actingAs($this->gerant);

        $auComptoir = Livewire::test(PosComptant::class);
        $this->assertNull($auComptoir->viewData('panier'));
    }

    /**
     * Les TROIS etats de table du maitre, derives des paniers reels.
     *
     * `ouverte` — un panier ouvert et vide — n'etait pas rendu tant que le
     * panier vivait en memoire : il y etait indiscernable d'une table libre.
     * Le quatrieme etat du maitre (`fermee`) reste non rendu, faute de colonne
     * qui le porte (PA-126).
     */
    #[Test]
    public function l_etat_d_une_table_se_derive_du_panier_reel_et_couvre_les_trois_etats(): void
    {
        $this->actingAs($this->gerant);

        $composant = Livewire::test(PosComptant::class);

        // 1. LIBRE — aucun panier ouvert.
        $this->assertSame(PosComptant::ETAT_LIBRE, $composant->viewData('etatsDesTables')[$this->tableR1]['etat']);

        // 2. EN COURS — un panier ouvert qui porte des lignes, avec son encours.
        $composant->set('selectedTableId', $this->tableR1)->call('ajouterAuPanier', 'M4', $this->plat->id);
        $etats = $composant->viewData('etatsDesTables');
        $this->assertSame(PosComptant::ETAT_EN_COURS, $etats[$this->tableR1]['etat']);
        $this->assertSame('2500.00', $etats[$this->tableR1]['total']);

        // Les autres tables n'ont pas bouge.
        $this->assertSame(PosComptant::ETAT_LIBRE, $etats[$this->tableJ1]['etat']);

        // 3. OUVERTE — le panier est vide, le client est toujours assis.
        $composant->call('viderPanier');
        $this->assertSame(PosComptant::ETAT_OUVERTE, $composant->viewData('etatsDesTables')[$this->tableR1]['etat']);

        // Et « Abandonner » la libere pour de bon.
        $composant->call('abandonnerPanier');
        $this->assertSame(PosComptant::ETAT_LIBRE, $composant->viewData('etatsDesTables')[$this->tableR1]['etat']);
    }

    /**
     * ⚠ Consulter n'OUVRE aucun panier.
     *
     * Ouvrir a la lecture ferait passer toutes les tables a « ouverte » des
     * qu'un role en `L` affiche la page, pour des couverts que personne n'a
     * servis — l'indicateur qui affirme un etat que rien n'a produit
     * (PA-59/60/61). Et un role sans droit d'ecriture ecrirait en base par le
     * seul fait de regarder.
     */
    #[Test]
    public function afficher_les_deux_ecrans_n_ouvre_aucun_panier(): void
    {
        $reservation = $this->reservationEnCours();
        $comptable = $this->utilisateur('comptable');   // M5 = 'L'

        $this->actingAs($comptable)->get('/pwa/pos/comptant')->assertOk();
        $this->actingAs($comptable)->get('/pwa/pos/heberges')->assertOk();

        $this->actingAs($comptable);

        Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->assertStatus(200);

        $this->assertSame(0, Panier::count());
    }

    /**
     * L'encaissement CLOT le panier — sinon il serait encaisse deux fois.
     *
     * Avant PA-161 le panier etait une variable d'ecran, videe a la main apres
     * l'encaissement. Elle survivait a un rechargement de page dans l'autre
     * onglet : le meme panier repartait au registre des ventes.
     */
    #[Test]
    public function l_encaissement_clot_le_panier_et_libere_la_table(): void
    {
        $this->ouvrirLaCaisse();

        $this->actingAs($this->gerant);

        $composant = Livewire::test(PosComptant::class)
            ->set('selectedTableId', $this->tableR1)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('encaisser')
            ->assertSet('toastType', 'success');

        $vente = Vente::firstOrFail();
        $panier = Panier::firstOrFail();

        $this->assertTrue($panier->estCloture());
        $this->assertSame($vente->id, $panier->vente_id);

        // La table est libre, et un second encaissement ne repart pas du meme
        // panier : il n'y a plus rien a encaisser.
        $this->assertSame(PosComptant::ETAT_LIBRE, $composant->viewData('etatsDesTables')[$this->tableR1]['etat']);

        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('selectedTableId', $this->tableR1)
            ->call('encaisser')
            ->assertSet('toastType', 'error');

        $this->assertSame(1, Vente::count());
    }

    /**
     * ⚠ Une panne de stock N'ENCAISSE PAS et NE CLOT PAS.
     *
     * La vente et la cloture vivent dans la meme transaction : si l'une echoue,
     * l'autre est annulee. Sans cela, un panier clos sur une vente inexistante
     * serait perdu pour tout le monde — le client aurait consomme, la commande
     * serait fermee, et rien ne la porterait.
     */
    #[Test]
    public function une_rupture_de_stock_laisse_le_panier_ouvert_et_intact(): void
    {
        $this->ouvrirLaCaisse();

        // Une boisson dont l'article n'a JAMAIS ete receptionne : stock a zero.
        $sansStock = CarteBoisson::create([
            'article_id' => $this->article('Sodabi', 'bouteille')->id,
            'libelle' => 'Sodabi 1 L',
            'categorie' => 'locale',
            'prix_vente' => '3000.00',
            'unites_vendables_par_unite_stock' => '1.0000',
        ]);

        $this->actingAs($this->gerant);

        $composant = Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $sansStock->id)
            ->call('encaisser');

        // Le maitre pose la question (« Vendre quand meme »), il ne subit pas.
        $composant->assertSet('etatFormulaire', 'rupture');

        $panier = $this->panierDuComptoir();
        $this->assertTrue($panier->estOuvert());
        $this->assertCount(1, $panier->lignes);
        $this->assertSame(0, Vente::count());
    }

    // =====================================================================
    // P6 — le RBAC, sur les DEUX modules d'un ticket mixte
    // =====================================================================

    #[Test]
    public function un_role_sans_droit_d_ecriture_sur_m5_ne_peut_rien_porter_au_panier(): void
    {
        $comptable = $this->utilisateur('comptable');   // M5 = 'L'

        $this->actingAs($comptable);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->assertForbidden();
    }

    #[Test]
    public function un_barman_ne_peut_pas_encaisser_un_plat_que_l_api_m4_lui_refuse(): void
    {
        $this->ouvrirLaCaisse();
        $barman = $this->utilisateur('barman');   // M5 = 'C', M4 = '-'

        // La boisson passe : c'est son module.
        $this->actingAs($barman);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('encaisser')
            ->assertSet('toastType', 'success');

        // Le plat exige M4 a l'encaissement : `VenteService` y cree et transmet
        // une commande de cuisine. Le laisser passer donnerait par le
        // navigateur ce que l'API refuse (PA-65).
        $this->actingAs($barman);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M4', $this->plat->id)
            ->call('encaisser')
            ->assertForbidden();

        $this->assertSame(1, Vente::count());
    }

    /**
     * Le CONTRE-CAS de `un_role_sans_droit…`, et il est indispensable.
     *
     * Sans lui, le cas de refus prouverait seulement que la garde est posee
     * quelque part — il resterait vert si `exigerEcriture()` etait pose sur
     * TOUT, y compris sur la lecture. Or c'est exactement ce qui s'etait
     * produit au premier jet : le comptable, dont le metier EST de sortir le
     * journal des ventes, ne pouvait ni l'exporter ni telecharger un ticket.
     *
     * `/pwa/historique-ventes` ne porte aucun middleware `module:` : les deux
     * moities de la regle se lisent donc ici, sur le meme role.
     */
    #[Test]
    public function un_comptable_exporte_le_journal_et_son_ticket_mais_n_encaisse_pas(): void
    {
        $this->ouvrirLaCaisse();

        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('encaisser');

        $vente = Vente::firstOrFail();
        $comptable = $this->utilisateur('comptable');   // M5 = 'L'

        // 1. Il ATTEINT l'ecran, et le bouton d'export unique y est rendu.
        //
        // ⚠ Depuis le 01/09/2026 (derogation PO, `export_bouton_unique` du
        // registre `DerogationsMaquette`), les deux boutons distincts du
        // maitre (« Export Excel » / « Export PDF ») sont fusionnes en UN
        // bouton « Exporter » qui ouvre la modale ou le format se choisit.
        //
        // Prouve par mutation le 01/09/2026 : remplacer temporairement le
        // libelle du bouton (`{{ __('pwa.export.bouton') }}`) par un texte
        // arbitraire dans `historique-ventes.blade.php` rend ce cas ROUGE
        // (« To contain: Exporter ») — l'assertion tient donc reellement la
        // presence du bouton fusionne, restaure ensuite (suite au vert,
        // 26/26).
        $this->actingAs($comptable)
            ->get('/pwa/historique-ventes')
            ->assertOk()
            ->assertSee(__('pwa.export.bouton'));

        /*
         * ⚠ `assertStatus(200)`, et surtout PAS `assertHasNoErrors()`.
         *
         * Livewire rend un refus `abort(403)` comme un STATUT, pas comme une
         * exception : ni `assertHasNoErrors()` ni `assertSet()` ne le voient.
         * La premiere version de ce cas est restee VERTE alors que la garde
         * d'ecriture avait ete remise sur `genererExport` — elle ne prouvait
         * donc rien. Mesure du 31/08/2026, par mutation.
         */

        // 2. Il OBTIENT son export — la liste n'est pas vide, donc aucun refus.
        $this->actingAs($comptable);

        // `assertStatus()` rend le `TestResponse` sous-jacent : il clot la
        // chaine, il ne s'y intercale pas (analyse statique, 02/09/2026).
        Livewire::test(HistoriqueVentes::class)
            ->call('ouvrirExport', 'pdf')
            ->assertSet('etatFormulaire', 'export')
            ->call('genererExport')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null)
            ->assertStatus(200);

        // 3. Il OBTIENT le ticket d'une vente, et peut refermer la modale.
        $this->actingAs($comptable);

        Livewire::test(HistoriqueVentes::class)
            ->set('venteDetailId', $vente->id)
            ->call('telechargerTicket')
            ->assertHasNoErrors()
            ->call('fermerModales')
            ->assertStatus(200);

        // 4. Il CONSULTE le journal du jour au point de vente.
        $this->actingAs($comptable);

        Livewire::test(PosComptant::class)
            ->call('ouvrirJournalDuJour')
            ->assertSet('etatFormulaire', 'journal')
            ->assertStatus(200);

        // 5. Mais il n'ENCAISSE pas, et il n'ANNULE pas : ce sont des
        //    ecritures, et son niveau sur M5 est `L`.
        $this->actingAs($comptable);

        Livewire::test(PosComptant::class)
            ->call('encaisser')
            ->assertForbidden();

        $this->actingAs($comptable);

        Livewire::test(HistoriqueVentes::class)
            ->set('venteDetailId', $vente->id)
            ->set('motifAnnulation', 'Tentative sans droit')
            ->call('annulerVente')
            ->assertForbidden();

        $this->assertSame('validee', $vente->refresh()->statut);
    }

    // =====================================================================
    // P3 — un echec de facturation ne detruit pas le panier et ne dit pas
    //      « succes »
    // =====================================================================

    #[Test]
    public function un_echec_de_facturation_laisse_le_panier_intact_et_ne_dit_pas_succes(): void
    {
        $reservation = $this->reservationEnCours();

        /*
         * L'etat que `CalculTvaService` refuse DELIBEREMENT (PA-62) : la TVA
         * est active, aucun taux n'est pose. L'emission leve, au comptoir.
         */
        ParametreSysteme::create(['cle' => CalculTvaService::CLE_PARAMETRE_ACTIVE, 'valeur' => 'true']);

        $this->actingAs($this->gerant);

        $composant = Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('ajouterAuPanier', 'M4', $this->plat->id)
            ->call('cloturerEtFacturer');

        // 1. L'ecran ne dit PAS « succes ».
        $composant->assertSet('toastType', 'error');

        // 2. Le panier est INTACT, et il l'est EN BASE : la transaction a ete
        //    annulee, il est toujours OUVERT avec ses deux lignes. C'est la
        //    seule copie de ce que le client a consomme.
        $panier = $this->panierDuSejour($reservation->id);
        $this->assertTrue($panier->estOuvert());
        $this->assertCount(2, $panier->lignes);

        // 3. Et rien n'a ete a moitie ecrit : ni facture, ni vente.
        $this->assertSame(0, Facture::count());
        $this->assertSame(0, Vente::count());
    }

    /**
     * La SECONDE branche du `catch`, et elle n'etait exercee par rien.
     *
     * La mutation du 31/08/2026 l'a montre : poser un `Session::forget()` dans
     * le `catch (\Throwable)` ne faisait rougir AUCUN cas, parce que le refus
     * de TVA remonte en `RuntimeException` et sort par l'autre branche. Un
     * chemin qu'aucun test n'emprunte est un chemin dont personne ne sait ce
     * qu'il fait — c'est le defaut que PA-59/60/61 nomment.
     *
     * Ce cas y fait entrer une panne technique, et verifie les DEUX choses que
     * cette branche doit tenir : le panier survit, et le message d'exception
     * brut n'atteint PAS l'ecran. Un `$e->getMessage()` affiche au comptoir
     * ferait fuir du SQL a qui passe devant la caisse.
     */
    #[Test]
    public function une_panne_technique_ne_fait_fuir_ni_le_panier_ni_le_message_d_exception(): void
    {
        $reservation = $this->reservationEnCours();

        $fuite = 'SQLSTATE[42S02]: Base table or view not found: factures';
        $service = \Mockery::mock(EmissionFactureService::class);
        $service->shouldReceive('emettrePourReservation')->andThrow(new \LogicException($fuite));
        $this->app->instance(EmissionFactureService::class, $service);

        $this->actingAs($this->gerant);

        $composant = Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('ajouterAuPanier', 'M4', $this->plat->id)
            ->call('cloturerEtFacturer');

        $composant->assertSet('toastType', 'error');

        // Le message technique ne remonte PAS a l'ecran.
        $this->assertStringNotContainsString($fuite, (string) $composant->get('toastMessage'));
        $this->assertSame(
            __('pos_pwa.heberges.refus_facturation'),
            (string) $composant->get('toastMessage'),
        );

        // Le panier survit, et la transaction n'a rien laisse a moitie ecrit.
        $panier = $this->panierDuSejour($reservation->id);
        $this->assertTrue($panier->estOuvert());
        $this->assertCount(2, $panier->lignes);
        $this->assertSame(0, Vente::count());
        $this->assertSame(0, Facture::count());
    }

    // =====================================================================
    // P3bis — aucun tarif de repli n'est facture
    // =====================================================================

    #[Test]
    public function aucun_tarif_de_repli_n_est_facture_quand_la_categorie_n_en_porte_pas(): void
    {
        $reservation = $this->reservationEnCours(tarifBase: '0.00');

        $this->actingAs($this->gerant);

        Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('cloturerEtFacturer')
            ->assertSet('toastType', 'error');

        // Le refus est le livrable : facturer 20 000 F que personne n'a decides
        // sur un document remis au client serait pire que ne rien emettre.
        $this->assertSame(0, Facture::count());

        $panier = $this->panierDuSejour($reservation->id);
        $this->assertTrue($panier->estOuvert());
        $this->assertCount(1, $panier->lignes);
    }

    // =====================================================================
    // La cloture nominale d'un sejour
    // =====================================================================

    #[Test]
    public function la_cloture_d_un_sejour_produit_une_vente_en_note_puis_une_seule_facture(): void
    {
        $reservation = $this->reservationEnCours();
        $stocks = app(StockTheoriqueService::class);

        $this->actingAs($this->gerant);

        Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('ajouterAuPanier', 'M4', $this->plat->id)
            ->call('ouvrirClotureSejour')
            ->call('cloturerEtFacturer')
            ->assertHasNoErrors();

        $vente = Vente::with('lignes')->firstOrFail();

        // Une note de chambre n'est PAS un encaissement : c'est une creance.
        $this->assertSame('note_chambre', $vente->mode_paiement);
        $this->assertFalse($vente->encaisse);
        $this->assertSame($this->client->id, $vente->client_id);
        $this->assertSame('3500.00', (string) $vente->montant_total);

        // RG-05 s'applique comme au comptoir.
        $this->assertSame('47.00', $stocks->stock($this->articleBiere->id, $this->bar->id));

        // UNE seule facture : les nuitees d'abord, les consommations ensuite.
        $this->assertSame(1, Facture::count());
        $facture = Facture::firstOrFail();
        $this->assertEqualsCanonicalizing(
            ['M1', 'M4', 'M5'],
            $facture->lignes()->pluck('source_module')->unique()->values()->all(),
        );

        /*
         * Le panier est clos — et « clos » se mesure en base, pas par l'absence
         * d'une cle de session. L'ancienne assertion
         * (`assertSame([], Session::get(...))`) serait restee VERTE apres la
         * bascule sans rien mesurer : une cle qui n'existe plus rend toujours
         * son defaut. C'est exactement le balayage vide que ce depot traque.
         */
        $panierClos = Panier::where('reservation_id', $reservation->id)->firstOrFail();
        $this->assertTrue($panierClos->estCloture());
        $this->assertSame($vente->id, $panierClos->vente_id);
        $this->assertNotNull($panierClos->cloture_at);

        $this->actingAs($this->gerant);

        Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('cloturerEtFacturer')
            ->assertSet('toastType', 'error');

        $this->assertSame(1, Facture::count());
    }

    #[Test]
    public function le_pos_des_clients_heberges_ne_propose_ni_circuit_ni_vehicule_ni_rayon_prestations(): void
    {
        \App\Domain\Tourisme\Models\Circuit::create([
            'nom' => 'Cascades de Kota', 'theme' => 'nature', 'zone' => 'Atacora',
            'duree' => '1 jour', 'prix' => '15000.00', 'capacite_max' => 12,
        ]);
        \App\Domain\Vehicules\Models\Vehicule::create([
            'categorie' => '4x4', 'immatriculation' => 'AB-123-CD', 'annee' => 2022,
            'transmission' => 'automatique', 'capacite' => 5, 'tarif_jour' => '65000.00',
            'statut' => 'disponible',
        ]);
        $reservation = $this->reservationEnCours();

        $this->actingAs($this->gerant);

        Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->assertDontSee('Cascades de Kota')
            ->assertDontSee('AB-123-CD')
            ->assertDontSee('Tourisme')
            ->assertDontSee('Location');
    }

    #[Test]
    public function une_action_forgee_sur_le_tourisme_ou_la_location_n_ouvre_aucun_panier_de_sejour(): void
    {
        $reservation = $this->reservationEnCours();

        $this->actingAs($this->gerant);

        $composant = Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->call('ajouterAuPanier', 'M9', (string) Str::uuid());

        // Plus aucune carte ne les propose (PO, 26/10/2026) : une action
        // forgee est refusee, jamais un echec silencieux.
        $composant->assertSet('toastType', 'error');
        $composant->assertSet('toastMessage', __('pos_pwa.commun.reference_inconnue'));
        /*
         * Et AUCUN panier n'a ete ouvert : un refus qui laisserait derriere lui
         * un panier vide ferait passer le sejour a « PANIER OUVERT » sur la
         * liste de gauche, pour une prestation que rien n'a pu y porter.
         */
        $this->assertSame(0, Panier::where('reservation_id', $reservation->id)->count());
    }

    // =====================================================================
    // PA-119 — l'export porte sur ce qui est affiche et DIT son filtre
    // =====================================================================

    #[Test]
    public function un_export_sur_une_liste_vide_est_refuse(): void
    {
        $this->actingAs($this->gerant);

        Livewire::test(HistoriqueVentes::class)
            ->call('ouvrirExport', 'pdf')
            ->call('genererExport')
            ->assertHasErrors('formatExport');
    }

    #[Test]
    public function l_export_porte_le_filtre_affiche_et_le_document_le_dit(): void
    {
        $this->ouvrirLaCaisse();

        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('encaisser');

        $this->actingAs($this->gerant);

        $composant = Livewire::test(HistoriqueVentes::class)
            ->set('statut', 'annulee');

        // Le filtre ne laisse rien : l'export REFUSE au lieu de rendre le
        // registre entier ou une page blanche.
        $composant->call('ouvrirExport', 'pdf')
            ->call('genererExport')
            ->assertHasErrors('formatExport');

        // Et l'ecran DIT son filtre, avant meme d'exporter.
        $composant->assertSee('statut annulee');
    }

    /**
     * LES CHIPS DE CATÉGORIE SONT LES VRAIES CATÉGORIES MÉTIER, PAS LE NOM DU
     * MENU NI LE CODE BRUT DE L'ENUM (corrigé le 02/09/2026).
     *
     * `depuisPlat()` lisait `$plat->menu->libelle` — un seul menu porte tous
     * les plats du maître, donc CHAQUE rayon affichait « Carte principale »
     * (ici) / « Carte du restaurant » (au maître), au lieu du rayon réel
     * (« Entrées », « Plats complets »…). Deux plats de rayons DIFFÉRENTS
     * doivent donc produire deux chips DISTINCTES, jamais le nom du menu.
     *
     * `depuisBoisson()` rendait le code brut de `cartes_boisson.categorie`
     * (« locale ») au lieu de son libellé français (« Locale »).
     *
     * Éprouvé par mutation le 02/09/2026 : remettre
     * `$plat->menu->libelle ?? $plat->categorie ?? ''` dans `depuisPlat()`
     * fait rougir ce cas sur « Carte principale » toujours présent — restauré
     * ensuite.
     */
    #[Test]
    public function les_chips_de_categorie_sont_les_rayons_reels_pas_le_menu(): void
    {
        Plat::create([
            'menu_id' => $this->plat->menu_id,
            'recette_id' => $this->plat->recette_id,
            'libelle' => 'Salade peulh',
            'categorie' => 'Entrées',
            'prix_vente' => '2000.00',
        ]);

        $this->actingAs($this->gerant);

        $html = (string) Livewire::test(PosComptant::class)
            ->html();

        // Les deux rayons distincts du plat, jamais le nom du menu qui les
        // porte tous les deux — cherché comme la chip elle-même (le clic sur
        // `categorieActive`), pas comme une sous-chaîne qui traînerait
        // ailleurs sur la page.
        $this->assertStringContainsString("categorieActive', 'Entrées'", $html);
        $this->assertStringContainsString("categorieActive', 'plat'", $html);
        $this->assertStringNotContainsString('Carte principale', $html);

        // Le libellé français de la boisson, jamais le code brut de l'enum.
        $this->assertStringContainsString(CarteBoisson::CATEGORIES['locale'], $html);
    }

    // =====================================================================
    // Fixtures
    // =====================================================================

    // =====================================================================
    // Directives PO du 02/09/2026 — remise, mention client, modes du
    // comptoir, cloture « Payer separement »
    // =====================================================================

    /**
     * Remise 10 % : total NET a l'encaissement, et piece comptable
     * EQUILIBREE AU NET — la regle des 7 (meme transaction) portee sur le
     * montant reellement encaisse.
     *
     * Mutation faite le 02/09/2026 : fausser le net dans
     * `Panier::remiseSur()` (diviser le pourcentage par 10 au lieu de 100)
     * → ROUGE (« '3150.00' ≠ '0.00' » sur le montant). Restaure.
     */
    #[Test]
    public function une_remise_de_dix_pour_cent_encaisse_le_net_et_equilibre_la_piece_au_net(): void
    {
        $this->ouvrirLaCaisse();
        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M4', $this->plat->id)
            ->set('remiseType', 'pourcentage')
            ->set('remiseValeur', '10')
            ->call('appliquerRemise')
            ->assertHasNoErrors()
            ->call('encaisser')
            ->assertSet('toastType', 'success');

        $vente = Vente::with('lignes')->firstOrFail();

        // 3 500 brut − 10 % = 3 150 net. Les LIGNES restent au prix brut
        // fige du catalogue — la remise est la difference, jamais des prix
        // reecrits.
        $this->assertSame('3150.00', (string) $vente->montant_total);
        $this->assertSame('3500.00', $vente->totalLignes());
        $this->assertSame('350.00', $vente->remiseDeduite());

        // La piece comptable porte le NET : debit unique = 3 150, et la
        // somme des credits l'egale centime par centime.
        $piece = \App\Domain\Comptabilite\Models\EcritureComptable::where('libelle', 'Vente '.$vente->numero)
            ->whereNull('ecriture_contrepassee_id')
            ->get();
        $this->assertNotEmpty($piece);

        $debits = '0.00';
        $credits = '0.00';

        foreach ($piece as $ecriture) {
            $debits = bcadd($debits, (string) $ecriture->debit, 2);
            $credits = bcadd($credits, (string) $ecriture->credit, 2);
        }

        $this->assertSame('3150.00', $debits, 'Le debit de tresorerie ne porte pas le net encaisse.');
        $this->assertSame($debits, $credits, 'La piece de la vente remisee ne s equilibre pas.');
    }

    /**
     * Remise en FRANCS : net exact — et un net NEGATIF refuse, il ne produit
     * jamais un montant plausible.
     */
    #[Test]
    public function une_remise_en_francs_encaisse_le_net_et_un_net_negatif_est_refuse(): void
    {
        $this->ouvrirLaCaisse();
        $this->actingAs($this->gerant);

        // 1. Une remise superieure au total est refusee A L'APPLICATION, et
        // rien n'est ecrit sur le panier.
        $composant = Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->set('remiseType', 'montant')
            ->set('remiseValeur', '5000')
            ->call('appliquerRemise')
            ->assertHasErrors('remiseValeur');

        $this->assertSame(Panier::REMISE_AUCUNE, $this->panierDuComptoir()->remise_type);

        // 2. La remise de 500 F passe, et l'encaissement porte le net.
        $composant
            ->set('remiseValeur', '500')
            ->call('appliquerRemise')
            ->assertHasNoErrors()
            ->call('encaisser')
            ->assertSet('toastType', 'success');

        $vente = Vente::firstOrFail();
        $this->assertSame('500.00', (string) $vente->montant_total);
        $this->assertSame('500.00', $vente->remiseDeduite());

        // La remise est FIGEE sur le panier clos, comme les prix.
        $panierClos = Panier::where('vente_id', $vente->id)->firstOrFail();
        $this->assertSame('montant', $panierClos->remise_type);
        $this->assertSame(0, bccomp((string) $panierClos->remise_valeur, '500.00', 2));
    }

    /**
     * La MENTION client du comptoir (texte libre, PO 02/09/2026) est ecrite
     * sur la vente — jamais une FK — et imprimee sur le ticket 80 mm ET la
     * facture A4 de la vente.
     *
     * Mutation faite le 02/09/2026 : retirer la ligne client de
     * `ticket-thermique.blade.php` → ROUGE (« M. HOUNSOU » absent du flux).
     * Restaure.
     */
    #[Test]
    public function la_mention_client_du_comptoir_est_imprimee_sur_le_ticket_et_la_facture(): void
    {
        $this->ouvrirLaCaisse();
        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->set('clientMention', 'M. HOUNSOU')
            ->call('encaisser')
            ->assertSet('toastType', 'success');

        $vente = Vente::firstOrFail();

        // Une MENTION, pas une fiche : aucun registre client n'est touche.
        $this->assertSame('M. HOUNSOU', $vente->client_mention);
        $this->assertNull($vente->client_id);
        $this->assertSame(1, Client::count(), 'Une fiche client a ete creee par la vente au comptoir.');

        // Le ticket 80 mm — la fenetre REELLE, par sa route. Tant que MECeF
        // n'est pas configuree, l'emplacement du cachet ne s'imprime PLUS
        // (directive PO 02/09/2026) ; la mention « en attente » du pied,
        // honnete, reste.
        $this->actingAs($this->gerant)
            ->get(route('pwa.pos.ticket-thermique', $vente->id))
            ->assertOk()
            ->assertSee('M. HOUNSOU')
            ->assertDontSee('Emplacement réservé au cachet fiscal MECeF')
            ->assertSee('en attente d');

        // La facture A4 de la vente — la MEME vue que `imprimerTicketA4()`,
        // rendue avec exactement les variables que le composant lui passe.
        $html = view('pdf.facture-ticket', [
            'vente' => $vente->load('lignes'),
            'quand' => now()->format('d/m/Y H:i'),
            'auteur' => $this->gerant->login,
            'entete' => app(\App\Shared\ReportEngine\Services\ReportHeaderService::class)->genererEnTete(
                typeRapport: (string) __('pos_pwa.document.ticket_titre'),
                periode: '',
                auteur: $this->gerant,
            ),
        ])->render();

        $this->assertStringContainsString('M. HOUNSOU', $html);
        // L'en-tete de TOUS les documents (PO 02/09/2026) : raison sociale
        // puis enseigne EN MINUSCULES, derivees par l'auteur unique.
        $this->assertStringContainsString('TATACORA AFRIQUE', $html);
        $this->assertStringContainsString('gîte chez noël', $html);
        // Meme regle que le 80 mm : ni emplacement de cachet, ni « Ne vaut
        // pas facture normalisee » tant que MECeF n'est pas configuree.
        $this->assertStringNotContainsString('Emplacement réservé au cachet fiscal MECeF', $html);
        $this->assertStringNotContainsString('Document transactionnel unitaire', $html);
    }

    /**
     * « Porte sur la note de chambre » n'existe plus au comptoir (PO
     * 02/09/2026) : absent du selecteur ET refuse par le serveur — une
     * propriete Livewire se pose depuis le navigateur.
     */
    #[Test]
    public function le_mode_note_de_chambre_est_refuse_au_comptoir(): void
    {
        $this->assertArrayNotHasKey(
            'note_chambre',
            \App\Domain\Ventes\Services\VenteService::modesPaiementComptoir(),
        );

        $this->ouvrirLaCaisse();
        $this->actingAs($this->gerant);

        Livewire::test(PosComptant::class)
            ->set('comptoirChoisi', true)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->set('modePaiement', 'note_chambre')
            ->call('encaisser')
            ->assertSet('toastType', 'error');

        $this->assertSame(0, Vente::count(), 'Une vente en note de chambre a ete enregistree au comptoir.');
        // Le panier reste OUVERT : rien n'a ete perdu.
        $this->assertTrue($this->panierDuComptoir()->estOuvert());
    }

    /**
     * « Payer separement » (PO 02/09/2026, amendement de RG-04) : la facture
     * emise ne porte QUE les consommations (nettes de la remise du panier),
     * le RAPPEL est rendu dans la modale, et le reste du est coherent — la
     * facture partielle n'absorbe ni l'acompte ni l'hebergement, qui restent
     * portes par la fiche (`Reservation::resteAPayer()`).
     *
     * Mutation faite le 02/09/2026 : supprimer le bloc de rappel de
     * `heberges.blade.php` → ROUGE (« L'hébergement n'est pas réglé » absent
     * du rendu). Restaure.
     */
    #[Test]
    public function la_cloture_payee_separement_ne_facture_que_les_consommations_et_le_reste_du_le_dit(): void
    {
        $reservation = $this->reservationEnCours();
        // Le tarif FIGE de la fiche (PA-55/PA-163) et un acompte : c'est eux
        // que `resteAPayer()` derive — la cloture partielle ne doit pas les
        // toucher.
        $reservation->update(['tarif_nuit' => '30000.00', 'acompte' => '10000.00']);

        $this->actingAs($this->gerant);

        $composant = Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->set('remiseType', 'pourcentage')
            ->set('remiseValeur', '10')
            ->call('appliquerRemise')
            ->assertHasNoErrors()
            ->call('ouvrirClotureSejour')
            ->assertSet('payerSeparement', false)
            ->set('payerSeparement', true);

        // Le RAPPEL exige par la directive est REELLEMENT rendu.
        $composant->assertSee('L\'hébergement n\'est pas réglé');

        $composant->call('cloturerEtFacturer')->assertSet('toastType', 'success');

        // UNE facture, SANS ligne M1 : consommations 1 000 − remise 100.
        $this->assertSame(1, Facture::count());
        $facture = Facture::with('lignes')->firstOrFail();
        $this->assertNotContains('M1', $facture->lignes->pluck('source_module')->all());
        $this->assertSame(0, bccomp((string) $facture->montant_ttc, '900.00', 2));

        // La ligne de remise est DEDIEE et negative, sur le module des
        // consommations — le TTC de la facture egale le net de la vente.
        $remiseLigne = $facture->lignes->firstWhere('libelle', __('ventes.remise_ligne_facture').' — Bar');
        $this->assertNotNull($remiseLigne, 'La ligne dediee de remise manque a la facture.');
        $this->assertSame(0, bccomp((string) $remiseLigne->montant, '-100.00', 2));

        $vente = Vente::firstOrFail();
        $this->assertSame('note_chambre', $vente->mode_paiement);
        $this->assertSame(0, bccomp((string) $vente->montant_total, '900.00', 2));

        // Reste du de la FACTURE : les 900 F de consommations — l'acompte de
        // la reservation n'y est PAS deduit (aucune ligne M1 ne l'y lie).
        $this->assertSame('900.00', $facture->resteDu());

        // Et la FICHE porte toujours l'hebergement : 2 nuitees × 30 000
        // − 10 000 d'acompte. La facture partielle ne l'a pas solde.
        $this->assertSame(0, bccomp((string) $reservation->refresh()->resteAPayer(), '50000.00', 2));

        // Une cloture ulterieure AVEC hebergement reste possible : rien n'a
        // ete consomme du controle « deja facture » (aucune ligne M1).
        $this->actingAs($this->gerant);
        Livewire::test(PosHeberges::class)
            ->set('selectedReservationId', $reservation->id)
            ->call('ajouterAuPanier', 'M5', $this->biere->id)
            ->call('ouvrirClotureSejour')
            ->call('cloturerEtFacturer')
            ->assertSet('toastType', 'success');

        $this->assertSame(2, Facture::count());
        $this->assertTrue(
            Facture::with('lignes')->get()->flatMap->lignes->pluck('source_module')->contains('M1'),
            "La seconde cloture n'a pas facture l'hebergement.",
        );
    }

    private function ouvrirLaCaisse(string $fond = '10000'): SessionCaisse
    {
        return SessionCaisse::create([
            'point_vente' => 'bar',
            'utilisateur_ouverture_id' => $this->gerant->id,
            'date_ouverture' => now(),
            'montant_fond' => $fond,
        ]);
    }

    private function reservationEnCours(string $tarifBase = '30000.00'): Reservation
    {
        $categorie = CategorieHebergement::create([
            'libelle' => 'Chambre standard',
            'capacite_max' => 2,
            'tarif_base' => $tarifBase,
        ]);

        $unite = UniteHebergement::create([
            'categorie_id' => $categorie->id,
            'numero' => 'CH-01',
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
