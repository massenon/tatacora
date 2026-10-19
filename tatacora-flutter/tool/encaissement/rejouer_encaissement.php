<?php

declare(strict_types=1);

/*
| TEST DE CARACTERISATION de l'ENCAISSEMENT DE FACTURE du serveur (12/10/2026,
| lot 5 de la reprise locale). Ce script rejoue, par les VRAIS services et le
| VRAI composant du serveur, un scenario que le test Flutter joue ensuite sur le
| poste, pour comparer CHAMP A CHAMP :
|
|   - `EncaissementFactureService::encaisser` / `annuler` (refus dans l'ordre,
|     phrases, paiement ecrit, piece comptable, session choisie) ;
|   - `ClientsCreances::enregistrerRecouvrement` (droit M3 puis M2, validation
|     Laravel des trois proprietes, message de succes) ;
|   - `Facture::SQL_RESTE_DU`, `SoldeClientService` (registre, totaux,
|     encaisseDepuis) ;
|   - `TableauDeBordService` (CA encaisse, tresorerie de caisse, factures
|     impayees) ;
|   - `EtatCreancesClients` (l'etat M14) ;
|   - `PosComptant` (vente encaissee dans une session, theorique et ecart de
|     cloture).
|
| Rien n'est modifie dans `tatacora-api` : le script l'appelle, il ne le touche
| pas. Il travaille sur `tatacora_test` (il REFUSE toute autre base), seme les
| roles et le referentiel comptable par les VRAIS seeders, puis ANNULE tout
| (rollback). Si MySQL est injoignable, il echoue.
|
| Entree (stdin, JSON) : { "aujourdhui": "2026-10-12", "ops": [ ... ] }
|   {"op":"utilisateur","ref":"g","role":"gerant"}
|   {"op":"client","ref":"k","nom":"KORA","prenom":"Jean"}
|   {"op":"reservation","ref":"r1","client":"k","acompte":"20000"}
|   {"op":"facture","ref":"f1","client":"k","ttc":"50000","date":"2026-10-01",
|    "reservation":"r1"|null,"statut":"certifiee"}
|   {"op":"avoir","facture":"f1","montant":"10000"}
|   {"op":"session","user":"g","point":"bar","fond":"10000","ouverte":true,
|    "il_y_a_minutes":30}
|   {"op":"encaisser","facture":"f1","montant":"30000.00","mode":"especes","user":"g"}
|   {"op":"recouvrer","user":"g","client":"k","facture":"f1","montant":"30000",
|    "mode":"especes"}
|   {"op":"annuler","paiement":0,"motif":"Doublon","user":"g"}
|   {"op":"droits_recouvrement","role":"gerant"}
|   {"op":"catalogue_bar","prix":"1000"}
|   {"op":"vente_pos","user":"g","mode":"especes"}
|   {"op":"cloturer","user":"g","constate":"11000"}
|   {"op":"theorique_propose","user":"g"}
|   {"op":"etat"}  {"op":"soldes"}  {"op":"kpis","periode":"mois"}
|   {"op":"etat_creances"}  {"op":"libelles"}
| Sortie (stdout, JSON) : { "resultats": [ ... un par operation ... ] }
|
| Usage : php tool/encaissement/rejouer_encaissement.php < scenario.json
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

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Crm\Etats\EtatCreancesClients;
use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\SoldeClientService;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\Paiement;
use App\Domain\Facturation\Services\EncaissementFactureService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use App\Domain\Ventes\Models\Vente;
use App\Models\User;
use App\Pwa\Livewire\Crm\ClientsCreances;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\TablesSalleSeeder;
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
/** @var array<string, Client> $clients */
$clients = [];
/** @var array<string, string> $reservations ref => id */
$reservations = [];
/** @var array<string, Facture> $factures */
$factures = [];
/** @var list<Paiement> $paiements dans l'ordre de creation */
$paiements = [];
$resultats = [];
$boisson = null;
/** @var array<string, true> $paiementsConnus identifiants deja vus : on ne se fie JAMAIS a un tri par date (meme seconde) */
$paiementsConnus = [];
/** @var array<string, true> $ventesConnues */
$ventesConnues = [];
$serieUnite = 0;

$refDe = static function (array $table, string $id): ?string {
    foreach ($table as $ref => $objet) {
        $cle = is_object($objet) ? (string) $objet->id : (string) $objet;
        if ($cle === $id) {
            return (string) $ref;
        }
    }

    return null;
};

/**
 * Un message d'erreur de validation Livewire, tel qu'il est porte.
 *
 * @return array<string, list<string>>
 */
$erreursDe = static function ($composant): array {
    $erreurs = [];
    foreach ($composant->errors()->toArray() as $champ => $messages) {
        $erreurs[$champ] = array_values($messages);
    }

    return $erreurs;
};

/** Le message de succes de `ClientsCreances` (bandeau `pwa-succes`). */
$succesCreances = static function ($composant): ?string {
    $html = (string) $composant->html();

    if (preg_match('/background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">\s*(.*?)\s*<\/div>/s', $html, $m) !== 1) {
        return null;
    }

    return html_entity_decode(trim($m[1]), ENT_QUOTES, 'UTF-8');
};

/**
 * Le refus RBAC (`exigerEcriture` -> `abort(403)`), tel que le harnais le rend.
 * Le harnais Livewire ne sait pas relire une page 403 : il leve « Invalid
 * Livewire snapshot structure ». On le RECOUPE avec la trace que le serveur
 * ecrit lui-meme (`acces_refuse_rbac`, module concerne) : le refus est reconnu
 * si, et seulement si, cette trace existe pour CET utilisateur, et elle dit QUEL
 * module a refuse.
 *
 * @return array<string, mixed>|null
 */
$refusRbac = static function (Throwable $e, User $u): ?array {
    if (! str_contains($e->getMessage(), 'Invalid Livewire snapshot')) {
        return null;
    }

    $trace = JournalSecurite::query()
        ->where('utilisateur_id', $u->id)
        ->where('type_evenement', 'acces_refuse_rbac')
        ->orderByDesc('id')
        ->first();

    return $trace === null ? null : ['statut' => 403, 'module_refuse' => $trace->module_concerne];
};

/**
 * Livewire rend `abort(403)` comme un STATUT de reponse, pas comme une
 * exception : on le lit sur la reponse du test.
 */
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

/** Le module que le serveur a trace comme refuse pour CET utilisateur. */
$moduleRefuse = static function (User $u): ?string {
    return JournalSecurite::query()
        ->where('utilisateur_id', $u->id)
        ->where('type_evenement', 'acces_refuse_rbac')
        ->orderByDesc('id')
        ->first()?->module_concerne;
};

/** Normalise un montant DECIMAL en chaine a deux decimales. */
$m2 = static fn (mixed $v): string => bcadd((string) $v, '0', 2);

/**
 * Un paiement tel que le serveur l'a ecrit, lisible sans identifiant.
 *
 * @return array<string, mixed>
 */
$decrirePaiement = static function (Paiement $p) use (&$utilisateurs, &$factures, $refDe, $m2): array {
    $p->refresh();
    $session = SessionCaisse::find($p->session_id);

    return [
        'facture' => $refDe($factures, (string) $p->facture_id),
        'session_point' => $session?->point_vente,
        'mode' => $p->mode_paiement,
        'montant' => $m2($p->montant),
        'statut' => $p->statut,
        'motif_annulation' => $p->motif_annulation,
        'annule_par_renseigne' => $p->annule_par_id !== null,
        'date_annulation_renseignee' => $p->date_annulation !== null,
        'par' => $refDe($utilisateurs, (string) $p->utilisateur_creation_id),
    ];
};

/**
 * Les lignes comptables dont le libelle commence par « Encaissement » ou qui
 * contre-passent l'une d'elles, sous forme canonique (triees).
 *
 * @return list<array<string, mixed>>
 */
$decrireEcritures = static function (): array {
    $lignes = [];

    foreach (EcritureComptable::with(['journal', 'compte', 'centre'])->orderBy('created_at')->orderBy('id')->get() as $e) {
        $lignes[] = [
            'journal' => $e->journal->code,
            'compte' => $e->compte->numero_compte,
            'centre' => $e->centre->libelle,
            'libelle' => $e->libelle,
            'debit' => bcadd((string) $e->debit, '0', 2),
            'credit' => bcadd((string) $e->credit, '0', 2),
            'statut' => $e->statut,
            'numero_piece_renseigne' => $e->numero_piece !== null,
            'numero_piece' => $e->numero_piece,
            'date' => $e->date_ecriture->format('Y-m-d'),
            'contrepasse' => $e->ecriture_contrepassee_id !== null,
        ];
    }

    return $lignes;
};

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    (new ComptabiliteReferentielSeeder())->run();
    (new TablesSalleSeeder())->run();

    // Le compte de depart : la base de test peut porter des lignes etrangeres.
    $depart = [
        'paiements' => Paiement::count(),
        'ecritures' => EcritureComptable::count(),
        'ventes' => Vente::count(),
    ];

    foreach (Paiement::pluck('id') as $id) {
        $paiementsConnus[(string) $id] = true;
    }
    foreach (Vente::pluck('id') as $id) {
        $ventesConnues[(string) $id] = true;
    }

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
                    $resultats[] = ['ok' => true, 'niveaux' => [
                        'M2' => $utilisateurs[$op['ref']]->niveauSurModule('M2'),
                        'M3' => $utilisateurs[$op['ref']]->niveauSurModule('M3'),
                        'M5' => $utilisateurs[$op['ref']]->niveauSurModule('M5'),
                    ]];
                    break;

                case 'client':
                    $clients[$op['ref']] = Client::create([
                        'nom' => $op['nom'],
                        'prenom' => $op['prenom'] ?? null,
                        'telephone' => $op['telephone'] ?? '97111111',
                        'type_client' => 'particulier',
                    ]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'reservation':
                    $serieUnite++;
                    $categorieId = (string) Str::uuid();
                    DB::table('categories_hebergement')->insert([
                        'id' => $categorieId, 'libelle' => 'Bungalow', 'capacite_max' => 2,
                        'tarif_base' => '28000.00', 'created_at' => now(), 'updated_at' => now(),
                    ]);
                    $uniteId = (string) Str::uuid();
                    DB::table('unites_hebergement')->insert([
                        'id' => $uniteId, 'categorie_id' => $categorieId, 'numero' => 'BNG-' . $serieUnite,
                        'statut' => 'libre', 'created_at' => now(), 'updated_at' => now(),
                    ]);
                    $reservationId = (string) Str::uuid();
                    DB::table('reservations')->insert([
                        'id' => $reservationId,
                        'client_id' => $clients[$op['client']]->id,
                        'unite_id' => $uniteId,
                        'date_arrivee' => '2026-10-20',
                        'date_depart' => '2026-10-22',
                        'statut' => 'confirmee',
                        'acompte' => $op['acompte'],
                        'created_at' => now(), 'updated_at' => now(),
                    ]);
                    $reservations[$op['ref']] = $reservationId;
                    $resultats[] = ['ok' => true];
                    break;

                case 'facture':
                    $f = Facture::create([
                        'numero_mecef' => $op['numero'] ?? ('MECEF-DEMO-' . strtoupper($op['ref'])),
                        'client_id' => $clients[$op['client']]->id,
                        'date_emission' => $op['date'],
                        'montant_ht' => $op['ttc'],
                        'montant_tva' => '0.00',
                        'montant_ttc' => $op['ttc'],
                        'statut' => $op['statut'] ?? 'certifiee',
                    ]);
                    DB::table('lignes_facture')->insert([
                        'id' => (string) Str::uuid(),
                        'facture_id' => $f->id,
                        'source_module' => isset($op['reservation']) ? 'M1' : 'M5',
                        'source_id' => isset($op['reservation']) ? $reservations[$op['reservation']] : (string) Str::uuid(),
                        'libelle' => 'Prestation',
                        'quantite' => '1.00',
                        'prix_unitaire' => $op['ttc'],
                        'montant' => $op['ttc'],
                        'created_at' => now(), 'updated_at' => now(),
                    ]);
                    $factures[$op['ref']] = $f;
                    $resultats[] = ['ok' => true];
                    break;

                case 'avoir':
                    Avoir::create([
                        'facture_id' => $factures[$op['facture']]->id,
                        'motif' => 'Erreur de saisie',
                        'montant' => $op['montant'],
                        'date_emission' => $scenario['aujourdhui'],
                        'utilisateur_validation_id' => array_values($utilisateurs)[0]->id,
                    ]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'renommer_facture':
                    // Insertion DIRECTE : le numero d'une facture figee ne se
                    // change par aucun geste. C'est le moyen de fabriquer une piece
                    // comptable que le libelle ne retrouve plus (PA-52).
                    DB::table('factures')->where('id', $factures[$op['facture']]->id)
                        ->update(['numero_mecef' => 'MECEF-DEMO-' . strtoupper($op['numero'])]);
                    $factures[$op['facture']]->refresh();
                    $resultats[] = ['ok' => true];
                    break;

                case 'session':
                    DB::table('sessions_caisse')->insert([
                        'id' => (string) Str::uuid(),
                        'point_vente' => $op['point'],
                        'utilisateur_ouverture_id' => $utilisateurs[$op['user']]->id,
                        'date_ouverture' => now()->subMinutes((int) ($op['il_y_a_minutes'] ?? 30)),
                        'montant_fond' => $op['fond'],
                        'date_cloture' => ($op['ouverte'] ?? true) ? null : now(),
                        'created_at' => now(), 'updated_at' => now(),
                    ]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'encaisser':
                    Auth::setUser($utilisateurs[$op['user']]);
                    $facture = $factures[$op['facture']]->refresh();
                    $paiement = $app->make(EncaissementFactureService::class)
                        ->encaisser($facture, $op['montant'], $op['mode']);
                    $paiements[] = $paiement;
                    $paiementsConnus[(string) $paiement->id] = true;
                    $resultats[] = ['ok' => true, 'paiement' => $decrirePaiement($paiement),
                        'reste_du' => $factures[$op['facture']]->refresh()->resteDu()];
                    break;

                case 'recouvrer':
                    $u = $utilisateurs[$op['user']];
                    try {
                        $c = Livewire::actingAs($u)->test(ClientsCreances::class)
                            ->call('ouvrirRecouvrement', $clients[$op['client']]->id)
                            ->set('recouvrementFactureId', $op['facture'] === '' ? '' : ($factures[$op['facture']]->id ?? $op['facture']))
                            ->set('recouvrementMontant', $op['montant'])
                            ->set('recouvrementMode', $op['mode'])
                            ->call('enregistrerRecouvrement');
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
                    $nouveau = Paiement::query()->whereNotIn('id', array_keys($paiementsConnus))->first();
                    $ajoute = $nouveau !== null;
                    if ($ajoute) {
                        $paiements[] = $nouveau;
                        $paiementsConnus[(string) $nouveau->id] = true;
                    }
                    $resultats[] = [
                        'erreurs' => $erreursDe($c),
                        'succes' => $succesCreances($c),
                        'paiement' => $ajoute && $nouveau !== null ? $decrirePaiement($nouveau) : null,
                        'modale_fermee' => $c->get('etatFormulaire') === null,
                    ];
                    break;

                case 'ouvrir_recouvrement':
                    // Le geste « Recouvrement » d'une LIGNE : ce que la modale propose
                    // a l'ouverture (pieces impayees du client, la premiere
                    // selectionnee, son reste en montant, le mode espece), ou la
                    // phrase « aucune creance ».
                    $u = $utilisateurs[$op['user']];
                    $c = Livewire::actingAs($u)->test(ClientsCreances::class)
                        ->call('ouvrirRecouvrement', $clients[$op['client']]->id);
                    $listees = [];
                    foreach ((array) $c->get('recouvrementFactures') as $ligne) {
                        $listees[] = [
                            'facture' => $refDe($factures, (string) $ligne['id']),
                            'libelle_renseigne' => $ligne['libelle'] !== '',
                            'reste' => $ligne['reste'],
                        ];
                    }
                    $resultats[] = [
                        'ouverture' => true,
                        'erreurs' => $erreursDe($c),
                        'modale_ouverte' => $c->get('etatFormulaire') === 'recouvrement',
                        'factures' => $listees,
                        'facture_selectionnee' => $refDe($factures, (string) $c->get('recouvrementFactureId')),
                        'montant' => $c->get('recouvrementMontant'),
                        'mode' => $c->get('recouvrementMode'),
                    ];
                    break;

                case 'droits_recouvrement':
                    // Le geste « Recouvrement » joue par chaque ROLE : quel module
                    // refuse (M3 d'abord, puis M2), ou aucun.
                    $u = User::create([
                        'login' => 'droit.' . $op['role'] . '.' . Str::random(6),
                        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
                        'role_id' => Role::where('libelle', $op['role'])->firstOrFail()->id,
                        'statut' => 'actif',
                    ]);
                    $client = $clients[$op['client']];
                    try {
                        $c = Livewire::actingAs($u)->test(ClientsCreances::class)
                            ->call('ouvrirRecouvrement', $client->id);
                        $statut = $statutHttp($c);
                        $refus = ['statut' => $statut, 'module_refuse' => $statut === 403 ? $moduleRefuse($u) : null];
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                    }
                    $resultats[] = $refus + ['niveaux' => [
                        'M2' => $u->niveauSurModule('M2'),
                        'M3' => $u->niveauSurModule('M3'),
                    ]];
                    break;

                case 'annuler':
                    Auth::setUser($utilisateurs[$op['user']]);
                    $cible = $paiements[$op['paiement']];
                    $annule = $app->make(EncaissementFactureService::class)->annuler($cible->refresh(), $op['motif']);
                    $resultats[] = ['ok' => true, 'paiement' => $decrirePaiement($annule),
                        'reste_du' => $cible->facture->refresh()->resteDu()];
                    break;

                case 'catalogue_bar':
                    $bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
                    $article = Article::create([
                        'libelle' => 'Biere 65cl', 'categorie' => 'test', 'unite_mesure' => 'bouteille',
                        'seuil_alerte' => '5.00', 'seuil_reappro' => '10.00', 'cout_moyen_pondere' => '500.0000',
                    ]);
                    $boisson = CarteBoisson::create([
                        'article_id' => $article->id, 'libelle' => 'Beninoise 65cl', 'categorie' => 'locale',
                        'prix_vente' => $op['prix'], 'unites_vendables_par_unite_stock' => '1.0000',
                    ]);
                    Auth::setUser(array_values($utilisateurs)[0]);
                    $app->make(MouvementStockService::class)->entree($article->id, $bar->id, '500.00', 'Reception');
                    $resultats[] = ['ok' => true];
                    break;

                case 'vente_pos':
                    $u = $utilisateurs[$op['user']];
                    try {
                        $c = Livewire::actingAs($u)->test(PosComptant::class)
                            ->set('comptoirChoisi', true)
                            ->call('ajouterAuPanier', 'M5', $boisson->id)
                            ->set('modePaiement', $op['mode'])
                            ->call('encaisser');
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                        $resultats[] = $refus;
                        break;
                    }
                    $vente = Vente::query()->whereNotIn('id', array_keys($ventesConnues))->first();
                    $creee = $vente !== null;
                    if ($creee) {
                        $ventesConnues[(string) $vente->id] = true;
                    }
                    $session = $creee && $vente?->session_id !== null ? SessionCaisse::find($vente->session_id) : null;
                    $resultats[] = [
                        'toast_type' => $c->get('toastType'),
                        'toast' => $c->get('toastMessage'),
                        'vente_creee' => $creee,
                        'session_point' => $session?->point_vente,
                        'session_renseignee' => $creee && $vente?->session_id !== null,
                        'montant' => $creee ? $m2($vente->montant_total) : null,
                        'mode' => $creee ? $vente->mode_paiement : null,
                    ];
                    break;

                case 'theorique_propose':
                    $u = $utilisateurs[$op['user']];
                    $c = Livewire::actingAs($u)->test(PosComptant::class)
                        ->call('ouvrirFormulaireClotureCaisse');
                    $resultats[] = ['propose' => $c->get('montantConstateSaisi')];
                    break;

                case 'cloturer':
                    $u = $utilisateurs[$op['user']];
                    $c = Livewire::actingAs($u)->test(PosComptant::class)
                        ->call('ouvrirFormulaireClotureCaisse')
                        ->set('montantConstateSaisi', $op['constate'])
                        ->call('cloturerCaisse');
                    $html = (string) $c->html();
                    $succes = null;
                    if (preg_match('/bg-emerald-600 text-white text-\[13px\] font-medium no-print">\s*(.*?)\s*<\/div>/s', $html, $m) === 1) {
                        $succes = html_entity_decode(trim($m[1]), ENT_QUOTES, 'UTF-8');
                    }
                    $derniere = SessionCaisse::query()->orderByDesc('date_ouverture')->first();
                    $resultats[] = [
                        'erreurs' => $erreursDe($c),
                        'succes' => $succes,
                        'theorique' => $derniere?->montant_theorique === null ? null : $m2($derniere->montant_theorique),
                        'constate' => $derniere?->montant_constate === null ? null : $m2($derniere->montant_constate),
                    ];
                    break;

                case 'etat':
                    $lignes = [];
                    foreach (Paiement::query()->orderBy('created_at')->orderBy('id')->get() as $p) {
                        $lignes[] = $decrirePaiement($p);
                    }
                    $resultats[] = [
                        'paiements' => $lignes,
                        'ecritures' => $decrireEcritures(),
                        'nb_paiements' => Paiement::count() - $depart['paiements'],
                        'nb_ecritures' => EcritureComptable::count() - $depart['ecritures'],
                    ];
                    break;

                case 'soldes':
                    $service = $app->make(SoldeClientService::class);
                    $registre = [];
                    foreach ($service->registre(null, $op['etat'] ?? null) as $l) {
                        $registre[] = [
                            'nom' => trim($l->nom . ' ' . ($l->prenom ?? '')),
                            'solde' => $l->solde,
                            'pieces' => $l->pieces,
                            'anciennete' => $l->anciennete,
                        ];
                    }
                    $resultats[] = [
                        'registre' => $registre,
                        'totaux' => $service->totaux(),
                        'encaisse_30j' => $service->encaisseDepuis(now()->subDays(30)),
                        'resteDu' => array_map(
                            static fn (Facture $f): string => $f->refresh()->resteDu(),
                            $factures,
                        ),
                    ];
                    break;

                case 'kpis':
                    // La periode du SELECTEUR de la vue d'accueil
                    // (`Accueil::periode()` -> `Periode::resoudre`), calendaire,
                    // sous l'horloge figee du scenario (`setTestNow`) — plus les
                    // codes « a date » de l'API (D296).
                    $periode = Periode::resoudre($op['periode'], $op['du'] ?? null, $op['au'] ?? null);
                    $k = $app->make(TableauDeBordService::class)->indicateurs($periode);
                    $resultats[] = ['kpis' => [
                        'chiffre_affaires_encaisse' => $k['chiffre_affaires_encaisse'],
                        'tresorerie_caisse' => $k['tresorerie_caisse'],
                        'factures_impayees' => $k['factures_impayees'],
                    ]];
                    break;

                case 'dette_agee':
                    // La balance âgée du serveur : methodes PRIVEES de l'ecran, lues
                    // par reflexion — le script appelle le code du serveur, il ne le
                    // recopie pas.
                    $ecran = new ClientsCreances();
                    $dette = new ReflectionMethod(ClientsCreances::class, 'detteAgeeParClient');
                    $dette->setAccessible(true);
                    $kpi = new ReflectionMethod(ClientsCreances::class, 'kpiParTranche');
                    $kpi->setAccessible(true);
                    $globale = $dette->invoke($ecran, null);
                    $affichee = isset($op['terme']) ? $dette->invoke($ecran, $op['terme']) : $globale;
                    $lignesDette = [];
                    foreach ($affichee as $l) {
                        $lignesDette[] = [
                            'nom' => $l['nom'],
                            'tranches' => $l['tranches'],
                            'total' => $l['total'],
                        ];
                    }
                    $resultats[] = [
                        'dette_agee' => $lignesDette,
                        'kpi_douteux' => $kpi->invoke($ecran, $globale, 'plus_90'),
                        'kpi_recent' => $kpi->invoke($ecran, $globale, '0_30'),
                        'tranches' => array_keys(ClientsCreances::TRANCHES),
                    ];
                    break;

                case 'anciennete_accueil':
                    // Le graphique « Creances par anciennete » de l'accueil
                    // (`Accueil::creancesParAnciennete`, methode PRIVEE lue par
                    // reflexion, 13/10/2026) : ses bornes ne sont PAS celles
                    // de la balance de l'ecran Clients & creances.
                    $accueil = (new ReflectionClass(\App\Pwa\Livewire\Accueil::class))->newInstanceWithoutConstructor();
                    $anciennete = new ReflectionMethod(\App\Pwa\Livewire\Accueil::class, 'creancesParAnciennete');
                    $anciennete->setAccessible(true);
                    $resultats[] = ['anciennete' => $anciennete->invoke($accueil)];
                    break;

                case 'etat_creances':
                    $etat = $app->make(EtatCreancesClients::class);
                    $r = $etat->calculer($op['filtres'] ?? []);
                    $resultats[] = [
                        'libelle' => $etat->libelle([]),
                        'module' => $etat->module(),
                        'kpis' => $r->kpis,
                        'entetes' => $r->entetes,
                        'lignes' => $r->lignes,
                    ];
                    break;

                case 'libelles':
                    $resultats[] = ['libelles' => [
                        'non_figee' => __('facturation.encaissement_facture_non_figee'),
                        'mode_inconnu' => __('facturation.encaissement_mode_inconnu', ['mode' => ':mode']),
                        'montant_invalide' => __('facturation.encaissement_montant_invalide'),
                        'superieur_au_reste' => __('facturation.encaissement_superieur_au_reste', ['reste' => ':reste']),
                        'caisse_fermee' => __('facturation.encaissement_caisse_fermee'),
                        'deja_annule' => __('facturation.paiement_deja_annule'),
                        'motif_requis' => __('facturation.paiement_motif_requis'),
                        'piece_introuvable' => __('facturation.paiement_piece_introuvable', ['libelle' => ':libelle']),
                        'module_refuse' => __('auth.module_refuse'),
                        'aucune_creance' => __('pwa.clients.recouvrement_aucune_creance'),
                        'avertissement' => __('pwa.clients.recouvrement_avertissement'),
                        'succes' => __('pwa.clients.recouvrement_succes', ['montant' => ':montant', 'client' => ':client']),
                        'titre_modale' => __('pwa.clients.modale_recouvrement_titre'),
                        'champ_piece' => __('pwa.clients.champ_piece_reglee'),
                        'champ_du' => __('pwa.clients.champ_du'),
                        'champ_montant' => __('pwa.clients.champ_montant_recu'),
                        'champ_mode' => __('pwa.clients.champ_mode'),
                        'champ_enregistrer' => __('pwa.clients.champ_enregistrer_recouvrement'),
                        'action_recouvrement' => __('pwa.clients.action_recouvrement'),
                        'col_client' => __('pwa.clients.col_client'),
                        'recouvrements_titre' => __('pwa.clients.recouvrements_titre', ['nombre' => ':nombre']),
                        'recouvrements_vide' => __('pwa.clients.recouvrements_vide'),
                        'mode_especes' => __('pwa.clients.mode_especes'),
                        'mode_mobile_money' => __('pwa.clients.mode_mobile_money'),
                        'mode_carte' => __('pwa.clients.mode_carte'),
                        'mode_virement' => __('pwa.clients.mode_virement'),
                        'encaisser_sans_caisse' => __('pos_pwa.comptant.encaisser_sans_caisse'),
                        'refus_sans_caisse' => __('pos_pwa.comptant.refus_sans_caisse'),
                        'validation_gt' => __('validation.gt.numeric'),
                        'validation_required' => __('validation.required', ['attribute' => ':attribute']),
                        'validation_numeric' => __('validation.numeric', ['attribute' => ':attribute']),
                        'validation_in' => __('validation.in', ['attribute' => ':attribute']),
                        'validation_exists' => __('validation.exists', ['attribute' => ':attribute']),
                        'tresorerie_par_mode' => EncaissementFactureService::TRESORERIE_PAR_MODE,
                        'tresoreries' => \App\Domain\Depenses\Services\DepenseService::TRESORERIES,
                        'modes' => Paiement::MODES,
                        'tableau_dates' => ['plafond' => ClientsCreances::PLAFOND],
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
