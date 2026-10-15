<?php

declare(strict_types=1);

/*
| Rejoue, en PHP, la carte du restaurant du SERVEUR sur un scenario donne —
| pour que les tests Flutter confrontent `RestaurantApi.carte()` a la SOURCE,
| jamais a une formule recopiee (09/10/2026).
|
| Le code execute est le VRAI : `CarteRestaurantService::carte()` et, derriere
| lui, `CompositionRecetteService::coutMatiere()`. Seule la base est factice :
| une base SQLite en memoire, avec les seules colonnes que ces deux services
| lisent. Aucun demarrage de l'application, aucune migration MySQL.
|
| Entree (stdin, JSON) :
|   { "points": [{"id","libelle","type"|null}],
|     "articles": [{"id","libelle","unite","seuil":"5.00","suivi":"permanent",
|                    "cmp":"1000.0000"}],
|     "mouvements": [{"article_id","point_id","type":"entree","quantite":"10.00"}],
|     "menus": [{"id","libelle","type"}],
|     "recettes": [{"id","libelle"}],
|     "ingredients": [{"recette_id","article_id","quantite":"0.250"}],
|     "plats": [{"id","libelle","menu_id","recette_id","prix_vente":"2500.00",
|                "prix_provisoire":false}],
|     "requetes": [{"recherche":null,"categorie":null,"etat":null}] }
| Sortie (stdout, JSON) : pour chaque requete, les lignes, les indicateurs, la
| couverture et le point cuisine, tels que le serveur les calcule.
|
| Usage : php tool/restaurant/exporter_carte.php < scenario.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Domain\Restaurant\Services\CarteRestaurantService;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use Illuminate\Container\Container;
use Illuminate\Database\Capsule\Manager as Capsule;
use Illuminate\Support\Facades\Facade;

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario)) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

$capsule = new Capsule();
$capsule->addConnection(['driver' => 'sqlite', 'database' => ':memory:', 'prefix' => '']);
$capsule->setAsGlobal();
$capsule->bootEloquent();

$conteneur = new Container();
$conteneur->instance('db', $capsule->getDatabaseManager());
Container::setInstance($conteneur);
Facade::setFacadeApplication($conteneur);

$pdo = $capsule->getConnection()->getPdo();

foreach ([
    'CREATE TABLE points_stockage (id TEXT PRIMARY KEY, libelle TEXT, type TEXT, created_at TEXT, updated_at TEXT)',
    'CREATE TABLE articles (id TEXT PRIMARY KEY, libelle TEXT, categorie TEXT, unite_mesure TEXT, '
        . 'point_stockage_id TEXT, suivi TEXT, seuil_alerte TEXT, seuil_reappro TEXT, '
        . 'cout_moyen_pondere TEXT, prix_achat TEXT, actif INTEGER DEFAULT 1, created_at TEXT, updated_at TEXT)',
    'CREATE TABLE mouvements_stock (id TEXT PRIMARY KEY, article_id TEXT, point_id TEXT, '
        . 'type_mouvement TEXT, quantite TEXT)',
    'CREATE TABLE menus (id TEXT PRIMARY KEY, libelle TEXT, type TEXT, date_debut TEXT, date_fin TEXT, '
        . 'created_at TEXT, updated_at TEXT)',
    'CREATE TABLE recettes (id TEXT PRIMARY KEY, libelle TEXT, cout_matiere_calcule TEXT, '
        . 'composition_provisoire INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT)',
    'CREATE TABLE ingredients_recette (recette_id TEXT, article_id TEXT, quantite_unitaire TEXT, '
        . 'PRIMARY KEY (recette_id, article_id))',
    'CREATE TABLE plats (id TEXT PRIMARY KEY, menu_id TEXT, recette_id TEXT, article_id TEXT, '
        . 'unites_vendables_par_unite_stock TEXT, libelle TEXT, prix_vente TEXT, categorie TEXT, '
        . 'prix_provisoire INTEGER DEFAULT 0, prix_corrige_main INTEGER DEFAULT 0, created_at TEXT, updated_at TEXT)',
] as $ddl) {
    $pdo->exec($ddl);
}

$db = $capsule->getConnection();

foreach ($scenario['points'] ?? [] as $p) {
    $db->table('points_stockage')->insert(['id' => $p['id'], 'libelle' => $p['libelle'], 'type' => $p['type'] ?? null]);
}
foreach ($scenario['articles'] ?? [] as $a) {
    $db->table('articles')->insert([
        'id' => $a['id'], 'libelle' => $a['libelle'], 'categorie' => '', 'unite_mesure' => $a['unite'],
        'suivi' => $a['suivi'], 'seuil_alerte' => $a['seuil'], 'cout_moyen_pondere' => $a['cmp'],
    ]);
}
foreach ($scenario['mouvements'] ?? [] as $i => $m) {
    $db->table('mouvements_stock')->insert([
        'id' => 'm' . $i, 'article_id' => $m['article_id'], 'point_id' => $m['point_id'],
        'type_mouvement' => $m['type'], 'quantite' => $m['quantite'],
    ]);
}
foreach ($scenario['menus'] ?? [] as $m) {
    $db->table('menus')->insert(['id' => $m['id'], 'libelle' => $m['libelle'], 'type' => $m['type']]);
}
foreach ($scenario['recettes'] ?? [] as $r) {
    $db->table('recettes')->insert(['id' => $r['id'], 'libelle' => $r['libelle'], 'cout_matiere_calcule' => '0.00']);
}
foreach ($scenario['ingredients'] ?? [] as $i) {
    $db->table('ingredients_recette')->insert([
        'recette_id' => $i['recette_id'], 'article_id' => $i['article_id'], 'quantite_unitaire' => $i['quantite'],
    ]);
}
foreach ($scenario['plats'] ?? [] as $p) {
    $db->table('plats')->insert([
        'id' => $p['id'], 'menu_id' => $p['menu_id'], 'recette_id' => $p['recette_id'],
        'libelle' => $p['libelle'], 'prix_vente' => $p['prix_vente'],
        'prix_provisoire' => ($p['prix_provisoire'] ?? false) ? 1 : 0,
    ]);
}

$service = new CarteRestaurantService(new CompositionRecetteService());

$sortie = [];

foreach ($scenario['requetes'] ?? [[]] as $requete) {
    $carte = $service->carte(
        $requete['recherche'] ?? null,
        $requete['categorie'] ?? null,
        $requete['etat'] ?? null,
    );

    $lignes = [];
    foreach ($carte->lignes as $l) {
        $lignes[] = [
            'id' => $l->plat->id,
            'libelle' => $l->plat->libelle,
            'categorie' => $l->categorie,
            'nb_ingredients' => $l->nbIngredients,
            'lie' => $l->lieAuStock,
            'motif' => $l->motifSansStock,
            'portions' => $l->portionsVendables,
            'limitant' => $l->ingredientLimitant?->id,
            'rupture' => $l->rupture,
            'sous_seuil' => $l->sousSeuil,
            'cout' => $l->coutMatiere->montant,
            'cout_incomplet' => $l->coutMatiere->incomplet,
            'cout_vide' => $l->coutMatiere->compositionVide,
            'sans_cout' => $l->coutMatiere->articlesSansCout,
            'marge' => $l->marge(),
        ];
    }

    $sortie[] = [
        'lignes' => $lignes,
        'indicateurs' => $carte->indicateurs,
        'couverture' => $carte->couverture,
        'point_cuisine' => $carte->pointCuisineId,
    ];
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
