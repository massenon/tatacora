<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Référentiel ARTICLES et POINTS DE STOCKAGE — auteur unique, données réelles
 * du Gîte Chez Noël.
 *
 * ## Ce qui a changé le 03/09/2026 : le maître fait foi, pas la spécification
 *
 * Ce seeder posait cinq articles génériques tirés de `SEEDER_TEST_LARAVEL.md`
 * §5 (« Riz local », « Huile de palme », « Poisson frais (tilapia) »…). Le
 * référentiel RÉEL est celui du maître, `prototype_v2/assets/js/seed-donnees.js`
 * l.45-96 : **38 articles avec leur conditionnement, leur prix d'achat et leur
 * mode de suivi**, relevés de l'exploitation. Les libellés génériques sont
 * REMPLACÉS, pas complétés — les garder à côté des vrais aurait produit
 * exactement le défaut que `RestaurantSeeder` décrit dans son propre en-tête :
 * « Riz local » et « Riz local (sac 50 kg) » côte à côte, et une fiche
 * technique qui décrémente celui que personne n'approvisionne.
 *
 * ## Ce seeder est l'AUTEUR UNIQUE de `articles` — `BarSeeder` les LIT
 *
 * Jusqu'ici `BarSeeder` créait ses 24 articles de bar. C'était un second
 * auteur du même référentiel : la sixième occurrence du défaut PA-160/PA-161,
 * et la plus discrète, parce que les deux jeux ne se recouvraient pas encore.
 * Ils se recouvrent depuis que le stock du maître descend « AU LITRAGE PRÈS »
 * (`seed-donnees.js` l.58-63). Tous les articles du bar sont donc créés ici,
 * et `BarSeeder` les retrouve par leur libellé EXACT, refusant si l'un manque.
 *
 * ## Le conditionnement est la substance, pas un détail de libellé
 *
 * Le maître stocke des CASIERS et vend des BOUTEILLES : « Béninoise 66 cl
 * (casier 12) » est une ligne de stock, « Béninoise 66 cl » est une ligne de
 * carte, et `cartes_boisson.unites_vendables_par_unite_stock` porte le 12 qui
 * les relie. Un casier de 12 et un casier de 24 ne se décrémentent pas au même
 * rythme — c'est le sujet même de la migration `2026_09_01_110000`, qui
 * avertit que « se tromper de sens vide le stock 24 fois trop vite ».
 *
 * Deux contenances = deux articles, et le maître l'écrit lui-même
 * (`referentiel-carte.js` l.229-232) : une Béninoise 33 cl et une 66 cl ne
 * sortent pas du même casier.
 *
 * ## L'entrée initiale passe par `MouvementStockService::entree()`
 *
 * Elle était posée en `MouvementStock::create()`. Le service est le seul
 * chemin qui écrit `articles.prix_achat` (il n'est délibérément pas
 * `fillable`) et qui intègre le coût moyen pondéré. Le prix d'achat du maître
 * entre donc par la porte réelle, et le CMP naît de l'entrée qui le justifie —
 * là où l'ancien en-tête de ce fichier notait « le CMP reste à 0, aucune
 * facture d'achat n'existe au dossier ». Le maître en porte une valeur pour
 * chacun de ses 38 articles, et se dit lui-même « tiré de l'exploitation du
 * gîte » (l.12-14).
 *
 * Conséquence assumée : le mouvement est daté du jour (le service pose
 * `now()`), là où l'ancien code le reculait de trente jours. Une date
 * d'entrée décalée ne valait rien de plus qu'un affichage ; contourner le
 * service pour l'obtenir coûterait le prix d'achat et le CMP.
 *
 * ## Quatre écarts au maître, NOMMÉS
 *
 * 1. **Deux articles de garage n'existent chez personne.** « Gasoil » et
 *    « Filtres à huile (véhicules) » viennent de `SEEDER_TEST_LARAVEL.md` §5 :
 *    le maître ne porte aucun article de garage, alors que le point de
 *    stockage existe et que M8 en a besoin. Ils sont conservés SANS prix
 *    d'achat — aucune source ne les tarife, et un montant plausible entrerait
 *    tel quel dans la valorisation du bilan. « Filtres à huile » démarre SOUS
 *    son seuil : l'écran d'alertes a réellement quelque chose à montrer.
 * 2. **Sept références de la carte du bar n'ont aucun casier au maître**
 *    (EKU 66 cl, Guinness 66 cl, Vody / Loco, les deux vins, le rhum, le jus
 *    naturel) : sa liste de stock s'arrête aux dix-huit casiers courants.
 *    `cartes_boisson.article_id` étant NOT NULL, leur article est créé ici, à
 *    la BOUTEILLE et sans prix d'achat. Leur conditionnement réel est inconnu,
 *    et un casier de 12 inventé ferait sortir un douzième de bouteille par
 *    verre servi.
 * 3. **Les neuf préparations maison de M5** (jus au moyen et au grand format,
 *    cafés) reçoivent chacune leur article. Le maître les range en suivi
 *    `journalier` (`seed-restauration.js` l.18-19) ; ils sont posés
 *    `permanent` avec une préparation du jour, parce que `VenteBarService`
 *    sort du stock à CHAQUE vente sans regarder `suivi` — un article
 *    journalier à zéro ferait refuser tout café par RG-06. L'écart est nommé,
 *    pas dissimulé.
 * 4. **`seuil_reappro` n'est semé nulle part.** Le maître ne porte que le
 *    seuil d'alerte ; le seuil de réapprovisionnement M7 est une décision de
 *    gestion (délai fournisseur), pas une donnée relevée.
 *
 * Dév/Recette UNIQUEMENT. Idempotent — un mouvement d'entrée dupliqué serait
 * indiscernable d'une vraie livraison.
 *
 * @see EF-M6-01 Référentiel articles multi-catégories
 * @see EF-M6-03 Valorisation au coût moyen pondéré
 */
class StocksSeeder extends Seeder
{
    use Concerns\CompteAmorcage;

    /**
     * Les articles du maître, plus les quatre écarts nommés en en-tête.
     *
     * Colonnes : libellé, catégorie, unité de mesure, point de stockage,
     * mode de suivi, seuil d'alerte, prix d'achat (null = aucune source),
     * quantité initiale.
     *
     * @return list<array{string, string, string, string, string, string, string|null, string}>
     */
    public static function catalogue(): array
    {
        return [
            // ============================================================
            // GROS STOCK — `seed-donnees.js` l.47-56
            // ============================================================
            ['Riz local (sac 50 kg)', 'Denrées', 'sac', 'magasin', 'permanent', '4', '32000', '18'],
            ['Riz parfumé importé (25 kg)', 'Denrées', 'sac', 'magasin', 'permanent', '4', '21000', '12'],
            ['Huile végétale (bidon 20 L)', 'Denrées', 'bidon', 'magasin', 'permanent', '3', '22000', '7'],
            ['Farine de blé (sac 50 kg)', 'Denrées', 'sac', 'magasin', 'permanent', '2', '26000', '5'],
            ['Fromage peulh (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '10', '2500', '14'],
            ['Viande de bœuf (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '15', '3200', '22'],
            ['Viande de mouton (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '10', '3800', '9'],
            ['Poulet entier', 'Denrées', 'unité', 'cuisine', 'permanent', '12', '3500', '26'],
            ['Poisson carpe (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '8', '2800', '11'],
            ['Mozzarella (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '4', '6500', '6'],

            // ============================================================
            // BOISSONS — les casiers du maître, l.64-81.
            //
            // « le stock DOIT refléter la carte du bar AU LITRAGE PRÈS ».
            // Le nombre entre parenthèses est le conditionnement, et c'est lui
            // que `BarSeeder` reporte en taux de conversion.
            // ============================================================
            ['Béninoise 66 cl (casier 12)', 'Boissons', 'casier', 'bar', 'permanent', '5', '7200', '16'],
            ['Béninoise 33 cl (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '4', '8400', '9'],
            ['Beaufort 50 cl (casier 12)', 'Boissons', 'casier', 'bar', 'permanent', '5', '7200', '11'],
            ['Beaufort 33 cl (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '4', '8400', '6'],
            ['Doppel 33 cl (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '3', '8400', '5'],
            ['Doppel 66 cl (casier 12)', 'Boissons', 'casier', 'bar', 'permanent', '5', '7200', '4'],
            ['Pils 66 cl (casier 12)', 'Boissons', 'casier', 'bar', 'permanent', '3', '9000', '7'],
            ['Pils 33 cl (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '3', '8400', '4'],
            ['Guinness 33 cl (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '2', '15600', '5'],
            ['EKU 33 cl (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '2', '12000', '3'],
            ['Flag (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '2', '13200', '6'],
            ['Castel (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '2', '13200', '5'],
            ['Awoyo (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '2', '16800', '3'],
            ['Racine (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '2', '13200', '4'],
            ['XXL (carton 24)', 'Boissons', 'carton', 'bar', 'permanent', '2', '11000', '4'],
            ['Sucrerie 66 cl (casier 12)', 'Boissons', 'casier', 'bar', 'permanent', '4', '6000', '8'],
            ['Sucrerie 33 cl (casier 24)', 'Boissons', 'casier', 'bar', 'permanent', '4', '7200', '10'],
            // Aucune ligne de carte ne lui correspond : l'ardoise du bar ne
            // porte pas l'eau minérale, alors que le stock la porte. L'écart
            // est du maître, il n'est pas comblé ici — inventer un prix de
            // vente serait inventer une ligne de carte.
            ['Eau minérale 1,5 L (pack 6)', 'Boissons', 'pack', 'bar', 'permanent', '10', '1800', '24'],

            // ============================================================
            // FOURNITURES — l.84-87
            // ============================================================
            ['Papier hygiénique (carton 48)', 'Fournitures', 'carton', 'magasin', 'permanent', '2', '12000', '5'],
            ['Gobelets jetables (carton 1000)', 'Fournitures', 'carton', 'bar', 'permanent', '2', '9000', '3'],
            ['Savon de ménage (carton 24)', 'Fournitures', 'carton', 'magasin', 'permanent', '2', '6000', '4'],
            ['Gaz butane (bouteille 12 kg)', 'Fournitures', 'bouteille', 'cuisine', 'permanent', '3', '8500', '6'],

            // ============================================================
            // PETIT STOCK — acheté au marché chaque matin, l.90-95.
            //
            // `journalier` : AUCUNE entrée n'est posée. « Les tomates achetées
            // au marché chaque matin ne se suivent pas en permanence, sous
            // peine d'écarts d'inventaire permanents. »
            // ============================================================
            ['Tomate fraîche', 'Denrées', 'kg', 'cuisine', 'journalier', '0', '700', '0'],
            ['Oignon frais', 'Denrées', 'kg', 'cuisine', 'journalier', '0', '600', '0'],
            ['Laitue', 'Denrées', 'kg', 'cuisine', 'journalier', '0', '900', '0'],
            ['Piment frais', 'Denrées', 'kg', 'cuisine', 'journalier', '0', '1200', '0'],
            ['Carotte', 'Denrées', 'kg', 'cuisine', 'journalier', '0', '800', '0'],
            ['Concombre', 'Denrées', 'kg', 'cuisine', 'journalier', '0', '700', '0'],

            // ============================================================
            // ÉCART 4 — LES DENRÉES QUE LA CARTE RÉELLE NOMME (04/09/2026).
            //
            // `menu_restaurant_reel.txt` (transcription de la carte du Gîte,
            // remise par le Product Owner) donne les INGRÉDIENTS de dix-sept
            // préparations, entre parenthèses : « Salade du chef (Laitue,
            // jambon, fromage peulh, maïs doux, carotte, betterave, œuf,
            // tomate, oignon, concombre) ». Douze de ces denrées n'existaient
            // dans AUCUN article : sans elles, la fiche technique aurait dû
            // taire la moitié de ce que le client mange.
            //
            // ⚠ AUCUN PRIX D'ACHAT : la carte donne des prix de VENTE, jamais
            // d'achat. `null` plutôt qu'un montant plausible — même règle que
            // le garage et les sept bouteilles sans casier. Conséquence
            // assumée et VISIBLE : le coût matière des fiches qui les
            // contiennent est rendu « incomplet », avec le nom des articles
            // non valorisés, jamais un total sous-évalué.
            //
            // Le mode de suivi suit la nature de la denrée, pas une
            // convention : ce qui s'achète au marché le matin est
            // `journalier` (et ne bouge donc aucun stock, voir
            // `DeductionStockCuisineService`), ce qui se conserve est
            // `permanent` et reçoit un stock de travail à la cuisine.
            // ============================================================
            ['Jambon (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '6'],
            ['Œufs (plateau de 30)', 'Denrées', 'plateau', 'cuisine', 'permanent', '3', null, '10'],
            ['Maïs doux (boîte 400 g)', 'Denrées', 'boîte', 'cuisine', 'permanent', '6', null, '24'],
            ['Poisson fumé (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '3', null, '8'],
            ['Peau de bœuf (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '5'],
            ['Saucisse (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '6'],
            ['Betterave', 'Denrées', 'kg', 'cuisine', 'journalier', '0', null, '0'],
            ['Aubergine', 'Denrées', 'kg', 'cuisine', 'journalier', '0', null, '0'],
            ['Chou', 'Denrées', 'kg', 'cuisine', 'journalier', '0', null, '0'],
            ['Haricot vert', 'Denrées', 'kg', 'cuisine', 'journalier', '0', null, '0'],
            ['Champignon', 'Denrées', 'kg', 'cuisine', 'journalier', '0', null, '0'],
            ['Petit pois', 'Denrées', 'kg', 'cuisine', 'journalier', '0', null, '0'],

            // ============================================================
            // ÉCART 5 — LES DENRÉES QUE LES LIBELLÉS DE LA CARTE NOMMENT.
            //
            // La carte réelle ne détaille les ingrédients que de dix-sept
            // préparations ; les soixante-dix-sept autres nomment leur denrée
            // DANS LEUR LIBELLÉ — « Frites d'igname », « Demi pintade »,
            // « Couscous de fonio », « Crêpe au miel », « Portion de boyaux
            // bœuf ». Ce sont des lectures du libellé, pas des suppositions.
            //
            // Sans ces articles, la fiche technique de ces plats ne pourrait
            // porter aucune ligne, et une fiche vide REFUSE la vente
            // (`RecetteManquanteException`) : le point de vente serait resté
            // bloqué sur les trois quarts de la carte.
            //
            // ⚠ Deux choses ne viennent d'AUCUNE source et sont posées : la
            // QUANTITÉ détenue (c'est un stock de démonstration) et le
            // conditionnement retenu. Le PRIX D'ACHAT, lui, reste `null` —
            // la carte donne des prix de vente, jamais d'achat.
            //
            // ⚠ Aucune substitution : le poisson chat n'est pas la carpe, la
            // pintade n'est pas le poulet. Rattacher « Repe soupe
            // (Poisson-chat) » à la carpe aurait décrémenté le mauvais casier
            // — le défaut exact que le maître nomme en imposant « deux
            // contenances = deux articles ».
            // ============================================================
            ['Igname (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '10', null, '40'],
            ['Pomme de terre (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '8', null, '30'],
            ['Patate douce (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '5', null, '20'],
            ['Plantain (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '6', null, '25'],
            ['Attiéké (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '4', null, '15'],
            ['Pâtes alimentaires (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '3', null, '12'],
            ['Semoule de couscous (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '3', null, '10'],
            ['Fonio (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '8'],
            ['Haricot sec (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '3', null, '10'],
            ['Farine de maïs (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '6', null, '25'],
            ["Pâte d'arachide (kg)", 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '8'],
            ['Mil (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '8'],
            ['Lapin (unité)', 'Denrées', 'unité', 'cuisine', 'permanent', '2', null, '4'],
            ['Pintade (unité)', 'Denrées', 'unité', 'cuisine', 'permanent', '2', null, '6'],
            ['Poisson dorade (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '3', null, '8'],
            ['Poisson silivi (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '6'],
            ['Poisson chat (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '7'],
            ['Boyaux de bœuf (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '4'],
            ['Tête de mouton (unité)', 'Denrées', 'unité', 'cuisine', 'permanent', '1', null, '3'],
            ['Tête de cabri (unité)', 'Denrées', 'unité', 'cuisine', 'permanent', '1', null, '3'],
            ['Sardine (boîte 125 g)', 'Denrées', 'boîte', 'cuisine', 'permanent', '6', null, '20'],
            ['Sucre (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '5', null, '15'],
            ['Miel (L)', 'Denrées', 'L', 'cuisine', 'permanent', '1', null, '3'],
            ['Chocolat à tartiner (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '1', null, '4'],
            ['Lait en poudre (kg)', 'Denrées', 'kg', 'cuisine', 'permanent', '2', null, '6'],
            ['Pain sandwich (unité)', 'Denrées', 'unité', 'cuisine', 'permanent', '12', null, '40'],
            ['Galette à chawarma (unité)', 'Denrées', 'unité', 'cuisine', 'permanent', '12', null, '40'],
            ['Cake (unité)', 'Denrées', 'unité', 'cuisine', 'permanent', '4', null, '12'],
            ['Fruits de saison', 'Denrées', 'kg', 'cuisine', 'journalier', '0', null, '0'],

            // ============================================================
            // ÉCART 1 — le garage, absent du maître (voir l'en-tête).
            // ============================================================
            ['Gasoil', 'Fournitures', 'L', 'garage', 'permanent', '30', null, '120'],
            ['Filtres à huile (véhicules)', 'Pièces véhicules', 'unité', 'garage', 'permanent', '5', null, '4'],

            // ============================================================
            // ÉCART 2 — les sept références de carte sans casier au maître.
            // À la bouteille, sans prix d'achat : leur conditionnement réel
            // est inconnu et ne s'invente pas.
            // ============================================================
            ['EKU 66 cl (bouteille)', 'Boissons', 'bouteille', 'bar', 'permanent', '12', null, '24'],
            ['Guinness 66 cl (bouteille)', 'Boissons', 'bouteille', 'bar', 'permanent', '12', null, '24'],
            // Scindés le 01/09/2026 (décision PO) : deux produits, deux
            // casiers — une référence fusionnée décrémenterait le mauvais
            // stock au premier écart de vente entre les deux.
            ['Vody (bouteille)', 'Boissons', 'bouteille', 'bar', 'permanent', '6', null, '12'],
            ['Loco (bouteille)', 'Boissons', 'bouteille', 'bar', 'permanent', '6', null, '12'],
            ['Vin blanc (bouteille)', 'Boissons', 'bouteille', 'bar', 'permanent', '6', null, '12'],
            ['Vin rouge (bouteille)', 'Boissons', 'bouteille', 'bar', 'permanent', '6', null, '12'],
            ['Rhum (bouteille)', 'Boissons', 'bouteille', 'bar', 'permanent', '6', null, '12'],
            ['Jus naturel (L)', 'Boissons', 'L', 'bar', 'permanent', '2', null, '10'],

            // ============================================================
            // ÉCART 3 — les neuf préparations maison de M5.
            //
            // Un article par ligne de carte : « moyen » et « grand » sont deux
            // articles vendables, exactement comme la 33 cl et la 66 cl
            // (`referentiel-carte.js` l.207-212). Les fusionner obligerait à
            // inventer un nombre de portions par litre.
            // ============================================================
            ["Jus d'ananas moyen (préparation du jour)", 'Boissons', 'portion', 'bar', 'permanent', '5', null, '20'],
            ["Jus d'ananas grand (préparation du jour)", 'Boissons', 'portion', 'bar', 'permanent', '5', null, '20'],
            ['Jus de pastèque moyen (préparation du jour)', 'Boissons', 'portion', 'bar', 'permanent', '5', null, '20'],
            ['Jus de pastèque grand (préparation du jour)', 'Boissons', 'portion', 'bar', 'permanent', '5', null, '20'],
            ['Jus de banane moyen (préparation du jour)', 'Boissons', 'portion', 'bar', 'permanent', '5', null, '20'],
            ['Jus de banane grand (préparation du jour)', 'Boissons', 'portion', 'bar', 'permanent', '5', null, '20'],
            ['Café simple petit (préparation du jour)', 'Boissons', 'portion', 'bar', 'permanent', '5', null, '30'],
            ['Café simple grand (préparation du jour)', 'Boissons', 'portion', 'bar', 'permanent', '5', null, '30'],
            ['Café expresso (préparation du jour)', 'Boissons', 'portion', 'bar', 'permanent', '5', null, '30'],
        ];
    }

    public function run(): void
    {
        // ⚠ COMPLEMENTAIRE, jamais « tout ou rien » (04/09/2026). La garde
        // rendait la main des qu'un point existait — donc sur TOUTE base deja
        // semee : les denrees ajoutees au catalogue n'y entraient JAMAIS, et
        // `RestaurantSeeder::articleId()` levait sur la premiere fiche qui les
        // nomme (« Igname (kg) », constate sur la base du Gite). Meme angle
        // mort que `RolePermissionSeeder` le 02/09, meme reponse : completer
        // ce qui manque, ne jamais reecrire ce qui existe.
        //
        // Seuls les ARTICLES manquants sont crees, JAMAIS leur stock initial :
        // une entree posee ici sur une base vivante fabriquerait de la
        // marchandise que personne n'a recue. Les nouvelles denrees suivies
        // naissent donc a zero et s'approvisionnent par le geste metier
        // (ecran Approvisionnement), comme n'importe quel achat reel.
        if (PointStockage::query()->exists()) {
            $this->completerLeCatalogue();

            return;
        }

        // La colonne `type` n'est pas décorative : `VenteBarService` retrouve
        // le point du bar par `type = 'bar'` et `DeductionStockCuisineService`
        // la cuisine par `type = 'cuisine'` — un point sans type rend toute
        // vente impossible (mesuré à la première exécution de l'exploitation
        // de démonstration, 28/08/2026).
        $points = [
            'cuisine' => PointStockage::create(['id' => (string) Str::uuid(), 'libelle' => 'Cuisine', 'type' => 'cuisine']),
            'bar' => PointStockage::create(['id' => (string) Str::uuid(), 'libelle' => 'Bar', 'type' => 'bar']),
            'magasin' => PointStockage::create(['id' => (string) Str::uuid(), 'libelle' => 'Magasin général', 'type' => 'magasin']),
            'garage' => PointStockage::create(['id' => (string) Str::uuid(), 'libelle' => 'Garage', 'type' => 'garage']),
        ];

        $auteur = User::findOrFail($this->compteAmorcageId());
        $mouvements = app(MouvementStockService::class);

        // Le service lit `auth()->id()` pour l'auteur du mouvement (RG-15) :
        // l'ancien code posait la colonne à la main, ce qui était le symptôme
        // d'une écriture hors du chemin réel.
        Auth::login($auteur);

        try {
            foreach (self::catalogue() as [$libelle, $categorie, $unite, $point, $suivi, $seuil, $prixAchat, $quantite]) {
                $article = Article::create([
                    'id' => (string) Str::uuid(),
                    'libelle' => $libelle,
                    'categorie' => $categorie,
                    'unite_mesure' => $unite,
                    // Le point PRINCIPAL, jamais la portée du stock (PA-161(a)) :
                    // le stock reste l'agrégation des mouvements par couple
                    // (article, point).
                    'point_stockage_id' => $points[$point]->id,
                    'suivi' => $suivi,
                    'seuil_alerte' => $seuil,
                ]);

                // Un article journalier n'a pas de stock à tenir : lui poser
                // une entrée produirait un solde théorique qui ne correspond à
                // rien de compté.
                if ($suivi === 'journalier' || bccomp($quantite, '0', 2) <= 0) {
                    continue;
                }

                // ⚠ AUCUN STOCK D'OUVERTURE EN PRODUCTION (09/09/2026).
                //
                // Ces quantites sont celles du jeu de demonstration. Posees
                // sur la base du Gite, elles FABRIQUERAIENT de la marchandise
                // que personne n'a recue : le stock theorique partirait faux,
                // et l'ecart n'apparaitrait qu'au premier inventaire, impute
                // a une perte physique ou a un vol. Le referentiel des
                // articles, lui, est utile partout — c'est la ligne qui
                // precede, et elle reste.
                //
                // En production, le stock entre par son geste reel : la
                // reception d'une commande d'achat, ou l'entree depuis la
                // fiche article (PA-181).
                if (app()->environment('production')) {
                    continue;
                }

                // JAMAIS de colonne de stock directe : le stock théorique est
                // toujours l'agrégation des mouvements
                // (03_DATABASE_ENGINEERING.md §7, StockTheoriqueService).
                $mouvements->entree(
                    articleId: $article->id,
                    pointId: $points[$point]->id,
                    quantite: $quantite,
                    // Un motif se LIT sur la fiche de stock (colonne
                    // « Motif ») : jamais un identifiant technique —
                    // « stock_initial_seeder » sortait tel quel a l'ecran
                    // (passage navigateur du 02/09/2026).
                    motif: 'Stock initial',
                    // `null` reste `null` : sans source, pas de prix d'achat
                    // et pas de coût moyen pondéré. Zéro se lirait « gratuit ».
                    coutUnitaire: $prixAchat,
                );
            }

            // Meme raison : le transfert magasin -> cuisine deplace un stock
            // de demonstration. En production, il n'y a rien a deplacer tant
            // que rien n'a ete recu.
            if (! app()->environment('production')) {
                $this->approvisionnerLaCuisine($points, $mouvements);
            }
        } finally {
            Auth::logout();
        }
    }

    /**
     * LE MAGASIN APPROVISIONNE LA CUISINE — et sans ce transfert, aucun plat
     * ne se vendait (04/09/2026).
     *
     * ## Le défaut, mesuré et non supposé
     *
     * `DeductionStockCuisineService` sort les denrées du point de type
     * `cuisine`, et de lui seul. Or le riz, la farine et l'huile ont pour point
     * principal le MAGASIN — c'est la donnée du maître, et elle est juste : un
     * sac de 50 kg ne vit pas sur le plan de travail. La cuisine ne détenait
     * donc aucun féculent, et la première vente d'un plat levait
     * `RuptureStockException` : « 0.00 disponible, 0.01 demandé ». Relevé le
     * 04/09/2026 en tentant une vraie vente de Tchep au poisson sur la base
     * semée — la fiche technique était correcte, le stock était au mauvais
     * endroit.
     *
     * ## Un TRANSFERT, pas une seconde entrée
     *
     * Une entrée valorisée à la cuisine aurait créé du stock à partir de rien
     * et fait entrer une seconde fois le même achat dans le coût moyen
     * pondéré. Le geste réel est un mouvement interne : `sortie()` au magasin,
     * `entree()` à la cuisine **sans coût unitaire** — la seule forme que
     * `MouvementStockService::entree()` documente comme « transfert entrant »,
     * et la seule qui ne touche pas le CMP. Le total détenu par
     * l'établissement est inchangé ; il a seulement changé d'étagère.
     *
     * @param  array<string, PointStockage>  $points
     */
    /**
     * Cree les articles du catalogue absents d'une base DEJA semee.
     *
     * Sans stock initial et sans toucher aux articles existants : un libelle
     * deja present fait foi, avec son point, son suivi et son seuil, que le
     * Gite a pu ajuster a l'ecran.
     */
    private function completerLeCatalogue(): void
    {
        $points = PointStockage::query()->get()->keyBy('type');

        foreach (self::catalogue() as [$libelle, $categorie, $unite, $point, $suivi, $seuil, , ]) {
            if (Article::query()->where('libelle', $libelle)->exists()) {
                continue;
            }

            $pointDeStockage = $points->get($point);

            if ($pointDeStockage === null) {
                // Un point absent est une base incoherente, pas un cas a
                // contourner : creer l'article ailleurs le rendrait
                // introuvable par le service qui le cherche par type.
                throw new RuntimeException(
                    'StocksSeeder : point de stockage « '.$point.' » introuvable pour l article « '
                    .$libelle.' ». La base est incomplete — ne pas creer l article ailleurs.',
                );
            }

            Article::create([
                'id' => (string) Str::uuid(),
                'libelle' => $libelle,
                'categorie' => $categorie,
                'unite_mesure' => $unite,
                'point_stockage_id' => $pointDeStockage->id,
                'suivi' => $suivi,
                'seuil_alerte' => $seuil,
            ]);
        }
    }

    /** @param  array<string, PointStockage>  $points */
    private function approvisionnerLaCuisine(array $points, MouvementStockService $mouvements): void
    {
        // Le stock de TRAVAIL de la cuisine : ce que le cuisinier a sous la
        // main pour le service, jamais la réserve entière.
        $transferts = [
            'Riz local (sac 50 kg)' => '4',
            'Farine de blé (sac 50 kg)' => '2',
            'Huile végétale (bidon 20 L)' => '2',
        ];

        foreach ($transferts as $libelle => $quantite) {
            $article = Article::query()->where('libelle', $libelle)->first();

            if (! $article instanceof Article) {
                // Le libellé vient du catalogue ci-dessus : s'il ne s'y trouve
                // plus, c'est un renommage, et le transfert doit être relu
                // plutôt que silencieusement sauté.
                throw new \RuntimeException(
                    'StocksSeeder : article introuvable pour le transfert magasin → cuisine ('
                    .$libelle.'). Le catalogue a ete renomme : sans ce transfert, la cuisine ne '
                    .'detient aucun feculent et toute vente de plat est refusee (RuptureStockException).',
                );
            }

            $mouvements->sortie(
                articleId: $article->id,
                pointId: $points['magasin']->id,
                quantite: $quantite,
                motif: 'Transfert vers la cuisine',
            );

            $mouvements->entree(
                articleId: $article->id,
                pointId: $points['cuisine']->id,
                quantite: $quantite,
                motif: 'Transfert depuis le magasin',
                // `null` : un transfert ne valorise rien. Y remettre le prix
                // d'achat ferait entrer le meme achat deux fois dans le cout
                // moyen pondere.
                coutUnitaire: null,
            );
        }
    }
}
