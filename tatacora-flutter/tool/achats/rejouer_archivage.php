<?php

declare(strict_types=1);

/*
| TEST DE CARACTERISATION de l'ARCHIVAGE D'UN FOURNISSEUR du serveur
| (12/10/2026, lot 7 de la reprise locale, D63) et de la BASCULE
| `activation_suppression`. Ce script rejoue, par les VRAIS services et le VRAI
| composant du serveur, un scenario que le test Flutter joue ensuite sur le
| poste, pour comparer CHAMP A CHAMP :
|
|   - `Achats::confirmerArchivageFournisseur` (droit d'archiver, lot compose,
|     etat BLOQUE / PARTIEL / NOMINAL de la modale, motifs de verrou),
|     `archiverFournisseurs` (refus d'un service par element, succes),
|     `restaurerFournisseur` (droit d'ecriture seulement) ;
|   - `ReferentielFournisseurService::engagements` (le verrou) ;
|   - `AutoriseArchivage::peutArchiver` (via la valeur `peutArchiver` que la
|     vue recoit) et `OptionsSystemeService::suppressionActive` ;
|   - le selecteur de fournisseurs de `Approvisionnement` (actifs seulement).
|
| Rien n'est modifie dans `tatacora-api` : le script l'appelle, il ne le touche
| pas. Il travaille sur `tatacora_test` (il REFUSE toute autre base), seme les
| roles par le VRAI seeder, puis ANNULE tout (rollback).
|
| Entree (stdin, JSON) : { "aujourdhui": "2026-10-13", "ops": [ ... ] }
|   {"op":"utilisateur","ref":"g","role":"gerant"}
|   {"op":"fournisseur","ref":"f1","nom":"Grand Marche SARL"}
|   {"op":"article","ref":"a1","libelle":"Sucre"}
|   {"op":"commande","ref":"c1","fournisseur":"f1","user":"g",
|    "date":"2026-10-01","statut":"envoyee",
|    "lignes":[{"article":"a1","quantite":"4","prix":"1000"}]}
|   {"op":"statut","commande":"c1","statut":"receptionnee"}
|   {"op":"parametre","valeur":"true"}        (valeur null : la cle est ABSENTE)
|   {"op":"bascule"}
|   {"op":"peut_archiver","role":"gerant"}
|   {"op":"archiver","user":"g","fournisseurs":["f1"],"confirmer":true,
|    "mode":"ligne"|"lot"}
|   {"op":"restaurer","user":"g","fournisseur":"f1"}
|   {"op":"liste","user":"g"}   {"op":"selecteur","user":"g"}
|   {"op":"libelles"}
| Sortie (stdout, JSON) : { "resultats": [ ... un par operation ... ] }
|
| Usage : php tool/achats/rejouer_archivage.php < scenario.json
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

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Services\CommandeAchatService;
use App\Domain\Stocks\Models\Article;
use App\Models\User;
use App\Pwa\Livewire\Achats\Achats;
use App\Pwa\Livewire\Achats\Approvisionnement;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\OptionsSystemeService;
use App\Shared\Rbac\Models\JournalSecurite;
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
/** @var array<string, Fournisseur> $fournisseurs */
$fournisseurs = [];
/** @var array<string, Article> $articles */
$articles = [];
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

/**
 * Le message de succes (bandeau `pwa-succes`) tel que la vue le RENDUE : le
 * flash de session n'est pas relisible depuis le harnais, la page, si.
 */
$succesDe = static function ($composant): ?string {
    $html = (string) $composant->html();

    if (preg_match('/background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">\s*(.*?)\s*<\/div>/s', $html, $m) !== 1) {
        return null;
    }

    return html_entity_decode(trim($m[1]), ENT_QUOTES, 'UTF-8');
};

$statutHttp = static function ($composant): int {
    foreach ([401, 403] as $code) {
        try {
            $composant->assertStatus($code);

            return $code;
        } catch (Throwable) {
            // pas ce statut
        }
    }

    return 200;
};

$moduleRefuse = static function (User $u): ?string {
    return JournalSecurite::query()
        ->where('utilisateur_id', $u->id)
        ->where('type_evenement', 'acces_refuse_rbac')
        ->orderByDesc('id')
        ->first()?->module_concerne;
};

/** @return array<string, mixed>|null */
$refusRbac = static function (Throwable $e, User $u) use ($moduleRefuse): ?array {
    if (! str_contains($e->getMessage(), 'Invalid Livewire snapshot')) {
        return null;
    }

    $module = $moduleRefuse($u);

    return $module === null ? null : ['statut' => 403, 'module_refuse' => $module];
};

/**
 * Cree un utilisateur du role donne : un utilisateur par ROLE, jamais partage.
 */
$creerUtilisateur = static function (string $ref, string $role) use (&$utilisateurs): User {
    return $utilisateurs[$ref] = User::create([
        'login' => $ref . '.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
        'statut' => 'actif',
    ]);
};

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'utilisateur':
                    $u = $creerUtilisateur($op['ref'], $op['role']);
                    $resultats[] = ['ok' => true, 'niveau_m7' => $u->niveauSurModule('M7')];
                    break;

                case 'fournisseur':
                    $fournisseurs[$op['ref']] = Fournisseur::create(['raison_sociale' => $op['nom']]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'article':
                    $articles[$op['ref']] = Article::create([
                        'libelle' => $op['libelle'],
                        'categorie' => 'Denrées',
                        'unite_mesure' => 'kg',
                        'seuil_alerte' => '4.00',
                        'seuil_reappro' => '10.00',
                        'cout_moyen_pondere' => '0.0000',
                    ]);
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

                case 'statut':
                    DB::table('commandes_achat')->where('id', $commandes[$op['commande']]->id)
                        ->update(['statut' => $op['statut']]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'parametre':
                    // La valeur est posee BRUTE (la forme stockee n'est pas
                    // l'affaire de ce script) ; `null` retire la cle.
                    if ($op['valeur'] === null) {
                        ParametreSysteme::query()->where('cle', OptionsSystemeService::CLE_SUPPRESSION)->delete();
                    } else {
                        ParametreSysteme::query()->updateOrCreate(
                            ['cle' => OptionsSystemeService::CLE_SUPPRESSION],
                            ['valeur' => $op['valeur']],
                        );
                    }
                    $resultats[] = ['ok' => true];
                    break;

                case 'bascule':
                    $resultats[] = [
                        'suppression_active' => $app->make(OptionsSystemeService::class)->suppressionActive(),
                    ];
                    break;

                case 'peut_archiver':
                    $u = $creerUtilisateur('role.' . $op['role'], $op['role']);
                    $c = Livewire::actingAs($u)->test(Achats::class);
                    $resultats[] = [
                        'role' => $op['role'],
                        'niveau_m7' => $u->niveauSurModule('M7'),
                        'peutArchiver' => $c->viewData('peutArchiver'),
                        'peutEcrire' => $c->viewData('peutEcrire'),
                    ];
                    break;

                case 'archiver':
                    $u = $utilisateurs[$op['user']];
                    $ids = array_map(static fn (string $r): string => (string) $fournisseurs[$r]->id, $op['fournisseurs']);
                    try {
                        $c = Livewire::actingAs($u)->test(Achats::class);
                        if (($op['mode'] ?? 'ligne') === 'lot') {
                            $c->set('selection', $ids)->call('confirmerArchivageFournisseur');
                        } else {
                            $c->call('confirmerArchivageFournisseur', $ids[0]);
                        }
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                        $resultats[] = $refus;
                        break;
                    }
                    if ($statutHttp($c) === 403) {
                        $resultats[] = ['statut' => 403, 'module_refuse' => $moduleRefuse($u)];
                        break;
                    }
                    $aArchiver = array_map(
                        static fn (string $id): ?string => $refDe($fournisseurs, $id),
                        (array) $c->get('fournisseursAArchiver'),
                    );
                    $etat = [
                        'modale' => $c->get('etatFormulaire'),
                        'a_archiver' => $aArchiver,
                        'verrous' => array_values((array) $c->get('verrousArchivage')),
                        'bloque' => $c->get('archivageBloque'),
                        'conserves' => $c->get('conservesArchivage'),
                        'libelle' => $c->get('libelleArchivage'),
                    ];
                    if (! ($op['confirmer'] ?? false) || $c->get('etatFormulaire') !== 'archivage') {
                        $resultats[] = ['ouverture' => $etat];
                        break;
                    }
                    // Un engagement peut naitre ENTRE l'ouverture et le clic : le
                    // scenario peut le simuler (`engager_entre_les_deux`).
                    foreach ((array) ($op['engager_entre_les_deux'] ?? []) as $ref) {
                        DB::table('commandes_achat')->insert([
                            'id' => (string) Str::uuid(),
                            'fournisseur_id' => $fournisseurs[$ref]->id,
                            'date_commande' => $scenario['aujourdhui'],
                            'statut' => 'envoyee',
                            'utilisateur_id' => $u->id,
                            'created_at' => now(), 'updated_at' => now(),
                        ]);
                    }
                    $c->call('archiverFournisseurs');
                    $erreurs = [];
                    foreach ($c->errors()->toArray() as $champ => $messages) {
                        $erreurs[$champ] = array_values($messages);
                    }
                    $resultats[] = [
                        'ouverture' => $etat,
                        'succes' => $succesDe($c),
                        'erreurs' => $erreurs,
                        'modale_fermee' => $c->get('etatFormulaire') === null,
                        'selection_videe' => $c->get('selection') === [],
                    ];
                    break;

                case 'restaurer':
                    $u = $utilisateurs[$op['user']];
                    try {
                        $c = Livewire::actingAs($u)->test(Achats::class)
                            ->call('restaurerFournisseur', $fournisseurs[$op['fournisseur']]->id);
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                        $resultats[] = $refus;
                        break;
                    }
                    if ($statutHttp($c) === 403) {
                        $resultats[] = ['statut' => 403, 'module_refuse' => $moduleRefuse($u)];
                        break;
                    }
                    $resultats[] = ['succes' => $succesDe($c)];
                    break;

                case 'liste':
                    $u = $utilisateurs[$op['user']];
                    $c = Livewire::actingAs($u)->test(Achats::class);
                    $html = (string) $c->html();
                    $texte = static function (string $fragment): string {
                        $s = trim((string) preg_replace('/\s+/u', ' ', strip_tags($fragment)));

                        return str_replace("\u{00A0}", ' ', html_entity_decode($s, ENT_QUOTES, 'UTF-8'));
                    };
                    $lignes = [];
                    if (preg_match_all('/<tr wire:key="fournisseur-([^"]+)"[^>]*>(.*?)<\/tr>/s', $html, $rows, PREG_SET_ORDER)) {
                        foreach ($rows as $r) {
                            preg_match_all('/<td\b[^>]*>(.*?)<\/td>/s', $r[2], $cells);
                            $cellules = array_map($texte, $cells[1]);
                            $lignes[] = [
                                'ref' => $refDe($fournisseurs, $r[1]),
                                'fournisseur' => $cellules[1] ?? null,
                                'actions' => $cellules[6] ?? null,
                            ];
                        }
                    }
                    $resultats[] = [
                        'lignes' => $lignes,
                        'peutArchiver' => $c->viewData('peutArchiver'),
                        'peutEcrire' => $c->viewData('peutEcrire'),
                    ];
                    break;

                case 'barre_lot':
                    // Le lien « Supprimer » de la BARRE de selection : present ou
                    // non selon le droit d'archiver, lu du HTML rendu.
                    $u = $utilisateurs[$op['user']];
                    $ids = array_map(static fn (string $r): string => (string) $fournisseurs[$r]->id, $op['fournisseurs']);
                    $c = Livewire::actingAs($u)->test(Achats::class)->set('selection', $ids);
                    $html = (string) $c->html();
                    $resultats[] = [
                        'lien_supprimer' => (bool) preg_match('/wire:click="confirmerArchivageFournisseur"/', $html),
                    ];
                    break;

                case 'selecteur':
                    $u = $utilisateurs[$op['user']];
                    $c = Livewire::actingAs($u)->test(Approvisionnement::class);
                    $resultats[] = [
                        'fournisseurs' => $c->viewData('fournisseurs')
                            ->map(static fn ($f) => $refDe($fournisseurs, (string) $f->id))
                            ->values()->all(),
                    ];
                    break;

                case 'etat':
                    $etat = [];
                    foreach ($fournisseurs as $ref => $f) {
                        $etat[$ref] = (bool) $f->refresh()->actif;
                    }
                    $resultats[] = ['actifs' => $etat, 'nb_commandes' => CommandeAchat::query()->count()];
                    break;

                case 'libelles':
                    $resultats[] = ['libelles' => [
                        'bouton_ligne' => __('achats_pwa.archivage.bouton_ligne'),
                        'bouton_lot' => __('achats_pwa.archivage.bouton_lot'),
                        'bouton_restaurer' => __('achats_pwa.archivage.bouton_restaurer'),
                        'badge' => __('achats_pwa.archivage.badge'),
                        'verrou' => __('achats_pwa.archivage.verrou', ['nombre' => ':nombre']),
                        'succes_un' => trans_choice('achats_pwa.archivage.succes', 1, ['nombre' => 1]),
                        'succes_deux' => trans_choice('achats_pwa.archivage.succes', 2, ['nombre' => 2]),
                        'succes_trois' => trans_choice('achats_pwa.archivage.succes', 3, ['nombre' => 3]),
                        'restaure' => __('achats_pwa.archivage.restaure', ['nom' => ':nom']),
                        'refus_bascule' => __('pwa.archivage.refus_bascule'),
                        'defauts' => OptionsSystemeService::DEFAUTS,
                        'roles_administration' => User::ROLES_ADMINISTRATION,
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
