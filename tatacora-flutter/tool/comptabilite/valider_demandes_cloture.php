<?php

declare(strict_types=1);

/*
| Pousse les DEMANDES de cloture d'exercice du poste (file d'envoi) au VRAI
| moteur de synchronisation du serveur (26/10/2026) : chaque demande ecrite par
| `ClotureExerciceLocale` est traitee par `SynchronisationService::traiterLot` —
| idempotence, RBAC par operation (M10), `GestionnaireDemandesCloture`, puis
| `ClotureExerciceService` — et le serveur REJOUE ses regles. C'est l'ancrage
| EXTERIEUR du contrat de synchronisation d'exercice (piege 12) : le poste
| n'envoie aucune piece, le serveur passe les siennes, et ce qu'il a ecrit se lit.
|
| La base N'EST PAS un double. Le script travaille sur `tatacora_test` — ou sur
| la base d'essai nommee par TATACORA_BASE_ESSAI (un nom `tatacora_<x>_test`) —,
| seme roles et referentiel par les VRAIS seeders, pose en option les pieces que
| les AUTRES postes ont envoyees au serveur (`pieces_serveur`), puis ANNULE tout
| (rollback). L'archive est ecrite sur un disque FACTICE. MySQL injoignable : il
| echoue.
|
| Entree (stdin, JSON) :
|   { "aujourdhui": "2031-06-15", "poste_id": "poste-essai",
|     "role": "comptable" | "administrateur",
|     "exercices": [ {"annee": 2030, "statut": "ouvert"} ],
|     "pieces_serveur": [ {"journal": "CAI", "date": "2031-03-10", "libelle": "...", "valide": true,
|                          "lignes": [ {"compte": "5711", "debit": "1.00", "centre": "Bar"} ]} ],
|     "operations": [ { "uuid_operation", "table", "type", "entite_id",
|                       "payload": {...}, "horodatage_client" }, ... ] }
| Sortie (stdout, JSON) :
|   { "enveloppe": {...} | [], "resultats": [ ... ],
|     "statuts": { "2031": "cloture" },
|     "clotures": [ {annee, piece_cloture, piece_a_nouveaux, resultat, active, archive} ],
|     "lignes": { "2031": [ {journal, numero_piece, date, compte, centre, debit, credit, contrepasse} ] },
|     "demandes": [ {id, annee, action, issue, statut_exercice} ] }
|
| Usage : php tool/comptabilite/valider_demandes_cloture.php < lot.json
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

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\DemandeClotureExercice;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\PasserEcritureService;
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
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseAutorisee) {
    fwrite(STDERR, "Refus : la base active est « {$base} », pas « {$baseAutorisee} ».\n");
    exit(1);
}

Carbon::setTestNow($lot['aujourdhui'] . ' 10:00:00');
Storage::fake('local');

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

    foreach ($lot['exercices'] ?? [] as $e) {
        $annee = (int) $e['annee'];
        ExerciceComptable::firstOrCreate(
            ['annee' => $annee],
            ['date_debut' => "{$annee}-01-01", 'date_fin' => "{$annee}-12-31", 'statut' => (string) $e['statut']],
        )->forceFill(['statut' => (string) $e['statut']])->save();
    }

    // Les pieces que les AUTRES postes ont envoyees au serveur : les siennes.
    $passer = $app->make(PasserEcritureService::class);
    foreach ($lot['pieces_serveur'] ?? [] as $p) {
        $lignes = [];
        foreach ($p['lignes'] as $l) {
            $ligne = ['compte' => $l['compte']];
            foreach (['debit', 'credit', 'libelle'] as $cle) {
                if (array_key_exists($cle, $l)) {
                    $ligne[$cle] = $l[$cle];
                }
            }
            if (($l['centre'] ?? null) !== null) {
                $ligne['centre_id'] = (string) CentreCout::where('libelle', $l['centre'])->firstOrFail()->id;
            }
            $lignes[] = $ligne;
        }
        $donnees = [
            'journal' => $p['journal'], 'date' => $p['date'], 'libelle' => $p['libelle'], 'lignes' => $lignes,
            'statuts_exercice_admis' => $p['statuts_admis'] ?? ['ouvert'],
        ];
        ($p['valide'] ?? true) ? $passer->passerEtValider($donnees) : $passer->passer($donnees);
    }

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

    $exercices = ExerciceComptable::query()->orderBy('annee')->get();

    echo json_encode([
        'enveloppe' => $erreurs,
        'resultats' => $resultats,
        'statuts' => $exercices->mapWithKeys(static fn (ExerciceComptable $e): array => [(string) $e->annee => $e->statut])->all(),
        'clotures' => ClotureExercice::query()->with('exercice')->orderBy('created_at')->get()
            ->map(static fn (ClotureExercice $c): array => [
                'annee' => (int) $c->exercice->annee,
                'piece_cloture' => $c->piece_cloture,
                'piece_a_nouveaux' => $c->piece_a_nouveaux,
                'resultat' => (string) $c->resultat,
                'active' => $c->estActive(),
                'archive' => $c->archive_empreinte !== null,
            ])->all(),
        'lignes' => $exercices->mapWithKeys(static fn (ExerciceComptable $e): array => [
            (string) $e->annee => EcritureComptable::query()->where('exercice_id', $e->id)
                ->with(['journal', 'compte', 'centre'])->get()
                ->map(static fn (EcritureComptable $l): array => [
                    'journal' => $l->journal->code,
                    'numero_piece' => $l->numero_piece,
                    'date' => $l->date_ecriture->format('Y-m-d'),
                    'compte' => $l->compte->numero_compte,
                    'centre' => $l->centre->libelle,
                    'debit' => (string) $l->debit,
                    'credit' => (string) $l->credit,
                    'contrepasse' => $l->ecriture_contrepassee_id !== null,
                ])->all(),
        ])->all(),
        'demandes' => DemandeClotureExercice::query()->orderBy('created_at')->get()
            ->map(static fn (DemandeClotureExercice $d): array => [
                'id' => (string) $d->id,
                'annee' => $d->annee,
                'action' => $d->action,
                'issue' => $d->issue,
                'statut_exercice' => $d->statut_exercice,
                'poste_id' => $d->poste_id,
            ])->all(),
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
    Storage::disk('local')->deleteDirectory('');
}
