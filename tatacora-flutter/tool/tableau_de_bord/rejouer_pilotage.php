<?php

declare(strict_types=1);

/*
| Rejoue la carte « Location de vehicules » du Pilotage consolide
| (`Accueil::moduleVehicules`, methode PRIVEE appelee par reflexion) sur des
| donnees donnees — pour que le poste (`domain/modules_pilotage.dart`) soit
| confronte a la SOURCE (13/10/2026, fin du Pilotage).
|
| Le VRAI `Accueil`, le VRAI `ParcVehiculeService` (`contratsSurFenetre`,
| `agregerContratsActifs`) et les VRAIS modeles `ContratLocation` / `Vehicule`
| sont charges par l'autoloader de Composer ; seule la base est un double : un
| SQLite en memoire portant les colonnes que ces methodes lisent.
|
| Entree (stdin, JSON) :
|   { "vehicules": [{"id":"v1","statut":"disponible"}],
|     "contrats":  [{"id":"c1","vehicule_id":"v1","date_debut":"2026-10-10",
|                    "date_fin":"2026-10-13","montant":"45000.00","statut":"actif"}],
|     "jours": ["2026-10-13", ...] }
| Sortie : pour chaque jour (l'horloge posee par `setTestNow`), la carte.
|
| Usage : php tool/tableau_de_bord/rejouer_pilotage.php < cas.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Domain\Vehicules\Services\ParcVehiculeService;
use App\Pwa\Livewire\Accueil;
use Carbon\CarbonImmutable;
use Illuminate\Container\Container;
use Illuminate\Database\Capsule\Manager as Capsule;
use Illuminate\Support\Facades\Facade;

date_default_timezone_set('UTC');

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario)) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

CarbonImmutable::setLocale('fr');

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
    'CREATE TABLE vehicules (id TEXT PRIMARY KEY, statut TEXT)',
    'CREATE TABLE contrats_location (id TEXT PRIMARY KEY, vehicule_id TEXT, date_debut TEXT, date_fin TEXT, montant NUMERIC, reste_a_payer NUMERIC, statut TEXT)',
] as $ddl) {
    $pdo->exec($ddl);
}

$db = $capsule->getConnection();
foreach ($scenario['vehicules'] ?? [] as $v) {
    $db->table('vehicules')->insert(['id' => $v['id'], 'statut' => $v['statut']]);
}
foreach ($scenario['contrats'] ?? [] as $c) {
    $db->table('contrats_location')->insert([
        'id' => $c['id'], 'vehicule_id' => $c['vehicule_id'],
        'date_debut' => $c['date_debut'], 'date_fin' => $c['date_fin'],
        'montant' => $c['montant'], 'reste_a_payer' => '0.00',
        'statut' => $c['statut'] ?? 'actif',
    ]);
}

// Le service est resolu par `app()` dans `moduleVehicules` : on l'enregistre.
$conteneur->singleton(ParcVehiculeService::class, static fn () => new ParcVehiculeService());

$composant = (new ReflectionClass(Accueil::class))->newInstanceWithoutConstructor();
$methode = new ReflectionMethod(Accueil::class, 'moduleVehicules');

$cartes = [];
foreach ($scenario['jours'] ?? [] as $jour) {
    CarbonImmutable::setTestNow(CarbonImmutable::parse($jour . ' 10:00:00'));
    $carte = $methode->invoke($composant);
    CarbonImmutable::setTestNow();
    $cartes[] = ['jour' => $jour] + $carte;
}

echo json_encode(['cartes' => $cartes], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
