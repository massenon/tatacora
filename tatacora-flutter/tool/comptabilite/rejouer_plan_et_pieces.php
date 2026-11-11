<?php

declare(strict_types=1);

/*
| Pousse les COMPTES du plan et les PIECES SAISIES A LA MAIN du poste (file
| d'envoi) au VRAI moteur de synchronisation du serveur (28/10/2026, D246 rouvert
| par le PO) : chaque operation ecrite par `MoteurComptable.creerCompte` et
| `MoteurComptable.saisirPiece` est traitee par `SynchronisationService::traiterLot`
| — idempotence, RBAC par operation (M10), `GestionnairePlanComptable`,
| `GestionnairePiecesSaisie`, puis `PlanComptableService` et `PasserEcritureService`.
| Le serveur REJOUE ses regles et passe SA piece : ce qu'il a ecrit se lit.
|
| La base N'EST PAS un double : `tatacora_test`, ou la base d'essai nommee par
| TATACORA_BASE_ESSAI (un nom `tatacora_<x>_test`), semee par les VRAIS seeders ;
| tout est ANNULE a la fin (rollback). MySQL injoignable : il echoue.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15", "poste_id": "poste-essai", "role": "comptable",
|     "operations": [ { "uuid_operation", "table", "type", "entite_id",
|                       "payload": {...}, "horodatage_client" }, ... ],
|     "redescente": true | false }
| Sortie (stdout, JSON) :
|   { "enveloppe": [...], "resultats": [...], "comptes": [ {id, numero, libelle, classe, nature} ],
|     "lignes": [ {journal, numero_piece, date, compte, centre, debit, credit, statut, origine} ],
|     "sources": [ {id, journal, statut, numero_piece, nombre_lignes} ],
|     "descente": [ elements `ecritures_comptables` tels que le poste les recoit ] }
|
| Usage : php tool/comptabilite/rejouer_plan_et_pieces.php < lot.json
*/

$baseAutorisee = (static function (): string {
    $voulue = getenv('TATACORA_BASE_ESSAI');

    return is_string($voulue) && preg_match('/^tatacora_[a-z0-9_]*test$/', $voulue) === 1
        ? $voulue
        : 'tatacora_test';
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

putenv('DB_DATABASE=' . $baseAutorisee);
$_ENV['DB_DATABASE'] = $baseAutorisee;
$_SERVER['DB_DATABASE'] = $baseAutorisee;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\EcritureComptable;
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

if ($base !== $baseAutorisee) {
    fwrite(STDERR, "Refus : la base active est « {$base} », pas « {$baseAutorisee} ».\n");
    exit(1);
}

Carbon::setTestNow($lot['aujourdhui'] . ' 10:00:00');

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();
    (new ComptabiliteReferentielSeeder())->run();

    $utilisateur = User::create([
        'login' => 'sync.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', (string) ($lot['role'] ?? 'administrateur'))->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    Auth::login($utilisateur);

    $erreurs = [];
    $resultats = [];

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
            ->traiterLot((string) $lot['poste_id'], $morceau, (string) $utilisateur->id);
        $resultats = [...$resultats, ...$traite['resultats']];
    }

    $descente = [];

    if (($lot['redescente'] ?? false) === true) {
        Illuminate\Support\Facades\Cache::flush();
        $app->make(Illuminate\Contracts\Console\Kernel::class);
        $service = $app->make(App\Shared\Sync\Services\CatalogueDescendantService::class);
        Carbon::setTestNow(Carbon::now()->addSeconds(App\Shared\Sync\Services\CatalogueDescendantService::HORIZON_SECONDES + 1));
        $curseur = null;
        do {
            $page = $service->page($utilisateur, (string) $lot['poste_id'] . '-autre', $curseur, 500);
            foreach ($page['elements'] as $element) {
                if ($element['table'] === 'ecritures_comptables' || $element['table'] === 'plan_comptable') {
                    $descente[] = $element;
                }
            }
            $curseur = $page['curseur'];
        } while (! $page['complet']);
    }

    echo json_encode([
        'enveloppe' => $erreurs,
        'resultats' => $resultats,
        'comptes' => CompteComptable::query()->orderBy('numero_compte')->get()
            ->map(static fn (CompteComptable $c): array => [
                'id' => (string) $c->id,
                'numero' => $c->numero_compte,
                'libelle' => $c->libelle,
                'classe' => $c->classe,
                'nature' => $c->nature,
            ])->all(),
        'lignes' => EcritureComptable::query()->with(['journal', 'compte', 'centre'])->orderBy('created_at')->orderBy('id')->get()
            ->map(static fn (EcritureComptable $l): array => [
                'journal' => $l->journal->code,
                'numero_piece' => $l->numero_piece,
                'date' => $l->date_ecriture->format('Y-m-d'),
                'compte' => $l->compte->numero_compte,
                'centre' => $l->centre->libelle,
                'debit' => (string) $l->debit,
                'credit' => (string) $l->credit,
                'statut' => $l->statut,
                'origine' => $l->piece_origine_id,
            ])->all(),
        'sources' => DB::table('pieces_saisie')->orderBy('created_at')->get()
            ->map(static fn (object $p): array => [
                'id' => (string) $p->id,
                'journal' => $p->journal,
                'statut' => $p->statut,
                'numero_piece' => $p->numero_piece,
                'nombre_lignes' => (int) $p->nombre_lignes,
            ])->all(),
        'descente' => $descente,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}
