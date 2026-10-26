<?php

declare(strict_types=1);

/*
| Rejoue un scenario de VENTES par les VRAIS composants et services du serveur
| (12/10/2026, lot 6 de la reprise locale) : le composant Livewire `PosComptant`
| (le comptoir : panier vide, note de chambre refusee, caisse ouverte, puis
| `VenteService::enregistrer`) et `VenteService` lui-meme (le chemin de
| `PosHeberges` — la consommation d'un sejour est portee sur la note de chambre
| — et l'appel direct du service). Le test Flutter compare, champ a champ, ce que
| `PanierDao.cloturer` fait du MEME scenario : chaque refus (sa phrase) et chaque
| ligne de la piece comptable.
|
| Rien n'est modifie dans `tatacora-api` : le script l'appelle, il ne le touche
| pas. Il travaille sur `tatacora_test` (il REFUSE toute autre base), seme le
| referentiel comptable par le VRAI `ComptabiliteReferentielSeeder` et les roles
| par le VRAI `RolePermissionSeeder`, puis ANNULE tout (rollback). Si MySQL est
| injoignable, il echoue. Jamais deux processus PHP en parallele sur cette base.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15",
|     "catalogue": [{"ref":"biere","id":"<uuid>","module":"M5",
|                    "libelle":"Beninoise 65cl","prix":"1000"}, ...],
|     "ops": [ ... ] }
|   {"op":"parametre","cle":"tva_active","valeur":"true"|null}
|   {"op":"vente","canal":"comptoir"|"sejour"|"service","mode":"especes",
|    "session":true|false,                       (comptoir et service)
|    "remise":{"type":"pourcentage"|"montant","valeur":"10"},   (facultative)
|    "lignes":[{"ref":"biere","quantite":3}]}    (ou {"module":"M8","id":"..."})
|    La remise (21/10/2026) : au comptoir, par `appliquerRemise` du composant
|    (un refus y est une erreur de champ, rendue comme refus) ; au sejour et au
|    service, passee a `VenteService::enregistrer` (refus a l'encaissement).
|   {"op":"retirer_du_catalogue","ref":"biere"}
|   {"op":"retirer_centre","libelle":"Bar"}        (avant toute vente)
|   {"op":"horloge","date":"2040-01-02"}           (change le jour courant)
|   {"op":"statut_exercice","annee":2031,"statut":"en_cloture"}
|   {"op":"ventiler","taux":"18","convention":"ttc","montants":["1000.00"]}
|                                                  (le VRAI CalculTvaService)
|   {"op":"compter"}
|   {"op":"libelles"}
| Sortie (stdout, JSON) : { "resultats": [ ... un resultat par operation ... ] }
|   - une vente reussie : { "ok":true, "montant", "mode", "session", "piece":[..] }
|   - un refus          : { "refus": "<phrase du serveur>" }
|
| Usage : php tool/ventes/rejouer_ventes.php < scenario.json
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['ops'], $scenario['aujourdhui'], $scenario['catalogue'])) {
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
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Crm\Models\Client;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\VenteService;
use App\Models\User;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\ComptabiliteReferentielSeeder;
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

$resultats = [];

/** @var array<string, array{module: string, id: string}> $catalogue ref => entree */
$catalogue = [];

/**
 * La piece d'une vente, lignes triees de facon canonique. Le LIBELLE n'est pas
 * compare ligne a ligne : le serveur y met le numero `V-AAAA-NNNNN`, le poste
 * n'en a pas (ecart nomme) — le test verifie a part qu'il commence par
 * « Vente ».
 *
 * @return list<array<string, string>>
 */
$decrirePiece = static function (Vente $vente): array {
    $piece = [];

    $lignes = EcritureComptable::with(['journal', 'compte', 'centre'])
        ->where('libelle', 'Vente ' . $vente->numero)
        ->get();

    foreach ($lignes as $e) {
        $piece[] = [
            'numero_piece' => (string) $e->numero_piece,
            'journal' => $e->journal->code,
            'date' => $e->date_ecriture->format('Y-m-d'),
            'compte' => $e->compte->numero_compte,
            'centre' => $e->centre->libelle,
            'debit' => (string) $e->debit,
            'credit' => (string) $e->credit,
            'statut' => $e->statut,
        ];
    }

    // Tri sur une CLE TEXTE comparee octet a octet : `<=>` sur des tableaux
    // comparerait "8500.00" et "0.00" comme des nombres.
    usort($piece, static fn (array $a, array $b): int => strcmp(
        implode('|', [$a['compte'], $a['debit'], $a['credit']]),
        implode('|', [$b['compte'], $b['debit'], $b['credit']]),
    ));

    return $piece;
};

$decrireVente = static function (Vente $vente) use ($decrirePiece): array {
    $vente->refresh();

    return [
        'ok' => true,
        'montant' => (string) $vente->montant_total,
        'mode' => $vente->mode_paiement,
        'encaisse' => (bool) $vente->encaisse,
        'session' => $vente->session_id !== null,
        'piece' => $decrirePiece($vente),
    ];
};

/** Ouvre (ou ferme) la caisse du bar, comme le ferait `ouvrirCaisse` / une cloture. */
$poserSession = static function (bool $ouverte, User $u): void {
    $ouvertes = DB::table('sessions_caisse')
        ->where('point_vente', 'bar')
        ->whereNull('date_cloture');

    if ($ouverte) {
        if (! $ouvertes->exists()) {
            DB::table('sessions_caisse')->insert([
                'id' => (string) Str::uuid(),
                'point_vente' => 'bar',
                'utilisateur_ouverture_id' => $u->id,
                'date_ouverture' => now()->subMinutes(30),
                'montant_fond' => '10000.00',
                'date_cloture' => null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        return;
    }

    $ouvertes->update(['date_cloture' => now()]);
};

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    (new ComptabiliteReferentielSeeder())->run();

    // Gerant : C sur M4, M5 et M2 — le comptoir exige M5 puis M4 pour un plat.
    $gerant = User::create([
        'login' => 'gerant.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'gerant')->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    Auth::login($gerant);

    $client = Client::create([
        'id' => (string) Str::uuid(),
        'nom' => 'KORA',
        'prenom' => 'Aline',
        'telephone' => '97000000',
        'type_client' => 'particulier',
    ]);

    $stocks = $app->make(MouvementStockService::class);
    $bar = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
    $cuisine = PointStockage::create(['libelle' => 'Cuisine', 'type' => 'cuisine']);
    $menu = Menu::create(['libelle' => 'Carte principale', 'type' => 'local']);

    // Le catalogue, avec les identifiants du SCENARIO : le poste porte les
    // memes, et la phrase « L'article <id> est introuvable » doit etre
    // identique des deux cotes.
    foreach ($scenario['catalogue'] as $a) {
        if ($a['module'] === 'M5') {
            $article = Article::create([
                'libelle' => 'Article ' . $a['libelle'],
                'categorie' => 'test',
                'unite_mesure' => 'bouteille',
                'seuil_alerte' => '5.00',
                'seuil_reappro' => '10.00',
                'cout_moyen_pondere' => '500.0000',
            ]);
            CarteBoisson::create([
                'id' => $a['id'],
                'article_id' => $article->id,
                'libelle' => $a['libelle'],
                'categorie' => 'locale',
                'prix_vente' => $a['prix'],
                'unites_vendables_par_unite_stock' => '1.0000',
            ]);
            // Assez de stock pour qu'AUCUNE rupture ne parle a la place de la
            // piece : la sortie de stock n'est pas portee par le poste.
            $stocks->entree($article->id, $bar->id, '100000.00', 'Reception');
        } elseif ($a['module'] === 'M9') {
            // Tourisme (22/10/2026) : le prix est `circuits.prix`, aucun stock.
            Circuit::create([
                'id' => $a['id'],
                'nom' => $a['libelle'],
                'theme' => 'nature',
                'zone' => 'Atacora',
                'duree' => '1 jour',
                'prix' => $a['prix'],
                'capacite_max' => 12,
            ]);
        } elseif ($a['module'] === 'M8') {
            // Location (22/10/2026) : le prix est `vehicules.tarif_jour`.
            Vehicule::create([
                'id' => $a['id'],
                'categorie' => '4x4',
                'immatriculation' => $a['libelle'],
                'annee' => 2022,
                'transmission' => 'automatique',
                'capacite' => 5,
                'tarif_jour' => $a['prix'],
                'statut' => 'disponible',
            ]);
        } else {
            $article = Article::create([
                'libelle' => 'Denree ' . $a['libelle'],
                'categorie' => 'test',
                'unite_mesure' => 'kg',
                'seuil_alerte' => '5.00',
                'seuil_reappro' => '10.00',
                'cout_moyen_pondere' => '500.0000',
            ]);
            $recette = Recette::create(['libelle' => $a['libelle'], 'cout_matiere_calcule' => '0.00']);
            $recette->ingredients()->attach([$article->id => ['quantite_unitaire' => '0.250']]);
            Plat::create([
                'id' => $a['id'],
                'menu_id' => $menu->id,
                'recette_id' => $recette->id,
                'libelle' => $a['libelle'],
                'prix_vente' => $a['prix'],
            ]);
            $stocks->entree($article->id, $cuisine->id, '100000.00', 'Reception');
        }

        $catalogue[$a['ref']] = ['module' => $a['module'], 'id' => $a['id']];
    }

    $departVentes = Vente::count();
    $departEcritures = EcritureComptable::count();
    $ventes = $app->make(VenteService::class);

    /** Les lignes d'une operation, au format attendu par `VenteService`. */
    $lignesDe = static function (array $lignes) use (&$catalogue): array {
        $r = [];
        foreach ($lignes as $l) {
            if (isset($l['ref'])) {
                $r[] = [
                    'module' => $catalogue[$l['ref']]['module'],
                    'reference_id' => $catalogue[$l['ref']]['id'],
                    'quantite' => $l['quantite'],
                ];
            } else {
                $r[] = [
                    'module' => $l['module'],
                    'reference_id' => $l['id'],
                    'quantite' => $l['quantite'],
                ];
            }
        }

        return $r;
    };

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'parametre':
                    DB::table('parametres_systeme')->where('cle', $op['cle'])->delete();
                    if ($op['valeur'] !== null) {
                        DB::table('parametres_systeme')->insert([
                            'id' => (string) Str::uuid(),
                            'cle' => $op['cle'],
                            'valeur' => $op['valeur'],
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]);
                    }
                    $resultats[] = ['ok' => true];
                    break;

                case 'retirer_du_catalogue':
                    $entree = $catalogue[$op['ref']];
                    if ($entree['module'] === 'M5') {
                        CarteBoisson::where('id', $entree['id'])->delete();
                    } elseif ($entree['module'] === 'M9') {
                        Circuit::where('id', $entree['id'])->delete();
                    } elseif ($entree['module'] === 'M8') {
                        Vehicule::where('id', $entree['id'])->delete();
                    } else {
                        Plat::where('id', $entree['id'])->delete();
                    }
                    $resultats[] = ['ok' => true];
                    break;

                case 'vente':
                    $mode = (string) $op['mode'];
                    $lignes = $lignesDe($op['lignes']);

                    // Un article RETIRE du catalogue entre l'ajout et
                    // l'encaissement : seul l'appel direct du service peut le
                    // rejouer (le composant resout l'article des l'ajout).
                    foreach ($op['retirer'] ?? [] as $ref) {
                        $entree = $catalogue[$ref];
                        CarteBoisson::where('id', $entree['id'])->delete();
                    }

                    if ($op['canal'] === 'comptoir') {
                        // Le VRAI composant : panier vide, note de chambre
                        // refusee, caisse, puis le service.
                        $poserSession((bool) $op['session'], $gerant);

                        $c = Livewire::actingAs($gerant)->test(PosComptant::class)
                            ->set('comptoirChoisi', true);

                        foreach ($lignes as $l) {
                            for ($i = 0; $i < $l['quantite']; $i++) {
                                $c->call('ajouterAuPanier', $l['module'], $l['reference_id']);
                            }
                        }

                        // La remise : posee sur le PANIER avant l'encaissement,
                        // comme l'operateur le fait ; un refus de la formule est
                        // une erreur du champ « Valeur de la remise ».
                        if (isset($op['remise'])) {
                            $c->set('remiseType', (string) $op['remise']['type'])
                                ->set('remiseValeur', (string) $op['remise']['valeur'])
                                ->call('appliquerRemise');

                            if ($c->errors()->has('remiseValeur')) {
                                $resultats[] = ['refus' => (string) $c->errors()->first('remiseValeur')];
                                $c->call('abandonnerPanier');
                                break;
                            }
                        }

                        $c->set('modePaiement', $mode)->call('encaisser');

                        $venteId = $c->get('derniereVenteId');

                        if ($venteId === null) {
                            $resultats[] = ['refus' => (string) $c->get('toastMessage')];
                            // Un panier refuse reste OUVERT cote serveur (« le
                            // panier est conserve ») : on l'abandonne pour que
                            // l'operation suivante reparte d'un comptoir propre.
                            $c->call('abandonnerPanier');
                            break;
                        }

                        $resultats[] = $decrireVente(Vente::findOrFail($venteId));
                        break;
                    }

                    if ($op['canal'] === 'sejour') {
                        // `PosHeberges::cloturerEtFacturer` : la vente est
                        // TOUJOURS portee sur la note de chambre, sans caisse.
                        $vente = $ventes->enregistrer([
                            'point_vente' => 'Hébergement',
                            'client_id' => $client->id,
                            'mode_paiement' => 'note_chambre',
                            'remise_type' => (string) ($op['remise']['type'] ?? 'aucune'),
                            'remise_valeur' => (string) ($op['remise']['valeur'] ?? '0.00'),
                            'utilisateur_id' => $gerant->id,
                            'lignes' => $lignes,
                        ]);
                        $resultats[] = $decrireVente($vente);
                        break;
                    }

                    // `service` : l'appel direct du service, avec le mode
                    // donne et sans passer par un composant.
                    $poserSession((bool) $op['session'], $gerant);
                    $vente = $ventes->enregistrer([
                        'point_vente' => 'Bar',
                        'session_id' => ($op['session'] ?? false)
                            ? DB::table('sessions_caisse')->where('point_vente', 'bar')->whereNull('date_cloture')->value('id')
                            : null,
                        'mode_paiement' => $mode,
                        'remise_type' => (string) ($op['remise']['type'] ?? 'aucune'),
                        'remise_valeur' => (string) ($op['remise']['valeur'] ?? '0.00'),
                        'utilisateur_id' => $gerant->id,
                        'lignes' => $lignes,
                    ]);
                    $resultats[] = $decrireVente($vente);
                    break;

                case 'retirer_centre':
                    CentreCout::where('libelle', $op['libelle'])->delete();
                    $resultats[] = ['ok' => true];
                    break;

                case 'horloge':
                    Carbon::setTestNow($op['date'] . ' 10:00:00');
                    $resultats[] = ['ok' => true];
                    break;

                case 'statut_exercice':
                    ExerciceComptable::where('annee', (int) $op['annee'])
                        ->firstOrFail()
                        ->forceFill(['statut' => $op['statut']])
                        ->save();
                    $resultats[] = ['ok' => true];
                    break;

                case 'ventiler':
                    // Le VRAI `CalculTvaService`, sur les parametres POSES par
                    // l'operation : `tva_active` a vrai, le taux et la
                    // convention donnes. Un montant par ligne de resultat.
                    foreach (['tva_active' => 'true', 'taux_tva' => $op['taux'], 'convention_prix' => $op['convention']] as $cle => $valeur) {
                        DB::table('parametres_systeme')->where('cle', $cle)->delete();
                        DB::table('parametres_systeme')->insert([
                            'id' => (string) Str::uuid(),
                            'cle' => $cle,
                            'valeur' => $valeur,
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]);
                    }
                    $tva = $app->make(CalculTvaService::class);
                    $lignes = [];
                    foreach ($op['montants'] as $montant) {
                        $v = $tva->ventiler($montant);
                        $lignes[] = ['ht' => $v['ht'], 'tva' => $v['tva'], 'ttc' => $v['ttc']];
                    }
                    $resultats[] = ['ok' => true, 'ventilations' => $lignes];
                    break;

                case 'compter':
                    $resultats[] = ['ok' => true, 'compte' => [
                        'ventes' => Vente::count() - $departVentes,
                        'ecritures' => EcritureComptable::count() - $departEcritures,
                    ]];
                    break;

                case 'libelles':
                    // Les phrases, lues de `lang/fr` par le VRAI traducteur
                    // (jamais recopiees a la main cote Dart).
                    $resultats[] = ['ok' => true, 'libelles' => [
                        'panier_vide' => __('ventes.panier_vide'),
                        'refus_panier_vide' => __('pos_pwa.comptant.refus_panier_vide'),
                        'refus_sans_caisse' => __('pos_pwa.comptant.refus_sans_caisse'),
                        'refus_note_chambre_comptoir' => __('pos_pwa.comptant.refus_note_chambre_comptoir'),
                        'mode_paiement_inconnu' => __('ventes.mode_paiement_inconnu', ['mode' => ':mode']),
                        'reference_inconnue' => __('ventes.reference_inconnue', ['reference' => ':reference']),
                        'module_non_encaissable' => __('ventes.module_non_encaissable', ['module' => ':module']),
                        'compte_produit_absent' => __('ventes.compte_produit_absent', ['module' => ':module']),
                        'convention_inconnue' => __('comptabilite.convention_inconnue', ['convention' => ':convention', 'cle' => ':cle']),
                        'taux_absent' => __('comptabilite.taux_absent', ['cle' => ':cle']),
                        'modules' => VenteService::MODULES,
                        'modules_encaissables' => VenteService::MODULES_ENCAISSABLES,
                        'journal' => VenteService::JOURNAL,
                        'comptes_produit' => VenteService::COMPTES_PRODUIT,
                        'comptes_tva' => VenteService::COMPTES_TVA,
                        'centres_par_module' => VenteService::CENTRES_PAR_MODULE,
                        'contreparties' => VenteService::CONTREPARTIES_TRESORERIE,
                        'compte_clients' => VenteService::COMPTE_CLIENTS,
                        'remise_valeur_invalide' => __('ventes.remise_valeur_invalide'),
                        'remise_pourcentage_hors_bornes' => __('ventes.remise_pourcentage_hors_bornes'),
                        'remise_superieure_au_total' => __('ventes.remise_superieure_au_total'),
                        'remise_ligne_facture' => __('ventes.remise_ligne_facture'),
                        'remise_appliquee' => __('pos_pwa.commun.remise_appliquee', ['brut' => ':brut']),
                    ]];
                    break;

                default:
                    fwrite(STDERR, "Operation inconnue : {$op['op']}\n");
                    exit(5);
            }
        } catch (Throwable $e) {
            $resultats[] = ['refus' => $e->getMessage()];
        }
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode(['resultats' => $resultats], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
