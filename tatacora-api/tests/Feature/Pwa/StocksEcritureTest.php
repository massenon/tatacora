<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\Inventaire;
use App\Domain\Stocks\Models\LigneInventaire;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Pwa\Livewire\Stocks\Inventaires;
use App\Pwa\Livewire\Stocks\Stocks;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les GESTES D'ÉCRITURE des deux écrans M6 — chacun exécuté pour de vrai.
 *
 * ## Pourquoi ce fichier existe à côté de `StocksAchatsPwaTest`
 *
 * Celui-là vérifie ce que les pages RENDENT ; celui-ci ce qu'elles ÉCRIVENT.
 * Les séparer n'est pas cosmétique : jusqu'au 31/08/2026, les sept actions
 * déclarées sur `Stocks` n'étaient câblées à aucune vue et n'ont donc jamais
 * été exécutées par personne — la définition même de PA-59/60/61, un composant
 * qui a l'air complet et dont aucun chemin n'a jamais tourné.
 *
 * ## Les mutations exécutées, et ce qu'elles ont fait rougir
 *
 * Chaque cas porte au-dessus de lui la mutation qui prouve qu'il peut échouer.
 * Elles ont toutes été rejouées puis annulées le 31/08/2026.
 *
 * @see EF-M6-01 Référentiel articles
 * @see EF-M6-03 Valorisation au coût moyen pondéré
 * @see EF-M6-05 Inventaire physique avec écarts
 * @see RG-06 Blocage au-delà du disponible, avec échappatoire contrôlée
 */
final class StocksEcritureTest extends TestCase
{
    use RefreshDatabase;

    private PointStockage $magasin;

    private Article $riz;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->actingAs($this->utilisateur('administrateur'));

        $this->magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $this->riz = Article::create([
            'libelle' => 'Riz local (sac 50 kg)',
            'categorie' => 'Denrées',
            'unite_mesure' => 'sac',
            'seuil_alerte' => '5.00',
            'cout_moyen_pondere' => '0.0000',
        ]);
    }

    /* ------------------------------------------------------- référentiel */

    /**
     * Le stock d'ouverture est un MOUVEMENT, et il valorise le CMP.
     *
     * ⚠ Le coût d'achat n'écrit JAMAIS `cout_moyen_pondere` en direct : il est
     * passé à `MouvementStockService::entree()`, qui le fait traverser
     * `ValorisationStockService`. La version précédente de ce composant écrivait
     * la colonne à la main — `EnregistrerArticleRequest` l'interdit déjà côté
     * API pour la raison qui compte : un CMP saisi alimente le poste de stocks
     * au bilan et la variation de stock au résultat.
     *
     * Mutation (31/08/2026) : `coutUnitaire: … ?? null` remplacé par
     * `coutUnitaire: null` dans `enregistrerArticle` → le CMP est resté à
     * `0.0000` et le cas a rougi sur `assertSame('32000.0000', …)`.
     */
    #[Test]
    public function creer_un_article_avec_un_stock_d_ouverture_pose_un_mouvement_et_valorise_le_cmp(): void
    {
        Livewire::test(Stocks::class)
            ->call('nouvelArticle')
            ->set('libelle', 'Sucre en poudre')
            ->set('categorieSaisie', 'Denrées')
            ->set('uniteSaisie', 'kg')
            ->set('seuilAlerte', '4')
            ->set('pointOuverture', $this->magasin->id)
            ->set('valeurAchat', '32000')
            ->set('stockOuverture', '10')
            ->call('enregistrerArticle')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $article = Article::where('libelle', 'Sucre en poudre')->firstOrFail();

        $mouvement = MouvementStock::where('article_id', $article->id)->firstOrFail();
        $this->assertSame('entree', $mouvement->type_mouvement);
        $this->assertSame('10.00', (string) $mouvement->quantite);
        $this->assertSame($this->magasin->id, $mouvement->point_id);

        // Le CMP vient du Service de valorisation, pas d'une écriture directe.
        $this->assertSame('32000.0000', (string) $article->refresh()->cout_moyen_pondere);
    }

    /**
     * Un article créé SANS stock d'ouverture ne produit aucun mouvement.
     *
     * Une entrée à zéro serait un mouvement sans objet dans la fiche de stock,
     * et le CMP se verrait affecter un coût pour une quantité nulle.
     *
     * Mutation : `bccomp(…) > 0` remplacé par `>= 0` → un mouvement de `0.00`
     * est apparu et le cas a rougi.
     */
    #[Test]
    public function creer_un_article_sans_stock_d_ouverture_ne_pose_aucun_mouvement(): void
    {
        Livewire::test(Stocks::class)
            ->call('nouvelArticle')
            ->set('libelle', 'Fournitures de bureau')
            ->set('categorieSaisie', 'Fournitures')
            ->set('uniteSaisie', 'unité')
            ->set('seuilAlerte', '2')
            ->set('pointOuverture', $this->magasin->id)
            ->set('valeurAchat', '500')
            ->set('stockOuverture', '0')
            ->call('enregistrerArticle')
            ->assertHasNoErrors();

        $article = Article::where('libelle', 'Fournitures de bureau')->firstOrFail();

        $this->assertSame(0, MouvementStock::where('article_id', $article->id)->count());
    }

    /**
     * L'édition ne touche ni le stock ni le CMP — ils se calculent.
     *
     * Mutation : `'cout_moyen_pondere' => $this->valeurAchat` ajouté au tableau
     * de `enregistrerArticle` → le CMP est passé de 1 000 à la valeur saisie et
     * le cas a rougi.
     */
    #[Test]
    public function modifier_un_article_ne_reecrit_ni_son_stock_ni_son_cout_moyen(): void
    {
        app(MouvementStockService::class)->entree(
            $this->riz->id,
            $this->magasin->id,
            '10.00',
            'Réception SODIS Bénin',
            '1000.00',
        );

        Livewire::test(Stocks::class)
            ->call('editerArticle', $this->riz->id)
            ->assertSet('libelle', 'Riz local (sac 50 kg)')
            ->set('libelle', 'Riz local (sac 25 kg)')
            ->set('seuilAlerte', '8')
            ->call('enregistrerArticle')
            ->assertHasNoErrors();

        $article = $this->riz->refresh();
        $this->assertSame('Riz local (sac 25 kg)', $article->libelle);
        $this->assertSame('8.00', (string) $article->seuil_alerte);
        $this->assertSame('1000.0000', (string) $article->cout_moyen_pondere);
        $this->assertSame(1, MouvementStock::where('article_id', $article->id)->count());
    }

    /* -------------------------------------------------------- mouvements */

    /**
     * Une entrée valorisée recalcule le coût moyen pondéré.
     *
     * 10 sacs à 1 000 F puis 10 à 2 000 F → CMP 1 500 F.
     *
     * Mutation : `coutUnitaire: $this->mvtCout === '' ? null : $this->mvtCout`
     * remplacé par `coutUnitaire: null` → le CMP est resté à 1 000 et le cas a
     * rougi.
     */
    #[Test]
    public function une_entree_valorisee_recalcule_le_cout_moyen_pondere(): void
    {
        app(MouvementStockService::class)->entree(
            $this->riz->id,
            $this->magasin->id,
            '10.00',
            'Première réception',
            '1000.00',
        );

        Livewire::test(Stocks::class)
            ->call('ouvrirMouvement', $this->riz->id)
            ->set('mvtType', 'entree')
            ->set('mvtPoint', $this->magasin->id)
            ->set('mvtQuantite', '10')
            ->set('mvtCout', '2000')
            ->set('mvtMotif', 'Réception SODIS Bénin')
            ->call('enregistrerMouvement')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame('1500.0000', (string) $this->riz->refresh()->cout_moyen_pondere);
    }

    /**
     * RG-06 — une sortie au-delà du disponible n'écrit RIEN et demande la
     * confirmation, avec le message chiffré du domaine.
     *
     * Mutation : le `catch (RuptureStockException)` remplacé par une relance →
     * le cas a rougi sur l'exception non attrapée, ce qui prouve que la branche
     * de confirmation est bien celle qui s'exécute.
     */
    #[Test]
    public function une_sortie_au_dela_du_disponible_demande_confirmation_sans_rien_ecrire(): void
    {
        app(MouvementStockService::class)->entree(
            $this->riz->id,
            $this->magasin->id,
            '2.00',
            'Réception',
            '1000.00',
        );

        $composant = Livewire::test(Stocks::class)
            ->call('ouvrirMouvement', $this->riz->id)
            ->set('mvtType', 'sortie')
            ->set('mvtPoint', $this->magasin->id)
            ->set('mvtQuantite', '5')
            ->set('mvtMotif', 'Consommation cuisine')
            ->call('enregistrerMouvement')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', 'rupture');

        $this->assertStringContainsString('2.00', (string) $composant->get('mvtRupture'));
        $this->assertStringContainsString('5.00', (string) $composant->get('mvtRupture'));

        // AUCUNE sortie n'a été écrite : la question précède le geste.
        $this->assertSame(0, MouvementStock::where('type_mouvement', 'sortie')->count());
    }

    /**
     * RG-06 — la rupture ASSUMÉE passe, et laisse une trace imputable.
     *
     * Mutation : `validationRupture: $forcer` remplacé par `false` dans
     * `deposerMouvement` → `forcerMouvement` a levé `RuptureStockException` et
     * le cas a rougi.
     */
    #[Test]
    public function la_rupture_forcee_est_ecrite_et_tracee(): void
    {
        app(MouvementStockService::class)->entree(
            $this->riz->id,
            $this->magasin->id,
            '2.00',
            'Réception',
            '1000.00',
        );

        Livewire::test(Stocks::class)
            ->call('ouvrirMouvement', $this->riz->id)
            ->set('mvtType', 'sortie')
            ->set('mvtPoint', $this->magasin->id)
            ->set('mvtQuantite', '5')
            ->set('mvtMotif', 'Consommation cuisine')
            ->call('enregistrerMouvement')
            ->call('forcerMouvement')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame(1, MouvementStock::where('type_mouvement', 'sortie')->count());

        $this->assertDatabaseHas('journal_audit', ['action' => 'rupture_stock_forcee']);
    }

    /**
     * Une perte passe par `perte()`, jamais par `sortie()` : une sortie suppose
     * une consommation identifiée, ce qui n'est justement pas le cas.
     *
     * Mutation (31/08/2026, rejouée puis annulée) : la condition
     * `$this->mvtType === 'perte'` de `deposerMouvement` remplacée par `false`
     * → le mouvement est sorti en `sortie` et le cas a rougi.
     */
    #[Test]
    public function une_perte_est_enregistree_avec_son_propre_type(): void
    {
        app(MouvementStockService::class)->entree(
            $this->riz->id,
            $this->magasin->id,
            '10.00',
            'Réception',
            '1000.00',
        );

        Livewire::test(Stocks::class)
            ->call('ouvrirMouvement', $this->riz->id)
            ->set('mvtType', 'perte')
            ->set('mvtPoint', $this->magasin->id)
            ->set('mvtQuantite', '2')
            ->set('mvtMotif', 'Casse au transport')
            ->call('enregistrerMouvement')
            ->assertHasNoErrors();

        $this->assertSame(1, MouvementStock::where('type_mouvement', 'perte')->count());
    }

    /**
     * Une quantité à zéro n'est pas un mouvement.
     */
    #[Test]
    public function une_quantite_nulle_est_refusee(): void
    {
        Livewire::test(Stocks::class)
            ->call('ouvrirMouvement', $this->riz->id)
            ->set('mvtPoint', $this->magasin->id)
            ->set('mvtQuantite', '0')
            ->set('mvtMotif', 'Rien')
            ->call('enregistrerMouvement')
            ->assertHasErrors(['mvtQuantite']);

        $this->assertSame(0, MouvementStock::count());
    }

    /* ------------------------------------------------------------- RBAC */

    /**
     * Le RBAC de la PWA, sur le canal Livewire — celui que le middleware
     * `ForcerLectureSeule` ne couvre PAS (PA-67).
     *
     * Le `receptionniste` a `M6 = 'L'` : il OUVRE la page, et chacune des
     * actions d'écriture lui est refusée, à l'ouverture comme à
     * l'enregistrement. La modale ne protège rien par elle-même — son état est
     * une propriété Livewire, modifiable depuis le navigateur.
     *
     * Mutation (31/08/2026, rejouée puis annulée) : la ligne
     * `$this->exigerEcriture(self::MODULE);` retirée de `Stocks::fermerModales()`
     * → ce geste-là a rendu 200 et le cas a rougi sur lui, après treize
     * assertions vertes. La mutation est délibérément posée sur l'action la
     * moins « dangereuse » de la liste : si même celle-là est gardée et
     * mesurée, les onze autres le sont aussi.
     */
    #[Test]
    public function un_role_en_lecture_seule_est_refuse_sur_chaque_action_d_ecriture(): void
    {
        $receptionniste = $this->utilisateur('receptionniste');
        $this->assertSame('L', $receptionniste->niveauSurModule('M6'));

        $this->actingAs($receptionniste);

        $gestes = [
            ['nouvelArticle', []],
            ['editerArticle', [$this->riz->id]],
            ['enregistrerArticle', []],
            ['ouvrirMouvement', [$this->riz->id]],
            ['enregistrerMouvement', []],
            ['forcerMouvement', []],
            ['ouvrirImport', []],
            ['lancerImport', []],
            ['telechargerModeleCsv', []],
            ['ouvrirExport', []],
            ['genererExport', []],
            ['fermerModales', []],
        ];

        foreach ($gestes as [$geste, $arguments]) {
            Livewire::test(Stocks::class)
                ->call($geste, ...$arguments)
                ->assertForbidden();
        }

        // Le refus est TRACÉ : un accès refusé qui ne laisse rien derrière lui
        // est indiscernable d'un accès qui n'a jamais eu lieu (RG-15).
        $this->assertGreaterThanOrEqual(
            count($gestes),
            JournalSecurite::where('type_evenement', 'acces_refuse_rbac')
                ->where('module_concerne', 'M6')
                ->count(),
        );
    }

    /**
     * Même contrat sur l'écran des inventaires — c'est celui qui régularise le
     * stock, donc celui où un défaut de RBAC coûte le plus cher.
     */
    #[Test]
    public function un_role_en_lecture_seule_est_refuse_sur_chaque_action_des_inventaires(): void
    {
        $this->actingAs($this->utilisateur('receptionniste'));

        $gestes = [
            ['ouvrirInventaire', []],
            ['ouvrirComptage', [$this->riz->id]],
            ['enregistrerComptage', []],
            ['demanderCloture', []],
            ['cloturer', []],
            ['ouvrirExport', []],
            ['genererExport', []],
            ['fermerModales', []],
        ];

        foreach ($gestes as [$geste, $arguments]) {
            Livewire::test(Inventaires::class)
                ->call($geste, ...$arguments)
                ->assertForbidden();
        }
    }

    /* ------------------------------------------------------- inventaires */

    /**
     * Ouvrir un inventaire ne crée AUCUNE ligne.
     *
     * `lignes_inventaire.quantite_constatee` est NOT NULL : une ligne posée à
     * l'ouverture porterait une valeur d'attente, et un article oublié
     * deviendrait indiscernable d'un article compté conforme — exactement ce
     * qu'un inventaire existe pour révéler. La version précédente de ce
     * composant en créait une par article.
     *
     * Mutation : une boucle `LigneInventaire::create()` remise dans
     * `ouvrirInventaire` → le cas a rougi sur `assertSame(0, …)`.
     */
    #[Test]
    public function ouvrir_un_inventaire_ne_cree_aucune_ligne_de_comptage(): void
    {
        Livewire::test(Inventaires::class)
            ->set('pointInventaire', $this->magasin->id)
            ->call('ouvrirInventaire')
            ->assertHasNoErrors();

        $inventaire = Inventaire::query()->firstOrFail();
        $this->assertSame($this->magasin->id, $inventaire->point_id);
        $this->assertSame(0, LigneInventaire::where('inventaire_id', $inventaire->id)->count());
    }

    /**
     * Le comptage fige le théorique et calcule l'écart — via le Service.
     *
     * Mutation : `quantiteComptee` forcée à `'0'` avant l'appel de `compter()`
     * → l'écart est passé de −2 à −10 et le cas a rougi.
     */
    #[Test]
    public function un_comptage_fige_le_theorique_et_calcule_l_ecart(): void
    {
        app(MouvementStockService::class)->entree(
            $this->riz->id,
            $this->magasin->id,
            '10.00',
            'Réception',
            '1000.00',
        );

        Livewire::test(Inventaires::class)
            ->set('pointInventaire', $this->magasin->id)
            ->call('ouvrirInventaire')
            ->set('onglet', 'inventaire')
            ->call('ouvrirComptage', $this->riz->id)
            ->set('quantiteComptee', '8')
            ->call('enregistrerComptage')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $ligne = LigneInventaire::query()->firstOrFail();
        $this->assertSame('10.00', (string) $ligne->quantite_theorique);
        $this->assertSame('8.00', (string) $ligne->quantite_constatee);
        $this->assertSame('-2.00', (string) $ligne->ecart);
    }

    /**
     * La clôture régularise par un MOUVEMENT, et un manquant est une PERTE.
     *
     * Corriger le stock par un `update` effacerait la raison de la correction.
     * Et un manquant constaté en `sortie` supposerait une consommation
     * identifiée — ce qui est justement ce qu'un inventaire ne sait pas.
     *
     * Mutation (31/08/2026, rejouée puis annulée) : l'appel
     * `$inventaires->cloturer($encours, partielAutorise: true)` de
     * `Inventaires::cloturer()` remplacé par un bilan fabriqué à zéro → aucun
     * mouvement de régularisation n'a été écrit et le cas a rougi. La mutation
     * porte sur le COMPOSANT, jamais sur `InventaireService` : le Service est
     * hors du périmètre de ce lot, et le casser même une seconde exposerait un
     * état incohérent aux autres travaux en cours.
     */
    #[Test]
    public function la_cloture_regularise_un_manquant_par_une_perte(): void
    {
        app(MouvementStockService::class)->entree(
            $this->riz->id,
            $this->magasin->id,
            '10.00',
            'Réception',
            '1000.00',
        );

        Livewire::test(Inventaires::class)
            ->set('pointInventaire', $this->magasin->id)
            ->call('ouvrirInventaire')
            ->set('onglet', 'inventaire')
            ->call('ouvrirComptage', $this->riz->id)
            ->set('quantiteComptee', '8')
            ->call('enregistrerComptage')
            ->call('demanderCloture')
            ->assertSet('etatFormulaire', 'cloture')
            ->call('cloturer')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $perte = MouvementStock::where('type_mouvement', 'perte')->firstOrFail();
        $this->assertSame('2.00', (string) $perte->quantite);

        // Le stock théorique retombe sur le constaté.
        $this->assertSame(
            '8.00',
            app(\App\Domain\Stocks\Services\StockTheoriqueService::class)
                ->stock($this->riz->id, $this->magasin->id),
        );
    }

    /* ----------------------------- entrée depuis la fiche article (PO) */

    /**
     * FAIRE ENTRER DU STOCK DEPUIS « MODIFIER L'ARTICLE » — PO 06/09/2026.
     *
     * ## Le geste qui manquait, et la forme qu'il ne devait PAS prendre
     *
     * `enregistrerArticle()` posait le stock d'ouverture à la CRÉATION
     * seulement : en édition il rendait la main AVANT le bloc de mouvement, et
     * les deux champs disparaissaient de la modale. Corriger un stock exigeait
     * de fermer la fiche et de rouvrir « Mouvement ».
     *
     * ⚠ La demande dit « modifier le stock », et ce qui est livré est une
     * ENTRÉE. Un champ qui écraserait le stock serait la deuxième des sept
     * règles du projet prise à revers — le stock est l'agrégation des
     * mouvements, et la modale continue de le rendre en LECTURE SEULE. Ce cas
     * tient les deux bouts : le mouvement existe, il est daté et signé, et le
     * stock s'en déduit.
     *
     * ## Mutation RÉELLEMENT exécutée puis annulée (06/09/2026)
     *
     * | Mutation | Résultat |
     * |---|---|
     * | `faireEntrerLeStock()` rend `null` sans appeler `entree()` | 1 failed — aucun mouvement, le stock reste à 10 |
     */
    #[Test]
    public function un_administrateur_fait_entrer_du_stock_depuis_la_fiche_article(): void
    {
        app(MouvementStockService::class)->entree(
            articleId: $this->riz->id,
            pointId: $this->magasin->id,
            quantite: '10',
            motif: 'Réception',
            coutUnitaire: '30000',
        );

        Livewire::test(Stocks::class)
            ->call('editerArticle', $this->riz->id)
            // Le point est PRÉ-SÉLECTIONNÉ sur le rattachement de l'article :
            // un défaut faux se valide sans se lire.
            ->assertSet('entreePoint', $this->magasin->id)
            ->set('entreeQuantite', '4')
            ->set('entreeCout', '35000')
            ->call('enregistrerArticle')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        // Le stock est CALCULÉ depuis les mouvements, jamais écrit.
        $this->assertSame(
            '14.00',
            app(\App\Domain\Stocks\Services\StockTheoriqueService::class)
                ->stock($this->riz->id, $this->magasin->id),
        );

        // Et l'entrée a traversé la valorisation : (10x30000 + 4x35000) / 14.
        $this->assertSame(
            0,
            bccomp((string) $this->riz->refresh()->cout_moyen_pondere, '31428.5714', 4),
            'Le coût moyen pondéré n\'a pas été recalculé par la valorisation.',
        );
    }

    /**
     * LES DEUX ROLES D'ADMINISTRATION passent, pas seulement l'administrateur.
     *
     * Confirmation du Product Owner (06/09/2026) : « non, juste l'administrateur
     * et le super admin ». Le cas voisin ne prouvait que le premier, et
     * `super_admin` n'a AUCUN compte dans le jeu de démonstration — son droit
     * sur M6 ne pouvait donc être constaté nulle part. Il l'a bien (`C`,
     * relevé sur le rôle), mais rien ne le tenait : le jour où la matrice le
     * passerait à `L`, le geste lui serait retiré en silence.
     *
     * ⚠ La boucle lit `User::ROLES_ADMINISTRATION`, la liste elle-même. Écrire
     * les deux rôles à la main ici en aurait fait une troisième copie — et un
     * rôle ajouté à la liste demain serait couvert sans qu'on y pense.
     */
    #[Test]
    public function les_deux_roles_d_administration_font_entrer_du_stock(): void
    {
        $this->assertSame(['administrateur', 'super_admin'], User::ROLES_ADMINISTRATION);

        app(MouvementStockService::class)->entree(
            articleId: $this->riz->id,
            pointId: $this->magasin->id,
            quantite: '10',
            motif: 'Réception',
            coutUnitaire: '30000',
        );

        $attendu = '10.00';

        foreach (User::ROLES_ADMINISTRATION as $role) {
            $compte = $this->utilisateur($role);

            // Le rôle ne dispense pas du droit sur le module : les deux sont
            // exigés, et ce cas le constate plutôt que de le supposer.
            $this->assertTrue($compte->estAdministrateur(), $role);
            $this->assertSame('C', $compte->niveauSurModule('M6'), $role);

            $this->actingAs($compte);

            Livewire::test(Stocks::class)
                ->call('editerArticle', $this->riz->id)
                ->set('entreeQuantite', '2')
                ->call('enregistrerArticle')
                ->assertHasNoErrors()
                ->assertSet('etatFormulaire', null);

            $attendu = bcadd($attendu, '2', 2);

            $this->assertSame(
                $attendu,
                app(\App\Domain\Stocks\Services\StockTheoriqueService::class)
                    ->stock($this->riz->id, $this->magasin->id),
                "Le role {$role} n'a pas pu faire entrer de stock depuis la fiche article.",
            );
        }
    }

    /**
     * Un rôle en écriture sur M6 qui n'administre PAS est refusé.
     *
     * Le bouton « Mouvement » de la ligne reste son chemin : il porte un motif
     * obligatoire et l'arbitrage de rupture (RG-06). Le raccourci de la fiche,
     * lui, valorise l'entrée et déplace le coût moyen pondéré, qui alimente le
     * poste de stocks au bilan — la directive le réserve à l'administrateur.
     *
     * ⚠ Le cas force la propriété SANS passer par l'écran : le bloc n'est pas
     * rendu pour ce rôle, et c'est précisément ce que l'ouverture ne protège
     * pas — `entreeQuantite` est une propriété Livewire, posée depuis le
     * navigateur.
     */
    #[Test]
    public function un_role_qui_n_administre_pas_ne_fait_pas_entrer_de_stock_depuis_la_fiche(): void
    {
        $magasinier = $this->utilisateur('magasinier');
        $this->assertSame('C', $magasinier->niveauSurModule('M6'));
        $this->assertFalse($magasinier->estAdministrateur());

        $this->actingAs($magasinier);

        Livewire::test(Stocks::class)
            ->call('editerArticle', $this->riz->id)
            ->set('entreeQuantite', '4')
            ->call('enregistrerArticle')
            ->assertForbidden();

        $this->assertSame(0, MouvementStock::count());
    }

    /**
     * Une fiche enregistrée SANS quantité ne pose aucun mouvement.
     *
     * Sans ce cas, annoncer « entrée enregistrée » sur chaque modification
     * serait un indicateur qui affirme un état qu'il n'a pas vérifié
     * (PA-59/60/61) — et le stock, lui, n'aurait pas bougé.
     */
    #[Test]
    public function modifier_la_fiche_sans_quantite_ne_pose_aucun_mouvement(): void
    {
        Livewire::test(Stocks::class)
            ->call('editerArticle', $this->riz->id)
            ->set('libelle', 'Riz local (sac 50 kg) — corrigé')
            ->call('enregistrerArticle')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $this->assertSame(0, MouvementStock::count());
        $this->assertSame('Riz local (sac 50 kg) — corrigé', $this->riz->refresh()->libelle);
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
