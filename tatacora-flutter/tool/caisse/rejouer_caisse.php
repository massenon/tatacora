<?php

declare(strict_types=1);

/*
| TEST DE CARACTERISATION des sessions de caisse du serveur (12/10/2026,
| lot 4 de la reprise locale) : l'ouverture et la cloture vivent dans le
| composant Livewire `PosComptant` (`ouvrirCaisse`, `cloturerCaisse`), pas dans
| un service de domaine. Ce script rejoue donc le VRAI composant — ses regles
| de validation, ses garde-fous, ses messages `lang/fr/pos_pwa.php`, son calcul
| du theorique — sur MySQL, pour que le test Flutter compare, champ a champ,
| ce que `SessionsCaisseDao` fait du MEME scenario.
|
| Rien n'est modifie dans `tatacora-api` : le script l'appelle, il ne le touche
| pas. Il travaille sur `tatacora_test` (il REFUSE toute autre base), seme les
| roles par le VRAI `RolePermissionSeeder`, puis ANNULE tout (rollback). Si
| MySQL est injoignable, il echoue.
|
| Entree (stdin, JSON) : { "ops": [ ... ] }
|   {"op":"utilisateur","ref":"g","role":"gerant"}
|   {"op":"ouvrir","user":"g","fond":"25000"}
|   {"op":"cloturer","user":"g","constate":"11000"}
|   {"op":"semer_session","user":"g","point_vente":"reception","fond":"20000",
|    "ouverte":true|false}               (insertion directe, comme le seeder)
|   {"op":"semer_vente","mode":"especes","statut":"validee","montant":"1000",
|    "point_session":"bar"}              (fixture : une vente rattachee a la
|                                         session OUVERTE du point donne)
|   {"op":"session_pour_encaissement"}   (le point de la session que
|                                         `EncaissementFactureService` choisirait)
|   {"op":"indicateur","user":"g"}       (le VRAI `IndicateurCaisse`)
|   {"op":"tresorerie_caisse"}           (le VRAI KPI `tresorerieCaisse`)
|   {"op":"etat"}                        (les sessions, sans les horodatages)
|   {"op":"theorique_propose","user":"g"}  (le champ de la modale de cloture)
|   {"op":"libelles"}
| Sortie (stdout, JSON) : { "resultats": [ ... un par operation ... ] }
|
| Usage : php tool/caisse/rejouer_caisse.php < scenario.json
*/

const BASE_AUTORISEE = 'tatacora_test';

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['ops'])) {
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

use App\Domain\Caisse\Models\SessionCaisse;
use App\Models\User;
use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Pwa\Support\IndicateurCaisse;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} " . BASE_AUTORISEE . " \u{bb}.\n");
    exit(1);
}

/** @var array<string, User> $utilisateurs */
$utilisateurs = [];
$resultats = [];
$serie = 0;

/**
 * Un message d'erreur de validation, tel que Livewire le porte (ou null).
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

/**
 * Le message de succes flashe par `terminerFormulaire()`, tel que l'ECRAN le
 * rend : la session du harnais Livewire n'est pas celle de l'appelant, mais le
 * toast de `comptant.blade.php` (l.62-67) est dans le HTML re-rendu apres le
 * geste — c'est aussi ce que voit le caissier.
 */
$succesFlashe = static function ($composant): ?string {
    $html = (string) $composant->html();

    if (preg_match('/bg-emerald-600 text-white text-\[13px\] font-medium no-print">\s*(.*?)\s*<\/div>/s', $html, $m) !== 1) {
        return null;
    }

    return html_entity_decode(trim($m[1]), ENT_QUOTES, 'UTF-8');
};

$statutHttp = static function ($composant): int {
    // Livewire rend `abort(403)` comme un STATUT de reponse, pas comme une
    // exception (leçon de PosPwaTest) : on le lit sur la reponse du test.
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

/**
 * Le refus RBAC (`exigerEcriture` -> `abort(403)`), tel que le harnais le rend.
 *
 * Le harnais Livewire ne sait pas relire une page 403 : il leve « Invalid
 * Livewire snapshot structure ». On ne s'en sert pas comme preuve, on la
 * RECOUPE avec ce que le serveur trace lui-meme (`tracerRefusEcriture` ecrit
 * une ligne `acces_refuse_rbac` au journal de securite, module M5) : le refus
 * est reconnu si, et seulement si, cette trace existe pour CET utilisateur.
 *
 * @return array<string, mixed>|null null : l'exception n'etait pas un refus
 */
$refusRbac = static function (Throwable $e, User $u): ?array {
    if (! str_contains($e->getMessage(), 'Invalid Livewire snapshot')) {
        return null;
    }

    $trace = JournalSecurite::query()
        ->where('utilisateur_id', $u->id)
        ->where('type_evenement', 'acces_refuse_rbac')
        ->where('module_concerne', 'M5')
        ->exists();

    return $trace ? ['statut' => 403, 'trace_refus_m5' => true] : null;
};

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
                    // Le droit M5 vient de la MATRICE du serveur : le test du poste le
                    // lit ici, il ne le recopie pas.
                    $resultats[] = ['ok' => true, 'm5' => $utilisateurs[$op['ref']]->niveauSurModule('M5')];
                    break;

                case 'ouvrir':
                    $u = $utilisateurs[$op['user']];
                    try {
                        $c = Livewire::actingAs($u)->test(PosComptant::class)
                            ->call('ouvrirFormulaireOuvertureCaisse')
                            ->set('fondCaisseSaisi', $op['fond'])
                            ->call('ouvrirCaisse');
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                        $resultats[] = $refus;
                        break;
                    }
                    $statut = $statutHttp($c);
                    $resultats[] = [
                        'statut' => $statut,
                        'erreurs' => $erreursDe($c),
                        'succes' => $succesFlashe($c),
                        'modale_fermee' => $c->get('etatFormulaire') === null,
                        'ouvreur_ok' => SessionCaisse::query()
                            ->where('utilisateur_ouverture_id', $u->id)
                            ->exists(),
                    ];
                    break;

                case 'theorique_propose':
                    $u = $utilisateurs[$op['user']];
                    try {
                        $c = Livewire::actingAs($u)->test(PosComptant::class)
                            ->call('ouvrirFormulaireClotureCaisse');
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                        $resultats[] = $refus;
                        break;
                    }
                    $resultats[] = [
                        'statut' => $statutHttp($c),
                        'propose' => $c->get('montantConstateSaisi'),
                    ];
                    break;

                case 'cloturer':
                    $u = $utilisateurs[$op['user']];
                    try {
                        $c = Livewire::actingAs($u)->test(PosComptant::class)
                            ->call('ouvrirFormulaireClotureCaisse')
                            ->set('montantConstateSaisi', $op['constate'])
                            ->call('cloturerCaisse');
                    } catch (Throwable $e) {
                        $refus = $refusRbac($e, $u);
                        if ($refus === null) {
                            throw $e;
                        }
                        $resultats[] = $refus;
                        break;
                    }
                    $resultats[] = [
                        'statut' => $statutHttp($c),
                        'erreurs' => $erreursDe($c),
                        'succes' => $succesFlashe($c),
                        'modale_fermee' => $c->get('etatFormulaire') === null,
                    ];
                    break;

                case 'semer_session':
                    $u = $utilisateurs[$op['user']];
                    DB::table('sessions_caisse')->insert([
                        'id' => (string) Str::uuid(),
                        'point_vente' => $op['point_vente'],
                        'utilisateur_ouverture_id' => $u->id,
                        'date_ouverture' => now()->subMinutes((int) ($op['il_y_a_minutes'] ?? 30)),
                        'montant_fond' => $op['fond'],
                        'date_cloture' => ($op['ouverte'] ?? true) ? null : now(),
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'semer_vente':
                    $session = SessionCaisse::query()
                        ->where('point_vente', $op['point_session'])
                        ->whereNull('date_cloture')
                        ->latest('date_ouverture')
                        ->firstOrFail();
                    $serie++;
                    DB::table('ventes')->insert([
                        'id' => (string) Str::uuid(),
                        'numero' => 'V-2031-' . str_pad((string) $serie, 5, '0', STR_PAD_LEFT),
                        'session_id' => $session->id,
                        'point_vente' => 'Bar',
                        'montant_total' => $op['montant'],
                        'mode_paiement' => $op['mode'],
                        'encaisse' => $op['mode'] !== 'note_chambre',
                        'statut' => $op['statut'],
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                    $resultats[] = ['ok' => true];
                    break;

                case 'session_pour_encaissement':
                    // La requete EXACTE de `EncaissementFactureService::encaisser`
                    // (l.97-100) : la session ouverte la plus recente, TOUS
                    // points de vente confondus. Recopiee (le service exige
                    // une facture figee) — la source est citee ici, pas
                    // reinventee.
                    $session = SessionCaisse::query()
                        ->whereNull('date_cloture')
                        ->orderByDesc('date_ouverture')
                        ->first();
                    $resultats[] = ['point_vente' => $session?->point_vente];
                    break;

                case 'indicateur':
                    // Le VRAI `IndicateurCaisse` de la barre superieure.
                    $resultats[] = ['indicateur' => IndicateurCaisse::pour($utilisateurs[$op['user']])];
                    break;

                case 'tresorerie_caisse':
                    // Le VRAI KPI : fonds des sessions ouvertes + paiements.
                    $resultats[] = ['tresorerie' => $app->make(TableauDeBordService::class)
                        ->tresorerieCaisse(Periode::mois())];
                    break;

                case 'etat':
                    $lignes = [];
                    foreach (SessionCaisse::query()->orderBy('created_at')->orderBy('id')->get() as $s) {
                        $lignes[] = [
                            'point_vente' => $s->point_vente,
                            'ouvreur_est' => array_search($s->utilisateur_ouverture_id, array_map(
                                static fn (User $x): string => $x->id,
                                $utilisateurs,
                            ), true),
                            'montant_fond' => (string) $s->montant_fond,
                            'cloturee' => $s->date_cloture !== null,
                            'montant_theorique' => $s->montant_theorique === null ? null : (string) $s->montant_theorique,
                            'montant_constate' => $s->montant_constate === null ? null : (string) $s->montant_constate,
                        ];
                    }
                    $resultats[] = ['sessions' => $lignes];
                    break;

                case 'libelles':
                    $resultats[] = ['libelles' => [
                        'caisse_ouverte' => __('pos_pwa.comptant.caisse_ouverte', ['point' => ':point']),
                        'caisse_depuis' => __('pos_pwa.comptant.caisse_depuis', ['heure' => ':heure']),
                        'caisse_fond' => __('pos_pwa.comptant.caisse_fond', ['montant' => ':montant']),
                        'caisse_aucune' => __('pos_pwa.comptant.caisse_aucune'),
                        'caisse_aucune_aide' => __('pos_pwa.comptant.caisse_aucune_aide'),
                        'ouvrir_caisse' => __('pos_pwa.comptant.ouvrir_caisse'),
                        'cloturer_caisse' => __('pos_pwa.comptant.cloturer_caisse'),
                        'ouverture_titre' => __('pos_pwa.comptant.ouverture_titre', ['point' => ':point']),
                        'ouverture_fond' => __('pos_pwa.comptant.ouverture_fond'),
                        'cloture_titre' => __('pos_pwa.comptant.cloture_titre', ['point' => ':point']),
                        'cloture_constate' => __('pos_pwa.comptant.cloture_constate'),
                        'cloture_theorique' => __('pos_pwa.comptant.cloture_theorique'),
                        'cloture_recap_fond' => __('pos_pwa.comptant.cloture_recap_fond'),
                        'cloture_recap_especes' => __('pos_pwa.comptant.cloture_recap_especes'),
                        'cloture_recap_theorique' => __('pos_pwa.comptant.cloture_recap_theorique'),
                        'cloture_recap_aide' => __('pos_pwa.comptant.cloture_recap_aide'),
                        'caisse_ouverte_message' => __('pos_pwa.comptant.caisse_ouverte_message', ['point' => ':point']),
                        'caisse_cloturee' => __('pos_pwa.comptant.caisse_cloturee', ['point' => ':point', 'ecart' => ':ecart']),
                        'caisse_cloturee_sans_ecart' => __('pos_pwa.comptant.caisse_cloturee_sans_ecart', ['point' => ':point']),
                        'refus_sans_caisse' => __('pos_pwa.comptant.refus_sans_caisse'),
                        'refus_caisse_deja_ouverte' => __('pos_pwa.comptant.refus_caisse_deja_ouverte'),
                        'encaisser_sans_caisse' => __('pos_pwa.comptant.encaisser_sans_caisse'),
                        'annuler' => __('pwa.modale.annuler'),
                        'point_caisse' => PosComptant::POINT_CAISSE,
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
