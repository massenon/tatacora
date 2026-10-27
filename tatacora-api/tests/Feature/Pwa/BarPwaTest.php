<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use App\Pwa\Livewire\Bar\CarteBar;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Pwa\Concerns\LitUnDocumentTelecharge;
use Tests\TestCase;

/**
 * Carte du bar (M5) — vue maîtresse (PA-183) :
 * `resources/views/pwa/bar/carte.blade.php`.
 *
 * ## Ce que ce fichier prouve, et pourquoi chaque cas existe
 *
 * 1. **Le taux de conversion arrive en base.** C'était le défaut bloquant : la
 *    modale le demandait en champ obligatoire, l'affichait en aperçu, et le
 *    composant n'écrivait que `article_id`. Un casier de 24 et une bouteille à
 *    l'unité produisaient le même enregistrement.
 * 2. **Un ratio de 24 déduit 1/24 d'unité de stock par vente**, et le stock
 *    vendable en montre 24 fois plus. Aucun test ne touchait ce chemin.
 * 3. **Le retrait de la carte est PERSISTÉ**, avec les codes du maître, et
 *    plus aucune clé de session.
 * 4. **Toute écriture exige `M5 = C`**, et le refus est tracé.
 *
 * ## Mutations RÉELLEMENT rejouées le 31/08/2026 — chaque cas prouvé non vide
 *
 * Trois mutations, exécutées puis annulées, toutes sur des fichiers de ce lot
 * (aucune sur `app/Domain`, que sept agents parcourent en parallèle) :
 *
 * | Mutation | Cas qui rougit | Résultat |
 * |---|---|---|
 * | `CarteBar::rattacherAuStock()` passe `'1'` au lieu de la valeur saisie — le défaut d'origine | `le_taux_de_conversion_saisi_est_reellement_enregistre` | 1 failed |
 * | `EcranDeCarte::enregistrerRetraitDeLaCarte()` écrit `'rupture'` au lieu du motif saisi | `le_retrait_est_persiste_en_base_avec_les_codes_du_maitre` | 1 failed |
 * | `EcranDeCarte::ouvrirLienAuStock()` pose `etatFormulaire` en direct au lieu d'appeler `ouvrirFormulaire()`, donc sans garde | `un_role_en_lecture_seule_ne_peut_pas_lier_une_boisson_au_stock` | 1 failed |
 *
 * @see EF-M5-02 Carte des boissons
 * @see RG-05 Sortie de stock automatique
 */
final class BarPwaTest extends TestCase
{
    use LitUnDocumentTelecharge;
    use RefreshDatabase;

    private Article $casierBeninoise;

    private Article $casierSucrerie;

    private PointStockage $bar;

    /** La boisson au tarif PROVISOIRE — PA-161 (b). */
    private CarteBoisson $ekuProvisoire;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    /* ----------------------------------------------------------- la page */

    #[Test]
    public function la_page_est_reellement_servie(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/bar/carte')->assertOk()->getContent();

        $this->assertStringContainsString('<title>Carte du bar — LogiReStock — TATACORA AFRIQUE</title>', $html);
        $this->assertSame(1, substr_count($html, '<h1 '), 'Un seul <h1> par page.');
        $this->assertStringContainsString(
            '<h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">Carte du bar</h1>',
            $html,
        );
        $this->assertStringContainsString('<body data-module="M5"', $html);

        // Le sous-titre du MAÎTRE (l.34), pas celui du restaurant : la vue
        // livrée affichait « Composition, disponibilité du jour… ».
        $this->assertStringContainsString('une 33 cl ne sort pas du casier de 66 cl', $html);
        $this->assertStringNotContainsString('Composition, disponibilité du jour', $html);

        $this->assertStringContainsString('Carte du jour', $html);
        $this->assertStringContainsString('Couverture du stock', $html);
        $this->assertStringContainsString('Béninoise 66 cl', $html);
    }

    #[Test]
    public function un_profil_sans_droit_sur_m5_est_refuse(): void
    {
        $acheteur = $this->utilisateur('achats');
        $this->assertSame('-', $acheteur->niveauSurModule('M5'), 'La matrice a changé : ce cas ne vérifie plus rien.');

        $this->actingAs($acheteur);
        $this->get('/pwa/bar/carte')->assertForbidden();
    }

    #[Test]
    public function un_invite_est_redirige_vers_le_formulaire_de_connexion(): void
    {
        $this->get('/pwa/bar/carte')->assertRedirect(route('pwa.connexion'));
    }

    /* ------------------------------------------------- le taux qui manquait */

    /**
     * LE DÉFAUT BLOQUANT C1 : la valeur saisie arrive en base.
     *
     * `unites_vendables_par_unite_stock` est le nombre d'unités VENDABLES
     * contenues dans une unité de stock — 24 pour un casier. Le composant
     * n'écrivait que `article_id`, et la colonne n'existait pas.
     */
    #[Test]
    public function le_taux_de_conversion_saisi_est_reellement_enregistre(): void
    {
        $this->jeuDeDonnees();
        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteBar::class)
            ->call('ouvrirLienAuStock', $boisson->id)
            ->assertSet('etatFormulaire', 'lien')
            ->set('articleStockId', $this->casierSucrerie->id)
            ->set('unitesVendablesParUniteStock', '24')
            ->call('enregistrerLienAuStock')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $boisson->refresh();

        $this->assertSame($this->casierSucrerie->id, $boisson->article_id);
        $this->assertSame(
            0,
            bccomp((string) $boisson->unites_vendables_par_unite_stock, '24', 4),
            'Le conditionnement saisi a été jeté : un casier de 24 et une bouteille à l\'unité '
            .'produiraient la même décrémentation.',
        );
    }

    /**
     * RG-05 — un ratio de 24 déduit 1/24 d'unité de stock par vente.
     *
     * C'est le test qui manquait. L'inverser vide le stock 24 fois trop vite,
     * et le maître avertit lui-même de ce piège (`carte-module.js` l.119-126).
     */
    #[Test]
    public function un_ratio_de_24_deduit_un_vingt_quatrieme_d_unite_de_stock_par_vente(): void
    {
        $this->jeuDeDonnees();

        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();
        $boisson->update(['unites_vendables_par_unite_stock' => '24.0000']);

        // `bcdiv` TRONQUE, il n'arrondit pas : 1/24 = 0,041666… rend 0,0416.
        // C'est la valeur réellement écrite dans `mouvements_stock`, et
        // l'assertion porte sur elle plutôt que sur l'arrondi mathématique —
        // un test qui attendrait 0,0417 décrirait un code qui n'existe pas.
        $this->assertSame('0.0416', $boisson->refresh()->stockConsommePour('1'));

        // Et un casier entier vendu retire EXACTEMENT une unité de stock :
        // passer par le facteur unitaire puis multiplier donnerait 1,0008.
        $this->assertSame('1.0000', $boisson->stockConsommePour('24'));
    }

    /**
     * Le pendant du cas précédent, côté restaurant : un ratio ABSENT ne déduit
     * rien, et il le DIT plutôt que de retirer une unité par défaut.
     */
    #[Test]
    public function un_ratio_absent_ne_deduit_rien_et_le_dit(): void
    {
        $plat = new \App\Domain\Restaurant\Models\Plat([
            'libelle' => 'Poulet DG',
            'prix_vente' => '4500.00',
        ]);

        $this->assertFalse($plat->aUnLienDirectAuStock());

        $this->expectException(\RuntimeException::class);
        // Le message NOMME le plat : « une unité par défaut » serait un chiffre
        // inventé sur une donnée de stock.
        $this->expectExceptionMessage('Poulet DG');

        $plat->stockConsommePour('1');
    }

    /**
     * Le stock vendable est celui du POINT BAR, exprimé en unités VENDABLES.
     *
     * Le jeu pose 2 casiers de 24 au bar et 100 au magasin : la réponse est
     * 48 bouteilles vendables. Un composant qui lirait tous points confondus
     * rendrait 2 448 — vendable au comptoir ce qui dort au magasin.
     */
    #[Test]
    public function le_stock_vendable_est_celui_du_point_bar_et_compte_en_unites_vendables(): void
    {
        $this->jeuDeDonnees();

        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();
        $boisson->update(['unites_vendables_par_unite_stock' => '24.0000']);

        $this->actingAs($this->utilisateur('administrateur'));
        $html = (string) $this->get('/pwa/bar/carte')->assertOk()->getContent();

        $this->assertStringContainsString('>48</span>', $html);
        $this->assertStringNotContainsString('>2448</span>', $html);
        // La conversion est rendue À L'ENDROIT : « 24 par bouteille », jamais
        // « 1/24 de bouteille » (maître, carte-module.js l.135-143).
        $this->assertStringContainsString('24 par bouteille', $html);
    }

    /* ------------------------------------------------ la disponibilité C2 */

    /**
     * LE DÉFAUT BLOQUANT C2 : le retrait est en BASE, avec les codes du maître.
     *
     * `Session::put('bar_boissons_indisponibles', …)` laissait revenir un
     * article retiré à l'expiration de la session, et aucun autre poste ne le
     * voyait retiré. Les codes divergeaient de surcroît (`hors_saison` /
     * `retrait` au lieu de `saison` / `retire`).
     */
    #[Test]
    public function le_retrait_est_persiste_en_base_avec_les_codes_du_maitre(): void
    {
        $this->jeuDeDonnees();
        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteBar::class)
            ->call('ouvrirRetraitDeLaCarte', $boisson->id)
            ->set('motifIndisponibilite', 'saison')
            ->set('commentaireIndisponibilite', 'Fin de saison sèche')
            ->call('enregistrerRetraitDeLaCarte')
            ->assertHasNoErrors();

        $ligne = IndisponibiliteCarte::where('boisson_id', $boisson->id)->firstOrFail();

        $this->assertSame('saison', $ligne->motif);
        $this->assertSame('Fin de saison sèche', $ligne->commentaire);
        $this->assertNull($ligne->date_retour_disponibilite);
        $this->assertTrue($ligne->estTemporaire());

        // Plus aucune donnée métier en session — c'est ce que le composant
        // faisait, et c'est ce que l'architecture interdit.
        $this->assertFalse(session()->has('bar_boissons_indisponibles'));

        // Les trois codes du maître, et rien d'autre.
        $this->assertSame(['rupture', 'saison', 'retire'], array_keys(IndisponibiliteCarte::MOTIFS));
    }

    /**
     * Remettre à la carte LÈVE l'indisponibilité, il ne l'efface pas :
     * effacer la ligne effacerait l'historique des ruptures, sur lequel se
     * décide un réapprovisionnement.
     */
    #[Test]
    public function remettre_a_la_carte_leve_l_indisponibilite_sans_effacer_la_ligne(): void
    {
        $this->jeuDeDonnees();
        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        $composant = Livewire::test(CarteBar::class)
            ->call('ouvrirRetraitDeLaCarte', $boisson->id)
            ->set('motifIndisponibilite', 'rupture')
            ->call('enregistrerRetraitDeLaCarte');

        $composant->call('remettreALaCarte', $boisson->id)->assertHasNoErrors();

        $this->assertSame(1, IndisponibiliteCarte::where('boisson_id', $boisson->id)->count());
        $this->assertNotNull(
            IndisponibiliteCarte::where('boisson_id', $boisson->id)->firstOrFail()->date_retour_disponibilite,
        );
    }

    /* ------------------------------------------------------------- C4 RBAC */

    /**
     * Un rôle `M5 = L` n'écrit pas — et le refus est TRACÉ.
     *
     * `comptable` a `M5 = L` : l'API lui refuse l'écriture en 403, et le
     * navigateur ne doit pas lui donner ce que l'API lui refuse (PA-67).
     */
    #[Test]
    public function un_role_en_lecture_seule_ne_peut_pas_lier_une_boisson_au_stock(): void
    {
        $this->jeuDeDonnees();
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M5'));

        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();
        $avant = $boisson->article_id;

        $this->actingAs($comptable);

        Livewire::test(CarteBar::class)
            ->call('ouvrirLienAuStock', $boisson->id)
            ->assertForbidden();

        $this->assertSame($avant, $boisson->refresh()->article_id);

        $this->assertTrue(
            JournalSecurite::where('type_evenement', 'acces_refuse_rbac')
                ->where('module_concerne', 'M5')
                ->where('utilisateur_id', $comptable->id)
                ->exists(),
            'Le refus RBAC n\'est pas tracé : un refus muet ne se constate nulle part.',
        );
    }

    /**
     * L'enregistrement est gardé LUI AUSSI : l'état de la modale est une
     * propriété Livewire, modifiable depuis le navigateur. L'ouverture ne
     * protège rien.
     */
    #[Test]
    public function l_enregistrement_du_lien_est_garde_meme_sans_passer_par_l_ouverture(): void
    {
        $this->jeuDeDonnees();
        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();
        $avant = $boisson->article_id;

        $this->actingAs($this->utilisateur('comptable'));

        Livewire::test(CarteBar::class)
            ->set('articleCibleId', $boisson->id)
            ->set('articleStockId', $this->casierSucrerie->id)
            ->set('unitesVendablesParUniteStock', '24')
            ->call('enregistrerLienAuStock')
            ->assertForbidden();

        $this->assertSame($avant, $boisson->refresh()->article_id);
    }

    /* ---------------------------------------------------------- documents */

    /**
     * C7 — la fiche des prix n'est JAMAIS vide, et elle écarte les non tarifés
     * en le DISANT : un tarif absent devient négociable au comptoir.
     */
    #[Test]
    public function la_fiche_des_prix_est_reellement_generee_et_n_est_pas_vide(): void
    {
        $this->jeuDeDonnees();

        $this->actingAs($this->utilisateur('administrateur'));

        $composant = Livewire::test(CarteBar::class)
            ->call('imprimerFichePrix');

        $contenu = $this->contenuTelecharge($composant);

        $this->assertStringStartsWith('%PDF', $contenu, 'La fiche des prix n\'est pas un PDF.');

        // ⚠ La taille ne suffit PAS : un PDF d'en-tête seul pèse déjà 2 Ko, et
        // c'est exactement la « page blanche » que ce cas existe pour attraper.
        // Le contenu est donc RELU, flux décompressés.
        $texte = $this->texteDuPdf($contenu);

        // ⚠ Le gabarit pose `text-transform: uppercase` sur le titre et sur
        // chaque catégorie : dompdf applique la transformation AVANT d'écrire
        // le flux. Chercher « Fiche des prix » dans le PDF répondrait
        // « absente » sur un document qui la porte.
        $this->assertStringContainsString('FICHE DES PRIX', mb_strtoupper($texte));
        $this->assertStringContainsString('66 cl', $texte, 'Aucune boisson sur la fiche des prix.');
        // Le titre de catégorie du gabarit — il était rendu « 2. Locale », la
        // balise `<h2>` ayant perdu ses chevrons à l'écriture : le style
        // existait, la balise non.
        $this->assertStringContainsString('LOCALE', mb_strtoupper($texte));
        $this->assertStringNotContainsString('2. Locale', $texte);
    }

    /**
     * PA-119 — l'export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre.
     * Une liste vide se REFUSE plutôt que de produire une page qu'on croirait
     * complète.
     */
    #[Test]
    public function l_export_refuse_une_liste_vide_et_dit_son_filtre_sinon(): void
    {
        $this->jeuDeDonnees();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteBar::class)
            ->set('recherche', 'aucune-boisson-ne-porte-ce-nom')
            ->call('genererExport')
            ->assertHasErrors('formatExport');

        $this->actingAs($this->utilisateur('administrateur'));

        $composant = Livewire::test(CarteBar::class)
            ->set('categorie', 'maison')
            ->call('genererExport');

        $contenu = $this->contenuTelecharge($composant);
        $this->assertStringStartsWith('%PDF', $contenu);
        $this->assertGreaterThan(3000, strlen($contenu));

        // PA-119 : le document DIT son filtre. Sans cette ligne, quelqu'un qui
        // filtre puis exporte envoie au comptable un document qu'il croit
        // avoir vérifié.
        $this->assertStringContainsString('Maison', $this->texteDuPdf($contenu));
    }

    /**
     * Un rôle en LECTURE exporte et imprime — c'est le pendant du cas de refus
     * juste au-dessus, et les deux se lisent ensemble.
     *
     * Un export ne produit rien de neuf : il rend sur un autre papier ce que
     * l'écran affiche déjà. Le `barman` a `M5 = C`, mais le `comptable`, en
     * `L`, doit pouvoir sortir la fiche des prix du bar sans obtenir un 403 —
     * la garde d'écriture ne s'applique qu'aux écritures (31/08/2026).
     */
    #[Test]
    public function un_role_en_lecture_seule_exporte_et_imprime_la_fiche_des_prix(): void
    {
        $this->jeuDeDonnees();
        $comptable = $this->utilisateur('comptable');
        $this->assertSame('L', $comptable->niveauSurModule('M5'));

        $this->actingAs($comptable);

        $fiche = Livewire::test(CarteBar::class)
            ->call('imprimerFichePrix');

        $this->assertStringStartsWith('%PDF', $this->contenuTelecharge($fiche));

        $this->actingAs($comptable);

        $export = Livewire::test(CarteBar::class)
            ->call('genererExport');

        $this->assertStringStartsWith('%PDF', $this->contenuTelecharge($export));
    }

    /* --------------------------------------------- la mesure des modales */

    /**
     * C3 — « Lier au stock » et « Retirer de la carte du jour » a la MESURE du
     * maitre, pas seulement au mot.
     *
     * Sept ecarts de geometrie coexistaient sur la premiere, et aucun ne se
     * voyait isolement : largeur 540 px au lieu de 560, titre `text-lg` au lieu
     * de `text-base`, sous-titre `text-[13px]` au lieu de `text-[12px]`,
     * en-tete `py-5` au lieu de `py-4`, champs `rounded-xl px-3.5` au lieu de
     * `rounded-lg px-3`, boutons `px-5 py-2.5 rounded-xl` au lieu de
     * `px-4 py-2 rounded-lg`, et un pied DANS le corps au lieu d'une barre.
     *
     * ⚠ `style="display:flex"` est le point qui ne pardonne pas :
     * `.overlay-modale` est `opacity:0; pointer-events:none` par defaut
     * (app.css l.114-117). Sans lui, la modale est dans le DOM, invisible et
     * inerte — et un test de rendu la trouverait pourtant.
     */
    #[Test]
    public function la_modale_de_lien_porte_la_geometrie_du_maitre(): void
    {
        $this->jeuDeDonnees();
        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        $html = Livewire::test(CarteBar::class)
            ->call('ouvrirLienAuStock', $boisson->id)
            // Le casier de Beninoise : 2 casiers AU BAR, 100 au magasin.
            ->set('articleStockId', $this->casierBeninoise->id)
            ->set('unitesVendablesParUniteStock', '24')
            ->html();

        // Le chassis, et son etat d'ouverture.
        $this->assertStringContainsString('class="overlay-modale no-print" style="display:flex"', $html);
        $this->assertStringContainsString('style="max-width:560px"', $html);

        // En-tete : `px-6 py-4`, titre `text-base`, sous-titre `text-[12px]`.
        $this->assertStringContainsString('flex items-center justify-between px-6 py-4 border-b border-slate-100', $html);
        $this->assertStringContainsString('<h2 class="text-base font-bold" style="color:var(--navy)">Lier au stock</h2>', $html);
        $this->assertStringContainsString('<p class="text-[12px] text-slate-500 mt-0.5">', $html);

        // Champs : `rounded-lg px-3 py-2.5`, jamais `rounded-xl px-3.5`.
        $this->assertStringContainsString('border border-slate-300 rounded-lg px-3 py-2.5', $html);
        $this->assertStringNotContainsString('rounded-xl px-3.5 py-2.5', $html);

        // Boutons : `text-[13px] px-4 py-2 rounded-lg`.
        $this->assertStringContainsString('text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold', $html);
        $this->assertStringNotContainsString('px-5 py-2.5 rounded-xl', $html);

        // Apercu : encadre SANS FOND, `p-3`, `text-[12px]`.
        $this->assertStringContainsString('border border-slate-200 rounded-lg p-3 text-[12px]', $html);
        $this->assertStringNotContainsString('bg-slate-50/60', $html);

        // La recherche du maitre, avec SON invite.
        $this->assertStringContainsString('Rechercher un article de stock…', $html);

        // Et l'apercu montre CE QUI SERA ENREGISTRE, sur le stock DU BAR :
        // 2 casiers x 24 = 48 bouteilles vendables (100 casiers dorment au
        // magasin et n'y entrent pas).
        $this->assertStringContainsString('48 × Béninoise 66 cl', $html);
    }

    #[Test]
    public function la_modale_de_retrait_porte_la_geometrie_et_les_mots_du_maitre(): void
    {
        $this->jeuDeDonnees();
        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        $html = Livewire::test(CarteBar::class)
            ->call('ouvrirRetraitDeLaCarte', $boisson->id)
            ->html();

        $this->assertStringContainsString('style="max-width:480px"', $html);
        $this->assertStringContainsString('<h2 class="text-base font-bold" style="color:var(--navy)">Retirer de la carte du jour</h2>', $html);

        // La note d'aide du maitre, a SA mesure.
        $this->assertStringContainsString(
            'text-[11px] text-slate-500 bg-slate-50 border border-slate-200 rounded-lg p-2.5',
            $html,
        );
        $this->assertStringNotContainsString('bg-slate-50/80 rounded-xl p-3.5', $html);

        // Le copywriting exact, et l'invite de commentaire du maitre.
        $this->assertStringContainsString('Ex. livraison attendue jeudi', $html);
        $this->assertStringContainsString('est une décision commerciale', $html);

        // Les trois motifs, avec leur caractere temporaire RENDU — c'est tout
        // l'objet du paragraphe d'aide du maitre.
        $this->assertStringContainsString('Rupture du jour — revient au réapprovisionnement', $html);
        $this->assertStringContainsString('Retiré de la carte — décision commerciale', $html);
    }

    /* ------------------------------------------------------------- refus */

    /**
     * Ce qui n'est pas rendu est NOMMÉ. Un motif de refus qu'on ne voit plus
     * redevient un oubli (PA-144).
     */
    /**
     * ⚠ Ce cas s'appelait `les_trois_refus_du_bar_sont_nommes_a_l_ecran` et il
     * serait resté VERT POUR LA MAUVAISE RAISON.
     *
     * Sa troisième assertion cherchait la chaîne « Prix provisoire » dans la
     * page, comme preuve que le refus était nommé. Depuis PA-161 (b), cette
     * chaîne est celle du FILTRE et de l'indicateur — le refus a disparu, la
     * fonction est livrée, et le test aurait continué de passer en affirmant
     * l'inverse de ce qui se produit. C'est le défaut que ce dépôt traque :
     * un contrôle qui affirme un état qu'il n'a pas vérifié.
     *
     * Il vérifie donc désormais les deux refus qui SUBSISTENT, et l'ABSENCE du
     * troisième motif — mot pour mot, pas par sa présence approximative.
     */
    #[Test]
    public function les_deux_refus_du_bar_sont_nommes_et_le_troisieme_a_disparu(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/bar/carte')->assertOk()->getContent();

        // ## Converti au nouveau contrat le 31/08/2026 (directive PO)
        //
        // Ce cas exigeait les refus AFFICHÉS — « cartes_boisson.article_id
        // est NOT NULL » rendu à l'utilisateur. La directive du Product Owner
        // a supprimé toute section de refus des écrans : la déclaration vit
        // dans le CODE, l'écran reste propre. Le cas tient désormais les DEUX
        // moitiés — sans la seconde, supprimer la déclaration en même temps
        // que la section passerait inaperçu, et le refus redeviendrait un
        // oubli (PA-144).

        // 1. L'écran ne porte ni vocabulaire de schéma ni section de refus —
        //    un réceptionniste n'a rien à faire d'une colonne SQL.
        $this->assertStringNotContainsString('NOT NULL', $html);
        $this->assertStringNotContainsString('ne portent de colonne les portant', $html);

        // 2. Aucun contrôle inerte : « Délier » est impossible au bar (le
        //    lien se REMPLACE), son action n'est pas câblée.
        $this->assertStringNotContainsString('ouvrirRetraitDuLien', $html);

        // 3. Et la déclaration EXISTE dans le code qui porte la page.
        $sources = file_get_contents(resource_path('views/pwa/bar/carte.blade.php'))
            .file_get_contents(app_path('Pwa/Livewire/Bar/CarteBar.php'));
        $this->assertStringContainsString('article_id` est NOT NULL', $sources);
        $this->assertStringContainsString('Rapprocher', $sources);
    }

    /* -------------------------------------------- PA-161 (b) — les marques */

    /**
     * maitre `carte-module.js` l.108-109 — la marque « provisoire » est rendue
     * SOUS le prix, AU PIXEL, et seulement sur la ligne qui la porte.
     *
     * Prouve par mutation (02/09/2026) : retirer le bloc `@if
     * ($ligne['prix_provisoire'])` de `pwa/carte/corps.blade.php` rougit sur la
     * première assertion.
     */
    #[Test]
    public function la_marque_provisoire_est_rendue_sous_le_prix_de_la_ligne_concernee(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/bar/carte')->assertOk()->getContent();

        // Les classes sont celles du maitre, au caractere pres : `text-[10px]`
        // est une valeur entre crochets, pas l'echelle nommee de Tailwind.
        $this->assertStringContainsString(
            '<div class="text-[10px] text-red-600 font-semibold">provisoire</div>',
            $html,
            'La marque « provisoire » du maître n\'est pas rendue avec ses classes.',
        );

        // UNE seule ligne la porte : une marque posée sur toute la carte ne
        // dirait plus rien (c'est ce que faisait le cast manquant sur le
        // `tinyint(1)`, dont « 0 » est vrai en PHP).
        $this->assertSame(
            1,
            substr_count($html, '>provisoire</div>'),
            'Seule la boisson au tarif provisoire doit porter la marque.',
        );

        // Et l'indicateur du bandeau compte la même chose.
        $this->assertStringContainsString('Prix provisoires', $html);
    }

    /**
     * maitre `m5-bar-carte.html` l.71 — le filtre « Prix provisoire » restreint
     * REELLEMENT la liste.
     *
     * Un filtre annoncé qui n'applique rien est pire que pas de filtre : le
     * lecteur croit la liste réduite.
     */
    #[Test]
    public function le_filtre_prix_provisoire_ne_rend_que_les_tarifs_a_valider(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/bar/carte?etat=provisoire')->assertOk()->getContent();

        $this->assertStringContainsString('carte-'.$this->ekuProvisoire->id, $html);
        $this->assertStringNotContainsString('Jus d&#039;ananas maison', $html);
    }

    /**
     * PA-161 (b) — LE CAS QUI A MOTIVE L'ARBITRAGE : la fiche des prix REMISE
     * AU CLIENT porte la marque.
     *
     * Un prix provisoire imprimé sans sa marque devient un tarif ferme,
     * opposable au comptoir. C'est la version papier de PA-61 : un document
     * qui affirme une certitude que personne n'a établie. Le maître ne
     * l'imprime pas (`assets/js/fiche-prix.js`) ; l'écart est assumé, et c'est
     * lui le livrable.
     *
     * ⚠ Le PDF est décompressé avant lecture : dompdf compresse ses flux, et
     * une recherche de chaîne sur l'octet brut passerait à vide — donc au
     * vert, quoi qu'il arrive.
     *
     * Prouve par mutation (02/09/2026) : retirer le bloc `@if
     * ($art->prix_provisoire)` de `pdf/fiche-prix.blade.php` rougit sur les
     * deux assertions.
     */
    #[Test]
    public function la_fiche_des_prix_remise_au_client_porte_la_marque_provisoire(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $composant = Livewire::test(CarteBar::class)->call('imprimerFichePrix');

        $texte = $this->texteDuPdf($this->contenuTelecharge($composant));

        $this->assertStringContainsString(
            'prix provisoire',
            $texte,
            'La fiche des prix remise au client doit signaler un tarif provisoire en regard du prix.',
        );

        $this->assertStringContainsString(
            'PROVISOIRE',
            $texte,
            'L\'avertissement de pied de fiche doit compter les tarifs provisoires imprimés.',
        );
    }

    /**
     * Toute action `wire:click` de la page correspond à une méthode publique
     * réellement déclarée — un bouton qui appelle une méthode absente échoue
     * en production, jamais au rendu.
     */
    #[Test]
    public function chaque_action_de_la_page_correspond_a_une_methode_publique(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $html = (string) $this->get('/pwa/bar/carte')->assertOk()->getContent();

        $this->assertActionsResolubles($html, CarteBar::class);
    }

    /* ----------------------------------------------------- auxiliaires */

    /**
     * Les actions `wire:click` d'un rendu, confrontées aux méthodes publiques.
     */
    private function assertActionsResolubles(string $html, string $composant): void
    {
        preg_match_all('/wire:click="([a-zA-Z_][a-zA-Z0-9_]*)\(/', $html, $appels);

        $publiques = array_map(
            static fn (\ReflectionMethod $m): string => $m->getName(),
            (new \ReflectionClass($composant))->getMethods(\ReflectionMethod::IS_PUBLIC),
        );

        // Les composants IMBRIQUES de la coquille (cloche de notifications,
        // recherche globale — audit PO du 01/09/2026) rendent leurs propres
        // actions sur CHAQUE page : elles se resolvent sur eux, jamais sur le
        // composant de page.
        foreach ([
            \App\Pwa\Livewire\Transverse\ClocheNotifications::class,
            \App\Pwa\Livewire\Transverse\RechercheGlobale::class,
        ] as $imbrique) {
            foreach ((new \ReflectionClass($imbrique))->getMethods(\ReflectionMethod::IS_PUBLIC) as $m) {
                $publiques[] = $m->getName();
            }
        }

        $this->assertNotEmpty($appels[1], 'Aucune action relevée : le contrôle serait vert à vide.');

        foreach (array_unique($appels[1]) as $appel) {
            $this->assertContains(
                $appel,
                $publiques,
                "Le bouton appelle `{$appel}()`, qui n'est pas une méthode publique de {$composant}.",
            );
        }
    }

    /*
     * `contenuTelecharge()` et `texteDuPdf()` vivaient ICI jusqu'au
     * 03/09/2026 ; ils sont passés dans `LitUnDocumentTelecharge` quand
     * `RestaurantPwaTest` a eu besoin des deux mêmes outils pour ses cas
     * d'export. Deux décompresseurs de PDF auraient fini par diverger, et
     * celui qui aurait vieilli déclarerait « absente » une chaîne que le
     * document porte : un contrôle vert à l'envers.
     *
     * Livewire capte la réponse d'un `streamDownload` et la range en base64
     * dans ses effets (`SupportFileDownloads`) : le document est donc bel et
     * bien GÉNÉRÉ pendant le test, pas seulement promis. « Le code livré a été
     * réellement exécuté, pas seulement relu. »
     */

    private function jeuDeDonnees(): void
    {
        $this->actingAs($this->utilisateur('administrateur'));

        $this->bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
        $magasin = PointStockage::create(['libelle' => 'Magasin général', 'type' => 'magasin']);

        $this->casierBeninoise = Article::create([
            'libelle' => 'Béninoise 66 cl (casier)',
            'categorie' => 'Boissons',
            'unite_mesure' => 'bouteille',
            'seuil_alerte' => '6.00',
            'seuil_reappro' => '24.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $this->casierSucrerie = Article::create([
            'libelle' => 'Sucrerie 66 cl (casier)',
            'categorie' => 'Boissons',
            'unite_mesure' => 'bouteille',
            'seuil_alerte' => '6.00',
            'seuil_reappro' => '24.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        $jus = Article::create([
            'libelle' => 'Ananas frais',
            'categorie' => 'Denrées',
            'unite_mesure' => 'litre',
            'seuil_alerte' => '2.00',
            'seuil_reappro' => '10.00',
            'cout_moyen_pondere' => '0.0000',
        ]);

        /** @var MouvementStockService $mouvements */
        $mouvements = app(MouvementStockService::class);

        // 2 casiers au BAR, 100 au MAGASIN : la carte doit rendre le bar seul.
        $mouvements->entree($this->casierBeninoise->id, $this->bar->id, '2.00', 'Dotation bar', '450.00');
        $mouvements->entree($this->casierBeninoise->id, $magasin->id, '100.00', 'Réception SOBEBRA', '450.00');
        // La sucrerie n'entre JAMAIS au bar : rupture mesurée.
        $mouvements->entree($this->casierSucrerie->id, $magasin->id, '48.00', 'Réception SOBEBRA', '300.00');
        $mouvements->entree($jus->id, $this->bar->id, '10.00', 'Préparation du jour', '500.00');

        CarteBoisson::create([
            'article_id' => $this->casierBeninoise->id,
            'unites_vendables_par_unite_stock' => '1.0000',
            'libelle' => 'Béninoise 66 cl',
            'categorie' => 'locale',
            'prix_vente' => '800.00',
        ]);

        CarteBoisson::create([
            'article_id' => $this->casierSucrerie->id,
            'unites_vendables_par_unite_stock' => '1.0000',
            'libelle' => 'Sucrerie 66 cl',
            'categorie' => 'locale',
            'prix_vente' => '700.00',
        ]);

        // PA-161 (b) — une boisson au TARIF PROVISOIRE, comme les six du
        // maitre : l'ardoise du bar ne donnait aucun montant pour EKU 66 cl,
        // et le prix pose l'a ete « faute de releve »
        // (`referentiel-carte.js` l.22-31). C'est la ligne qui doit porter la
        // marque partout ou son prix s'imprime.
        $this->ekuProvisoire = CarteBoisson::create([
            'article_id' => $this->casierBeninoise->id,
            'unites_vendables_par_unite_stock' => '1.0000',
            'libelle' => 'EKU 66 cl',
            'categorie' => 'importee',
            'prix_vente' => '1200.00',
            'prix_provisoire' => true,
        ]);

        CarteBoisson::create([
            'article_id' => $jus->id,
            'unites_vendables_par_unite_stock' => '1.0000',
            'libelle' => 'Jus d\'ananas maison',
            'categorie' => 'maison',
            'prix_vente' => '1000.00',
        ]);
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

    // =================================================================
    // Modifier le prix — directive PO du 02/09/2026
    // =================================================================

    /**
     * Le geste ET sa trace, dans la meme execution : le nouveau prix est
     * persiste par `CarteBoissonService::modifier()` et l'Observer consigne
     * la ligne d'historique que la modale « Historique des prix » affiche —
     * c'est la chaine entiere qui est prouvee, pas seulement l'update.
     */
    #[Test]
    public function modifier_le_prix_le_persiste_et_laisse_sa_trace_a_l_historique(): void
    {
        $this->jeuDeDonnees();
        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteBar::class)
            ->call('ouvrirModificationPrix', $boisson->id)
            ->assertSet('etatFormulaire', 'prix')
            ->assertSet('prixSaisi', '800.00')
            ->set('prixSaisi', '900')
            ->call('enregistrerModificationPrix')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $boisson->refresh();
        $this->assertSame(0, bccomp((string) $boisson->prix_vente, '900', 2));

        $trace = \App\Domain\Carte\Models\HistoriquePrixCarte::query()
            ->where('source_id', $boisson->id)
            ->where('champ', 'prix_vente')
            ->latest('created_at')
            ->first();
        $this->assertNotNull($trace, "Le changement de prix n'a laisse aucune trace a l'historique.");
        $this->assertSame(0, bccomp((string) $trace->ancien_prix, '800.00', 2));
        $this->assertSame(0, bccomp((string) $trace->nouveau_prix, '900', 2));
    }

    /**
     * Un prix a zero rendrait la boisson invendable sans un mot — le retrait
     * de la carte est le geste qui porte ce sens, avec son motif.
     */
    #[Test]
    public function un_prix_a_zero_est_refuse(): void
    {
        $this->jeuDeDonnees();
        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteBar::class)
            ->call('ouvrirModificationPrix', $boisson->id)
            ->set('prixSaisi', '0')
            ->call('enregistrerModificationPrix')
            ->assertHasErrors('prixSaisi');

        $this->assertSame(0, bccomp((string) $boisson->refresh()->prix_vente, '800.00', 2));
    }

    /**
     * L'enregistrement est garde meme sans passer par l'ouverture — la
     * propriete d'etat est modifiable depuis le navigateur (meme motif que
     * `l_enregistrement_du_lien_est_garde_meme_sans_passer_par_l_ouverture`).
     */
    #[Test]
    public function la_modification_du_prix_est_refusee_a_un_role_en_lecture(): void
    {
        $this->jeuDeDonnees();
        $boisson = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->actingAs($this->utilisateur('comptable'));

        Livewire::test(CarteBar::class)
            ->set('articleCibleId', $boisson->id)
            ->set('prixSaisi', '900')
            ->call('enregistrerModificationPrix')
            ->assertStatus(403);

        $this->assertSame(0, bccomp((string) $boisson->refresh()->prix_vente, '800.00', 2));
    }

    // =================================================================
    // ONGLET « VENTES DU BAR » — ajout du 03/09/2026 (Product Owner)
    // =================================================================

    /**
     * ## Ce que ces cinq cas prouvent, et les DEUX mutations tranchées
     *
     * L'onglet liste les LIGNES de vente du rayon. Le défaut le plus probable
     * n'est pas d'oublier une colonne : c'est de montrer au bar les plats du
     * même ticket. Une vente est multi-modules par nature — le module est
     * estampillé sur la LIGNE (`Vente`, docblock) —, et un filtre posé sur la
     * vente au lieu de la ligne passerait tous les tests d'affichage.
     *
     * | Mutation RÉELLEMENT exécutée puis annulée (03/09/2026) | Cas qui rougit | Résultat |
     * |---|---|---|
     * | `EcranDeCarte::requeteDesVentes()` filtre `lignes_vente.module` sur `'M4'` au lieu de `static::MODULE` | `l_onglet_ventes_du_bar_ne_montre_que_les_lignes_du_rayon` | 1 failed (« Le plat du même ticket est listé sur la carte du BAR ») |
     * | La borne haute passe de `whereDate(… '<=' …)` à `where('ventes.created_at', '<=', $fin)` — l'instant au lieu de la date | `la_borne_haute_de_la_plage_inclut_la_journee_entiere` | 1 failed (la vente de 19 h 40 disparaît) |
     *
     * ## Pourquoi les ventes du jeu d'essai sont écrites en direct
     *
     * `VenteService::enregistrer()` sort le stock (RG-05), exige une session
     * de caisse ouverte et passe sa pièce comptable dans la même transaction.
     * Ces cas-ci éprouvent une LECTURE — le filtre, les bornes, le rendu — et
     * ne prouvent aucun chemin d'écriture ; monter tout le référentiel
     * comptable pour afficher un tableau rendrait le cas fragile sans rien
     * prouver de plus. C'est le même arbitrage, écrit avec les mêmes mots, que
     * `database/seeders/VentesSeeder`. Le chemin réel reste prouvé par
     * `tests/Feature/Domain/Ventes/VenteServiceTest.php`.
     */
    #[Test]
    public function l_onglet_ventes_du_bar_ne_montre_que_les_lignes_du_rayon(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $beninoise = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        // UN SEUL ticket, DEUX rayons : c'est le cas qui distingue un filtre
        // sur la ligne d'un filtre sur la vente.
        $this->venteDeTest('V-TEST-00001', now()->subDay(), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 3],
            ['code' => 'PLAT-INCONNU', 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);

        $rendu = Livewire::test(CarteBar::class)->set('onglet', 'ventes');

        $rendu->assertSee('Ventes du Bar')
            ->assertSee('Béninoise 66 cl')
            ->assertSee('V-TEST-00001')
            // RG-15 — le login de qui a encaissé, jamais un « système » inventé.
            ->assertSee('compte.administrateur');

        $rendu->assertDontSee('Poulet DG');

        // ⚠ ET PAR L'URL, pas seulement par l'action : `#[Url(as: 'onglet')]`
        // est le chemin réel — celui d'un signet, d'un lien partagé, ou du
        // retour de pagination, qui repasse par un GET. Un onglet qui ne
        // s'ouvrirait qu'au clic laisserait ces trois cas sur la carte du
        // jour, sans que rien ne le dise.
        $html = (string) $this->get('/pwa/bar/carte?onglet=ventes')->assertOk()->getContent();

        $this->assertStringContainsString('Ventes du Bar', $html);
        $this->assertStringContainsString('V-TEST-00001', $html);
        $this->assertStringNotContainsString('Poulet DG', $html);
    }

    /**
     * La borne haute inclut la JOURNÉE ENTIÈRE — piège classique du `au`
     * exclusif : une vente encaissée à 19 h 40 le dernier jour de la plage
     * disparaîtrait sans qu'aucun message ne le dise.
     */
    #[Test]
    public function la_borne_haute_de_la_plage_inclut_la_journee_entiere(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $beninoise = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();
        $jour = \Carbon\CarbonImmutable::parse('2026-08-20 19:40:00');

        $this->venteDeTest('V-TEST-DERNIERJOUR', $jour, [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);

        // HORS bornes des deux côtés — la veille du début et le lendemain de
        // la fin : une plage qui ne rejetterait rien serait verte à vide.
        $this->venteDeTest('V-TEST-TROPTOT', $jour->subDays(5), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);
        $this->venteDeTest('V-TEST-TROPTARD', $jour->addDays(2), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);

        Livewire::test(CarteBar::class)
            ->set('onglet', 'ventes')
            ->set('debutVentes', '2026-08-18')
            ->set('finVentes', '2026-08-20')
            ->assertSee('V-TEST-DERNIERJOUR')
            ->assertDontSee('V-TEST-TROPTOT')
            ->assertDontSee('V-TEST-TROPTARD');
    }

    /**
     * RG-02 — une vente s'ANNULE, elle ne disparaît jamais du registre. Elle
     * reste listée, marquée « Annulée », et son motif part en infobulle.
     */
    #[Test]
    public function une_vente_annulee_reste_listee_avec_son_statut_et_son_motif(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $beninoise = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->venteDeTest('V-TEST-ANNULEE', now()->subDay(), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 2],
        ], statut: 'annulee', motif: 'Erreur de saisie au comptoir');

        $rendu = Livewire::test(CarteBar::class)->set('onglet', 'ventes');

        $rendu->assertSee('V-TEST-ANNULEE')
            ->assertSee('Annulée')
            ->assertSee('Erreur de saisie au comptoir');

        // Le filtre de statut retient l'annulation et écarte le reste.
        $this->venteDeTest('V-TEST-VALIDEE', now()->subDay(), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);

        Livewire::test(CarteBar::class)
            ->set('onglet', 'ventes')
            ->set('statutVente', 'annulee')
            ->assertSee('V-TEST-ANNULEE')
            ->assertDontSee('V-TEST-VALIDEE');
    }

    /**
     * Le total affiché est la somme des lignes VALIDÉES affichées, calculée en
     * `bcadd` sur des chaînes.
     *
     * L'annulation est exclue et le tableau le DIT : elle reste au registre
     * (RG-02) mais son montant n'est pas de l'argent — l'additionner
     * gonflerait le chiffre du rayon sur l'écran même où on le lit.
     */
    #[Test]
    public function le_total_est_la_somme_des_lignes_validees_affichees(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $beninoise = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();
        $sucrerie = CarteBoisson::where('libelle', 'Sucrerie 66 cl')->firstOrFail();

        $this->venteDeTest('V-TEST-T1', now()->subDay(), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 3],
        ]);
        $this->venteDeTest('V-TEST-T2', now()->subDay(), [
            ['code' => $sucrerie->id, 'nom' => 'Sucrerie 66 cl', 'module' => 'M5', 'prix' => '700.00', 'qte' => 2],
        ]);
        $this->venteDeTest('V-TEST-T3', now()->subDay(), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 10],
        ], statut: 'annulee', motif: 'Ticket saisi deux fois');

        // 3 × 800 + 2 × 700 = 3 800 F. Les 8 000 F annulés en sont exclus.
        $attendu = \App\Pwa\Support\MontantFcfa::format('3800.00');

        $html = Livewire::test(CarteBar::class)->set('onglet', 'ventes')->html();

        $this->assertStringContainsString('TOTAL DE LA PAGE', $html);
        $this->assertStringContainsString($attendu, $html);
        $this->assertStringNotContainsString(
            \App\Pwa\Support\MontantFcfa::format('11800.00'),
            $html,
            "Le total additionne la vente annulée : son montant n'est pas de l'argent.",
        );
        // Le compteur de tête porte le MÊME total, sur le jeu filtré entier.
        $this->assertStringContainsString('Total validé : '.$attendu, $html);
    }

    /**
     * Le stock rendu est celui d'AUJOURD'HUI, lu par le même chemin que
     * l'onglet Carte, et l'entête le dit. Une ligne dont l'article n'est plus
     * à la carte rend le tiret — jamais zéro, qui se lirait « rupture ».
     */
    #[Test]
    public function la_colonne_de_stock_dit_qu_elle_est_actuelle_et_rend_le_tiret_hors_carte(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $beninoise = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->venteDeTest('V-TEST-STOCK', now()->subDay(), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
            // Une boisson qui a quitté la carte depuis : le code ne désigne
            // plus aucun article, son stock ne se lit nulle part.
            ['code' => 'BOISSON-RETIREE', 'nom' => 'Guinness 33 cl', 'module' => 'M5', 'prix' => '1500.00', 'qte' => 1],
        ]);

        $html = Livewire::test(CarteBar::class)->set('onglet', 'ventes')->html();

        // ⚠ Les apostrophes sont ÉCHAPPÉES par Blade (`&#039;`) : les
        // fragments comparés n'en portent aucune, sinon le contrôle serait
        // rouge sur un écran parfaitement correct.
        $this->assertStringContainsString('Stock actuel', $html);
        $this->assertStringContainsString(
            'jamais celui du jour de la vente',
            $html,
            "L'écran doit dire que le stock n'est pas celui du jour de la vente.",
        );
        $this->assertStringContainsString(
            'plus à la carte',
            $html,
            'Une ligne sans article de carte doit expliquer son tiret.',
        );
    }

    // =================================================================
    // EXPORT DE L'ONGLET « VENTES DU BAR » — 03/09/2026 (Product Owner)
    // =================================================================

    /**
     * ## Ce que ces quatre cas prouvent
     *
     * Le bouton « Exporter » est UNIQUE et la modale de format est PARTAGÉE :
     * le document doit suivre l'onglet ouvert. Le défaut naturel n'est donc
     * pas qu'il ne produise rien — c'est qu'il produise le BON fichier au
     * MAUVAIS moment : l'état de la carte pendant qu'on regarde le journal des
     * ventes. Rien à l'écran ne le dirait, et le fichier téléchargé serait
     * parfaitement valide.
     *
     * ## MUTATION RÉELLEMENT EXÉCUTÉE PUIS ANNULÉE (03/09/2026)
     *
     * | Mutation | Cas qui rougit | Résultat |
     * |---|---|---|
     * | `EcranDeCarte::exportDesVentes()` construit ses lignes depuis `LigneVente::query()->where('module', static::MODULE)` — donc SANS aucun filtre de l'écran — au lieu de `requeteDesVentes()` | `l_export_de_l_onglet_ventes_respecte_la_plage_de_dates` | 1 failed (« V-TEST-TROPTARD » sort dans un document borné au 20/08) |
     *
     * La même mutation laisse `l_export_de_l_onglet_ventes_produit_un_document_du_rayon_seul`
     * VERT — le filtre de module y survit. C'est pourquoi le cas des dates
     * existe à part : sans lui, l'export pourrait ignorer les trois filtres de
     * l'onglet sans qu'aucune assertion ne bouge.
     */
    #[Test]
    public function l_export_de_l_onglet_ventes_produit_un_document_du_rayon_seul(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $beninoise = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        // UN ticket, DEUX rayons : le document du bar ne porte pas le plat.
        $this->venteDeTest('V-TEST-EXPORT', now()->subDay(), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 3],
            ['code' => 'PLAT-INCONNU', 'nom' => 'Poulet DG', 'module' => 'M4', 'prix' => '4500.00', 'qte' => 1],
        ]);

        // DOUZE lignes de plus : la page en montre dix. L'export porte sur le
        // jeu FILTRÉ ENTIER, pas sur la page — le compteur de tête, que
        // l'utilisateur lit juste au-dessus du bouton, porte déjà dessus.
        $lignesLongues = [];

        for ($rang = 1; $rang <= 12; $rang++) {
            $lignesLongues[] = [
                'code' => $beninoise->id,
                'nom' => 'BOISSONX'.str_pad((string) $rang, 2, '0', STR_PAD_LEFT),
                'module' => 'M5',
                'prix' => '100.00',
                'qte' => 1,
            ];
        }

        $this->venteDeTest('V-TEST-PAGINE', now()->subDays(2), $lignesLongues);

        $composant = Livewire::test(CarteBar::class)
            ->set('onglet', 'ventes')
            ->call('genererExport');

        $contenu = $this->contenuTelecharge($composant);
        $this->assertStringStartsWith('%PDF', $contenu);

        $texte = $this->texteDuPdf($contenu);

        $this->assertStringContainsString('V-TEST-EXPORT', $texte, 'La ligne du rayon manque au document.');
        // RG-15 — l'imputation nominative suit jusque sur le papier.
        $this->assertStringContainsString('compte.administrateur', $texte);
        $this->assertStringNotContainsString(
            'Poulet',
            $texte,
            "Le plat du même ticket sort dans l'export du BAR : le filtre porte sur la vente, pas sur la ligne.",
        );

        // Les douze lignes, page 11 et 12 comprises.
        $this->assertStringContainsString('BOISSONX01', $texte);
        $this->assertStringContainsString('BOISSONX12', $texte, "L'export s'arrête à la page affichée.");

        // PA-119 — le document DIT son filtre, période comprise, même sans
        // borne : « toutes les dates » est une information, pas un silence.
        $this->assertStringContainsString('dates', $texte, "Le document ne dit pas sa période.");
        // Le total du document est CELUI DE L'ÉCRAN : même clé de langue,
        // mêmes compteurs (`totauxDesVentes()`), annulations exclues.
        $this->assertStringContainsString('Total valid', $texte, "Le document ne porte pas le total validé.");
        // Et l'entête de stock reste « Stock actuel » : le document répète que
        // le chiffre est celui du jour de l'édition, jamais celui de la vente.
        //
        // ⚠ Comparé EN MAJUSCULES : le gabarit met les entêtes en
        // `text-transform: uppercase`, et dompdf applique la règle avant
        // d'écrire le flux. Chercher « actuel » tel quel serait rouge sur un
        // document parfaitement correct.
        $this->assertStringContainsString('ACTUEL', mb_strtoupper($texte));

        // Le TABLEUR sort par le même chemin, et c'est bien un classeur.
        $this->actingAs($this->utilisateur('administrateur'));

        $classeur = Livewire::test(CarteBar::class)
            ->set('onglet', 'ventes')
            ->set('formatExport', 'excel')
            ->call('genererExport');

        // « PK » — la signature ZIP d'un `.xlsx`. Un PDF renvoyé ici passerait
        // `assertFileDownloaded` sans qu'on le voie.
        $this->assertStringStartsWith('PK', $this->contenuTelecharge($classeur));
    }

    /**
     * Le filtre de dates est RESPECTÉ DANS LE DOCUMENT — c'est le cas que la
     * mutation rougit.
     *
     * Les deux bornes sont incluses, comme au tableau : une vente encaissée à
     * 19 h 40 le dernier jour de la plage figure au document. Ce qui est hors
     * plage n'y figure pas — sans quoi le comptable recevrait un journal plus
     * large que celui qu'il croit avoir vérifié (PA-119).
     */
    #[Test]
    public function l_export_de_l_onglet_ventes_respecte_la_plage_de_dates(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $beninoise = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();
        $jour = \Carbon\CarbonImmutable::parse('2026-08-20 19:40:00');

        $this->venteDeTest('V-TEST-DERNIERJOUR', $jour, [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);
        $this->venteDeTest('V-TEST-TROPTOT', $jour->subDays(5), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);
        $this->venteDeTest('V-TEST-TROPTARD', $jour->addDays(2), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);

        $composant = Livewire::test(CarteBar::class)
            ->set('onglet', 'ventes')
            ->set('debutVentes', '2026-08-18')
            ->set('finVentes', '2026-08-20')
            ->call('genererExport');

        $texte = $this->texteDuPdf($this->contenuTelecharge($composant));

        $this->assertStringContainsString('V-TEST-DERNIERJOUR', $texte);
        $this->assertStringNotContainsString(
            'V-TEST-TROPTOT',
            $texte,
            "L'export ignore la borne basse : le document est plus large que l'écran.",
        );
        $this->assertStringNotContainsString(
            'V-TEST-TROPTARD',
            $texte,
            "L'export ignore la borne haute : le document est plus large que l'écran.",
        );

        // Et il DIT la plage sur laquelle il porte, jour par jour.
        $this->assertStringContainsString('18/08/2026', $texte);
        $this->assertStringContainsString('20/08/2026', $texte);
    }

    /**
     * PA-119 — une liste vide se REFUSE, et AUCUN document n'est produit.
     *
     * Le message est celui de l'onglet, pas celui de la carte : ici les
     * filtres sont la période, le statut et la recherche, et un rayon peut
     * n'avoir simplement rien vendu sur la plage demandée.
     */
    #[Test]
    public function l_export_de_l_onglet_ventes_refuse_une_liste_vide_sans_produire_de_document(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $beninoise = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->venteDeTest('V-TEST-HORSPLAGE', \Carbon\CarbonImmutable::parse('2026-08-20 10:00:00'), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);

        $composant = Livewire::test(CarteBar::class)
            ->set('onglet', 'ventes')
            ->set('debutVentes', '2026-09-01')
            ->set('finVentes', '2026-09-02')
            ->call('genererExport')
            ->assertHasErrors('formatExport');

        /** @var array<string, mixed> $effets */
        $effets = $composant->__get('effects');

        $this->assertArrayNotHasKey(
            'download',
            $effets,
            'Un document a été produit sur une liste vide : une page que l\'on croirait complète.',
        );
    }

    /**
     * NON-RÉGRESSION — depuis l'onglet Carte, l'export reste CELUI DE LA CARTE.
     *
     * L'aiguillage se fait sur l'onglet courant : le brancher trop haut, ou
     * l'oublier, ferait sortir le journal des ventes à quelqu'un qui regarde
     * la carte du jour. Le contrôle porte sur une donnée qui n'existe QUE dans
     * le journal — un numéro de ticket — et sur une colonne qui n'existe QUE
     * sur la carte.
     */
    #[Test]
    public function l_export_de_l_onglet_carte_reste_celui_de_la_carte(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $beninoise = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();

        $this->venteDeTest('V-TEST-CARTE', now()->subDay(), [
            ['code' => $beninoise->id, 'nom' => 'Béninoise 66 cl', 'module' => 'M5', 'prix' => '800.00', 'qte' => 1],
        ]);

        $texte = $this->texteDuPdf($this->contenuTelecharge(
            Livewire::test(CarteBar::class)->call('genererExport'),
        ));

        $this->assertStringNotContainsString(
            'V-TEST-CARTE',
            $texte,
            "L'export de l'onglet Carte porte le journal des ventes.",
        );

        // La MODALE nomme ce qu'elle produira, et elle change avec l'onglet :
        // un titre unique laisserait douter du périmètre du fichier
        // téléchargé, ce que le maître évite en titrant « Exporter — <entité> »
        // (`crud-ui.js` l.147).
        $this->assertStringContainsString(
            'Exporter — Carte du bar',
            Livewire::test(CarteBar::class)->set('etatFormulaire', 'export')->html(),
        );

        $this->assertStringContainsString(
            'Exporter — Ventes du Bar',
            Livewire::test(CarteBar::class)
                ->set('onglet', 'ventes')
                ->set('etatFormulaire', 'export')
                ->html(),
        );
        // Le conditionnement de l'article de stock n'existe QUE sur l'état de
        // la carte — le journal des ventes ne porte aucune colonne d'article
        // de stock. Le contrôle porte donc sur une cellule de DONNÉES, pas sur
        // un entête : le gabarit les met en majuscules, et un entête comparé
        // en minuscules serait rouge sur un document correct.
        $this->assertStringContainsString(
            'casier',
            $texte,
            "L'état de la carte a perdu sa colonne « Article de stock ».",
        );
    }

    /**
     * Une ligne de vente FABRIQUÉE pour éprouver l'affichage.
     *
     * Écrite en direct, comme `VentesSeeder` et pour la même raison, nommée au
     * docblock du premier cas de cette section. `created_at` passe par
     * `forceFill()` : la colonne n'est pas dans `$fillable`, et un
     * `Vente::create(['created_at' => …])` la laisserait silencieusement à
     * `now()` — la plage de dates serait alors éprouvée à vide.
     *
     * @param  list<array{code: string, nom: string, module: string, prix: string, qte: int}>  $lignes
     */
    private function venteDeTest(
        string $numero,
        \DateTimeInterface $quand,
        array $lignes,
        string $statut = 'validee',
        string $motif = '',
    ): \App\Domain\Ventes\Models\Vente {
        $total = '0.00';

        foreach ($lignes as $ligne) {
            $total = bcadd($total, bcmul($ligne['prix'], (string) $ligne['qte'], 2), 2);
        }

        $vente = \App\Domain\Ventes\Models\Vente::create([
            'numero' => $numero,
            'point_vente' => 'bar',
            'montant_total' => $total,
            'mode_paiement' => 'especes',
            'encaisse' => true,
            'statut' => $statut,
            'motif_annulation' => $motif === '' ? null : $motif,
            'annulee_at' => $statut === 'annulee' ? $quand : null,
            'utilisateur_id' => $this->utilisateur('administrateur')->id,
        ]);

        $vente->forceFill(['created_at' => $quand])->save();

        foreach ($lignes as $ligne) {
            \App\Domain\Ventes\Models\LigneVente::create([
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

    // =================================================================
    // Creation de boisson — directive PO du 03/09/2026
    // =================================================================

    /**
     * Le geste MANQUAIT ENTIEREMENT a la PWA : `CarteBoissonService::creer()`
     * n'avait que deux appelants, l'API REST et l'import CSV. Sur un poste au
     * comptoir, ajouter une boisson exigeait donc un fichier ou un client
     * HTTP — dans le rayon ou le catalogue bouge le plus.
     *
     * MUTATION TRANCHEE : `article_id` remplace par une valeur en dur au lieu
     * de la saisie → ce cas ROUGE (la boisson pointe le mauvais article, donc
     * les ventes decrementeraient un autre casier). Restauree.
     */
    #[Test]
    public function creer_une_boisson_la_persiste_avec_son_article_de_stock(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteBar::class)
            ->call('ouvrirCreationBoisson')
            ->assertSet('etatFormulaire', 'boisson')
            ->set('libelleSaisi', 'Sodabi artisanal 50 cl')
            ->set('categorieSaisie', 'locale')
            ->set('prixSaisi', '1500')
            ->set('articleStockId', $this->casierSucrerie->id)
            ->call('enregistrerCreationBoisson')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $boisson = CarteBoisson::where('libelle', 'Sodabi artisanal 50 cl')->firstOrFail();

        $this->assertSame($this->casierSucrerie->id, $boisson->article_id);
        $this->assertSame('locale', $boisson->categorie);
        $this->assertSame(0, bccomp((string) $boisson->prix_vente, '1500', 2));
        // Un prix pose a la main EST une correction manuelle (PA-161 b).
        $this->assertTrue((bool) $boisson->prix_corrige_main);
    }

    /**
     * `cartes_boisson.article_id` est NOT NULL : une boisson sans article de
     * stock ne pourrait decrementer aucun casier a la vente. Le champ est un
     * selecteur, et le refus tient meme si la propriete est forgee depuis le
     * navigateur.
     */
    #[Test]
    public function une_boisson_sans_article_de_stock_est_refusee(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        Livewire::test(CarteBar::class)
            ->call('ouvrirCreationBoisson')
            ->set('libelleSaisi', 'Boisson sans article')
            ->set('categorieSaisie', 'locale')
            ->set('prixSaisi', '1000')
            ->set('articleStockId', null)
            ->call('enregistrerCreationBoisson')
            ->assertHasErrors('articleStockId');

        $this->assertDatabaseMissing('cartes_boisson', ['libelle' => 'Boisson sans article']);
    }

    /** Un role en lecture seule sur M5 ne cree pas de boisson. */
    #[Test]
    public function un_role_en_lecture_seule_ne_cree_pas_de_boisson(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('comptable'));

        Livewire::test(CarteBar::class)
            ->set('libelleSaisi', 'Tentative')
            ->set('categorieSaisie', 'locale')
            ->set('prixSaisi', '1000')
            ->set('articleStockId', $this->casierSucrerie->id)
            ->call('enregistrerCreationBoisson')
            ->assertStatus(403);

        $this->assertDatabaseMissing('cartes_boisson', ['libelle' => 'Tentative']);
    }

    /**
     * Modifier la boisson (PO 08/10/2026) : libelle et categorie changent, le
     * prix et le lien au stock restent ceux de la boisson.
     *
     * MUTATION : retirer `categorie` de l'appel a `modifier()` -> ce cas ROUGE.
     */
    #[Test]
    public function modifier_une_boisson_change_libelle_et_categorie_sans_toucher_au_prix_ni_au_stock(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $boisson = CarteBoisson::query()->firstOrFail();
        $prix = (string) $boisson->prix_vente;
        $articleId = $boisson->article_id;
        $autre = $boisson->categorie === 'maison' ? 'importee' : 'maison';

        Livewire::test(CarteBar::class)
            ->call('ouvrirModificationBoisson', $boisson->id)
            ->assertSet('etatFormulaire', 'modificationBoisson')
            ->assertSet('libelleSaisi', $boisson->libelle)
            ->set('libelleSaisi', 'Libelle renomme')
            ->set('categorieSaisie', $autre)
            ->call('enregistrerModificationBoisson')
            ->assertHasNoErrors()
            ->assertSet('etatFormulaire', null);

        $boisson->refresh();
        $this->assertSame('Libelle renomme', $boisson->libelle);
        $this->assertSame($autre, $boisson->categorie);
        $this->assertSame(0, bccomp((string) $boisson->prix_vente, $prix, 2));
        $this->assertSame($articleId, $boisson->article_id);
    }

    #[Test]
    public function modifier_une_boisson_refuse_un_libelle_vide_et_une_categorie_inconnue(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('administrateur'));

        $boisson = CarteBoisson::query()->firstOrFail();
        $libelle = $boisson->libelle;

        Livewire::test(CarteBar::class)
            ->call('ouvrirModificationBoisson', $boisson->id)
            ->set('libelleSaisi', '')
            ->set('categorieSaisie', 'inconnue')
            ->call('enregistrerModificationBoisson')
            ->assertHasErrors(['libelleSaisi', 'categorieSaisie']);

        $this->assertSame($libelle, $boisson->fresh()->libelle);
    }

    #[Test]
    public function un_role_en_lecture_seule_ne_modifie_pas_une_boisson(): void
    {
        $this->jeuDeDonnees();
        $this->actingAs($this->utilisateur('comptable'));

        $boisson = CarteBoisson::query()->firstOrFail();
        $libelle = $boisson->libelle;

        Livewire::test(CarteBar::class)
            ->set('articleCibleId', $boisson->id)
            ->set('libelleSaisi', 'Tentative')
            ->set('categorieSaisie', 'locale')
            ->call('enregistrerModificationBoisson')
            ->assertStatus(403);

        $this->assertSame($libelle, $boisson->fresh()->libelle);
    }
}
