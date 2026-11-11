<?php

declare(strict_types=1);

namespace Tests\Feature\Domain\Ventes;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Domain\Ventes\Models\Vente;
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
 * Registre unique des ventes — PA-159 lot 0b, T1.
 *
 * Deux défauts sont couverts ici, et le second n'est visible que si l'on
 * regarde le schéma plutôt que le comportement :
 *
 *  1. `HistoriqueVentes` lisait `ventes` pendant que `PosComptant` écrivait
 *     `ventes_bar`. Le journal de caisse n'affichait que le seeder, et l'écran
 *     était plein — donc personne ne voyait rien manquer.
 *  2. `ventes.client_id` et `ventes.utilisateur_id` étaient des `bigint`
 *     libres face à des tables en `char(36)`. Ils NE POUVAIENT PAS porter de
 *     clé étrangère, et RG-15 — une vente doit nommer qui l'a encaissée —
 *     n'était donc tenue par rien.
 *
 * @see RG-05 Sortie de stock automatique
 * @see RG-15 Journalisation
 */
final class VenteServiceTest extends TestCase
{
    use RefreshDatabase;

    private VenteService $ventes;

    private StockTheoriqueService $stock;

    private PointStockage $bar;

    private PointStockage $cuisine;

    private Article $articleBiere;

    private Article $articleRiz;

    private CarteBoisson $biere;

    private Plat $platRiz;

    private User $caissier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);

        $this->ventes = app(VenteService::class);
        $this->stock = app(StockTheoriqueService::class);

        $this->caissier = $this->utilisateur('barman');
        $this->actingAs($this->caissier);

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
        $this->platRiz = Plat::create([
            'menu_id' => $menu->id,
            'recette_id' => $recette->id,
            'libelle' => 'Riz sauce arachide',
            'prix_vente' => '2500.00',
        ]);

        app(MouvementStockService::class)->entree($this->articleBiere->id, $this->bar->id, '48.00', 'Réception');
        app(MouvementStockService::class)->entree($this->articleRiz->id, $this->cuisine->id, '20.00', 'Réception');

        /*
         * Le référentiel comptable fait désormais partie du décor MINIMAL
         * d'une vente, et ce n'est pas une commodité de test : depuis la règle
         * du 31/08/2026, un encaissement sans pièce n'est plus enregistré du
         * tout. Un cas qui vendrait sans plan comptable ne décrirait donc
         * aucun établissement réel — il décrirait le refus.
         *
         * Le refus lui-même est éprouvé séparément
         * ({@see self::sans_referentiel_comptable_aucune_vente_n_est_enregistree()}),
         * sur une base d'où le référentiel est RETIRÉ.
         */
        $this->seed(ComptabiliteReferentielSeeder::class);
    }

    // ------------------------------------------------ Schéma (le défaut n°2)

    #[Test]
    public function les_cles_de_rattachement_sont_de_vraies_cles_etrangeres_en_uuid(): void
    {
        foreach (['id', 'client_id', 'utilisateur_id', 'session_id'] as $colonne) {
            $this->assertSame(
                'char',
                Schema::getColumnType('ventes', $colonne),
                "ventes.{$colonne} doit être un CHAR(36) : un bigint ne peut pas référencer "
                .'une table dont la clé est un UUID.',
            );
        }

        $this->assertSame('char', Schema::getColumnType('lignes_vente', 'vente_id'));

        $contraintes = collect(DB::select(
            'SELECT rc.CONSTRAINT_NAME, rc.DELETE_RULE, kcu.COLUMN_NAME, kcu.REFERENCED_TABLE_NAME
             FROM information_schema.REFERENTIAL_CONSTRAINTS rc
             JOIN information_schema.KEY_COLUMN_USAGE kcu
               ON kcu.CONSTRAINT_NAME = rc.CONSTRAINT_NAME
              AND kcu.CONSTRAINT_SCHEMA = rc.CONSTRAINT_SCHEMA
             WHERE rc.CONSTRAINT_SCHEMA = DATABASE()
               AND rc.TABLE_NAME IN (?, ?)',
            ['ventes', 'lignes_vente'],
        ));

        $referencees = $contraintes->pluck('REFERENCED_TABLE_NAME')->all();

        foreach (['clients', 'utilisateurs', 'ventes'] as $cible) {
            $this->assertContains($cible, $referencees, "Aucune clé étrangère vers {$cible}.");
        }

        // `cascadeOnDelete` est interdit sur une table transactionnelle : la
        // suppression d'une vente emporterait ses lignes sans laisser de trace.
        foreach ($contraintes as $contrainte) {
            $this->assertNotSame(
                'CASCADE',
                $contrainte->DELETE_RULE,
                "La contrainte {$contrainte->CONSTRAINT_NAME} est en CASCADE.",
            );
        }
    }

    // ------------------------------------------------------- Registre unique

    #[Test]
    public function une_vente_encaissee_est_lisible_dans_le_registre_que_l_historique_interroge(): void
    {
        $vente = $this->encaisserUneBiere(3);

        // Le registre lu par l'écran d'historique, et lui seul.
        $this->assertDatabaseHas('ventes', ['id' => $vente->id, 'numero' => $vente->numero]);
        $this->assertSame('3000.00', (string) $vente->montant_total);
        $this->assertSame($this->caissier->id, $vente->utilisateur_id);
        $this->assertCount(1, $this->ventes->filtrer()->get());
    }

    #[Test]
    public function une_vente_melange_le_bar_et_le_restaurant_sur_le_meme_ticket(): void
    {
        $vente = $this->ventes->enregistrer([
            'point_vente' => 'Restaurant',
            'mode_paiement' => 'especes',
            'lignes' => [
                ['module' => 'M5', 'reference_id' => $this->biere->id, 'quantite' => 2],
                ['module' => 'M4', 'reference_id' => $this->platRiz->id, 'quantite' => 2],
            ],
        ]);

        $this->assertSame('7000.00', (string) $vente->montant_total);
        $this->assertEqualsCanonicalizing(
            ['M4', 'M5'],
            $vente->lignes()->pluck('module')->unique()->values()->all(),
        );

        // RG-05 des deux côtés : le bar par mouvement direct, la cuisine par
        // la recette, via la commande transmise.
        $this->assertSame('46.00', $this->stock->stock($this->articleBiere->id, $this->bar->id));
        $this->assertSame('19.50', $this->stock->stock($this->articleRiz->id, $this->cuisine->id));
    }

    /**
     * Demande du Product Owner du 01/09/2026 : « il ne faut pas que le
     * changement de ce prix impute les ventes précédentes ou la
     * comptabilité ». Les TROIS surfaces sont vérifiées ici — la ligne de
     * vente, le montant de la vente, ET la pièce comptable, qui n'avait
     * encore jamais été contrôlée sur ce cas précis avant cette extension.
     *
     * La raison structurelle : `resoudreLignes()` fige `prix_unitaire` sur
     * chaque ligne, et `totaliser()` calcule `montant_total` à partir de ces
     * lignes figées — les DEUX AVANT la transaction, donc avant même que la
     * pièce comptable ne soit passée (PA-98). Aucun des trois ne relit
     * `cartes_boisson.prix_vente` après coup ; ce test le mesure plutôt que
     * de le supposer.
     */
    #[Test]
    public function le_prix_est_fige_a_l_encaissement_et_ne_suit_pas_le_catalogue(): void
    {
        $vente = $this->encaisserUneBiere(2);
        $piece = $this->piece($vente);
        $creditAvant = $this->creditDuCompte($piece, '7011');

        $this->biere->update(['prix_vente' => '1500.00']);

        $ligne = $vente->refresh()->lignes()->first();

        $this->assertSame('1000.00', (string) $ligne->prix_unitaire);
        $this->assertSame('2000.00', (string) $ligne->montant);
        $this->assertSame('2000.00', (string) $vente->montant_total);

        // La pièce comptable, elle aussi, reste sur l'ancien prix : elle a
        // été passée AVANT la hausse de tarif, et rien ne la relit après
        // coup. Une hausse de tarif qui rouvrirait le grand livre créditerait
        // un chiffre d'affaires que la caisse n'a jamais encaissé.
        $this->assertSame(
            $creditAvant,
            $this->creditDuCompte($this->piece($vente), '7011'),
            'La pièce comptable ne doit pas suivre le catalogue.',
        );
        $this->assertSame(0, bccomp($creditAvant, '2000', 2));
    }

    // ----------------------------------------------- Numérotation et idempotence

    #[Test]
    public function la_numerotation_est_sequentielle_par_annee(): void
    {
        $premiere = $this->encaisserUneBiere(1);
        $seconde = $this->encaisserUneBiere(1);

        $annee = now()->format('Y');

        $this->assertSame("V-{$annee}-00001", $premiere->numero);
        $this->assertSame("V-{$annee}-00002", $seconde->numero);
    }

    #[Test]
    public function un_rejeu_du_meme_identifiant_ne_cree_ni_doublon_ni_numero(): void
    {
        $identifiant = (string) Str::uuid();

        $premiere = $this->encaisserUneBiere(2, $identifiant);
        $rejeu = $this->encaisserUneBiere(2, $identifiant);

        $this->assertSame($premiere->id, $rejeu->id);
        $this->assertSame($premiere->numero, $rejeu->numero);
        $this->assertSame(1, Vente::count());

        // Le numéro n'est pas BRÛLÉ par le rejeu : la vente suivante prend le
        // suivant immédiat, pas le troisième.
        $suivante = $this->encaisserUneBiere(1);
        $this->assertSame('V-'.now()->format('Y').'-00002', $suivante->numero);

        // Et surtout, le stock n'est décrémenté qu'une fois.
        $this->assertSame('45.00', $this->stock->stock($this->articleBiere->id, $this->bar->id));
    }

    // -------------------------------------------------------------- Refus

    #[Test]
    public function une_quantite_a_zero_ne_devient_jamais_une_ligne_facturee(): void
    {
        $this->expectException(RuntimeException::class);

        $this->ventes->enregistrer([
            'lignes' => [['module' => 'M5', 'reference_id' => $this->biere->id, 'quantite' => 0]],
        ]);
    }

    #[Test]
    public function un_module_sans_catalogue_encaissable_est_refuse_et_nomme(): void
    {
        $this->expectException(RuntimeException::class);
        // M9 (tourisme) est encaissable depuis le 22/10/2026 : l'hébergement
        // (M1) reste le module sans catalogue d'où figer un prix.
        $this->expectExceptionMessageMatches('/Hébergement/');

        $this->ventes->enregistrer([
            'lignes' => [['module' => 'M1', 'reference_id' => (string) Str::uuid(), 'quantite' => 1]],
        ]);
    }

    #[Test]
    public function une_reference_absente_du_catalogue_est_refusee(): void
    {
        $this->expectException(RuntimeException::class);

        $this->ventes->enregistrer([
            'lignes' => [['module' => 'M5', 'reference_id' => (string) Str::uuid(), 'quantite' => 1]],
        ]);
    }

    #[Test]
    public function une_note_de_chambre_n_est_pas_un_encaissement(): void
    {
        $vente = $this->ventes->enregistrer([
            'mode_paiement' => 'note_chambre',
            'lignes' => [['module' => 'M5', 'reference_id' => $this->biere->id, 'quantite' => 1]],
        ]);

        $this->assertFalse($vente->encaisse);

        $comptant = $this->encaisserUneBiere(1);
        $this->assertTrue($comptant->encaisse);
    }

    // ----------------------------------------------------------- Annulation

    #[Test]
    public function rg02_une_annulation_conserve_la_vente_et_compense_le_stock(): void
    {
        $vente = $this->encaisserUneBiere(4);
        $this->assertSame('44.00', $this->stock->stock($this->articleBiere->id, $this->bar->id));

        $annulee = $this->ventes->annuler($vente, 'Erreur de saisie');

        $this->assertSame('annulee', $annulee->statut);
        $this->assertSame('Erreur de saisie', $annulee->motif_annulation);
        $this->assertNotNull($annulee->annulee_at);

        // La vente reste au registre avec son numéro.
        $this->assertDatabaseHas('ventes', ['id' => $vente->id, 'numero' => $vente->numero]);

        // Le stock est compensé par une ENTRÉE, pas par la disparition du
        // mouvement de sortie : les deux restent à la fiche de stock.
        $this->assertSame('48.00', $this->stock->stock($this->articleBiere->id, $this->bar->id));

        $mouvements = DB::table('mouvements_stock')
            ->where('article_id', $this->articleBiere->id)
            ->orderBy('date_mouvement')
            ->pluck('type_mouvement')
            ->all();

        // Réception, sortie de la vente, entrée de compensation : les trois
        // restent lisibles à la fiche de stock.
        $this->assertSame(['entree', 'sortie', 'entree'], $mouvements);
    }

    #[Test]
    public function une_vente_deja_annulee_ne_se_reannule_pas(): void
    {
        $vente = $this->ventes->annuler($this->encaisserUneBiere(1), 'Première annulation');

        $this->expectException(RuntimeException::class);

        $this->ventes->annuler($vente, 'Seconde annulation');
    }

    // =====================================================================
    // La pièce comptable — règle du Product Owner du 31/08/2026
    // =====================================================================

    /**
     * MUTATION PROUVÉE (31/08/2026) : retirer l'appel à `passerEtValider()`
     * de `VenteService::enregistrer()` fait rougir ce cas sur son premier
     * `assertNotNull($vente->ecriture_id)`. Retirer la seule ventilation par
     * module (un crédit unique sur 7011) le fait rougir sur le crédit de
     * 7061. Les deux moitiés mordent.
     */
    #[Test]
    public function une_vente_produit_sa_piece_comptable_ventilee_par_module(): void
    {
        $vente = $this->ventes->enregistrer([
            'point_vente' => 'Bar',
            'mode_paiement' => 'especes',
            'lignes' => [
                ['module' => 'M5', 'reference_id' => $this->biere->id, 'quantite' => 2],
                ['module' => 'M4', 'reference_id' => $this->platRiz->id, 'quantite' => 1],
            ],
        ]);

        // 2 × 1 000 + 1 × 2 500 = 4 500.
        $this->assertSame(0, bccomp((string) $vente->montant_total, '4500', 2));
        $this->assertNotNull($vente->ecriture_id);
        $this->assertTrue($vente->estComptabilisee());

        $piece = $this->piece($vente);

        // Trois lignes : la contrepartie au débit, un produit par module.
        $this->assertCount(3, $piece);

        // Le débit va bien à la CAISSE — le compte de `DepenseService`, pas
        // un numéro recopié : les deux services doivent parler du même 571000.
        $this->assertSame(
            DepenseService::TRESORERIES['caisse']['compte'],
            $this->compteDe($piece->firstWhere(fn ($e): bool => bccomp((string) $e->debit, '0', 2) > 0)),
        );

        // 7011 « Ventes bar », 7061 « Ventes restauration » — le chiffre
        // d'affaires est ventilé sur la seule donnée fiable : le module
        // estampillé sur la ligne à l'encaissement.
        //
        // Le crédit est CHERCHÉ, jamais replié sur « 0 » quand le compte est
        // absent : un repli ferait échouer le cas sur un montant faux au lieu
        // de dire que le compte n'a pas été crédité du tout.
        $this->assertSame(0, bccomp($this->creditDuCompte($piece, '7011'), '2000', 2));
        $this->assertSame(0, bccomp($this->creditDuCompte($piece, '7061'), '2500', 2));

        // Et la pièce est VALIDÉE : un brouillon reste invisible du grand
        // livre, de la balance et du compte de résultat — l'argent y serait
        // encore absent (PA-159, note de `passerEtValider()`).
        foreach ($piece as $ecriture) {
            $this->assertSame('validee', $ecriture->statut);
        }
    }

    /**
     * TVA par module, au centime : la TVA du bar (marchandises revendues) se
     * crédite sur 4431, celle du restaurant (prestation) sur 4432, et la pièce
     * s'équilibre. MUTATION PROUVÉE : `ROLES_TVA['M5'] = 'TVA_FACTUREE_PRESTATIONS'` rougit ce cas.
     */
    #[Test]
    public function la_tva_se_credite_par_module_4431_bar_4432_restaurant_et_la_piece_s_equilibre(): void
    {
        foreach ([
            \App\Domain\Comptabilite\Services\CalculTvaService::CLE_PARAMETRE_TAUX => '18.00',
            \App\Domain\Comptabilite\Services\CalculTvaService::CLE_PARAMETRE_ACTIVE => 'true',
            \App\Domain\Comptabilite\Services\CalculTvaService::CLE_PARAMETRE_CONVENTION => 'ttc',
        ] as $cle => $valeur) {
            \App\Shared\Parametres\Models\ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
        }

        $vente = $this->ventes->enregistrer([
            'point_vente' => 'Bar',
            'mode_paiement' => 'especes',
            'lignes' => [
                ['module' => 'M5', 'reference_id' => $this->biere->id, 'quantite' => 2],
                ['module' => 'M4', 'reference_id' => $this->platRiz->id, 'quantite' => 1],
            ],
        ]);

        $piece = $this->piece($vente);

        // 2 000 TTC bar : HT 1 694,92 + TVA 305,08 ; 2 500 TTC restaurant : HT 2 118,64 + TVA 381,36.
        $this->assertSame('305.08', $this->creditDuCompte($piece, '4431'));
        $this->assertSame('381.36', $this->creditDuCompte($piece, '4432'));
        $this->assertSame('1694.92', $this->creditDuCompte($piece, '7011'));
        $this->assertSame('2118.64', $this->creditDuCompte($piece, '7061'));

        $debit = '0.00';
        $credit = '0.00';
        foreach ($piece as $ecriture) {
            $debit = bcadd($debit, (string) $ecriture->debit, 2);
            $credit = bcadd($credit, (string) $ecriture->credit, 2);
        }
        $this->assertSame('4500.00', $debit);
        $this->assertSame(0, bccomp($debit, $credit, 2));
    }

    /**
     * MUTATION PROUVÉE : remplacer le rôle `ROLE_CLIENTS` du débit par la caisse
     * fait rougir ce cas — c'est exactement l'erreur qui gonflerait le fond
     * de caisse d'un argent que personne n'a remis.
     */
    #[Test]
    public function une_note_de_chambre_debite_le_compte_client_et_non_la_caisse(): void
    {
        $vente = $this->ventes->enregistrer([
            'point_vente' => 'Bar',
            'mode_paiement' => 'note_chambre',
            'lignes' => [['module' => 'M5', 'reference_id' => $this->biere->id, 'quantite' => 2]],
        ]);

        $debit = $this->piece($vente)->firstWhere(fn ($e): bool => bccomp((string) $e->debit, '0', 2) > 0);

        $this->assertSame(\App\Domain\Comptabilite\Support\ComptesSyscohada::CLIENTS, $this->compteDe($debit));
        $this->assertNotSame(DepenseService::TRESORERIES['caisse']['compte'], $this->compteDe($debit));
    }

    /**
     * Le refus, éprouvé sur une base d'où le référentiel est RETIRÉ.
     *
     * MUTATION PROUVÉE : rendre l'écriture facultative — un `try/catch` autour
     * de `passerEtValider()` — laisse ce cas rouge sur `Vente::count()`, qui
     * vaudrait 1. C'est la mesure du « refus = rien n'est écrit » : sans elle,
     * on retomberait sur le défaut que PA-159 a corrigé côté dépenses.
     */
    #[Test]
    public function sans_referentiel_comptable_aucune_vente_n_est_enregistree(): void
    {
        // Le journal est le premier maillon que `PasserEcritureService`
        // cherche : le retirer suffit, et c'est plus honnête que de vider
        // quatre tables dont on ne saurait plus laquelle a mordu.
        JournalComptable::where('code', VenteService::JOURNAL)->delete();

        $avantStock = $this->stock->stock($this->articleBiere->id, $this->bar->id);

        try {
            $this->encaisserUneBiere(2);
            $this->fail('Une vente sans pièce comptable ne doit pas être enregistrée.');
        } catch (RuntimeException) {
            // La raison remonte telle quelle : c'est elle que le caissier lit.
        }

        // Rien n'a été écrit — ni la vente, ni ses lignes, ni la sortie de
        // stock. La transaction a bien tout emporté.
        $this->assertSame(0, Vente::count());
        $this->assertSame(0, DB::table('lignes_vente')->count());
        $this->assertSame($avantStock, $this->stock->stock($this->articleBiere->id, $this->bar->id));

        // Et le numéro n'est pas brûlé : la séquence lit le maximum de la
        // table, que le rejet a laissée vide.
        $this->seed(ComptabiliteReferentielSeeder::class);
        $this->assertStringEndsWith('-00001', $this->encaisserUneBiere(1)->numero);
    }

    /**
     * MUTATION PROUVÉE : ne contre-passer que la ligne désignée par
     * `ecriture_id` (au lieu de la pièce entière) laisse ce cas rouge sur
     * l'équilibre — les débits l'emporteraient de 2 000 F, exactement le
     * produit resté crédité sans contrepartie.
     */
    #[Test]
    public function rg11_une_annulation_contrepasse_la_piece_entiere_sans_rien_effacer(): void
    {
        $vente = $this->encaisserUneBiere(2);
        $piece = $this->piece($vente);

        $this->ventes->annuler($vente, 'Erreur de saisie');

        // L'originale est INTACTE : aucune suppression, aucune modification.
        foreach ($piece as $ecriture) {
            $this->assertDatabaseHas('ecritures_comptables', [
                'id' => $ecriture->id,
                'statut' => 'validee',
                'ecriture_contrepassee_id' => null,
            ]);
        }

        // Une inverse par ligne, liée à son originale — la traçabilité
        // qu'exige SYSCOHADA, jamais une correction qui efface.
        $inverses = EcritureComptable::whereIn(
            'ecriture_contrepassee_id',
            $piece->pluck('id')->all(),
        )->get();

        $this->assertCount($piece->count(), $inverses);

        // Et le compte de la vente est SOLDÉ : débits = crédits sur les
        // quatre lignes. C'est la seule mesure qui dit que la comptabilité
        // ne garde pas de produit fantôme.
        $toutes = $piece->concat($inverses);
        $debits = '0.00';
        $credits = '0.00';

        foreach ($toutes as $ecriture) {
            $debits = bcadd($debits, (string) $ecriture->debit, 2);
            $credits = bcadd($credits, (string) $ecriture->credit, 2);
        }

        $this->assertSame(0, bccomp($debits, $credits, 2));
        $this->assertSame(0, bccomp($debits, '4000', 2)); // 2 000 à l'aller, 2 000 au retour.
    }

    /**
     * Le rattrapage — ce qui sert les ventes antérieures à la règle et les
     * trois ventes de démonstration de `VentesSeeder`.
     *
     * MUTATION PROUVÉE : retirer la garde `estComptabilisee()` en tête de
     * `comptabiliser()` fait rougir ce cas sur le nombre d'écritures, qui
     * doublerait — une seconde pièce pour le même argent.
     */
    #[Test]
    public function le_rattrapage_passe_la_piece_une_seule_fois(): void
    {
        $vente = $this->encaisserUneBiere(2);
        $avant = EcritureComptable::count();

        $this->assertSame($vente->ecriture_id, $this->ventes->comptabiliser($vente)->ecriture_id);
        $this->assertSame($avant, EcritureComptable::count());
    }

    #[Test]
    public function une_vente_annulee_ne_se_comptabilise_plus(): void
    {
        $vente = $this->encaisserUneBiere(2);
        $annulee = $this->ventes->annuler($vente, 'Erreur');

        // On efface le lien pour reproduire l'état d'une vente écrite AVANT
        // la règle, puis annulée : le rattrapage doit refuser.
        $annulee->forceFill(['ecriture_id' => null])->save();

        $this->expectException(RuntimeException::class);

        $this->ventes->comptabiliser($annulee->refresh());
    }

    // ------------------------------------------------------------- Fixtures

    /**
     * Les lignes de la pièce d'une vente, relues en base.
     *
     * Elles se retrouvent par leur libellé : `ecritures_comptables` n'a aucune
     * colonne groupant les lignes d'une même pièce (PA-52). C'est le même lien
     * que celui du service, et c'est assumé — le vérifier autrement demanderait
     * une colonne que le schéma n'a pas.
     *
     * @return \Illuminate\Database\Eloquent\Collection<int, EcritureComptable>
     */
    private function piece(Vente $vente): \Illuminate\Database\Eloquent\Collection
    {
        return EcritureComptable::where('libelle', 'Vente '.$vente->numero)
            ->whereNull('ecriture_contrepassee_id')
            ->get();
    }

    /**
     * Le crédit porté par la ligne d'un compte donné, ou l'échec du cas.
     *
     * @param  \Illuminate\Database\Eloquent\Collection<int, EcritureComptable>  $piece
     */
    private function creditDuCompte(\Illuminate\Database\Eloquent\Collection $piece, string $numero): string
    {
        foreach ($piece as $ecriture) {
            if ($this->compteDe($ecriture) === $numero) {
                return (string) $ecriture->credit;
            }
        }

        $this->fail("La pièce ne porte aucune ligne sur le compte {$numero}.");
    }

    private function compteDe(?EcritureComptable $ecriture): string
    {
        $this->assertNotNull($ecriture, 'La pièce ne porte pas la ligne attendue.');

        return CompteComptable::findOrFail($ecriture->compte_id)->numero_compte;
    }

    private function encaisserUneBiere(int $quantite, ?string $identifiant = null): Vente
    {
        $donnees = [
            'point_vente' => 'Bar',
            'mode_paiement' => 'especes',
            'lignes' => [['module' => 'M5', 'reference_id' => $this->biere->id, 'quantite' => $quantite]],
        ];

        if ($identifiant !== null) {
            $donnees['id'] = $identifiant;
        }

        return $this->ventes->enregistrer($donnees);
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
