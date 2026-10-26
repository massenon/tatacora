<?php

declare(strict_types=1);

/*
| Rejoue, en PHP, les calculs de M11 du SERVEUR sur des cas donnes — pour que
| les tests Flutter confrontent `periode_locale.dart` et `indicateurs_locaux.dart`
| a la SOURCE, jamais a une formule recopiee (10/10/2026).
|
| Le VRAI `Periode` et le VRAI `TableauDeBordService` sont charges par
| l'autoloader de Composer ; seule la base est un double : un SQLite en memoire
| auquel on apprend les trois fonctions MySQL que le service emploie
| (DATEDIFF, LEAST, GREATEST). Les requetes, les predicats et les bornes sont
| ceux du serveur, pas une copie.
|
| Deux familles de periodes, comme la classe `Periode` (12/10/2026) :
|   - « a date » (`code`) : `Periode::depuisCode` — le contrat de l'API et du
|     moteur d'etats (M14 l'emploie toujours) ;
|   - « calendaire » (`calendaire`, `du`, `au`) : `Periode::resoudre`, appele
|     sous `setTestNow(reference)` — le registre du SELECTEUR de la vue
|     d'accueil (`Accueil::periode()`). `resoudre` lit l'horloge : c'est la
|     seule facon d'appeler la VRAIE methode a une date choisie.
|
| Entree (stdin, JSON) :
|   { "requetes": [{ "code": "30j", "reference": "2026-10-10 14:30:00" },
|                  { "calendaire": "personnalisee", "reference": "...",
|                    "du": "2026-10-05", "au": "2026-10-20" }, ...],
|     "stocks": [{ "articles": [{"id":"a1","libelle":"Riz","unite_mesure":"sac",
|                                 "seuil_alerte":"5.00"}],
|                  "mouvements": [{"article_id":"a1","type_mouvement":"entree",
|                                  "quantite":"10.00"}] }, ...],
|     "unites":       [{"id":"u1","statut":"libre"}, ...],
|     "reservations": [{"id":"r1","statut":"confirmee","arrivee":"2026-10-01",
|                       "depart":"2026-10-04","creee_le":"2026-09-30 10:00:00"}, ...],
|     "employes":     [{"statut":"actif"}, ...],
|     "factures":     [{"id":"f1","date_emission":"2026-10-02 09:00:00",
|                       "lignes":[{"module":"M1","montant":"50000.00"}]}, ...] }
| Sortie (stdout, JSON) : pour chaque requete, la periode (bornes, precedente,
| nombre de jours, libelle), puis les mesures, courantes et precedentes ; pour
| chaque jeu de stock, le nombre d'articles critiques du panneau « A traiter »
| (`Accueil::articlesCritiques`, methode PRIVEE appelee par reflexion) ; le
| registre du selecteur de la vue (codes, libelles, defaut du composant).
|
| Depuis le 12/10/2026 (lot 2, « Vue d'exploitation ») : `unites` portent
| aussi `numero` et `categorie_id`, `reservations` leur `unite_id`, et trois
| entrees s'ajoutent — `categories` ({id, libelle, tarif_base}), `ventes`
| ({statut, encaisse, created_at, montant_total}) et `journees` (dates
| `AAAA-MM-JJ`). Pour chaque journee : `Accueil::recapDuJour`,
| `Accueil::chambresDisponibles` (ids dans l'ordre) et le titre
| `translatedFormat('l j F')`. Chaque jeu de stock rend aussi les `stocks` et
| `seuils` de la liste des critiques, tels que la modale les ecrit.
|
| `ventes[].encaisse` est un BOOLEEN, comme la colonne du serveur : une vente
| du poste SANS mode de reglement (etat que le serveur n'a pas) arrive ici en
| `false` — l'etat le plus proche — et le test verifie que le poste ne la
| compte pas non plus dans « Encaisse aujourd'hui » (13/10/2026).
|
| Usage : php tool/tableau_de_bord/exporter_indicateurs.php < cas.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
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

// --- La locale de Carbon est CELLE DU SERVEUR (12/10/2026) -----------------
//
// `Periode::semaine()` appelle `startOfWeek()` SANS argument : le premier jour
// de la semaine vient de la locale de Carbon. Le serveur tourne en `fr`
// (`APP_LOCALE=fr` dans `.env` et `.env.example` ; `php artisan tinker` rend
// `CarbonImmutable::getLocale() === 'fr'`, semaine au LUNDI). Hors application,
// Carbon n'a que son defaut `en` — lundi aussi, mais par hasard : en `en_US`,
// la semaine commence le DIMANCHE (mesure : le 11/10/2026 donne le 11/10 au
// lieu du 05/10). La confrontation ne doit pas dependre de ce defaut.
//
// `locale_ambiante` (facultatif) SIMULE un poste dont la locale de Carbon
// differe, AVANT que le script ne pose celle du serveur : c'est la preuve
// executable que la locale est bien imposee (indicateurs_contre_serveur_test).
if (isset($scenario['locale_ambiante'])) {
    CarbonImmutable::setLocale((string) $scenario['locale_ambiante']);
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

// Les trois fonctions MySQL du service. Dates en chaine `AAAA-MM-JJ`.
$pdo->sqliteCreateFunction(
    'DATEDIFF',
    static fn (string $a, string $b): int => (int) round((strtotime(substr($a, 0, 10)) - strtotime(substr($b, 0, 10))) / 86400),
    2,
);
$pdo->sqliteCreateFunction('LEAST', static fn (string ...$v): string => min($v), -1);
$pdo->sqliteCreateFunction('GREATEST', static fn (string ...$v): string => max($v), -1);

foreach ([
    // `numero` et `categorie_id` : lus par `Accueil::chambresDisponibles`
    // (tri par numero, categorie chargee) ; `unite_id` des reservations : lu
    // par `DisponibiliteService::unitesDisponibles` (12/10/2026, lot 2).
    'CREATE TABLE unites_hebergement (id TEXT PRIMARY KEY, statut TEXT, numero TEXT, categorie_id TEXT)',
    'CREATE TABLE categories_hebergement (id TEXT PRIMARY KEY, libelle TEXT, tarif_base NUMERIC)',
    'CREATE TABLE reservations (id TEXT PRIMARY KEY, statut TEXT, date_arrivee TEXT, date_depart TEXT, date_creation TEXT, unite_id TEXT)',
    // Les colonnes que lit `Accueil::recapDuJour` sur `ventes` — et elles seules.
    'CREATE TABLE ventes (id INTEGER PRIMARY KEY AUTOINCREMENT, statut TEXT, encaisse INTEGER, created_at TEXT, montant_total NUMERIC)',
    'CREATE TABLE employes (id INTEGER PRIMARY KEY AUTOINCREMENT, statut TEXT)',
    'CREATE TABLE factures (id TEXT PRIMARY KEY, date_emission TEXT)',
    'CREATE TABLE lignes_facture (id INTEGER PRIMARY KEY AUTOINCREMENT, facture_id TEXT, source_module TEXT, montant TEXT)',
    // Les colonnes que lit `Accueil::articlesCritiques` — et elles seules.
    'CREATE TABLE articles (id TEXT PRIMARY KEY, libelle TEXT, unite_mesure TEXT, seuil_alerte NUMERIC)',
    'CREATE TABLE mouvements_stock (id INTEGER PRIMARY KEY AUTOINCREMENT, article_id TEXT, type_mouvement TEXT, quantite NUMERIC)',
    // « Depenses cumulees » et la serie mensuelle (26/10/2026) : les colonnes
    // que lisent `depensesCumulees()` et `chiffreAffairesEncaisse()`.
    'CREATE TABLE plan_comptable (id TEXT PRIMARY KEY, classe TEXT)',
    'CREATE TABLE ecritures_comptables (id INTEGER PRIMARY KEY AUTOINCREMENT, compte_id TEXT, statut TEXT, date_ecriture TEXT, debit NUMERIC, credit NUMERIC)',
    'CREATE TABLE paiements (id INTEGER PRIMARY KEY AUTOINCREMENT, date_paiement TEXT, montant NUMERIC)',
] as $ddl) {
    $pdo->exec($ddl);
}

$db = $capsule->getConnection();

foreach ($scenario['unites'] ?? [] as $u) {
    $db->table('unites_hebergement')->insert([
        'id' => $u['id'], 'statut' => $u['statut'],
        'numero' => $u['numero'] ?? $u['id'], 'categorie_id' => $u['categorie_id'] ?? null,
    ]);
}
foreach ($scenario['categories'] ?? [] as $c) {
    $db->table('categories_hebergement')->insert([
        'id' => $c['id'], 'libelle' => $c['libelle'], 'tarif_base' => $c['tarif_base'],
    ]);
}
foreach ($scenario['reservations'] ?? [] as $r) {
    $db->table('reservations')->insert([
        'id' => $r['id'], 'statut' => $r['statut'], 'date_arrivee' => $r['arrivee'],
        'date_depart' => $r['depart'], 'date_creation' => $r['creee_le'],
        'unite_id' => $r['unite_id'] ?? null,
    ]);
}
foreach ($scenario['ventes'] ?? [] as $v) {
    $db->table('ventes')->insert([
        'statut' => $v['statut'], 'encaisse' => $v['encaisse'] ? 1 : 0,
        'created_at' => $v['created_at'], 'montant_total' => $v['montant_total'],
    ]);
}
foreach ($scenario['employes'] ?? [] as $e) {
    $db->table('employes')->insert(['statut' => $e['statut']]);
}
foreach ($scenario['factures'] ?? [] as $f) {
    $db->table('factures')->insert(['id' => $f['id'], 'date_emission' => $f['date_emission']]);
    foreach ($f['lignes'] as $l) {
        $db->table('lignes_facture')->insert([
            'facture_id' => $f['id'], 'source_module' => $l['module'], 'montant' => $l['montant'],
        ]);
    }
}

foreach ($scenario['ecritures'] ?? [] as $i => $e) {
    $db->table('plan_comptable')->insertOrIgnore(['id' => 'c' . $e['classe'], 'classe' => (string) $e['classe']]);
    $db->table('ecritures_comptables')->insert([
        'compte_id' => 'c' . $e['classe'], 'statut' => $e['statut'],
        'date_ecriture' => $e['date'], 'debit' => $e['debit'], 'credit' => $e['credit'],
    ]);
}
foreach ($scenario['paiements'] ?? [] as $p) {
    $db->table('paiements')->insert(['date_paiement' => $p['date'], 'montant' => $p['montant']]);
}

$service = new TableauDeBordService();

// `variation()` est privee : on appelle la VRAIE methode, pas une copie.
$variation = new ReflectionMethod(TableauDeBordService::class, 'variation');

$modele = require $api . '/lang/fr/tableaux_de_bord.php';
$gabarit = (string) $modele['periode']['du_au'];

$decrire = static function (Periode $p) use ($gabarit): array {
    return [
        'debut' => $p->debut->format('Y-m-d H:i:s'),
        'fin' => $p->fin->format('Y-m-d H:i:s'),
        'jours' => $p->nombreJours(),
        // Le libelle est celui de `Periode::libelle()` : meme gabarit de langue,
        // memes bornes (`fin` moins un jour). `__()` n'existe pas hors application.
        'libelle' => strtr($gabarit, [
            ':debut' => $p->debut->format('d/m/Y'),
            ':fin' => $p->fin->subDay()->format('d/m/Y'),
        ]),
    ];
};

$mesures = static function (Periode $p) use ($service): array {
    return [
        'taux_occupation' => $service->tauxOccupation($p),
        'reservations_en_attente' => $service->reservationsEnAttente($p),
        'ventilation' => $service->ventilationParActivite($p),
        'depenses_cumulees' => $service->depensesCumulees($p),
    ];
};

$sortie = [];

foreach ($scenario['requetes'] ?? [] as $requete) {
    $reference = CarbonImmutable::parse($requete['reference']);
    if (isset($requete['calendaire'])) {
        // `resoudre()` lit l'horloge : on la pose, on appelle la VRAIE
        // methode, on la rend. `du`/`au` arrivent comme de la vue (chaines
        // `AAAA-MM-JJ`, ou vides quand le champ n'est pas rempli).
        CarbonImmutable::setTestNow($reference);
        $periode = Periode::resoudre(
            (string) $requete['calendaire'],
            $requete['du'] ?? null,
            $requete['au'] ?? null,
        );
        CarbonImmutable::setTestNow();
    } else {
        $periode = Periode::depuisCode($requete['code'], $reference);
    }
    $precedente = $periode->precedente();

    $courant = $mesures($periode);
    $avant = $mesures($precedente);

    $variations = [];
    foreach (['taux_occupation', 'reservations_en_attente'] as $cle) {
        $variations[$cle] = $variation->invoke(
            $service,
            (string) $courant[$cle],
            (string) $avant[$cle],
        );
    }

    $sortie[] = [
        'periode' => $decrire($periode),
        'precedente' => $decrire($precedente),
        'courant' => $courant,
        'avant' => $avant,
        'variations' => $variations,
    ];
}

// --- La serie mensuelle (26/10/2026) : la VRAIE methode, sur les memes tables.
$series = [];
foreach ($scenario['series'] ?? [] as $q) {
    $series[] = [
        'reference' => $q['reference'],
        'mois' => (int) $q['mois'],
        'points' => $service->serieMensuelle(
            (int) $q['mois'],
            CarbonImmutable::parse($q['reference']),
        ),
    ];
}

// --- « A traiter » : le compte des articles critiques du serveur -----------
//
// `Accueil::articlesCritiques()` est PRIVEE et vit sur le composant Livewire :
// on l'appelle par reflexion sur une instance construite SANS constructeur
// (aucun cycle de vie Livewire n'est necessaire a une requete de lecture).
$composant = (new ReflectionClass(Accueil::class))->newInstanceWithoutConstructor();
$critiques = new ReflectionMethod(Accueil::class, 'articlesCritiques');

$stocks = [];
foreach ($scenario['stocks'] ?? [] as $jeu) {
    $db->table('mouvements_stock')->delete();
    $db->table('articles')->delete();
    foreach ($jeu['articles'] as $a) {
        $db->table('articles')->insert([
            'id' => $a['id'], 'libelle' => $a['libelle'],
            'unite_mesure' => $a['unite_mesure'], 'seuil_alerte' => $a['seuil_alerte'],
        ]);
    }
    foreach ($jeu['mouvements'] as $m) {
        $db->table('mouvements_stock')->insert([
            'article_id' => $m['article_id'], 'type_mouvement' => $m['type_mouvement'],
            'quantite' => $m['quantite'],
        ]);
    }
    $liste = $critiques->invoke($composant);
    $stocks[] = [
        'nombre' => $liste->count(),
        'ids' => $liste->pluck('id')->values()->all(),
        // Ce que la modale « Articles sous le seuil d'alerte » ecrit, ligne par
        // ligne (`{{ $article->stock }}`, `{{ $article->seuil_alerte }}`).
        'stocks' => $liste->pluck('stock')->values()->all(),
        'seuils' => $liste->pluck('seuil_alerte')->values()->all(),
    ];
}

// --- La « Vue d'exploitation » (12/10/2026, lot 2) --------------------------
//
// `Accueil::recapDuJour()` et `Accueil::chambresDisponibles()` sont PRIVEES :
// appelees par reflexion, sur les memes tables. Un jour par demande.
$recap = new ReflectionMethod(Accueil::class, 'recapDuJour');
$chambres = new ReflectionMethod(Accueil::class, 'chambresDisponibles');
$disponibilites = new \App\Domain\Hebergement\Services\DisponibiliteService(
    new \App\Shared\Integrite\Services\VerificationChevauchementService(),
);

$journees = [];
foreach ($scenario['journees'] ?? [] as $jour) {
    $date = CarbonImmutable::parse($jour);
    $journees[] = [
        'jour' => $jour,
        'recap' => $recap->invoke($composant, $date),
        'chambres' => $chambres->invoke($composant, $disponibilites, $date)
            ->pluck('id')->values()->all(),
        // Le titre du recapitulatif : `translatedFormat('l j F')`, locale `fr`.
        'titre' => $date->translatedFormat('l j F'),
    ];
}

$accueil = require $api . '/lang/fr/accueil_pwa.php';

echo json_encode([
    'series' => $series,
    'resultats' => $sortie,
    'stocks' => $stocks,
    'journees' => $journees,
    // Le registre du SELECTEUR de la vue : codes (`Periode::CODES_CALENDAIRES`,
    // dans l'ordre), libelles (`accueil_pwa.periodes`, l'ordre des options) et
    // le defaut du composant (`Accueil::$filtrePeriode`, lu par reflexion —
    // jamais recopie).
    'selecteur' => [
        'codes' => Periode::CODES_CALENDAIRES,
        'libelles' => $accueil['periodes'],
        'defaut' => (new ReflectionProperty(Accueil::class, 'filtrePeriode'))->getDefaultValue(),
        'plafond_critiques' => Accueil::PLAFOND_CRITIQUES,
    ],
    // Libelles et notes des huit cartes, tels que la vue les lit
    // (`accueil_pwa.kpi.<cle>.libelle|note`).
    'kpi' => $accueil['kpi'],
    // La modale d'export du pilotage : titre et sous-titre que la vue passe au
    // partiel `modale-export` (`accueil.blade.php` l.1749), et le bouton.
    'export' => [
        'titre' => $accueil['export_titre'],
        'sous_titre' => $accueil['modale_rapport']['note'],
        'bouton' => (require $api . '/lang/fr/pwa.php')['export']['bouton'],
    ],
    'carbon_locale' => CarbonImmutable::getLocale(),
    'employes' => [
        'actifs' => $service->employesActifs(),
        'total' => $service->effectif()['total'],
    ],
    'libelles' => $modele['periode'],
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
