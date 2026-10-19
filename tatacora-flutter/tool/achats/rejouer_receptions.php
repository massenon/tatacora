<?php

declare(strict_types=1);

/*
| TEST DE CARACTERISATION de la RECEPTION du serveur et de sa VALORISATION
| (12/10/2026, lot 7 de la reprise locale, D132). Ce script rejoue, par les
| VRAIS services et le VRAI composant du serveur, un scenario que le test
| Flutter joue ensuite sur le poste, pour repondre par EXECUTION a la question
| posee : « la reception M7 valorise-t-elle l'entree de stock ? »
|
|   - `ReceptionService::receptionner` (bon, conformite, statut de la commande,
|     entrees de stock) ;
|   - `MouvementStockService::entree` (la seule porte de la valorisation :
|     `integrerEntree` + `prix_achat`, quand un cout est passe) ;
|   - `ConsultationStockService::etatConsolide` (stock, CMP, prix d'achat,
|     valeur de chaque article — l'etat M6) ;
|   - `TableauDeBordService::valeurStock` (la carte « Valeur du stock » de M11) ;
|   - `Approvisionnement::enregistrerReception` (le composant, son message de
|     succes).
|
| Rien n'est modifie dans `tatacora-api` : le script l'appelle, il ne le touche
| pas. Il travaille sur `tatacora_test` (il REFUSE toute autre base), seme les
| roles par le VRAI seeder, puis ANNULE tout (rollback).
|
| Entree (stdin, JSON) : { "aujourdhui": "2026-10-13", "ops": [ ... ] }
|   {"op":"utilisateur","ref":"g","role":"gerant"}
|   {"op":"tolerance","valeur":"5"}
|   {"op":"point","ref":"p1","libelle":"Magasin"}
|   {"op":"article","ref":"a1","libelle":"Sucre","seuil":"4"}
|   {"op":"entree","article":"a1","point":"p1","quantite":"2","cout":"500",
|    "user":"g"}                       (cout absent ou null : entree NON valorisee)
|   {"op":"fournisseur","ref":"f1","nom":"Grand Marche SARL"}
|   {"op":"commande","ref":"c1","fournisseur":"f1","user":"g",
|    "date":"2026-10-01","statut":"envoyee",
|    "lignes":[{"article":"a1","quantite":"4","prix":"1000"}]}
|   {"op":"reception","commande":"c1","user":"g","point":"p1",
|    "quantites":{"a1":"4"}}
|   {"op":"reception_pwa","commande":"c1","user":"g","point":"p1",
|    "quantites":{"a1":"4"}}
|   {"op":"etat_stock"}  {"op":"libelles"}
| Sortie (stdout, JSON) : { "resultats": [ ... un par operation ... ] }
|
| Usage : php tool/achats/rejouer_receptions.php < scenario.json
| Ne JAMAIS en lancer deux en parallele : ils partagent `tatacora_test`.
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['ops'], $scenario['aujourdhui'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

putenv('DB_DATABASE=' . BASE_AUTORISEE);
$_ENV['DB_DATABASE'] = BASE_AUTORISEE;
$_SERVER['DB_DATABASE'] = BASE_AUTORISEE;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Services\CommandeAchatService;
use App\Domain\Achats\Services\ReceptionService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ConsultationStockService;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use App\Models\User;
use App\Pwa\Livewire\Achats\Approvisionnement;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . BASE_AUTORISEE . " \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow($scenario['aujourdhui'] . ' 10:00:00');

/** @var array<string, User> $utilisateurs */
$utilisateurs = [];
/** @var array<string, PointStockage> $points */
$points = [];
/** @var array<string, Article> $articles */
$articles = [];
/** @var array<string, Fournisseur> $fournisseurs */
$fournisseurs = [];
/** @var array<string, CommandeAchat> $commandes */
$commandes = [];
$resultats = [];

$refDe = static function (array $table, string $id): ?string {
    foreach ($table as $ref => $objet) {
        if ((string) $objet->id === $id) {
            return (string) $ref;
        }
    }

    return null;
};

$m = static fn (mixed $v, int $d = 2): string => bcadd((string) $v, '0', $d);

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'utilisateur':
                    $utilisateurs[$op['ref']] = User::create([
                        'login' => $op['ref'] . '.' . Str::random(6),
                        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
                        'role_id' => Role::where('libelle', $op['role'])->firstOrFail()->id,
                        'statut' => 'actif',
                    ]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'tolerance':
                    ParametreSysteme::query()->updateOrCreate(
                        ['cle' => ReceptionService::CLE_TOLERANCE],
                        ['valeur' => $op['valeur']],
                    );
                    $resultats[] = ['ok' => true];
                    break;

                case 'point':
                    $points[$op['ref']] = PointStockage::create(['libelle' => $op['libelle'], 'type' => 'magasin']);
                    $resultats[] = ['ok' => true];
                    break;

                case 'article':
                    $articles[$op['ref']] = Article::create([
                        'libelle' => $op['libelle'],
                        'categorie' => 'Denrées',
                        'unite_mesure' => 'kg',
                        'seuil_alerte' => $op['seuil'] ?? '4',
                        'seuil_reappro' => '10.00',
                        'cout_moyen_pondere' => '0.0000',
                    ]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'entree':
                    Auth::setUser($utilisateurs[$op['user']]);
                    $app->make(MouvementStockService::class)->entree(
                        $articles[$op['article']]->id,
                        $points[$op['point']]->id,
                        $op['quantite'],
                        'Entrée de test',
                        $op['cout'] ?? null,
                    );
                    $resultats[] = ['ok' => true];
                    break;

                case 'fournisseur':
                    $fournisseurs[$op['ref']] = Fournisseur::create(['raison_sociale' => $op['nom']]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'commande':
                    Auth::setUser($utilisateurs[$op['user']]);
                    $lignes = [];
                    foreach ($op['lignes'] as $l) {
                        $lignes[] = [
                            'article_id' => $articles[$l['article']]->id,
                            'quantite_commandee' => $l['quantite'],
                            'prix_unitaire' => $l['prix'],
                        ];
                    }
                    $commandes[$op['ref']] = $app->make(CommandeAchatService::class)->creer([
                        'fournisseur_id' => $fournisseurs[$op['fournisseur']]->id,
                        'date_commande' => $op['date'],
                        'statut' => $op['statut'] ?? 'brouillon',
                        'lignes' => $lignes,
                    ]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'reception':
                    Auth::setUser($utilisateurs[$op['user']]);
                    $quantites = [];
                    foreach ($op['quantites'] as $ref => $q) {
                        $quantites[$articles[$ref]->id] = $q;
                    }
                    $commande = $commandes[$op['commande']]->refresh();
                    $connus = MouvementStock::query()->pluck('id')->all();
                    $bon = $app->make(ReceptionService::class)
                        ->receptionner($commande, $quantites, $points[$op['point']]->id);
                    // Les mouvements ECRITS par cette reception : leur motif porte
                    // les identifiants de la commande et du bon (ramenes a des
                    // jetons), leur type et leur quantite.
                    $ecrits = [];
                    foreach (MouvementStock::query()->whereNotIn('id', $connus)->get() as $mv) {
                        $ecrits[] = [
                            'article' => $refDe($articles, (string) $mv->article_id),
                            'type' => $mv->type_mouvement,
                            'quantite' => $m($mv->quantite),
                            'motif' => str_replace(
                                [(string) $commande->id, (string) $bon->id],
                                ['COMMANDE', 'BON'],
                                (string) $mv->motif,
                            ),
                        ];
                    }
                    usort($ecrits, static fn (array $a, array $b): int => strcmp((string) $a['article'], (string) $b['article']));
                    $resultats[] = [
                        'conformite' => $bon->conformite,
                        'statut_commande' => $commande->refresh()->statut,
                        'mouvements' => $ecrits,
                    ];
                    break;

                case 'reception_pwa':
                    $u = $utilisateurs[$op['user']];
                    $c = Livewire::actingAs($u)->test(Approvisionnement::class)
                        ->call('ouvrirFormulaireReception', $commandes[$op['commande']]->id)
                        ->set('rPointId', $points[$op['point']]->id);
                    foreach ($op['quantites'] as $ref => $q) {
                        $c->set('rQuantites.' . $articles[$ref]->id, $q);
                    }
                    $c->call('enregistrerReception');
                    $html = (string) $c->html();
                    $succes = null;
                    if (preg_match('/background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">\s*(.*?)\s*<\/div>/s', $html, $mm) === 1) {
                        $succes = html_entity_decode(trim($mm[1]), ENT_QUOTES, 'UTF-8');
                    }
                    $erreurs = [];
                    foreach ($c->errors()->toArray() as $champ => $messages) {
                        $erreurs[$champ] = array_values($messages);
                    }
                    $resultats[] = [
                        'succes' => $succes,
                        'erreurs' => $erreurs,
                        'modale_fermee' => $c->get('etatFormulaire') === null,
                    ];
                    break;

                case 'etat_stock':
                    Auth::setUser(array_values($utilisateurs)[0]);
                    $etat = $app->make(ConsultationStockService::class)->etatConsolide();
                    $lignes = [];
                    foreach ($etat->lignes as $l) {
                        $ref = $refDe($articles, (string) $l->article->id);
                        $a = Article::query()->find($l->article->id);
                        $lignes[(string) $ref] = [
                            'stock' => $m($l->stock),
                            'cmp' => $m($a->cout_moyen_pondere, 4),
                            'prix_achat' => $a->prix_achat === null ? null : $m($a->prix_achat, 4),
                            'valeur' => $m($l->valeur),
                        ];
                    }
                    $resultats[] = [
                        'articles' => $lignes,
                        'valeur_totale' => $m($etat->valeurTotale),
                        'valeur_stock_m11' => $m($app->make(TableauDeBordService::class)->valeurStock()),
                    ];
                    break;

                case 'bons':
                    $resultats[] = [
                        'nb_bons' => BonReception::query()->count(),
                        'nb_mouvements' => MouvementStock::query()->count(),
                    ];
                    break;

                case 'libelles':
                    $resultats[] = ['libelles' => [
                        'reception_enregistree' => __('achats_pwa.appro.reception_enregistree', ['conformite' => ':conformite']),
                        'form_avertissement_double' => __('achats_pwa.appro.form_avertissement_double'),
                        'motif_reception' => __('achats.motif_reception', ['commande' => ':commande', 'bon' => ':bon']),
                        'receptions_detail' => __('pwa.appro.receptions_detail'),
                    ]];
                    break;

                default:
                    fwrite(STDERR, "Operation inconnue : {$op['op']}\n");
                    exit(5);
            }
        } catch (Throwable $e) {
            $resultats[] = [
                'refus' => (new ReflectionClass($e))->getShortName(),
                'message' => $e->getMessage(),
            ];
        }
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
