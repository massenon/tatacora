<?php

declare(strict_types=1);

/*
| Pousse la FILE D'ENVOI du poste au VRAI moteur de synchronisation du serveur
| (lot F1, 15/10/2026) : chaque operation enfilee par un ecrivain du poste est
| traitee par `SynchronisationService::traiterLot` — idempotence, RBAC par
| operation, gestionnaire de la table, regles et phrases de l'API, service de
| domaine, pieces comptables produites par le serveur. C'est l'ancrage
| EXTERIEUR des documents du poste (piege 12) : un payload qui ne respecte pas
| le contrat rend `rejete` avec le motif du serveur, jamais un vert de
| complaisance.
|
| L'enveloppe du lot est d'abord validee par les regles de `SynchroniserRequest`
| (uuid_operation, entite_id, type, horodatage_client), les memes que la route
| `/api/v1/sync`.
|
| La base N'EST PAS un double. Le script travaille sur `tatacora_test` (il
| REFUSE toute autre base), seme les roles et le referentiel comptable par les
| VRAIS seeders, pose la tolerance de reception, ferme les caisses restees
| ouvertes, puis ANNULE tout (rollback) : la base n'est pas modifiee. MySQL
| injoignable : il echoue.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2026-10-12",
|     "poste_id": "poste-essai",
|     "operations": [ { "uuid_operation", "table", "type", "entite_id",
|                       "payload": {...}, "horodatage_client" }, ... ] }
| Sortie (stdout, JSON) :
|   { "enveloppe": { "<champ>": ["<phrase>"] } | [],
|     "resultats": [ ... le resultat du serveur, operation par operation ... ] }
|
| Usage : php tool/sync/valider_charge.php < lot.json
*/

const BASE_AUTORISEE = 'tatacora_test';

// Une base d'ESSAI privee (`TATACORA_BASE_ESSAI=tatacora_<nom>_test`) peut
// remplacer `tatacora_test` quand plusieurs essais tournent en meme temps : la
// base partagee est alors migree sous les pieds de l'un ou de l'autre. Le nom
// doit finir par `test` — la base de developpement reste refusee.
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

$lot = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($lot) || ! isset($lot['operations'], $lot['aujourdhui'], $lot['poste_id'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

// La base est choisie AVANT l'amorcage : le fichier `.env` ne l'emporte pas sur
// une variable deja posee.
putenv('DB_DATABASE=' . $baseEssai);
$_ENV['DB_DATABASE'] = $baseEssai;
$_SERVER['DB_DATABASE'] = $baseEssai;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Caisse\Models\SessionCaisse;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Http\Requests\SynchroniserRequest;
use App\Shared\Sync\Services\SynchronisationService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow($lot['aujourdhui'] . ' 10:00:00');

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    (new ComptabiliteReferentielSeeder())->run();

    // La tolerance de reception (RG-10) : sans elle, le serveur refuse toute
    // reception. Le poste d'essai porte la meme valeur.
    DB::table('parametres_systeme')->updateOrInsert(
        ['cle' => 'tolerance_reception_pct'],
        ['id' => (string) Str::uuid(), 'valeur' => '5', 'created_at' => now(), 'updated_at' => now()],
    );

    // Une caisse laissee ouverte par un autre essai ferait refuser l'ouverture
    // du poste — ce n'est pas le contrat qu'on mesure ici.
    SessionCaisse::query()->whereNull('date_cloture')->update(['date_cloture' => now()]);

    // L'administrateur : C sur tous les modules, et le droit d'archiver.
    $admin = User::create([
        'login' => 'sync.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    Auth::login($admin);

    // La file est poussée par lots de 50 au plus, dans l'ordre, comme le
    // moteur d'envoi du poste (`SyncManager.tailleLot`, plafond de
    // `SynchroniserRequest`) : chaque lot est validé puis traité.
    $erreurs = [];
    $sortie = ['resultats' => []];

    foreach (array_chunk($lot['operations'], 50) as $morceau) {
        $enveloppe = Validator::make(
            ['poste_id' => $lot['poste_id'], 'operations' => $morceau],
            (new SynchroniserRequest())->rules(),
        );

        if ($enveloppe->fails()) {
            $erreurs = $enveloppe->errors()->toArray();

            break;
        }

        $traite = $app->make(SynchronisationService::class)
            ->traiterLot((string) $lot['poste_id'], $morceau, (string) $admin->id);
        $sortie['resultats'] = [...$sortie['resultats'], ...$traite['resultats']];
    }

    if ($erreurs !== []) {
        echo json_encode(['enveloppe' => $erreurs, 'resultats' => []], JSON_UNESCAPED_UNICODE);
    } else {

        // Ce que le serveur a REELLEMENT ecrit, relu avant l'annulation : la
        // ligne de chaque element accepte (sous son identifiant serveur quand
        // il y a eu fusion), et les anomalies signalees par le lot. Un
        // document accepte mais mal converti (un seuil x100, un prix en
        // centimes) se lit ici, pas dans le statut.
        $etats = [];

        foreach ($sortie['resultats'] as $rang => $resultat) {
            $table = (string) $lot['operations'][$rang]['table'];
            $id = (string) ($resultat['fusionne_avec'] ?? $resultat['entite_id']);
            $ligne = DB::table($table)->where('id', $id)->first();

            if ($ligne !== null) {
                $etat = (array) $ligne;

                // Un inventaire se lit AVEC ses lignes comptees (21/10/2026) :
                // le document est atomique, et ses valeurs doivent se verifier.
                if ($table === 'inventaires') {
                    $etat['lignes'] = DB::table('lignes_inventaire')
                        ->where('inventaire_id', $id)
                        ->orderBy('article_id')
                        ->get(['article_id', 'quantite_theorique', 'quantite_constatee', 'ecart'])
                        ->map(static fn (object $l): array => (array) $l)
                        ->all();
                }

                $etats[$table . ':' . (string) $lot['operations'][$rang]['entite_id']] = $etat;
            }
        }

        $anomalies = DB::table('anomalies_synchronisation')
            ->where('poste_id', (string) $lot['poste_id'])
            ->orderBy('created_at')
            ->get(['table_concernee', 'entite_id', 'type', 'valeur_poste', 'valeur_serveur', 'details'])
            ->map(static fn (object $a): array => [...(array) $a, 'details' => json_decode((string) $a->details, true)])
            ->all();

        echo json_encode([
            'enveloppe' => [],
            'resultats' => $sortie['resultats'],
            'etats' => $etats,
            'anomalies' => $anomalies,
        ], JSON_UNESCAPED_UNICODE);
    }
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}
