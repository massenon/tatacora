<?php

declare(strict_types=1);

namespace Tests\Feature\Seeders;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\MarquesDePrix;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Comptabilite\Services\DeclarationTvaService;
use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Rh\Services\CalculPaieService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use Database\Seeders\DemonstrationSeeder;
use Database\Seeders\PaieReferentielSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les seeders de démonstration sont RÉELLEMENT EXÉCUTÉS — pas seulement écrits.
 *
 * Précédent direct : la spécification `SEEDER_TEST_LARAVEL.md` décrivait un
 * `StocksSeeder` qui, tel qu'écrit, échouait sur la contrainte NOT NULL de
 * `mouvements_stock.utilisateur_id` — un seeder documenté et jamais lancé est
 * la forme PA-59/60/61 du peuplement de données. Ces cas empruntent le chemin
 * entier, contraintes de clés et enums compris, et vérifient les données par
 * les MÊMES services que les écrans (stock théorique, coût matière) — jamais
 * par une seconde formule.
 *
 * ## Arbitrage (i)(j)(k) du 31/08/2026 — la démonstration COMPLÈTE fait foi
 *
 * Six des huit cas étaient rouges. Le Product Owner a tranché qu'ils tombent
 * par les DONNÉES : `RestaurantSeeder` réactivé, `StocksSeeder`,
 * `FournisseurSeeder`, `VehiculeSeeder` et `TourismeSeeder` rebranchés comme
 * auteurs uniques de leurs référentiels, leurs doublons en `DB::table()`
 * supprimés. Un seul nombre attendu a changé — le compte de réservations,
 * passé de 1 à 4 — et sa cause est écrite à l'endroit où il est vérifié.
 *
 * ## « Reprendre les seeders avec les données RÉELLES » — 03/09/2026
 *
 * Ordre du Product Owner. Les référentiels ne portaient pas les données du
 * Gîte mais celles de `SEEDER_TEST_LARAVEL.md` : cinq articles génériques pour
 * les 38 du maître, trois catégories d'hébergement pour six, cinq véhicules
 * aux tarifs arrondis pour huit, cinq circuits inventés pour treize
 * prestations du catalogue commercial, 37 plats pour 83, 24 boissons pour 33.
 *
 * ⚠ Aucune attente n'a été ABAISSÉE. Chaque nombre qui change porte sa cause à
 * l'endroit où il est vérifié, et le sens de la variation est toujours le
 * même : la démonstration montre plus, parce que le maître en porte plus.
 *
 * MUTATION PROUVÉE sur le refus de lecture (03/09/2026) : retirer « Béninoise
 * 66 cl (casier 12) » du catalogue de `StocksSeeder` fait échouer `db:seed`
 * sur le refus explicite de `BarSeeder`, avec le libellé manquant dans le
 * message — jamais sur un `LIKE` de repli, jamais en créant un second article
 * que personne n'approvisionne.
 */
final class AmorcageDemonstrationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DemonstrationSeeder::class);
    }

    #[Test]
    public function le_parc_les_stocks_et_les_deux_cartes_sont_reellement_amorces(): void
    {
        // M1 — le parc RÉEL du catalogue commercial
        // (`referentiel-tatacora.js` l.55-123) : six unites nommees d'apres
        // des oiseaux de l'Atacora, et SIX categories.
        //
        // 6 categories et non 3 depuis le 03/09/2026 : le tarif vit sur la
        // categorie, et les six unites du catalogue ont six tarifs distincts
        // (50 000 / 40 000 / 30 000 / 22 000 / 12 000 / 5 000 F la nuit).
        // Trois categories generiques en ecrasaient quatre sur six.
        // Toujours 6 au SEED — le 2ᵉ bungalow (PA-168, précisé le
        // 01/09/2026) se crée À L'ÉCRAN avec son tarif réel, jamais par un
        // seeder qui inventerait un prix opposable. La catégorie du Calao
        // s'appelle « Bungalow » tout court (catégories génériques, décision
        // PO).
        $this->assertSame(6, CategorieHebergement::count());
        $this->assertSame(6, UniteHebergement::count());
        $this->assertSame(1, CategorieHebergement::where('libelle', 'Bungalow')->count());
        $this->assertSame(
            1,
            UniteHebergement::where('numero', 'Calao à Bec Rouge')->where('statut', 'libre')->count(),
            'Le parc ne porte plus les noms du catalogue : « BNG-01 » etait un code de specification.',
        );

        // M6 — les 4 points, et le referentiel REEL du maitre
        // (`seed-donnees.js` l.45-96, 38 articles).
        //
        // ⚠ Le CONDITIONNEMENT fait partie du libelle : « Riz local (sac
        // 50 kg) » et non « Riz local ». Un sac de 50 kg et un sac de 25 kg
        // sont deux articles, et le maitre en porte les deux.
        $this->assertSame(4, PointStockage::count());
        $this->assertNotNull(Article::where('libelle', 'Riz local (sac 50 kg)')->first());
        $this->assertNotNull(Article::where('libelle', 'Riz parfumé importé (25 kg)')->first());

        // M5 — les 33 references du maitre : l'ardoise du bar (24, l.238-268)
        // ET le rayon « Jus maison & cafes » (9, l.213-223). C'est la somme
        // des deux, et la seule lecture qui rende les « 33 references du
        // bar » de `seed-restauration.js` l.15.
        //
        // 33 et non 24 depuis le 03/09/2026 : les jus maison et les cafes
        // n'existaient nulle part, si bien que le point de vente ne pouvait
        // pas encaisser un cafe.
        // 34 depuis le 01/09/2026 : « Vody / Loco » est scindé en deux
        // références (décision PO, PA-168) — 24 + 9 de l'ardoise et des jus,
        // plus la référence née de la scission.
        $this->assertSame(34, CarteBoisson::count());
        $this->assertSame(
            34,
            CarteBoisson::query()->distinct('article_id')->count('article_id'),
            'Deux boissons partagent un article : une 33 cl et une 66 cl se '
            .'decrementeraient du meme casier.',
        );

        // M4 — LA CARTE REELLE DU GITE : 94 preparations sur NEUF rayons
        // (04/09/2026, `menu_restaurant_reel.txt` remis par le Product Owner).
        //
        // 94 et non 83 : la carte venait du PROTOTYPE, qui ignorait l'ardoise
        // « plat + accompagnement » et les deux brochettes — onze preparations
        // qui se vendent tous les jours et n'existaient nulle part. Une carte
        // amputee s'affiche parfaitement, elle a juste moins de lignes, et
        // rien ne dit lesquelles.
        $this->assertSame(94, Plat::count());
        $this->assertSame(0, Article::where('libelle', 'Tchep au poisson')->count());

        // Les neuf rayons, avec leur compte : un rayon vide ne se voit pas
        // sur un total juste.
        //
        // ⚠ La cle est le CODE du rayon, plus son libelle affiche. Elle
        // portait « Entrées » alors que le filtre des ecrans interroge les
        // cles de `CarteRestaurant::CATEGORIES` (`entrees`) : le filtre par
        // rayon ne renvoyait JAMAIS aucune ligne sur les donnees reelles, sur
        // les deux ecrans. Ce cas tient desormais les deux bouts.
        $this->assertSame([
            'accompagnements' => 19,
            'desserts' => 8,
            'entrees' => 5,
            'formules' => 11,
            'garnitures' => 19,
            'pizzas' => 5,
            'plats' => 8,
            'sandwicherie' => 14,
            'sauces' => 5,
        ], Plat::query()->orderBy('categorie')
            ->get()->groupBy('categorie')->map->count()->all());

        // Chaque code de rayon seme EXISTE au registre : un code hors registre
        // s'afficherait en clair sur une chip du comptoir (« entrees »), et
        // son option de filtre n'existerait pas.
        foreach (Plat::query()->distinct()->pluck('categorie') as $code) {
            $this->assertArrayHasKey(
                (string) $code,
                \App\Pwa\Livewire\Restaurant\CarteRestaurant::CATEGORIES,
                "Le rayon « {$code} » n'est pas au registre : son filtre n'existe pas.",
            );
        }
    }

    /**
     * Deux contenances = DEUX articles, et deux casiers distincts.
     *
     * C'est la regle que le maitre ecrit lui-meme (`referentiel-carte.js`
     * l.229-232) et le defaut qu'elle previent est arrive : un `LIKE
     * '%Béninoise%'` sans `ORDER BY` a deja fait decrementer la 33 cl a la
     * place de la 66 (PA-161).
     *
     * MUTATION PROUVEE (03/09/2026) : faire pointer « Béninoise 33 cl » sur
     * l'article « Béninoise 66 cl (casier 12) » dans `BarSeeder` fait rougir
     * ce cas sur l'egalite des articles, ET le decompte de `article_id`
     * distincts du cas precedent. Retirer le casier de 12 du catalogue de
     * `StocksSeeder` le fait rougir sur le refus explicite du seeder.
     */
    #[Test]
    public function une_33_cl_et_une_66_cl_ne_sortent_pas_du_meme_casier(): void
    {
        $soixanteSix = CarteBoisson::where('libelle', 'Béninoise 66 cl')->firstOrFail();
        $trenteTrois = CarteBoisson::where('libelle', 'Béninoise 33 cl')->firstOrFail();

        $this->assertNotSame($soixanteSix->article_id, $trenteTrois->article_id);

        // Et les deux articles portent leur conditionnement REEL, celui du
        // maitre (`seed-donnees.js` l.64-65) : un casier de 12 pour la 66 cl,
        // de 24 pour la 33 cl.
        $this->assertSame(
            'Béninoise 66 cl (casier 12)',
            Article::whereKey($soixanteSix->article_id)->value('libelle'),
        );
        $this->assertSame(
            'Béninoise 33 cl (casier 24)',
            Article::whereKey($trenteTrois->article_id)->value('libelle'),
        );

        // Le taux de conversion carte -> stock est celui du casier, jamais le
        // 1 par defaut du schema. La migration `2026_09_01_110000` avertit
        // elle-meme que « se tromper de sens vide le stock 24 fois trop
        // vite » — et il valait 1 partout jusqu'au 03/09/2026.
        $this->assertSame(0, bccomp((string) $soixanteSix->unites_vendables_par_unite_stock, '12', 4));
        $this->assertSame(0, bccomp((string) $trenteTrois->unites_vendables_par_unite_stock, '24', 4));

        // Consequence directe : trois bouteilles vendues sortent un quart de
        // casier, pas trois casiers.
        $this->assertSame(0, bccomp($soixanteSix->stockConsommePour('3'), '0.25', 4));
    }

    /**
     * Trois prix de l'ardoise, epingles au franc pres.
     *
     * Ce sont des PRIX DE VENTE : ils sont appliques a de vrais clients a
     * chaque service. Un arrondi introduit en passant ne se verrait nulle
     * part — la carte s'afficherait parfaitement, avec un montant faux.
     *
     * MUTATION PROUVEE (03/09/2026) : passer la Guinness 33 cl de 900 a 950 F
     * dans `BarSeeder` fait rougir ce cas ; passer la Pizza cordon bleu de
     * 9 000 a 9 500 F aussi.
     */
    #[Test]
    public function les_prix_de_l_ardoise_et_de_la_carte_sont_ceux_du_maitre(): void
    {
        // Bar — `referentiel-carte.js` l.250 : la biere 33 cl la plus chere.
        $this->assertSame(0, bccomp(
            (string) CarteBoisson::where('libelle', 'Guinness 33 cl')->value('prix_vente'),
            '900',
            2,
        ));

        // Jus maison — l.214-215 : « moyen » et « grand » sont DEUX articles
        // vendables, pas une fourchette. Les traiter comme un prix unique
        // rendrait le POS incapable d'encaisser un grand format.
        $this->assertSame(0, bccomp(
            (string) CarteBoisson::where('libelle', "Jus d'ananas (moyen)")->value('prix_vente'),
            '1500',
            2,
        ));
        $this->assertSame(0, bccomp(
            (string) CarteBoisson::where('libelle', "Jus d'ananas (grand)")->value('prix_vente'),
            '2000',
            2,
        ));

        // Restaurant — l.190, le plat le plus cher de la carte.
        $this->assertSame(0, bccomp(
            (string) Plat::where('libelle', 'Pizza cordon bleu')->value('prix_vente'),
            '9000',
            2,
        ));
    }

    /**
     * Les tarifs du CATALOGUE COMMERCIAL, ceux qui sont opposables au client.
     *
     * `referentiel-tatacora.js` s'annonce lui-meme comme « une SOURCE DE
     * VERITE COMMERCIALE, pas un jeu de demo ». Les trois referentiels
     * ci-dessous etaient semes avec des valeurs arrondies de specification —
     * et aucune n'etait la bonne.
     *
     * MUTATION PROUVEE (03/09/2026) : remettre le Prado a 65 000 F (le chiffre
     * de `SPEC_ECRAN_M8_VEHICULES.md` §1) fait rougir ce cas. C'est
     * exactement l'ecart que le maitre signale l.171-177 : le catalogue
     * imprime affiche 70 000 F, et c'est lui qui est opposable au client.
     */
    #[Test]
    public function les_tarifs_semes_sont_ceux_du_catalogue_commercial(): void
    {
        // M1 — le bungalow du Calao, catalogue p. 11. Catégorie « Bungalow »
        // tout court depuis le 01/09/2026 (catégories génériques, décision
        // PO — PA-168).
        $this->assertSame(0, bccomp(
            (string) CategorieHebergement::where('libelle', 'Bungalow')->value('tarif_base'),
            '50000',
            2,
        ));

        // M8 — le Prado, catalogue p. 26 : 70 000 F et non 65 000.
        $this->assertSame(8, \App\Domain\Vehicules\Models\Vehicule::count());
        $this->assertSame(0, bccomp(
            (string) \App\Domain\Vehicules\Models\Vehicule::where(
                'immatriculation',
                \Database\Seeders\VehiculeSeeder::PRADO,
            )->value('tarif_jour'),
            '70000',
            2,
        ));

        // M9 — 13 prestations : 5 circuits (p. 20-21) et 8 excursions
        // (p. 22-23), qui vivent dans la meme table faute de colonne de
        // nature au schema.
        $this->assertSame(13, \App\Domain\Tourisme\Models\Circuit::count());
        $this->assertSame(0, bccomp(
            (string) \App\Domain\Tourisme\Models\Circuit::where('nom', 'Bénin Complet')->value('prix'),
            '561000',
            2,
        ));
        $this->assertSame(0, bccomp(
            (string) \App\Domain\Tourisme\Models\Circuit::where('nom', 'Chutes de Kota')->value('prix'),
            '35000',
            2,
        ));
    }

    /**
     * Le grand livre s'equilibre APRES l'amorcage complet.
     *
     * L'equilibre n'est garanti qu'a l'ecriture, piece par piece (PA-52) : il
     * n'y a aucun identifiant de piece au schema. Le verifier sur le TOTAL du
     * journal apres seed est donc un controle de flux — celui qui tombe si un
     * seeder pose une contrepartie sans son produit, ou l'inverse.
     *
     * MUTATION PROUVEE (03/09/2026) : c'est le controle qui a rougi quand la
     * commande d'achat de demonstration a change de lignes sans que son total
     * suive.
     */
    #[Test]
    public function le_grand_livre_est_equilibre_apres_l_amorcage(): void
    {
        $totaux = DB::table('ecritures_comptables')
            ->selectRaw('SUM(debit) AS debit, SUM(credit) AS credit')
            ->first();

        $this->assertNotNull($totaux);
        $this->assertSame(
            0,
            bccomp((string) $totaux->debit, (string) $totaux->credit, 2),
            'Le grand livre de demonstration est desequilibre : un mouvement d argent '
            .'a ete seme sans sa contrepartie.',
        );

        // Et il n'est pas vide — un journal a zero s'equilibre aussi.
        $this->assertSame(1, bccomp((string) $totaux->debit, '0', 2));
    }

    /**
     * Les deux marques de prix sont posees sur les BONNES lignes, et sur
     * elles seules.
     *
     * MUTATION PROUVEE (02/09/2026) : passer un seul `true` a `false` dans
     * `BarSeeder` ou `RestaurantSeeder` fait rougir ce cas sur le libelle
     * concerne. Les poser toutes a `true` le fait rougir sur le decompte.
     *
     * Le decompte compte autant que la liste : une marque posee partout ne
     * distingue plus rien, et « six lignes sur quatorze portent une etiquette »
     * deviendrait « la carte a ete refaite au stylo ».
     */
    #[Test]
    public function les_marques_de_prix_du_maitre_sont_posees_ligne_par_ligne(): void
    {
        $provisoires = CarteBoisson::query()
            ->where(MarquesDePrix::PROVISOIRE, true)
            ->orderBy('libelle')
            ->pluck('libelle')
            ->all();

        // « Vody / Loco » est SCINDÉ en deux références depuis le 01/09/2026
        // (décision du Product Owner, PA-168 — deux produits à 1 000 F, les
        // vins à 10 000 F la bouteille) : la liste du maître est amendée par
        // cette décision, la marque « provisoire » reste sur chacun.
        $this->assertSame([
            'EKU 66 cl',
            'Guinness 66 cl',
            'Loco',
            'Rhum',
            'Vin blanc',
            'Vin rouge',
            'Vody',
        ], $provisoires);

        $this->assertSame(0, bccomp((string) CarteBoisson::where('libelle', 'Vody')->value('prix_vente'), '1000', 2));
        $this->assertSame(0, bccomp((string) CarteBoisson::where('libelle', 'Loco')->value('prix_vente'), '1000', 2));
        $this->assertSame(0, bccomp((string) CarteBoisson::where('libelle', 'Vin rouge')->value('prix_vente'), '10000', 2));
        $this->assertSame(0, bccomp((string) CarteBoisson::where('libelle', 'Vin blanc')->value('prix_vente'), '10000', 2));

        // Les montants sont ceux du maitre, au franc pres : un tarif provisoire
        // « arrondi » en passant serait un prix de vente invente une seconde
        // fois, et le raisonnement consigne au maitre ne le couvrirait plus.
        $this->assertSame(0, bccomp(
            (string) CarteBoisson::where('libelle', 'EKU 66 cl')->value('prix_vente'),
            '1200',
            2,
        ));
        $this->assertSame(0, bccomp(
            (string) CarteBoisson::where('libelle', 'Guinness 66 cl')->value('prix_vente'),
            '1500',
            2,
        ));

        $corriges = Plat::query()
            ->where(MarquesDePrix::CORRIGE_MAIN, true)
            ->orderBy('libelle')
            ->pluck('libelle')
            ->all();

        // ⚠ UNE SEULE LIGNE, et non six (04/09/2026). La liste des six venait
        // du PROTOTYPE ; la carte reelle du client ne signale qu'une etiquette
        // manuscrite, en toutes lettres : « Chawarma poulet : 3 000 FCFA (Prix
        // corrige / 2000 FCFA) ». Marquer cinq lignes de plus aurait affirme
        // que cinq tarifs sont instables sans qu'aucun document ne le dise —
        // une marque posee a tort fait perdre a la marque son sens.
        $this->assertSame(['Chawarma poulet'], $corriges);

        // Le prix retenu est le MANUSCRIT, jamais l'imprime : 3 000 et non
        // 2 000. C'est le seul endroit ou la carte se corrige elle-meme.
        $this->assertSame(0, bccomp(
            (string) Plat::where('libelle', 'Chawarma poulet')->value('prix_vente'),
            '3000',
            2,
        ));

        // La Sandwicherie compte quatorze lignes : une marquee, treize non.
        // Sans ce decompte, semer la seule marquee laisserait la marque vraie
        // partout dans son rayon, ce qui ne signale plus rien.
        $this->assertSame(14, Plat::where('categorie', 'sandwicherie')->count());

        /*
         * DEUX PLATS PROVISOIRES, ET C'EST UNE CONTRADICTION MESUREE.
         *
         * Le document du client porte DEUX documents : la carte imprimee et
         * une ardoise. Elles se contredisent sur deux plats, et sur eux seuls —
         * Ragout de poulet (5 000 contre 6 000) et Ragout de mouton (4 000
         * contre 6 000). Le prix de la carte imprimee est retenu, et la marque
         * dit qu'il reste a confronter. Prendre 5 500 « au milieu » aurait ete
         * l'hypothese que ce depot refuse partout.
         */
        $this->assertSame(
            ['Ragoût de mouton', 'Ragoût de poulet'],
            Plat::query()->where(MarquesDePrix::PROVISOIRE, true)->orderBy('libelle')->pluck('libelle')->all(),
        );

        // Aucune ligne ne porte les DEUX marques : les confondre perdrait la
        // raison — aller lire l'ardoise, ou faire retirer l'etiquette collee.
        $this->assertSame(
            0,
            Plat::query()
                ->where(MarquesDePrix::PROVISOIRE, true)
                ->where(MarquesDePrix::CORRIGE_MAIN, true)
                ->count(),
        );
        $this->assertSame(0, CarteBoisson::where(MarquesDePrix::CORRIGE_MAIN, true)->count());
    }

    #[Test]
    public function le_stock_seme_est_lisible_par_le_vrai_service_de_stock_theorique(): void
    {
        $beninoise = Article::where('libelle', 'Béninoise 66 cl (casier 12)')->firstOrFail();
        $bar = PointStockage::where('libelle', 'Bar')->firstOrFail();

        // La quantité vient de l'agrégation des mouvements — le seul stock qui
        // existe dans ce schéma.
        //
        // 15,75 et non 21 depuis le 03/09/2026, et le chiffre porte tout le
        // correctif : le stock est en CASIERS (16 au départ, `seed-donnees.js`
        // l.64) et la vente sort `3 / 12 = 0,25` casier. Auparavant le taux de
        // conversion valait 1 partout, si bien que trois bouteilles vendues
        // sortaient trois CASIERS — un facteur douze, qui n'apparaît qu'à
        // l'inventaire et s'impute à une perte physique.
        $stock = app(StockTheoriqueService::class)->stock($beninoise->id, $bar->id);
        $this->assertSame(0, bccomp($stock, '15.75', 2));

        // Et les filtres à huile démarrent SOUS leur seuil : l'écran d'alertes
        // a réellement quelque chose à montrer, comme au prototype.
        //
        // Ce n'est plus le poisson : le référentiel du maître n'ouvre AUCUN
        // article sous son seuil, tous ses stocks initiaux sont au-dessus. Les
        // deux articles de garage sont les seuls du dépôt qui ne viennent pas
        // du maître (il ne porte aucun article de garage), et c'est là que la
        // rupture de démonstration a été gardée.
        $filtres = Article::where('libelle', 'Filtres à huile (véhicules)')->firstOrFail();
        $garage = PointStockage::where('libelle', 'Garage')->firstOrFail();
        $this->assertSame(
            -1,
            bccomp(app(StockTheoriqueService::class)->stock($filtres->id, $garage->id), (string) $filtres->seuil_alerte, 2),
        );

        // Le petit stock du maître n'a AUCUN mouvement : « les tomates
        // achetées au marché chaque matin ne se suivent pas en permanence,
        // sous peine d'écarts d'inventaire permanents ». Un stock initial posé
        // sur un article journalier serait un solde théorique qui ne
        // correspond à rien de compté.
        $tomate = Article::where('libelle', 'Tomate fraîche')->firstOrFail();
        $this->assertSame('journalier', $tomate->suivi);
        $this->assertFalse($tomate->estSuiviEnStock());
        $this->assertSame(0, $tomate->mouvements()->count());

        // Le prix d'achat du maître est entré par la porte réelle
        // (`MouvementStockService::entree()`, seul chemin qui l'écrit), et le
        // coût moyen pondéré est né de l'entrée qui le justifie.
        $riz = Article::where('libelle', 'Riz local (sac 50 kg)')->firstOrFail();
        $this->assertSame(0, bccomp((string) $riz->prix_achat, '32000', 2));
        $this->assertSame(0, bccomp((string) $riz->cout_moyen_pondere, '32000', 2));

        // Et il reste NUL là où aucune source ne le donne : le garage n'est
        // tarifé par personne, et zéro se lirait « gratuit ».
        $this->assertNull($filtres->prix_achat);
    }

    /**
     * ⚠ CE CAS S'APPELAIT `…_et_les_autres_restent_vides`, ET IL AVAIT TORT.
     *
     * Il gardait une décision devenue un défaut : « les autres fiches sont
     * VIDES, leur coût matière vaut 0 non renseigné, jamais un montant qu'aucune
     * pesée n'a produit ». Le raisonnement était juste — un grammage inventé
     * décrémente un stock réel — et sa conséquence ne l'était pas : une fiche
     * vide n'est pas une fiche neutre, c'est une vente REFUSÉE
     * (`DeductionStockCuisineService` lève `RecetteManquanteException`). Sur
     * 83 plats, 82 fiches vides bloquaient le point de vente restaurant EN
     * ENTIER, et ce cas VERT tenait le blocage en place (PA-179, 04/09/2026).
     *
     * Arbitrage du Product Owner : semer des compositions plausibles, « on
     * pourra modifier » — la décision de PA-161 (b) sur les prix, mot pour mot.
     * Elle appelle la même protection, et c'est ce que ce cas vérifie
     * désormais : chaque fiche semée porte `composition_provisoire`, et la
     * seule fiche PESÉE ne la porte pas.
     */
    #[Test]
    public function la_fiche_du_tchep_est_pesee_et_les_autres_sont_posees_puis_marquees(): void
    {
        $tchep = Recette::where('libelle', 'Tchep au poisson')->firstOrFail();
        $this->assertSame(3, $tchep->ingredients()->count());

        // Les ingrédients sont de VRAIES clés étrangères vers le référentiel
        // de `StocksSeeder`, portant son conditionnement : « Riz local (sac
        // 50 kg) » et non « Riz local », qu'aucun article ne porte plus.
        $this->assertEqualsCanonicalizing(
            ['Poisson carpe (kg)', 'Riz local (sac 50 kg)', 'Huile végétale (bidon 20 L)'],
            $tchep->ingredients()->pluck('libelle')->all(),
        );

        // La seule fiche dont les quantités viennent de la cuisine : elle NE
        // porte PAS la marque.
        $this->assertFalse($tchep->composition_provisoire);

        // AUCUNE fiche vide : chacune est composée, donc chaque plat est
        // vendable. C'est la moitié qui débloque le comptoir.
        $this->assertSame(
            0,
            Recette::query()->whereDoesntHave('ingredients')->count(),
            'Une fiche vide ne sortirait aucun stock à la vente (le plat se vendrait quand même).',
        );

        // …et l'autre moitié, qui empêche le déblocage de devenir un mensonge :
        // les compositions POSÉES sont marquées, sans quoi un grammage deviné
        // et un grammage pesé seraient indiscernables en base, et l'écart ne se
        // verrait qu'à l'inventaire — imputé à une perte qui n'a pas eu lieu.
        $salade = Recette::where('libelle', 'Salade verte')->firstOrFail();
        $this->assertGreaterThan(0, $salade->ingredients()->count());
        $this->assertTrue($salade->composition_provisoire);

        $this->assertSame(
            Recette::query()->count() - 1,
            Recette::query()->where(Recette::PROVISOIRE, true)->count(),
            'Toute fiche semée porte la marque, sauf la seule qui a été pesée.',
        );
    }

    /**
     * LES 94 PLATS DE LA CARTE SE VENDENT REELLEMENT — 04/09/2026.
     *
     * ## Le defaut que ce cas ferme, et pourquoi aucun autre ne le voyait
     *
     * Les fiches techniques ont ete composees le matin meme, et le point de
     * vente restaurant restait bloque : `DeductionStockCuisineService` sort les
     * denrees du point de type `cuisine`, et de lui seul. Or le riz, la farine
     * et l'huile ont pour point principal le MAGASIN. La premiere vente levait
     * `RuptureStockException` — « 0.00 disponible, 0.01 demande » — alors que
     * la fiche etait juste : le stock etait au mauvais endroit.
     *
     * Les cas existants ne pouvaient pas le voir. `FichesTechniquesPwaTest`
     * cree son propre stock a la cuisine ; ce fichier verifiait que les fiches
     * EXISTENT, jamais qu'une vente PASSE. C'est la question « quel chemin n'a
     * jamais ete execute ? » : entre « la fiche est composee » et « le plat se
     * vend », il y a un point de stockage que personne ne confrontait.
     *
     * ## Il vend la carte ENTIERE, pas un echantillon
     *
     * Un plat temoin aurait passe — le Tchep passait deja. Ce sont des rayons
     * entiers qui manquaient de matiere : les feculents, les poissons autres
     * que la carpe, la volaille autre que le poulet, la boulangerie. Une carte
     * se vend en entier, ou elle bloque une table sur deux.
     *
     * ## Mutation REELLEMENT executee puis annulee (04/09/2026)
     *
     * | Mutation | Resultat |
     * |---|---|
     * | `StocksSeeder::approvisionnerLaCuisine()` neutralisee | 1 failed — 62 plats sur 94 refuses, tous en `RuptureStockException` |
     *
     * ⚠ 62 et non 94 : les plats dont TOUS les ingredients sont journaliers se
     * vendent encore, et c'est correct — rien chez eux n'est suivi en stock.
     * C'est aussi ce qui rend la mutation instructive : un cas qui n'aurait
     * teste qu'une salade serait reste vert.
     */
    #[Test]
    public function les_quatre_vingt_quatorze_plats_de_la_carte_se_vendent_vraiment(): void
    {
        $this->actingAs(\App\Models\User::query()->where('statut', 'actif')->firstOrFail());

        $ventes = app(\App\Domain\Ventes\Services\VenteService::class);
        $refus = [];

        foreach (Plat::query()->orderBy('libelle')->get() as $plat) {
            try {
                $ventes->enregistrer([
                    'point_vente' => 'Restaurant',
                    'mode_paiement' => 'especes',
                    'lignes' => [['module' => 'M4', 'reference_id' => $plat->id, 'quantite' => 1]],
                ]);
            } catch (\Throwable $echec) {
                $refus[] = $plat->libelle.' : '.class_basename($echec).' - '.$echec->getMessage();
            }
        }

        $this->assertSame(
            [],
            $refus,
            "Des plats de la carte ne se vendent pas au comptoir :\n  ".implode("\n  ", $refus),
        );

        // Et le stock a REELLEMENT bouge : compter les ventes sans regarder les
        // mouvements dirait que la vente passe, jamais qu'elle consomme.
        $this->assertGreaterThan(
            0,
            \App\Domain\Stocks\Models\MouvementStock::query()
                ->where('type_mouvement', 'sortie')
                ->whereHas('point', fn ($q) => $q->where('type', 'cuisine'))
                ->count(),
        );

        /*
         * ⚠ ET AUCUN ARTICLE JOURNALIER N'A BOUGE.
         *
         * `Article::estSuiviEnStock()` porte la regle depuis toujours — « un
         * article journalier REFUSE le mouvement de stock » — et elle n'etait
         * branchee nulle part sur ce chemin. La laitue, la tomate et l'oignon
         * sont nommes par les cinq entrees et les cinq pizzas de la carte
         * reelle : sans ce filtre, chacun de ces dix plats levait une rupture
         * sur un article que personne ne compte ni ne reapprovisionne.
         */
        $this->assertSame(
            0,
            \App\Domain\Stocks\Models\MouvementStock::query()
                ->whereHas('article', fn ($q) => $q->where('suivi', 'journalier'))
                ->count(),
            'Un article journalier a recu un mouvement de stock : son solde theorique ne '
            .'correspond a rien de compte.',
        );
    }

    #[Test]
    public function relancer_les_seeders_ne_double_ni_le_parc_ni_le_stock(): void
    {
        // Un second `db:seed` arrive toujours (déploiement rejoué, agent qui
        // relance). Six chambres dédoublées feraient apparaître libre une
        // unité déjà prise ; un mouvement d'entrée dupliqué serait
        // indiscernable d'une vraie livraison.
        $this->seed(DemonstrationSeeder::class);

        $this->assertSame(6, CategorieHebergement::count());
        $this->assertSame(6, UniteHebergement::count());
        // 34 : Vody et Loco scindés (PA-168).
        $this->assertSame(34, CarteBoisson::count());
        // 94 : la carte REELLE du client (04/09/2026), ardoise comprise.
        $this->assertSame(94, Plat::count());
        // 98 : 57 + les 41 denrees que la carte reelle nomme — douze par ses
        // listes d'ingredients, vingt-neuf par les libelles des plats
        // eux-memes (« Frites d'igname », « Demi pintade », « Crepe au miel »).
        // Sans elles, la fiche technique de ces plats n'aurait pu porter
        // aucune ligne, et une fiche vide ne sortirait aucun stock à la vente.
        $this->assertSame(98, Article::count());
        $this->assertSame(13, \App\Domain\Tourisme\Models\Circuit::count());
        $this->assertSame(8, \App\Domain\Vehicules\Models\Vehicule::count());
        $this->assertSame(10, \App\Domain\Rh\Models\Employe::count());
        $this->assertSame(10, \App\Domain\Notifications\Models\ModeleNotification::count());

        $beninoise = Article::where('libelle', 'Béninoise 66 cl (casier 12)')->firstOrFail();
        $bar = PointStockage::where('libelle', 'Bar')->firstOrFail();
        // 15,75 et non 15,50 : les 3 ventes de l'exploitation ne doivent pas
        // être REJOUÉES au second passage — ni l'entrée initiale de 16
        // casiers, qui serait indiscernable d'une vraie livraison.
        $this->assertSame(0, bccomp(app(StockTheoriqueService::class)->stock($beninoise->id, $bar->id), '15.75', 2));
    }

    #[Test]
    public function le_compte_d_amorcage_est_desactive_et_ne_peut_pas_se_connecter(): void
    {
        // L'auteur du stock initial est un compte technique DÉSACTIVÉ au mot
        // de passe aléatoire jamais retenu. RG-15 le garde en base pour que
        // les mouvements portent leur auteur ; il n'ouvre pour personne.
        $compte = User::where('login', 'amorcage.systeme')->firstOrFail();

        $this->assertSame('desactive', $compte->statut);
        $this->assertFalse($compte->estActif());
    }

    #[Test]
    public function les_onze_comptes_de_recette_existent_et_savent_s_authentifier(): void
    {
        // Demandé par le Product Owner le 28/08/2026 : la recette de la PWA
        // exige de pouvoir OUVRIR l'écran de connexion. Le mot de passe est
        // `demo-<login>` (SEEDER_TEST_LARAVEL.md §2), et `UtilisateurSeeder`
        // REFUSE de tourner hors local/development/testing — le test tourne
        // en `testing`, c'est ce qui le laisse passer.
        $this->assertSame(12, User::count()); // 11 comptes + amorçage désactivé

        $gerant = User::where('login', 'n.nabogou')->firstOrFail();
        $this->assertTrue($gerant->estActif());
        $this->assertTrue(Hash::check('demo-n.nabogou', $gerant->mot_de_passe_hash));
        $this->assertSame('gerant', $gerant->role->libelle);
    }

    #[Test]
    public function les_referentiels_m7_m8_m9_et_les_caisses_sont_amorces(): void
    {
        $this->assertSame(6, \App\Domain\Achats\Models\Fournisseur::count());
        // 13 prestations et 8 vehicules : le catalogue commercial, pas la
        // specification. Detail et cause dans
        // {@see les_tarifs_semes_sont_ceux_du_catalogue_commercial}.
        $this->assertSame(13, \App\Domain\Tourisme\Models\Circuit::count());
        $this->assertSame(8, \App\Domain\Vehicules\Models\Vehicule::count());

        // Les deux guides sont des EMPLOYES du gite, pas des noms generiques :
        // ADJOVI Paul (Chauffeur-guide, service Tourisme) et GNANSOUNOU Eric.
        // « Guide Touristique Referent » n'existait nulle part ailleurs.
        $this->assertEqualsCanonicalizing(
            ['ADJOVI Paul', 'GNANSOUNOU Éric'],
            \App\Domain\Tourisme\Models\Guide::pluck('nom')->all(),
        );
        // Et leur certification reste NULLE : un titre professionnel ne
        // s'invente pas, meme famille qu'un IFU d'exemple sur une facture.
        $this->assertSame(0, \App\Domain\Tourisme\Models\Guide::whereNotNull('certification')->count());

        // Les TROIS caisses du schéma — et seulement elles : « plage » et
        // « jardin » sont des zones de tables de salle (locales au client
        // Flutter), pas des points de vente de l'enum. Ouvertes : la clôture
        // est un geste métier (PA-21), pas une donnée d'amorçage.
        $sessions = DB::table('sessions_caisse')->whereNull('date_cloture')->pluck('point_vente');
        $this->assertEqualsCanonicalizing(['reception', 'restaurant', 'bar'], $sessions->all());
    }

    /**
     * M12 N'ÉTAIT PAS DÉMONTRÉ (relevé du 02/09/2026, audit navigateur du
     * Product Owner) : `modeles_notification` n'avait aucun auteur, et
     * l'onglet « Modèles » rendait « Aucun modèle » sur une base fraîchement
     * amorcée — le quatorzième module du CdCF manquait à la démonstration
     * complète que l'arbitrage (i)(j)(k) du 31/08/2026 exige. Les dix
     * modèles du maître (`notifications-engine.js` `MODELES_SOCLE`) sont
     * désormais réellement rendus, cartes et gestes compris.
     *
     * Éprouvé par mutation le 02/09/2026 : décrocher `NotificationsModelesSeeder`
     * de `DemonstrationSeeder` fait rougir ce cas sur « 0 n'est pas identique à
     * 10 » — restauré ensuite.
     */
    #[Test]
    public function les_dix_modeles_de_notification_sont_amorces_et_rendus_a_l_ecran(): void
    {
        $this->assertSame(10, \App\Domain\Notifications\Models\ModeleNotification::count());

        // Le couple identifié par le maître comme désactivé par défaut
        // (créance échue, par e-mail) le reste : un modèle « livré » n'est
        // pas nécessairement un modèle « actif ».
        $creanceMail = \App\Domain\Notifications\Models\ModeleNotification::query()
            ->where('evenement', 'creance_echue')
            ->where('canal', 'email')
            ->firstOrFail();
        $this->assertFalse($creanceMail->actif);

        $gerant = User::where('login', 'n.nabogou')->firstOrFail();
        $html = (string) $this->actingAs($gerant)
            ->get('/pwa/notifications?onglet=modeles')
            ->assertOk()
            ->getContent();

        // La carte est rendue — jamais plus « Aucun modèle » — et porte les
        // deux gestes réels du maître : Modifier, Activer/Désactiver.
        $this->assertStringNotContainsString(__('notifications_pwa.aucun_modele'), $html);
        $this->assertStringContainsString(__('notifications_pwa.modele_modifier'), $html);
        $this->assertStringContainsString(__('notifications_pwa.modele_activer'), $html);
        $this->assertStringContainsString(__('notifications_pwa.modele_desactiver'), $html);
    }

    #[Test]
    public function l_exploitation_de_demonstration_est_passee_par_les_vrais_services(): void
    {
        // Les séjours : QUATRE, et non un — le chiffre a changé le 31/08/2026
        // avec sa cause, jamais pour faire passer le cas.
        //
        // Trois viennent de `HebergementExploitationSeeder` (le registre M1 :
        // un séjour clos, un en cours, un confirmé à venir, tous sur CH-101) et
        // un de `ExploitationDemonstrationSeeder` (le séjour du jour sur
        // CH-102, celui qui porte la vente imputée du bar et la commande du
        // restaurant). Le test n'en voyait qu'un parce que les trois autres
        // étaient insérés en `DB::table()`, donc hors de
        // `VerificationChevauchementService` : ils existaient bel et bien, mais
        // RG-01 n'avait jamais tourné dessus. Ils passent désormais par
        // `ReservationService`.
        $reservations = \App\Domain\Hebergement\Models\Reservation::query()
            ->orderBy('date_arrivee')->get();
        $this->assertCount(4, $reservations);

        // Ce que le passage par le service achète, et qu'un compte ne dit pas :
        // deux séjours ne se chevauchent jamais sur la même unité. Bornes
        // SEMI-OUVERTES — un départ le jour d'une arrivée n'est pas un conflit,
        // et c'est le cas réellement présent (CH-101, deux séjours bout à bout).
        foreach ($reservations as $a) {
            foreach ($reservations as $b) {
                if ($a->id === $b->id || $a->unite_id !== $b->unite_id) {
                    continue;
                }

                $this->assertTrue(
                    $a->date_depart <= $b->date_arrivee || $b->date_depart <= $a->date_arrivee,
                    'Deux sejours de demonstration se chevauchent sur la meme unite : '
                    .'RG-01 a ete contournee par le seeder.',
                );
            }
        }

        // Et chacun porte son auteur — les services tournent sous une identité
        // réelle, pas en anonyme (RG-15).
        $this->assertSame(
            0,
            $reservations->whereNull('utilisateur_creation_id')->count(),
            'Un sejour de demonstration sans auteur : le seeder a ecrit hors session.',
        );

        // Le bar : une vente comptant, une imputée — et le MONTANT est celui
        // que le service a calculé des lignes, jamais une valeur posée.
        $ventes = \App\Domain\Bar\Models\VenteBar::query()->orderBy('date_vente')->get();
        $this->assertCount(2, $ventes);
        $this->assertNull($ventes[0]->client_id);
        $this->assertSame(0, bccomp((string) $ventes[0]->montant, '1600', 2)); // 2 × 800
        $this->assertNotNull($ventes[1]->client_id);
        $this->assertSame(0, bccomp((string) $ventes[1]->montant, '1800', 2)); // 800 + 2 × 500

        // Et la vente a RÉELLEMENT sorti le stock, au taux de conversion du
        // casier : 16 casiers − 3/12 = 15,75. Cause détaillée en
        // {@see le_stock_seme_est_lisible_par_le_vrai_service_de_stock_theorique}.
        $beninoise = Article::where('libelle', 'Béninoise 66 cl (casier 12)')->firstOrFail();
        $bar = PointStockage::where('libelle', 'Bar')->firstOrFail();
        $this->assertSame(0, bccomp(app(StockTheoriqueService::class)->stock($beninoise->id, $bar->id), '15.75', 2));

        // Le restaurant : une commande rattachée au client hébergé.
        $this->assertSame(1, \App\Domain\Restaurant\Models\CommandeRestaurant::count());

        // L'inventaire magasin : l'écart du riz est CALCULÉ (18 − 17,5).
        //
        // Magasin et non cuisine depuis le 03/09/2026 : le maître range le riz
        // au magasin général (`seed-donnees.js` l.47). Le compter à la cuisine
        // aurait donné un écart de +17,5 sacs sur un point où son stock
        // théorique vaut zéro — un inventaire qui invente de la marchandise.
        $ligne = \App\Domain\Stocks\Models\LigneInventaire::query()
            ->whereHas('article', fn ($q) => $q->where('libelle', 'Riz local (sac 50 kg)'))
            ->firstOrFail();
        // 13,5 et non 17,5 : `StocksSeeder` transfere 4 sacs du magasin vers la
        // CUISINE (sans ce stock de travail, aucun plat ne se vendait). Le
        // theorique du magasin passe de 18 a 14 ; l'ecart de −0,5 sac, lui,
        // est conserve — c'est le fait que ce comptage existe pour montrer.
        $this->assertSame(0, bccomp((string) $ligne->quantite_constatee, '13.5', 2));

        // Et personne n'est resté connecté derrière le seeder.
        $this->assertGuest();
    }

    /**
     * La facture de démonstration est ÉMISE par le service, jamais insérée.
     *
     * ## Le défaut que ce cas épingle (01/09/2026)
     *
     * `HebergementExploitationSeeder` posait un `DB::table('factures')
     * ->insert()` direct : une pièce à 100 000 F TTC **sans aucune ligne**
     * (RG-04 ignorée), une TVA de 18 % écrite à la main alors que la TVA du
     * système est inactive, un total qu'aucune ligne ne soutient. Rien ne le
     * voyait : les 36 cas de cette classe mesuraient des comptes, pas la
     * FORME de la pièce — et la ventilation par activité du tableau de bord
     * n'avait rien à tracer sur une base pourtant « semée ».
     *
     * Mutation vérifiée : remettre l'ancien `insert()` sans ligne rend ce cas
     * rouge sur `lignes de la facture` et sur `total soutenu par les lignes`.
     */
    #[Test]
    public function la_facture_de_demonstration_est_emise_par_le_service_avec_ses_lignes(): void
    {
        $factures = \App\Domain\Facturation\Models\Facture::query()->get();
        $this->assertCount(1, $factures);

        $facture = $factures->first();

        // La pièce porte au moins une ligne RG-04, et sa source est un
        // enregistrement RÉEL — le séjour terminé de la démonstration.
        $lignes = $facture->lignes()->get();
        $this->assertGreaterThanOrEqual(1, $lignes->count(), 'lignes de la facture');
        $this->assertSame('M1', $lignes->first()->source_module);
        $this->assertTrue(
            \App\Domain\Hebergement\Models\Reservation::query()
                ->whereKey($lignes->first()->source_id)->exists(),
            'La ligne M1 doit pointer un sejour existant, jamais un id invente.',
        );

        // Le total est SOUTENU par les lignes : HT = somme des lignes,
        // TTC = HT + TVA — la définition même de `recalculerTotaux()`.
        $totalLignes = '0.00';
        foreach ($lignes as $ligne) {
            $totalLignes = bcadd($totalLignes, (string) $ligne->montant, 2);
        }
        $this->assertSame(0, bccomp((string) $facture->montant_ht, $totalLignes, 2), 'total soutenu par les lignes');
        $this->assertSame(
            0,
            bccomp((string) $facture->montant_ttc, bcadd((string) $facture->montant_ht, (string) $facture->montant_tva, 2), 2),
        );

        // La certification est de DÉMONSTRATION et se dit comme telle : le
        // prédicat la reconnaît, et `estCertifiee()` ne la prend jamais pour
        // une vraie certification fiscale (PA-61/PA-100).
        $this->assertTrue($facture->estCertificationDemonstration());
        $this->assertFalse($facture->estCertifiee());
        $this->assertTrue($facture->estFigee());
    }

    #[Test]
    public function les_commandes_d_achat_sont_saisissables_et_la_tolerance_rg10_n_est_pas_semee(): void
    {
        // M7 — deux commandes, chacune AVEC ses lignes. Une commande sans
        // ligne est réceptionnable, et sa réception serait déclarée
        // `non_conforme` pour un motif que personne ne pourrait expliquer.
        $commandes = \App\Domain\Achats\Models\CommandeAchat::query()->with('lignes')->get();
        $this->assertCount(2, $commandes);
        $this->assertSame(0, $commandes->filter(fn ($c) => $c->lignes->isEmpty())->count());

        // Aucune n'est « Réceptionnée » : ce statut est PRODUIT par une
        // réception qui a réellement généré ses entrées de stock, jamais posé
        // (`CommandeAchatService::STATUTS_SAISISSABLES`). Le maître en montre
        // deux ; les afficher sans mouvement en face serait PA-59/60/61.
        $this->assertEqualsCanonicalizing(
            ['envoyee', 'brouillon'],
            $commandes->pluck('statut')->all(),
        );

        // ⚠ ARBITRAGE (e) DU 31/08/2026 — la tolérance de réception RG-10
        // n'est semée NULLE PART, et ce cas est ce qui l'empêche de le
        // redevenir. Elle se saisit à l'écran Paramètres, par un
        // Administrateur muni d'une décision de gestion ; un pourcentage
        // deviné par un seeder ferait accepter ou refuser des livraisons sur
        // un critère arbitraire, et deviendrait la règle de production sans
        // que personne ne le rouvre (PA-53, même famille que le taux d'IS).
        $this->assertSame(
            0,
            \App\Shared\Parametres\Models\ParametreSysteme::query()
                ->where('cle', \App\Domain\Achats\Services\ReceptionService::CLE_TOLERANCE)
                ->count(),
            'La tolerance RG-10 a ete semee : elle doit se saisir a l ecran Parametres.',
        );

        // Conséquence directe et voulue : réceptionner refuse, en nommant la
        // clé à configurer.
        $this->expectException(\RuntimeException::class);
        app(\App\Domain\Achats\Services\ReceptionService::class)->tolerancePourcentage();
    }

    /**
     * Les deux referentiels de parametres sont REELLEMENT executes — et ce
     * qui doit rester absent l'est.
     *
     * ## Le defaut ferme ici (02/09/2026)
     *
     * `PaieReferentielSeeder` et `TvaReferentielSeeder` ne figuraient dans
     * AUCUN appel de `DemonstrationSeeder` : sixieme et septieme occurrences du
     * defaut de PA-160/PA-161 — un auteur de referentiel ecrit, documente, et
     * jamais execute. Sur toute base semee, `parametres_systeme` etait VIDE :
     * `CalculPaieService` levait a chaque calcul, et la declaration de TVA
     * n'avait ni ses deux comptes ni son taux.
     *
     * Le premier branchement a d'ailleurs ECHOUE — la description du VPS
     * faisait 346 caracteres pour une colonne `varchar(255)`. Un seeder
     * decroche n'est pas du code dormant, c'est du code jamais execute : la
     * lecon exacte de PA-59/60/61, appliquee aux seeders.
     *
     * ## Ce cas mesure les DEUX moities, et la seconde compte autant
     *
     * MUTATION PROUVEE : decrocher l'un des deux seeders de `DemonstrationSeeder`
     * fait rougir la premiere moitie. Ajouter
     * `taux_cnss_risques_professionnels` au seeder fait rougir la seconde —
     * c'est elle qui empeche de « completer » le referentiel avec un taux que
     * personne n'a confirme (PA-53). Sans elle, brancher le seeder aurait
     * ouvert la porte a exactement ce que le refus de calculer protege.
     */
    #[Test]
    public function les_referentiels_de_paie_et_de_tva_sont_semes_sans_aucun_taux_devine(): void
    {
        // 1. Les taux SOURCES sont la — sans eux, la paie ne calcule rien.
        foreach ([
            CalculPaieService::CLE_CNSS_SALARIE => '3.6',
            CalculPaieService::CLE_CNSS_PENSION_EMPLOYEUR => '6.4',
            CalculPaieService::CLE_CNSS_PRESTATIONS_FAMILIALES => '9',
            CalculPaieService::CLE_VPS => '4',
        ] as $cle => $attendu) {
            $valeur = ParametreSysteme::where('cle', $cle)->value('valeur');
            $this->assertNotNull($valeur, "Le taux {$cle} n'est seme par personne.");
            $this->assertSame(0, bccomp((string) $valeur, $attendu, 2), "Le taux {$cle} a change de valeur.");
        }

        // 2. Ce qui est DELIBEREMENT absent le reste. Le refus de calculer est
        //    le livrable (PA-53) : une valeur plausible inscrite ici
        //    deviendrait la regle de production, et personne ne la rouvrirait.
        foreach (PaieReferentielSeeder::parametresEnAttenteDeDecision() as $cle) {
            $this->assertSame(
                0,
                ParametreSysteme::where('cle', $cle)->count(),
                "Le parametre {$cle} a ete seme : il attend une decision, pas une valeur par defaut.",
            );
        }

        // 3. Consequence directe et voulue, mesuree sur les DEUX chemins : la
        //    part CONFIRMEE se calcule (19,4 % du brut : 6,4 + 9 + 4), et le
        //    total, lui, REFUSE — le taux de risques professionnels est « 1 %
        //    a 4 % selon l'activite », et le moyenner a 2,5 % serait
        //    exactement l'hypothese que PA-53 interdit.
        $paie = app(CalculPaieService::class);
        $this->assertSame(0, bccomp($paie->chargesPatronalesConfirmees('100000')['total'], '19400', 2));

        try {
            $paie->chargesPatronales('100000');
            $this->fail('La charge patronale TOTALE doit refuser tant que le taux de risques est absent.');
        } catch (\RuntimeException) {
            // Le refus est le livrable.
        }

        // 4. La TVA est semee INACTIVE. Une taxe active par defaut serait
        //    facturee a de vrais clients sans qu'aucune decision ne l'autorise.
        // « active » depuis la décision du PO du 01/09/2026 (prix TTC,
        // 18 %) — l'acte d'administration que l'état inactif attendait est
        // rendu, et le référentiel le seed (PA-168).
        $this->assertSame('active', app(CalculTvaService::class)->etatTva());
        $this->assertSame(0, bccomp((string) app(CalculTvaService::class)->taux(), '18', 2));

        // 5. Et ses deux comptes existent : sans eux, `DeclarationTvaService`
        //    lirait le solde d'un compte qui n'est pas au plan.
        foreach ([DeclarationTvaService::COMPTE_TVA_COLLECTEE, DeclarationTvaService::COMPTE_TVA_DEDUCTIBLE] as $numero) {
            $this->assertSame(1, CompteComptable::where('numero_compte', $numero)->count());
        }
    }

    /**
     * L'effectif REEL du gite — et ce que le maitre porte en plus.
     *
     * Les dix fiches etaient deja semees, mais trois colonnes du schema
     * restaient vides alors que le maitre en porte la donnee : `type_contrat`,
     * `date_fin_contrat` et `matricule`. Une echeance de CDD qu'aucune colonne
     * ne porte est une echeance que personne ne verra passer.
     *
     * MUTATION PROUVEE (03/09/2026) : passer le contrat de Rachidatou BIO a
     * `CDI` dans `PersonnelSeeder` fait rougir ce cas sur les deux dernieres
     * assertions a la fois — le type ET la date de fin.
     */
    #[Test]
    public function l_effectif_du_maitre_est_seme_avec_ses_contrats(): void
    {
        $this->assertSame(10, \App\Domain\Rh\Models\Employe::count());
        $this->assertSame(6, DB::table('services')->count());

        // Un employe est volontairement SANS numero CNSS : c'est le cas reel
        // d'une embauche anterieure a l'immatriculation, et l'ecran doit le
        // signaler sans empecher le calcul du bulletin. Ne pas « completer ».
        $sansCnss = DB::table('employes')->whereNull('numero_cnss')->pluck('nom');
        $this->assertSame(['BIO'], $sansCnss->all());

        // Neuf CDI et un CDD, celui de la meme personne.
        $cdd = DB::table('employes')->where('type_contrat', 'CDD')->get();
        $this->assertCount(1, $cdd);
        $this->assertSame('BIO', $cdd[0]->nom);
        $this->assertSame('2026-12-31', $cdd[0]->date_fin_contrat);
        $this->assertSame(9, DB::table('employes')->where('type_contrat', 'CDI')->count());

        // Aucun salaire n'approche le plafond ITS confirme de 500 000 F : le
        // refus de haut de bareme (PA-53) ne bloque personne aujourd'hui, et
        // se declenchera au premier recrutement de cadre. C'est l'etat reel du
        // dossier, pas un contournement.
        $this->assertSame(
            -1,
            bccomp((string) DB::table('employes')->max('salaire_base'), '500000', 2),
        );
    }

    #[Test]
    public function les_locations_et_le_depart_en_circuit_sont_passes_par_leurs_services(): void
    {
        // M8 — trois contrats, dont deux bout à bout sur le MÊME véhicule :
        // c'est le cas que RG-08 accepte (bornes semi-ouvertes) et qu'un
        // `DB::table()` n'aurait jamais soumis au verrou.
        $contrats = \App\Domain\Vehicules\Models\ContratLocation::query()
            ->orderBy('date_debut')->get();
        $this->assertCount(3, $contrats);

        foreach ($contrats as $a) {
            foreach ($contrats as $b) {
                if ($a->id === $b->id || $a->vehicule_id !== $b->vehicule_id) {
                    continue;
                }

                $this->assertTrue(
                    $a->date_fin <= $b->date_debut || $b->date_fin <= $a->date_debut,
                    'Deux locations de demonstration se chevauchent sur le meme vehicule : '
                    .'RG-08 a ete contournee par le seeder.',
                );
            }
        }

        // RG-09 — la pièce d'identité est présente sur chacun. Elle porte une
        // MENTION, pas un numéro : un identifiant plausible sur un contrat
        // imprimable serait une fausse pièce.
        $this->assertSame(0, $contrats->filter(fn ($c) => blank($c->piece_identite))->count());
        $this->assertSame(0, $contrats->filter(fn ($c) => blank($c->utilisateur_creation_id))->count());

        // M9 — un départ, six participants sur les treize places du « Nord
        // Togo » : RG-13 a été évaluée (capacité cumulée, exclusivité du
        // guide). Treize parce que le maître fait partir ce circuit en Hiace
        // et écrit lui-même « il reste 3 places sur 13 » après deux
        // réservations de 6 et 4 (`seed-locations-tourisme.js` l.114-115).
        $depart = \App\Domain\Tourisme\Models\ReservationTour::query()->sole();
        $this->assertSame(6, $depart->nb_participants);
        $this->assertSame('Nord Togo', $depart->circuit->nom);
        $this->assertNotNull($depart->utilisateur_creation_id);
        $this->assertLessThanOrEqual(
            $depart->circuit->capacite_max,
            $depart->nb_participants,
        );
    }
}
