<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI serveur, ce que les DEUX modales d'ouverture de session
| calculent (27/10/2026, lot A2 du poste) : les trois collecteurs de
| `AlertesOuverture` (`stockCritiqueModale`, `departsAEcheance`,
| `creancesModale`) et les deux gestes du composant `AlertesOuvertureModales`
| (`effectuerCheckOutOuverture`, `tracerRelanceOuverture`). Le serveur est
| l'ancrage des règles que le poste réplique, jamais une liste recopiée.
|
| Entrée (stdin, JSON) : { "monde": {...}, "ops": [...] }
|   monde.articles   [{ref, libelle, unite, seuil}]        monde.points [ref]
|   monde.mouvements [{article, point, type, quantite}]
|   monde.clients    [{ref, nom, prenom|null}]             monde.unites [ref]
|   monde.sejours    [{ref, client, unite, depart: <jours par rapport à aujourd'hui>,
|                       etat: "ouvert"|"clos"|"non_arrive"}]
|   monde.factures   [{ref, client, emission: <jours AVANT aujourd'hui>, ttc, paye}]
|   monde.relances   [{client, il_y_a: <jours>}]
|   ops: {"op":"lignes"}                              (les trois collecteurs)
|        {"op":"checkout","sejour":"ref"}              (le VRAI composant)
|        {"op":"relancer","client":"ref","canal":"…"}  (le VRAI composant)
|        {"op":"libelles"}                             (constantes et mots)
| Sortie (stdout, JSON) : { "resultats": [ ... un par opération ... ] }
|
| Le script travaille sur `tatacora_test` (il REFUSE toute autre base, sauf une
| base d'essai PRIVÉE `tatacora_<nom>_test` donnée par `TATACORA_BASE_ESSAI`),
| puis ANNULE tout (rollback).
| Usage : php tool/alertes/rejouer_modales_ouverture.php < scenario.json
*/

const BASE_AUTORISEE = 'tatacora_test';

$baseEssai = (static function (): string {
    $voulue = getenv('TATACORA_BASE_ESSAI');

    return is_string($voulue) && preg_match('/^tatacora_[a-z0-9_]*test$/', $voulue) === 1
        ? $voulue
        : BASE_AUTORISEE;
})();

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['ops'], $scenario['monde'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

putenv('DB_DATABASE=' . $baseEssai);
$_ENV['DB_DATABASE'] = $baseEssai;
$_SERVER['DB_DATABASE'] = $baseEssai;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Crm\Models\RelanceClient;
use App\Models\User;
use App\Pwa\Livewire\Transverse\AlertesOuvertureModales;
use App\Pwa\Support\AlertesOuverture;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

$monde = $scenario['monde'];
$resultats = [];

/** @var array<string, string> refs -> uuid */
$ids = ['article' => [], 'point' => [], 'client' => [], 'unite' => [], 'sejour' => [], 'reservation' => []];

$aujourdhui = Carbon::today();

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    $gerant = User::create([
        'login' => 'gerant.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'gerant')->firstOrFail()->id,
        'statut' => 'actif',
    ]);

    $categorie = (string) Str::uuid();
    DB::table('categories_hebergement')->insert([
        'id' => $categorie, 'libelle' => 'Standard', 'capacite_max' => 2, 'tarif_base' => '10000.00',
        'created_at' => now(), 'updated_at' => now(),
    ]);

    foreach ($monde['points'] ?? [] as $ref) {
        $ids['point'][$ref] = (string) Str::uuid();
        DB::table('points_stockage')->insert([
            'id' => $ids['point'][$ref], 'libelle' => 'Point ' . $ref,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    foreach ($monde['articles'] ?? [] as $a) {
        $ids['article'][$a['ref']] = (string) Str::uuid();
        DB::table('articles')->insert([
            'id' => $ids['article'][$a['ref']], 'libelle' => $a['libelle'], 'categorie' => 'Divers',
            'unite_mesure' => $a['unite'], 'seuil_alerte' => $a['seuil'],
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    foreach ($monde['mouvements'] ?? [] as $m) {
        DB::table('mouvements_stock')->insert([
            'id' => (string) Str::uuid(),
            'article_id' => $ids['article'][$m['article']], 'point_id' => $ids['point'][$m['point']],
            'type_mouvement' => $m['type'], 'quantite' => $m['quantite'], 'motif' => 'essai',
            'utilisateur_id' => $gerant->id, 'date_mouvement' => now(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    foreach ($monde['clients'] ?? [] as $c) {
        $ids['client'][$c['ref']] = (string) Str::uuid();
        DB::table('clients')->insert([
            'id' => $ids['client'][$c['ref']], 'nom' => $c['nom'], 'prenom' => $c['prenom'],
            'telephone' => '0100000000', 'type_client' => 'particulier',
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    foreach ($monde['unites'] ?? [] as $ref) {
        $ids['unite'][$ref] = (string) Str::uuid();
        DB::table('unites_hebergement')->insert([
            'id' => $ids['unite'][$ref], 'categorie_id' => $categorie, 'numero' => $ref,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    foreach ($monde['sejours'] ?? [] as $s) {
        $reservation = (string) Str::uuid();
        $ids['reservation'][$s['ref']] = $reservation;
        DB::table('reservations')->insert([
            'id' => $reservation, 'client_id' => $ids['client'][$s['client']], 'unite_id' => $ids['unite'][$s['unite']],
            'date_arrivee' => $aujourdhui->copy()->subDays(3)->toDateString(),
            'date_depart' => $aujourdhui->copy()->addDays((int) $s['depart'])->toDateString(),
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $ids['sejour'][$s['ref']] = (string) Str::uuid();
        if ($s['etat'] !== 'non_arrive') {
            DB::table('sejours')->insert([
                'id' => $ids['sejour'][$s['ref']], 'reservation_id' => $reservation,
                'date_checkin_reel' => now()->subDays(3),
                'date_checkout_reel' => $s['etat'] === 'clos' ? now()->subDay() : null,
                'created_at' => now(), 'updated_at' => now(),
            ]);
        }
    }

    foreach ($monde['factures'] ?? [] as $f) {
        DB::table('factures')->insert([
            'id' => (string) Str::uuid(), 'client_id' => $ids['client'][$f['client']],
            'date_emission' => $aujourdhui->copy()->subDays((int) $f['emission'])->toDateString(),
            'montant_ht' => $f['ttc'], 'montant_tva' => '0.00', 'montant_ttc' => $f['ttc'],
            'statut' => 'certifiee',
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    foreach ($monde['relances'] ?? [] as $r) {
        DB::table('relances_clients')->insert([
            'id' => (string) Str::uuid(), 'client_id' => $ids['client'][$r['client']],
            'date_relance' => $aujourdhui->copy()->subDays((int) $r['il_y_a'])->toDateString(),
            'canal' => 'telephone', 'montant_reclame' => '1.00',
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    $nomDe = static fn (string $uuid, string $type): ?string => array_search($uuid, $ids[$type], true) ?: null;

    foreach ($scenario['ops'] as $op) {
        try {
            switch ($op['op']) {
                case 'lignes':
                    $stock = AlertesOuverture::stockCritiqueModale();
                    $departs = AlertesOuverture::departsAEcheance();
                    $creances = AlertesOuverture::creancesModale();
                    $resultats[] = [
                        'stock' => array_map(static fn (array $l): array => [
                            'article' => $nomDe($l['article_id'], 'article'), 'libelle' => $l['libelle'],
                            'detail' => $l['detail'], 'critique' => $l['critique'],
                        ], $stock),
                        'departs' => array_map(static fn (array $l): array => [
                            'sejour' => $nomDe($l['sejour_id'], 'sejour'), 'libelle' => $l['libelle'],
                            'detail' => $l['detail'], 'critique' => $l['critique'],
                        ], $departs),
                        'creances' => array_map(static fn (array $l): array => [
                            'client' => $nomDe($l['client_id'], 'client'), 'libelle' => $l['libelle'],
                            'detail' => $l['detail'], 'critique' => $l['critique'],
                            'relance_requise' => $l['relance_requise'], 'reste' => $l['reste'],
                        ], $creances),
                    ];
                    break;

                case 'checkout':
                    $c = Livewire::actingAs($gerant)->test(AlertesOuvertureModales::class)
                        ->call('effectuerCheckOutOuverture', $ids['sejour'][$op['sejour']] ?? (string) Str::uuid());
                    $resultats[] = [
                        'erreur' => $c->errors()->get('alerte_ouverture')[0] ?? null,
                        'traites' => $c->get('traites'),
                        'statut_unite' => DB::table('unites_hebergement')
                            ->where('id', DB::table('reservations')->where('id', $ids['reservation'][$op['sejour']] ?? '')->value('unite_id') ?? '')
                            ->value('statut'),
                        'sejour_clos' => isset($ids['sejour'][$op['sejour']])
                            ? DB::table('sejours')->where('id', $ids['sejour'][$op['sejour']])->whereNotNull('date_checkout_reel')->exists()
                            : null,
                    ];
                    break;

                case 'relancer':
                    $c = Livewire::actingAs($gerant)->test(AlertesOuvertureModales::class)
                        ->set('canalRelance', $op['canal'])
                        ->call('tracerRelanceOuverture', $ids['client'][$op['client']] ?? (string) Str::uuid());
                    $derniere = RelanceClient::query()
                        ->where('client_id', $ids['client'][$op['client']] ?? '')
                        ->where('commentaire', __('pwa.alertes_ouverture.relance_commentaire'))
                        ->latest('created_at')->first();
                    $resultats[] = [
                        'erreur' => $c->errors()->get('alerte_ouverture')[0] ?? null,
                        'traites' => $c->get('traites'),
                        'relance' => $derniere === null ? null : [
                            'canal' => $derniere->canal,
                            'montant' => (string) $derniere->montant_reclame,
                            'commentaire' => $derniere->commentaire,
                        ],
                    ];
                    break;

                case 'libelles':
                    $mots = [];
                    foreach (['titre_stock', 'sous_titre_stock', 'titre_operations', 'sous_titre_operations',
                        'bloc_stock_titre', 'bloc_stock_sous_titre', 'lien_stocks', 'bloc_departs_titre',
                        'bloc_departs_sous_titre', 'depart_aujourdhui', 'lien_reservations', 'checkout', 'fait',
                        'sejour_introuvable', 'bloc_creances_titre', 'bloc_creances_sous_titre', 'jamais_relance',
                        'lien_creances', 'relancer', 'tracee', 'relance_recente', 'relance_indisponible',
                        'relance_commentaire', 'canal_telephone', 'canal_whatsapp', 'canal_email', 'canal_courrier',
                        'canal_visite', 'suivant', 'pris_connaissance', 'droit_manquant'] as $cle) {
                        $mots[$cle] = __('pwa.alertes_ouverture.' . $cle);
                    }
                    $mots['stock_detail'] = __('pwa.alertes_ouverture.stock_detail', ['stock' => ':stock', 'unite' => ':unite', 'seuil' => ':seuil']);
                    $mots['depart_depasse'] = __('pwa.alertes_ouverture.depart_depasse', ['date' => ':date']);
                    $mots['creance_detail'] = __('pwa.alertes_ouverture.creance_detail', ['montant' => ':montant', 'jours' => ':jours']);
                    $mots['relance_le'] = __('pwa.alertes_ouverture.relance_le', ['date' => ':date']);
                    $mots['et_autres'] = __('pwa.alertes_ouverture.et_autres', ['nombre' => ':nombre']);
                    $resultats[] = [
                        'mots' => $mots,
                        'ligne_par_bloc' => AlertesOuverture::LIGNES_PAR_BLOC,
                        'relance_recente_jours' => AlertesOuverture::JOURS_RELANCE_RECENTE,
                        'anciennete_jours' => AlertesOuverture::ANCIENNETE_CREANCE_JOURS,
                        'canaux' => RelanceClient::CANAUX,
                        'canal_defaut' => (new AlertesOuvertureModales())->canalRelance,
                    ];
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
