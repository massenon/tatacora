<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Domain\Carte\MarquesDePrix;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use App\Domain\Stocks\Models\Article;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * LA CARTE RÉELLE DU GÎTE CHEZ NOËL — 94 préparations, fiches comprises.
 *
 * ## Ce fichier a été REMPLACÉ le 04/09/2026, sur ordre du Product Owner
 *
 * Jusque-là, la carte venait de `prototype_v2/assets/js/referentiel-carte.js`,
 * c'est-à-dire du PROTOTYPE. Le Product Owner a remis la transcription de la
 * carte physique du Gîte (`menu_restaurant_reel.txt`, 04/09/2026) et tranché :
 * « delete les seeders de restaurant actuels et remplace par ceci ». La carte
 * du client l'emporte donc sur les données de démonstration du prototype —
 * c'est la même règle que partout ici, la source la plus proche du réel gagne.
 *
 * Ce que le remplacement a corrigé au passage, en confrontant les deux :
 *
 * - « Tête de mouton aux légumes (man) + accompagnement » vaut **3 500 F** et
 *   non 5 000 ; « Poisson dorade » vaut **2 500 F** et non 3 500. Le prototype
 *   se trompait sur deux prix REMIS AU CLIENT.
 * - Onze préparations manquaient entièrement — l'ardoise « plat +
 *   accompagnement » et les brochettes (rayon `formules`).
 * - Une seule ligne de sandwicherie porte une étiquette manuscrite (Chawarma
 *   poulet, 3 000 F au lieu de 2 000), là où le prototype en marquait six.
 *
 * ## DEUX SOURCES QUI SE CONTREDISENT, ET RIEN N'EST MOYENNÉ
 *
 * Le document porte DEUX documents : la carte imprimée (sections 1 à 6,
 * paginée « x/7 ») et une ardoise en fin de fichier. Elles se contredisent sur
 * deux plats, et sur eux seuls :
 *
 * | Plat             | Carte imprimée | Ardoise |
 * |------------------|----------------|---------|
 * | Ragoût de poulet | 5 000 F        | 6 000 F |
 * | Ragoût de mouton | 4 000 F        | 6 000 F |
 *
 * Le prix de la CARTE IMPRIMÉE est retenu — c'est le document structuré, daté
 * par sa pagination, et c'est lui que le client a sous les yeux. Mais retenir
 * n'est pas trancher : les deux plats portent `prix_provisoire`, la marque qui
 * dit « ce tarif reste à confronter à la carte physique » (PA-161 b). Elle
 * s'affiche au comptoir et sur la fiche des prix, et se lève d'un clic depuis
 * l'écran « Restaurant & Cuisine » le jour où le Gîte tranchera. Prendre 5 500
 * « au milieu » aurait été l'hypothèse que ce dépôt refuse partout.
 *
 * ## Ce qui n'est PAS repris du document, et pourquoi
 *
 * - **« Café au lait 1 000 F »**, et toute la section « Nos cafés » et « Jus de
 *   fruits fait maison » : ce sont des BOISSONS (M5). Elles vivent dans
 *   `cartes_boisson`, semées par `BarSeeder`, et neuf d'entre elles y sont
 *   déjà. Les recopier ici en ferait des plats, donc un second auteur du même
 *   produit — et le café serait vendu deux fois sous deux rayons. « Café au
 *   lait » est en revanche ABSENT du bar : signalé au Product Owner, pas ajouté
 *   d'autorité à un référentiel dont ce fichier n'est pas l'auteur.
 * - **Les crêpes de l'ardoise** (au miel 1 500, au sucre 1 000, au chocolat
 *   2 000) : mêmes produits et MÊMES prix que la carte imprimée, au libellé
 *   près (« Crêpe au sucre » / « Crêpe sucrée »). Une seconde ligne aurait
 *   dédoublé le dessert au catalogue.
 *
 * ## Quatre libellés recopiés VERBATIM malgré l'orthographe
 *
 * « Ailleron », « Attieke + plantin », « Aloco », « Poissons silivi » sont
 * écrits ainsi dans le document du client. Ils ne sont PAS corrigés : le
 * libellé d'un plat est ce qui figure sur la carte remise au client, et le
 * « corriger » ferait diverger l'écran du papier. Signalés au Product Owner
 * pour arbitrage. Deux artefacts de transcription sont en revanche réparés,
 * parce qu'ils ne sont pas des choix de mots : « Tête de cabri +
 * accompagnement + accompagnement » (le membre est écrit deux fois) et
 * « sauce d arachide » (apostrophe manquante).
 *
 * ## LA FICHE TECHNIQUE DE CHAQUE PLAT, ET D'OÙ ELLE VIENT
 *
 * Les 94 fiches sont composées — aucune n'est vide, parce qu'une fiche vide
 * REFUSE la vente (`DeductionStockCuisineService` lève
 * `RecetteManquanteException`). Deux origines, et elles ne se valent pas :
 *
 * 1. **Dix-sept fiches viennent de la carte elle-même**, qui donne ses
 *    ingrédients entre parenthèses : les cinq entrées, les cinq sauces, les
 *    cinq pizzas, le Chawarma mixte et le Chawarma gîte.
 * 2. **Les autres se lisent dans le LIBELLÉ du plat** — « Frites d'igname »,
 *    « Demi pintade », « Couscous de fonio », « Crêpe au miel ». C'est une
 *    lecture, pas une supposition.
 *
 * ⚠ **Dans les deux cas, les QUANTITÉS ne viennent d'aucune source.** Aucun
 * grammage ne figure nulle part, ni sur la carte ni au dépôt. Les 93 fiches
 * portent donc `composition_provisoire` : le stock décrémenté à chaque vente
 * est approximatif, l'écran et le point de vente le disent, et la marque tombe
 * d'elle-même dès que le cuisinier enregistre la composition pesée. La 94e —
 * le Tchep au poisson — garde ses trois grammages relevés en cuisine et n'est
 * pas marquée.
 *
 * ⚠ **Aucune quantité sous 0,005.** `mouvements_stock.quantite` est un
 * `DECIMAL(10,2)` alors que la fiche est au millième (PA-38) : une ligne plus
 * fine serait arrondie à zéro et figurerait à la fiche sans rien décrémenter.
 *
 * ⚠ **Aucune substitution d'article.** Le poisson chat n'est pas la carpe, la
 * pintade n'est pas le poulet, le lapin n'est pas le mouton. Rattacher un plat
 * à l'espèce voisine aurait décrémenté le mauvais casier sans qu'aucune erreur
 * ne s'affiche — le défaut que le maître nomme lui-même en imposant « deux
 * contenances = deux articles ».
 *
 * ## Ce seeder ne crée AUCUN article
 *
 * Les ingrédients sont LUS dans le référentiel de `StocksSeeder`, par leur
 * libellé EXACT, et l'absence est un refus explicite. Une recherche par `LIKE`
 * rattacherait la fiche au premier article dont le nom contient le motif —
 * « Riz local » a déjà remonté « Riz parfumé importé » — et une création de
 * repli poserait un article que personne n'approvisionne.
 *
 * ## `plats.categorie` porte le CODE du rayon, plus son libellé (04/09/2026)
 *
 * Elle portait le libellé affiché (« Entrées »), alors que le filtre de
 * l'écran « Restaurant & Cuisine » interroge les CLÉS de
 * `CarteRestaurant::CATEGORIES` (`entrees`). Conséquence mesurée : le filtre
 * par rayon ne renvoyait **jamais aucune ligne** sur les données réelles, sur
 * les deux écrans. Le code est désormais stocké et le libellé dérivé du
 * registre — comme `cartes_boisson.categorie` le fait depuis toujours.
 *
 * Dév/Recette UNIQUEMENT. Idempotent. Dépend de `StocksSeeder`.
 *
 * @see EF-M4-01 Carte et menus
 * @see EF-M4-02 Gestion des fiches techniques de recette
 * @see RG-05 Sortie de stock automatique
 */
class RestaurantSeeder extends Seeder
{
    /**
     * Les 94 préparations de la carte réelle.
     *
     * Colonnes : libellé, prix de vente, CODE du rayon
     * ({@see \App\Pwa\Livewire\Restaurant\CarteRestaurant::CATEGORIES}),
     * prix corrigé à la main ?, prix provisoire ?
     *
     * @return list<array{string, string, string, bool, bool}>
     */
    public static function carte(): array
    {
        return [
            // ======================================= Entrées (section 1)
            ['Salade peulh', '2000', 'entrees', false, false],
            ['Salade au poulet', '5000', 'entrees', false, false],
            ["Salade d'aubergine au fromage peulh", '1500', 'entrees', false, false],
            ['Salade du chef', '3500', 'entrees', false, false],
            ['Salade verte', '1500', 'entrees', false, false],

            // ================================ Plats complets (section 1)
            ['Tchep au poisson', '6000', 'plats', false, false],
            ['Tajine de mouton + couscous', '5000', 'plats', false, false],
            // Les deux seuls prix que les DEUX documents du client
            // contredisent (ardoise : 6 000 F). Le prix de la carte imprimée
            // est retenu, et la marque dit qu'il reste à confronter.
            ['Ragoût de mouton', '4000', 'plats', false, true],
            ['Ragoût de bœuf', '4000', 'plats', false, false],
            ['Ragoût de poulet', '5000', 'plats', false, true],
            ['Ragoût de lapin', '5000', 'plats', false, false],
            // 3 500 F et non 5 000 : le prototype se trompait.
            ['Tête de mouton aux légumes (man) + accompagnement', '3500', 'plats', false, false],
            ['Tête de cabri + accompagnement', '5000', 'plats', false, false],

            // ==================================== Nos sauces (section 2)
            ['Sauce man', '1500', 'sauces', false, false],
            ['Sauce acadjou', '1000', 'sauces', false, false],
            ['Sauce crin-crin / gombo', '1500', 'sauces', false, false],
            ['Sauce moyo', '1000', 'sauces', false, false],
            ["Sauce d'arachide", '1000', 'sauces', false, false],

            // ============================ Garnitures (sections 2 et 4)
            ['Demi poulet moyen', '3500', 'garnitures', false, false],
            ['Demi poulet grand', '4500', 'garnitures', false, false],
            ['Demi pintade', '4500', 'garnitures', false, false],
            ['Poisson carpe MOYEN', '3000', 'garnitures', false, false],
            ['Poisson carpe GRAND', '4500', 'garnitures', false, false],
            // 2 500 F et non 3 500 : le prototype se trompait.
            ['Poisson dorade', '2500', 'garnitures', false, false],
            ['Poissons silivi', '2000', 'garnitures', false, false],
            ['Poissons chat PETIT', '2000', 'garnitures', false, false],
            ['Poisson chat GRAND', '3000', 'garnitures', false, false],
            ['Ailleron', '2000', 'garnitures', false, false],
            ['Portion de bœuf', '2000', 'garnitures', false, false],
            ['Portion de mouton', '2000', 'garnitures', false, false],
            ['Portion de boyaux bœuf', '1500', 'garnitures', false, false],
            ['Saucisse', '500', 'garnitures', false, false],
            ['Omelette nature', '1000', 'garnitures', false, false],
            ['Omelette légume', '1500', 'garnitures', false, false],
            ['Omelette sardine', '2000', 'garnitures', false, false],
            ['Omelette du gîte', '2500', 'garnitures', false, false],
            ['Omelette soufflée au jambon', '3000', 'garnitures', false, false],

            // ======================= Accompagnements (sections 3 et 4)
            ["Frites d'igname, pommes de terre, patate douces", '1500', 'accompagnements', false, false],
            ['Pommes sautées', '1500', 'accompagnements', false, false],
            ['Spaghetti, coquillette', '1500', 'accompagnements', false, false],
            ['Attieke + plantin', '2000', 'accompagnements', false, false],
            ['Piron', '1000', 'accompagnements', false, false],
            ['Ratatouille', '1000', 'accompagnements', false, false],
            ['Akassa', '500', 'accompagnements', false, false],
            ['Aloco', '1500', 'accompagnements', false, false],
            ['Couscous de fonio', '1500', 'accompagnements', false, false],
            ['Couscous marocain', '1500', 'accompagnements', false, false],
            ["Couscous d'igname (wassa-wassa)", '1500', 'accompagnements', false, false],
            ['Riz blanc', '1500', 'accompagnements', false, false],
            ['Riz au gras', '1500', 'accompagnements', false, false],
            ['Riz créole', '1500', 'accompagnements', false, false],
            ['Atassi (riz + haricot) + dja', '1500', 'accompagnements', false, false],
            ['Pâte noire', '1000', 'accompagnements', false, false],
            ['Pâte blanche', '1000', 'accompagnements', false, false],
            ['Pâte rouge', '1000', 'accompagnements', false, false],
            ["Igname pilé + sauce d'arachide", '1500', 'accompagnements', false, false],

            // ========================= Sandwicherie (sections 3 et 5)
            ['Chawarma viande', '2000', 'sandwicherie', false, false],
            // La SEULE étiquette manuscrite de la carte réelle : le document
            // écrit « 3 000 FCFA (Prix corrigé / 2000 FCFA) ». Le prix retenu
            // est le MANUSCRIT, et la marque dit que la carte imprimée est
            // périmée sur cette ligne.
            ['Chawarma poulet', '3000', 'sandwicherie', true, false],
            ['Chawarma poisson', '2000', 'sandwicherie', false, false],
            ['Chawarma végan', '2000', 'sandwicherie', false, false],
            ['Chawarma mixte', '3000', 'sandwicherie', false, false],
            ['Chawarma gite', '3500', 'sandwicherie', false, false],
            ['Sandwich viande', '1500', 'sandwicherie', false, false],
            ['Sandwich poisson', '1500', 'sandwicherie', false, false],
            ['Sandwich omelette', '1500', 'sandwicherie', false, false],
            ['Sandwich poulet', '2000', 'sandwicherie', false, false],
            ['Panini', '2000', 'sandwicherie', false, false],
            ['Panini jambon', '2000', 'sandwicherie', false, false],
            ['Hamburger + frite', '2000', 'sandwicherie', false, false],
            ['Chicken burger + frite', '2000', 'sandwicherie', false, false],

            // ======================================= Pizzas (section 5)
            ['Pizza du gîte (grande)', '8000', 'pizzas', false, false],
            ['Pizza du nord (grande)', '7000', 'pizzas', false, false],
            ['Pizza cordon bleu', '9000', 'pizzas', false, false],
            ['Pizza végan', '6000', 'pizzas', false, false],
            ['Pizza royale (grande)', '8500', 'pizzas', false, false],

            // ================================== Nos desserts (section 6)
            ['Crêpe sucrée', '1000', 'desserts', false, false],
            ['Crêpe au chocolat', '2000', 'desserts', false, false],
            ['Crêpe au miel', '1500', 'desserts', false, false],
            ['Crêpe flambée', '1500', 'desserts', false, false],
            ['Pancake au miel', '2000', 'desserts', false, false],
            ['Pancake au chocolat', '2500', 'desserts', false, false],
            ['Salade de fruit', '1500', 'desserts', false, false],
            ['Dèguè + cake', '1500', 'desserts', false, false],

            // ===================== Formules & brochettes — L'ARDOISE
            // Onze préparations que la carte imprimée ne porte pas : les
            // formules « plat + accompagnement » et les deux brochettes.
            ['Poisson + accompagnement', '7000', 'formules', false, false],
            ['Poisson silvi + accompagnement', '4000', 'formules', false, false],
            ['Saucisse + accompagnement', '2000', 'formules', false, false],
            ['Omelette + accompagnement', '2500', 'formules', false, false],
            ['Viande de bœuf + accompagnement', '3500', 'formules', false, false],
            ['Viande de mouton + accompagnement', '5000', 'formules', false, false],
            ['Brochette de bœuf', '2000', 'formules', false, false],
            ['Brochette de mouton', '3000', 'formules', false, false],
            ['Pintade + accompagnement', '7000', 'formules', false, false],
            ['Poulet + accompagnement', '6000', 'formules', false, false],
            ['Repe soupe (Poisson-chat)', '7000', 'formules', false, false],
        ];
    }

    /**
     * La fiche technique de CHAQUE plat — article de stock => quantité.
     *
     * Les quantités sont exprimées dans l'unité de STOCK de l'article :
     * « 0.010 » sur un sac de 50 kg fait 500 g de riz, « 0.500 » sur un poulet
     * entier fait un demi-poulet, « 1.000 » sur un pain fait un pain.
     *
     * Les libellés d'articles sont ceux de `StocksSeeder` au caractère près :
     * `articleId()` refuse tout ce qu'il ne trouve pas, il n'en crée jamais.
     *
     * ⚠ Voir l'en-tête pour ce qui vient de la carte et ce qui se lit du
     * libellé — et pour le fait que, dans les deux cas, la QUANTITÉ est posée.
     *
     * @return array<string, array<string, string>>
     */
    public static function compositions(): array
    {
        return [
            // ---- Entrées : ingrédients DONNÉS PAR LA CARTE ---------------
            'Salade peulh' => [
                'Laitue' => '0.080', 'Carotte' => '0.040', 'Betterave' => '0.040',
                'Fromage peulh (kg)' => '0.050', 'Tomate fraîche' => '0.050', 'Oignon frais' => '0.020',
            ],
            'Salade au poulet' => [
                'Laitue' => '0.080', 'Poulet entier' => '0.150', 'Concombre' => '0.050',
                'Maïs doux (boîte 400 g)' => '0.100', 'Carotte' => '0.040',
                'Tomate fraîche' => '0.050', 'Oignon frais' => '0.020',
            ],
            "Salade d'aubergine au fromage peulh" => [
                'Aubergine' => '0.150', 'Tomate fraîche' => '0.050',
                'Oignon frais' => '0.020', 'Fromage peulh (kg)' => '0.050',
            ],
            'Salade du chef' => [
                'Laitue' => '0.080', 'Jambon (kg)' => '0.050', 'Fromage peulh (kg)' => '0.050',
                'Maïs doux (boîte 400 g)' => '0.100', 'Carotte' => '0.040', 'Betterave' => '0.040',
                'Œufs (plateau de 30)' => '0.034', 'Tomate fraîche' => '0.050',
                'Oignon frais' => '0.020', 'Concombre' => '0.050',
            ],
            'Salade verte' => [
                'Laitue' => '0.080', 'Tomate fraîche' => '0.050',
                'Oignon frais' => '0.020', 'Concombre' => '0.050',
            ],

            // ---- Plats complets ------------------------------------------
            // La SEULE fiche PESÉE de tout ce fichier : trois grammages
            // relevés en cuisine. Elle n'est pas marquée provisoire.
            'Tchep au poisson' => [
                'Poisson carpe (kg)' => '0.400', 'Riz local (sac 50 kg)' => '0.010',
                'Huile végétale (bidon 20 L)' => '0.050',
            ],
            'Tajine de mouton + couscous' => [
                'Viande de mouton (kg)' => '0.200', 'Semoule de couscous (kg)' => '0.150',
                'Oignon frais' => '0.050',
            ],
            'Ragoût de mouton' => [
                'Viande de mouton (kg)' => '0.200', 'Tomate fraîche' => '0.080', 'Oignon frais' => '0.050',
            ],
            'Ragoût de bœuf' => [
                'Viande de bœuf (kg)' => '0.200', 'Tomate fraîche' => '0.080', 'Oignon frais' => '0.050',
            ],
            'Ragoût de poulet' => [
                'Poulet entier' => '0.250', 'Tomate fraîche' => '0.080', 'Oignon frais' => '0.050',
            ],
            'Ragoût de lapin' => [
                'Lapin (unité)' => '0.250', 'Tomate fraîche' => '0.080', 'Oignon frais' => '0.050',
            ],
            'Tête de mouton aux légumes (man) + accompagnement' => [
                'Tête de mouton (unité)' => '0.250', 'Carotte' => '0.050', 'Riz local (sac 50 kg)' => '0.010',
            ],
            'Tête de cabri + accompagnement' => [
                'Tête de cabri (unité)' => '0.250', 'Riz local (sac 50 kg)' => '0.010',
            ],

            // ---- Nos sauces : ingrédients DONNÉS PAR LA CARTE ------------
            'Sauce man' => [
                'Fromage peulh (kg)' => '0.050', 'Peau de bœuf (kg)' => '0.050', 'Poisson fumé (kg)' => '0.050',
            ],
            'Sauce acadjou' => ['Fromage peulh (kg)' => '0.060'],
            'Sauce crin-crin / gombo' => [
                'Fromage peulh (kg)' => '0.050', 'Peau de bœuf (kg)' => '0.050', 'Poisson fumé (kg)' => '0.050',
            ],
            'Sauce moyo' => [
                'Poisson fumé (kg)' => '0.060', 'Tomate fraîche' => '0.080', 'Oignon frais' => '0.030',
            ],
            "Sauce d'arachide" => ['Fromage peulh (kg)' => '0.050', "Pâte d'arachide (kg)" => '0.060'],

            // ---- Garnitures ----------------------------------------------
            // ⚠ « moyen » et « grand » consomment le MÊME demi-poulet : le
            // référentiel ne distingue pas deux calibres de volaille, et
            // inventer un écart de grammage serait inventer un article.
            'Demi poulet moyen' => ['Poulet entier' => '0.500'],
            'Demi poulet grand' => ['Poulet entier' => '0.500'],
            'Demi pintade' => ['Pintade (unité)' => '0.500'],
            'Poisson carpe MOYEN' => ['Poisson carpe (kg)' => '0.350'],
            'Poisson carpe GRAND' => ['Poisson carpe (kg)' => '0.500'],
            'Poisson dorade' => ['Poisson dorade (kg)' => '0.300'],
            'Poissons silivi' => ['Poisson silivi (kg)' => '0.300'],
            'Poissons chat PETIT' => ['Poisson chat (kg)' => '0.250'],
            'Poisson chat GRAND' => ['Poisson chat (kg)' => '0.400'],
            'Ailleron' => ['Poulet entier' => '0.100'],
            'Portion de bœuf' => ['Viande de bœuf (kg)' => '0.150'],
            'Portion de mouton' => ['Viande de mouton (kg)' => '0.150'],
            'Portion de boyaux bœuf' => ['Boyaux de bœuf (kg)' => '0.150'],
            'Saucisse' => ['Saucisse (kg)' => '0.060'],
            'Omelette nature' => ['Œufs (plateau de 30)' => '0.100'],
            'Omelette légume' => [
                'Œufs (plateau de 30)' => '0.100', 'Tomate fraîche' => '0.040',
                'Oignon frais' => '0.020', 'Carotte' => '0.030',
            ],
            'Omelette sardine' => ['Œufs (plateau de 30)' => '0.100', 'Sardine (boîte 125 g)' => '1.000'],
            'Omelette du gîte' => [
                'Œufs (plateau de 30)' => '0.100', 'Jambon (kg)' => '0.040', 'Fromage peulh (kg)' => '0.030',
            ],
            'Omelette soufflée au jambon' => ['Œufs (plateau de 30)' => '0.130', 'Jambon (kg)' => '0.060'],

            // ---- Accompagnements -----------------------------------------
            "Frites d'igname, pommes de terre, patate douces" => [
                'Igname (kg)' => '0.100', 'Pomme de terre (kg)' => '0.100',
                'Patate douce (kg)' => '0.100', 'Huile végétale (bidon 20 L)' => '0.005',
            ],
            'Pommes sautées' => ['Pomme de terre (kg)' => '0.250', 'Huile végétale (bidon 20 L)' => '0.005'],
            'Spaghetti, coquillette' => ['Pâtes alimentaires (kg)' => '0.150'],
            'Attieke + plantin' => ['Attiéké (kg)' => '0.200', 'Plantain (kg)' => '0.150'],
            'Piron' => ['Farine de maïs (kg)' => '0.150'],
            'Ratatouille' => [
                'Tomate fraîche' => '0.100', 'Aubergine' => '0.100',
                'Oignon frais' => '0.050', 'Carotte' => '0.050',
            ],
            'Akassa' => ['Farine de maïs (kg)' => '0.150'],
            'Aloco' => ['Plantain (kg)' => '0.200', 'Huile végétale (bidon 20 L)' => '0.005'],
            'Couscous de fonio' => ['Fonio (kg)' => '0.150'],
            'Couscous marocain' => ['Semoule de couscous (kg)' => '0.150'],
            "Couscous d'igname (wassa-wassa)" => ['Igname (kg)' => '0.250'],
            'Riz blanc' => ['Riz local (sac 50 kg)' => '0.010'],
            'Riz au gras' => [
                'Riz local (sac 50 kg)' => '0.010', 'Tomate fraîche' => '0.050',
                'Huile végétale (bidon 20 L)' => '0.005',
            ],
            'Riz créole' => ['Riz local (sac 50 kg)' => '0.010', 'Carotte' => '0.040', 'Petit pois' => '0.040'],
            'Atassi (riz + haricot) + dja' => [
                'Riz local (sac 50 kg)' => '0.008', 'Haricot sec (kg)' => '0.080',
            ],
            'Pâte noire' => ['Farine de maïs (kg)' => '0.150'],
            'Pâte blanche' => ['Farine de maïs (kg)' => '0.150'],
            'Pâte rouge' => ['Farine de maïs (kg)' => '0.150', 'Tomate fraîche' => '0.050'],
            "Igname pilé + sauce d'arachide" => ['Igname (kg)' => '0.300', "Pâte d'arachide (kg)" => '0.050'],

            // ---- Sandwicherie --------------------------------------------
            'Chawarma viande' => [
                'Galette à chawarma (unité)' => '1.000', 'Viande de bœuf (kg)' => '0.100', 'Laitue' => '0.030',
            ],
            'Chawarma poulet' => [
                'Galette à chawarma (unité)' => '1.000', 'Poulet entier' => '0.150', 'Laitue' => '0.030',
            ],
            'Chawarma poisson' => [
                'Galette à chawarma (unité)' => '1.000', 'Poisson carpe (kg)' => '0.120', 'Laitue' => '0.030',
            ],
            'Chawarma végan' => [
                'Galette à chawarma (unité)' => '1.000', 'Carotte' => '0.050', 'Chou' => '0.050',
                'Laitue' => '0.030', 'Tomate fraîche' => '0.040',
            ],
            // Ingrédients DONNÉS PAR LA CARTE (viande de bœuf, saucisse).
            'Chawarma mixte' => [
                'Galette à chawarma (unité)' => '1.000', 'Viande de bœuf (kg)' => '0.080', 'Saucisse (kg)' => '0.050',
            ],
            // Ingrédients DONNÉS PAR LA CARTE (bœuf, jambon, fromage peulh).
            'Chawarma gite' => [
                'Galette à chawarma (unité)' => '1.000', 'Viande de bœuf (kg)' => '0.080',
                'Jambon (kg)' => '0.040', 'Fromage peulh (kg)' => '0.030',
            ],
            'Sandwich viande' => [
                'Pain sandwich (unité)' => '1.000', 'Viande de bœuf (kg)' => '0.080', 'Laitue' => '0.030',
            ],
            'Sandwich poisson' => [
                'Pain sandwich (unité)' => '1.000', 'Poisson carpe (kg)' => '0.100', 'Laitue' => '0.030',
            ],
            'Sandwich omelette' => ['Pain sandwich (unité)' => '1.000', 'Œufs (plateau de 30)' => '0.070'],
            'Sandwich poulet' => [
                'Pain sandwich (unité)' => '1.000', 'Poulet entier' => '0.120', 'Laitue' => '0.030',
            ],
            'Panini' => [
                'Pain sandwich (unité)' => '1.000', 'Fromage peulh (kg)' => '0.040', 'Tomate fraîche' => '0.040',
            ],
            'Panini jambon' => [
                'Pain sandwich (unité)' => '1.000', 'Jambon (kg)' => '0.050', 'Fromage peulh (kg)' => '0.040',
            ],
            'Hamburger + frite' => [
                'Pain sandwich (unité)' => '1.000', 'Viande de bœuf (kg)' => '0.100',
                'Pomme de terre (kg)' => '0.150', 'Huile végétale (bidon 20 L)' => '0.005',
            ],
            'Chicken burger + frite' => [
                'Pain sandwich (unité)' => '1.000', 'Poulet entier' => '0.150',
                'Pomme de terre (kg)' => '0.150', 'Huile végétale (bidon 20 L)' => '0.005',
            ],

            // ---- Pizzas : ingrédients DONNÉS PAR LA CARTE ----------------
            'Pizza du gîte (grande)' => [
                'Farine de blé (sac 50 kg)' => '0.006', 'Tomate fraîche' => '0.100',
                'Viande de bœuf (kg)' => '0.100', 'Saucisse (kg)' => '0.060',
                'Fromage peulh (kg)' => '0.050', 'Mozzarella (kg)' => '0.100',
            ],
            'Pizza du nord (grande)' => [
                'Farine de blé (sac 50 kg)' => '0.006', 'Tomate fraîche' => '0.100',
                'Fromage peulh (kg)' => '0.060', 'Mozzarella (kg)' => '0.100',
            ],
            'Pizza cordon bleu' => [
                'Farine de blé (sac 50 kg)' => '0.006', 'Tomate fraîche' => '0.100',
                'Poulet entier' => '0.150', 'Jambon (kg)' => '0.050', 'Mozzarella (kg)' => '0.100',
            ],
            'Pizza végan' => [
                'Farine de blé (sac 50 kg)' => '0.006', 'Carotte' => '0.050', 'Chou' => '0.050',
                'Haricot vert' => '0.050', 'Champignon' => '0.050', 'Petit pois' => '0.050',
                'Maïs doux (boîte 400 g)' => '0.100', 'Mozzarella (kg)' => '0.100',
            ],
            'Pizza royale (grande)' => [
                'Farine de blé (sac 50 kg)' => '0.006', 'Carotte' => '0.050', 'Chou' => '0.050',
                'Jambon (kg)' => '0.050', 'Viande de bœuf (kg)' => '0.100', 'Mozzarella (kg)' => '0.100',
            ],

            // ---- Nos desserts --------------------------------------------
            'Crêpe sucrée' => [
                'Farine de blé (sac 50 kg)' => '0.005', 'Sucre (kg)' => '0.030',
                'Œufs (plateau de 30)' => '0.034',
            ],
            'Crêpe au chocolat' => [
                'Farine de blé (sac 50 kg)' => '0.005', 'Chocolat à tartiner (kg)' => '0.040',
                'Œufs (plateau de 30)' => '0.034',
            ],
            'Crêpe au miel' => [
                'Farine de blé (sac 50 kg)' => '0.005', 'Miel (L)' => '0.030',
                'Œufs (plateau de 30)' => '0.034',
            ],
            'Crêpe flambée' => [
                'Farine de blé (sac 50 kg)' => '0.005', 'Sucre (kg)' => '0.030',
                'Œufs (plateau de 30)' => '0.034',
            ],
            'Pancake au miel' => [
                'Farine de blé (sac 50 kg)' => '0.005', 'Miel (L)' => '0.030',
                'Œufs (plateau de 30)' => '0.034', 'Lait en poudre (kg)' => '0.020',
            ],
            'Pancake au chocolat' => [
                'Farine de blé (sac 50 kg)' => '0.005', 'Chocolat à tartiner (kg)' => '0.040',
                'Œufs (plateau de 30)' => '0.034', 'Lait en poudre (kg)' => '0.020',
            ],
            'Salade de fruit' => ['Fruits de saison' => '0.200'],
            'Dèguè + cake' => [
                'Mil (kg)' => '0.080', 'Lait en poudre (kg)' => '0.030', 'Cake (unité)' => '1.000',
            ],

            // ---- Formules & brochettes -----------------------------------
            // « + accompagnement » : le riz est l'accompagnement par défaut du
            // Gîte. L'ardoise ne dit pas lequel — elle écrit « Accompagnement
            // (même prix) » et en liste sept. Le choix est POSÉ, comme les
            // quantités, et la marque provisoire le couvre.
            'Poisson + accompagnement' => [
                'Poisson carpe (kg)' => '0.400', 'Riz local (sac 50 kg)' => '0.010',
            ],
            'Poisson silvi + accompagnement' => [
                'Poisson silivi (kg)' => '0.300', 'Riz local (sac 50 kg)' => '0.010',
            ],
            'Saucisse + accompagnement' => ['Saucisse (kg)' => '0.060', 'Riz local (sac 50 kg)' => '0.010'],
            'Omelette + accompagnement' => [
                'Œufs (plateau de 30)' => '0.100', 'Riz local (sac 50 kg)' => '0.010',
            ],
            'Viande de bœuf + accompagnement' => [
                'Viande de bœuf (kg)' => '0.150', 'Riz local (sac 50 kg)' => '0.010',
            ],
            'Viande de mouton + accompagnement' => [
                'Viande de mouton (kg)' => '0.150', 'Riz local (sac 50 kg)' => '0.010',
            ],
            'Brochette de bœuf' => ['Viande de bœuf (kg)' => '0.120', 'Oignon frais' => '0.030'],
            'Brochette de mouton' => ['Viande de mouton (kg)' => '0.120', 'Oignon frais' => '0.030'],
            'Pintade + accompagnement' => ['Pintade (unité)' => '0.250', 'Riz local (sac 50 kg)' => '0.010'],
            'Poulet + accompagnement' => ['Poulet entier' => '0.250', 'Riz local (sac 50 kg)' => '0.010'],
            'Repe soupe (Poisson-chat)' => [
                'Poisson chat (kg)' => '0.400', 'Tomate fraîche' => '0.080', 'Oignon frais' => '0.040',
            ],
        ];
    }

    /**
     * La SEULE fiche dont les grammages viennent de la cuisine.
     *
     * Toutes les autres portent `composition_provisoire` : leurs quantités ont
     * été posées pour débloquer le service, personne ne les a pesées.
     */
    private const FICHE_PESEE = 'Tchep au poisson';

    public function run(): void
    {
        // ⚠ COMPLEMENTAIRE, jamais « tout ou rien » (04/09/2026, deuxieme
        // pose : le premier correctif a saute a la reecriture du seeder).
        //
        // La garde rendait la main des qu'un menu existait — donc sur TOUTE
        // base deja semee, celle du Gite comprise : ni les preparations
        // ajoutees a la carte, ni les denrees qu'elles exigent n'y seraient
        // jamais entrees, et les plats concernes resteraient invendables.
        // Meme angle mort que `RolePermissionSeeder` le 02/09 (un module
        // ajoute n'atteignait jamais une base existante), meme reponse :
        // COMPLETER ce qui manque, ne JAMAIS reecrire ce qui existe — un
        // prix ajuste a l'ecran par le Gite fait foi contre ce fichier.
        if (Menu::query()->exists()) {
            $this->completerLaCarte();

            return;
        }

        $cartes = app(CartePlatMenuService::class);
        $compositions = app(CompositionRecetteService::class);
        $recettesParPlat = self::compositions();

        $menu = Menu::create([
            'id' => (string) Str::uuid(),
            'libelle' => 'Carte du restaurant',
            'type' => 'local',
        ]);

        foreach (self::carte() as [$libelle, $prix, $rayon, $corrigeMain, $provisoire]) {
            $ingredients = $recettesParPlat[$libelle] ?? null;

            if ($ingredients === null || $ingredients === []) {
                // Une fiche vide ne REFUSE plus la vente (decision du PO du 30/10/2026),
                // mais le referentiel de demonstration doit decrementer le stock de
                // chaque plat : la laisser passer vendrait ce plat sans sortie de stock.
                throw new RuntimeException(
                    'RestaurantSeeder : aucune fiche technique pour « '.$libelle.' ». La vente '
                    .'de ce plat ne decrementerait aucun stock. Completer compositions().',
                );
            }

            $recette = Recette::create(['id' => (string) Str::uuid(), 'libelle' => $libelle]);

            $lignes = [];

            foreach ($ingredients as $libelleArticle => $quantite) {
                $lignes[] = [
                    'article_id' => $this->articleId($libelleArticle),
                    'quantite_unitaire' => $quantite,
                ];
            }

            // `provisoire: true` — la DECISION explicite de l'appelant. Ecrire
            // la colonne ici ferait de ce seeder un second auteur de la marque
            // (le service en est l'unique auteur, comme des lignes).
            $compositions->remplacerComposition(
                $recette,
                $lignes,
                provisoire: $libelle !== self::FICHE_PESEE,
            );

            $cartes->creerPlat([
                'id' => (string) Str::uuid(),
                'menu_id' => $menu->id,
                'recette_id' => $recette->id,
                'libelle' => $libelle,
                'prix_vente' => $prix,
                // Le CODE du rayon, jamais son libellé : le filtre des écrans
                // interroge les clés de `CarteRestaurant::CATEGORIES`, et un
                // libellé stocké ne correspondait à aucune option.
                // `article_id` reste NUL — un plat se cuisine, il ne se stocke
                // pas ; c'est sa fiche technique qui décrémente.
                'categorie' => $rayon,
                MarquesDePrix::CORRIGE_MAIN => $corrigeMain,
                MarquesDePrix::PROVISOIRE => $provisoire,
            ]);
        }
    }

    /**
     * Complete une carte DEJA en base : les preparations absentes et leurs
     * fiches, plus la composition des fiches restees vides.
     *
     * Ce qui existe n'est jamais touche — ni un prix, ni une composition, ni
     * une marque. Le Gite ajuste ses prix a l'ecran ; ce fichier n'a pas
     * autorite sur eux. Les ecarts se CONSTATENT (le rapport de livraison en
     * porte deux), ils ne s'ecrasent pas en silence.
     */
    private function completerLaCarte(): void
    {
        $menu = Menu::query()->firstOrFail();
        $cartes = app(CartePlatMenuService::class);
        $compositions = app(CompositionRecetteService::class);
        $recettesParPlat = self::compositions();

        foreach (self::carte() as [$libelle, $prix, $rayon, $corrigeMain, $provisoire]) {
            $ingredients = $recettesParPlat[$libelle] ?? [];

            if ($ingredients === []) {
                continue;
            }

            $plat = Plat::query()->where('libelle', $libelle)->first();

            if ($plat instanceof Plat) {
                // Le plat existe : on ne complete que sa fiche si elle est
                // VIDE. Une fiche composee — posee ici hier ou saisie par la
                // cuisine — l'emporte toujours.
                $recette = $plat->recette;

                if ($recette instanceof Recette && $compositions->lignes($recette) === []) {
                    $compositions->remplacerComposition(
                        $recette,
                        $this->lignesDeComposition($ingredients),
                        provisoire: $libelle !== self::FICHE_PESEE,
                    );
                }

                continue;
            }

            // La preparation manque entierement : fiche puis plat, dans cet
            // ordre — `plats.recette_id` est NOT NULL — et dans UNE
            // transaction. Sans elle, un article introuvable laisse la fiche
            // deja creee SANS plat ni composition : une orpheline que l'onglet
            // « Fiches techniques » rend comme une fiche vide, indiscernable
            // d'une fiche a completer. Constate sur la base du Gite le
            // 04/09/2026, deux orphelines apres un passage interrompu.
            DB::transaction(function () use ($libelle, $prix, $rayon, $corrigeMain, $provisoire, $ingredients, $menu, $cartes, $compositions): void {
                $recette = Recette::create(['id' => (string) Str::uuid(), 'libelle' => $libelle]);

                $compositions->remplacerComposition(
                    $recette,
                    $this->lignesDeComposition($ingredients),
                    provisoire: $libelle !== self::FICHE_PESEE,
                );

                $cartes->creerPlat([
                    'id' => (string) Str::uuid(),
                    'menu_id' => $menu->id,
                    'recette_id' => $recette->id,
                    'libelle' => $libelle,
                    'prix_vente' => $prix,
                    'categorie' => $rayon,
                    MarquesDePrix::CORRIGE_MAIN => $corrigeMain,
                    MarquesDePrix::PROVISOIRE => $provisoire,
                ]);
            });
        }
    }

    /**
     * Les lignes d'une composition, articles resolus par leur libelle EXACT.
     *
     * @param  array<string, string>  $ingredients
     * @return list<array{article_id: string, quantite_unitaire: string}>
     */
    private function lignesDeComposition(array $ingredients): array
    {
        $lignes = [];

        foreach ($ingredients as $libelleArticle => $quantite) {
            $lignes[] = [
                'article_id' => $this->articleId($libelleArticle),
                'quantite_unitaire' => $quantite,
            ];
        }

        return $lignes;
    }

    /**
     * L'article est LU dans le référentiel de `StocksSeeder`, par son libellé
     * EXACT. Un `LIKE` rattacherait la fiche technique au premier article dont
     * le nom contient le motif — « Riz local » a déjà remonté « Riz parfumé
     * importé » —, et une création de repli poserait un second article que
     * personne n'approvisionne.
     */
    private function articleId(string $libelle): string
    {
        $id = Article::query()->where('libelle', $libelle)->value('id');

        if ($id === null) {
            // Message exploitant, jamais affiche a un utilisateur.
            throw new RuntimeException(
                'RestaurantSeeder lit les articles de StocksSeeder : ingredient '
                .'introuvable ('.$libelle.'). Lancer StocksSeeder avant '
                .'(DatabaseSeeder le fait deja). Ce seeder ne cree AUCUN article — '
                .'un article cree ici serait un second auteur du referentiel, et la '
                .'fiche technique decrementerait un stock que personne ne remplit.',
            );
        }

        return (string) $id;
    }
}
