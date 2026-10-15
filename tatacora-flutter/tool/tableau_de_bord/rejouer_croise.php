<?php

declare(strict_types=1);

/*
| Rejoue le TABLEAU CROISE DYNAMIQUE du serveur (`Accueil::croiser`, methode
| PRIVEE appelee par reflexion) sur des donnees donnees — pour que le poste
| (`domain/croise_local.dart`) soit confronte a la SOURCE, jamais a une
| formule recopiee (13/10/2026, INSTRUCTION1.txt du PO).
|
| Le VRAI `Accueil` (registres AXES_CROISE, MESURES_CROISE, SOURCES_CROISE,
| `croiser`, `faitsCroises`, `fait`, `libelleMode`) et le VRAI `Periode` sont
| charges par l'autoloader de Composer ; seule la base est un double : un
| SQLite en memoire portant les seules colonnes que `faitsCroises` lit. Les
| libelles passent par le VRAI traducteur de Laravel sur `lang/fr`.
|
| Entree (stdin, JSON) :
|   { "ventes": [{"id":"v1","statut":"validee","created_at":"2026-10-03 10:00:00",
|                 "point_vente":"Comptoir","mode_paiement":"especes","encaisse":true,
|                 "lignes":[{"module":"M5","categorie":"locale","nom":"Biere",
|                            "quantite":2,"montant":"2000.00"}]}],
|     "depenses": [{"id":"d1","date_transaction":"2026-10-04","tresorerie":"caisse",
|                   "lignes":[{"famille":"Achats","nature":"Riz","montant":"5000.00"}]}],
|     "clients": [{"id":"c1","nom":"KORA","prenom":"Jean"}],
|     "reservations": [{"id":"r1","statut":"confirmee","date_arrivee":"2026-10-05",
|                       "acompte":"10000.00","client_id":"c1"}],
|     "requetes": [{"reference":"2026-10-15 12:00:00","periode":"mois","du":null,"au":null,
|                   "ligne":"activite","colonne":"mois","mesure":"montant",
|                   "sources":["ventes","depenses","reservations"]}] }
| Sortie (stdout, JSON) : pour chaque requete, le croisement tel que la vue le
| recoit ; puis les registres et les libelles de la vue.
|
| Usage : php tool/tableau_de_bord/rejouer_croise.php < cas.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Domain\TableauxDeBord\Data\Periode;
use App\Pwa\Livewire\Accueil;
use Carbon\CarbonImmutable;
use Illuminate\Container\Container;
use Illuminate\Database\Capsule\Manager as Capsule;
use Illuminate\Filesystem\Filesystem;
use Illuminate\Support\Facades\Facade;
use Illuminate\Translation\FileLoader;
use Illuminate\Translation\Translator;

date_default_timezone_set('UTC');

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario)) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

// La locale du serveur (`APP_LOCALE=fr`) : `translatedFormat('F Y')` rend
// « octobre 2026 », et `startOfWeek()` le lundi.
CarbonImmutable::setLocale('fr');

$capsule = new Capsule();
$capsule->addConnection(['driver' => 'sqlite', 'database' => ':memory:', 'prefix' => '']);
$capsule->setAsGlobal();
$capsule->bootEloquent();

$conteneur = new Container();
$conteneur->instance('db', $capsule->getDatabaseManager());
$conteneur->instance('translator', new Translator(new FileLoader(new Filesystem(), $api . '/lang'), 'fr'));
Container::setInstance($conteneur);
Facade::setFacadeApplication($conteneur);

$pdo = $capsule->getConnection()->getPdo();

foreach ([
    'CREATE TABLE ventes (id TEXT PRIMARY KEY, statut TEXT, created_at TEXT, point_vente TEXT, mode_paiement TEXT, encaisse INTEGER)',
    'CREATE TABLE lignes_vente (id INTEGER PRIMARY KEY AUTOINCREMENT, vente_id TEXT, module TEXT, categorie TEXT, nom TEXT, quantite INTEGER, montant NUMERIC)',
    'CREATE TABLE depenses (id TEXT PRIMARY KEY, date_transaction TEXT, tresorerie TEXT)',
    'CREATE TABLE lignes_depense (id INTEGER PRIMARY KEY AUTOINCREMENT, depense_id TEXT, famille TEXT, nature TEXT, montant NUMERIC)',
    'CREATE TABLE clients (id TEXT PRIMARY KEY, nom TEXT, prenom TEXT)',
    'CREATE TABLE reservations (id TEXT PRIMARY KEY, statut TEXT, date_arrivee TEXT, acompte NUMERIC, client_id TEXT)',
] as $ddl) {
    $pdo->exec($ddl);
}

$db = $capsule->getConnection();

foreach ($scenario['ventes'] ?? [] as $v) {
    $db->table('ventes')->insert([
        'id' => $v['id'], 'statut' => $v['statut'], 'created_at' => $v['created_at'],
        'point_vente' => $v['point_vente'], 'mode_paiement' => $v['mode_paiement'],
        'encaisse' => $v['encaisse'] ? 1 : 0,
    ]);
    foreach ($v['lignes'] as $l) {
        $db->table('lignes_vente')->insert([
            'vente_id' => $v['id'], 'module' => $l['module'], 'categorie' => $l['categorie'],
            'nom' => $l['nom'], 'quantite' => $l['quantite'], 'montant' => $l['montant'],
        ]);
    }
}
foreach ($scenario['depenses'] ?? [] as $d) {
    $db->table('depenses')->insert([
        'id' => $d['id'], 'date_transaction' => $d['date_transaction'], 'tresorerie' => $d['tresorerie'],
    ]);
    foreach ($d['lignes'] as $l) {
        $db->table('lignes_depense')->insert([
            'depense_id' => $d['id'], 'famille' => $l['famille'], 'nature' => $l['nature'],
            'montant' => $l['montant'],
        ]);
    }
}
foreach ($scenario['clients'] ?? [] as $c) {
    $db->table('clients')->insert(['id' => $c['id'], 'nom' => $c['nom'], 'prenom' => $c['prenom']]);
}
foreach ($scenario['reservations'] ?? [] as $r) {
    $db->table('reservations')->insert([
        'id' => $r['id'], 'statut' => $r['statut'], 'date_arrivee' => $r['date_arrivee'],
        'acompte' => $r['acompte'], 'client_id' => $r['client_id'],
    ]);
}

$composant = (new ReflectionClass(Accueil::class))->newInstanceWithoutConstructor();
$croiser = new ReflectionMethod(Accueil::class, 'croiser');
$sourcesValides = new ReflectionMethod(Accueil::class, 'sourcesCroiseValides');

$resultats = [];
foreach ($scenario['requetes'] ?? [] as $q) {
    CarbonImmutable::setTestNow(CarbonImmutable::parse($q['reference']));
    $periode = Periode::resoudre((string) $q['periode'], $q['du'] ?? null, $q['au'] ?? null);
    CarbonImmutable::setTestNow();

    $composant->croiseLigne = (string) $q['ligne'];
    $composant->croiseColonne = (string) $q['colonne'];
    $composant->croiseMesure = (string) $q['mesure'];
    $composant->croiseSources = $q['sources'];

    $resultats[] = [
        'croise' => $croiser->invoke($composant, $periode),
        'sources_retenues' => $sourcesValides->invoke($composant),
        'periode' => [
            'debut' => $periode->debut->format('Y-m-d H:i:s'),
            'fin' => $periode->fin->format('Y-m-d H:i:s'),
        ],
    ];
}

$accueil = require $api . '/lang/fr/accueil_pwa.php';

echo json_encode([
    'resultats' => $resultats,
    'registres' => [
        'axes' => array_keys(Accueil::AXES_CROISE),
        'mesures' => Accueil::MESURES_CROISE,
        'sources' => Accueil::SOURCES_CROISE,
        'defauts' => [
            'ligne' => (new ReflectionProperty(Accueil::class, 'croiseLigne'))->getDefaultValue(),
            'colonne' => (new ReflectionProperty(Accueil::class, 'croiseColonne'))->getDefaultValue(),
            'mesure' => (new ReflectionProperty(Accueil::class, 'croiseMesure'))->getDefaultValue(),
            'sources' => (new ReflectionProperty(Accueil::class, 'croiseSources'))->getDefaultValue(),
        ],
    ],
    'libelles' => [
        'croise' => $accueil['croise'],
        'tiret' => $accueil['tiret'],
        'non_consulte' => $accueil['non_consulte'],
        'onglet' => $accueil['onglets']['croise'],
        'export_bouton' => (require $api . '/lang/fr/pwa.php')['export']['bouton'],
    ],
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
