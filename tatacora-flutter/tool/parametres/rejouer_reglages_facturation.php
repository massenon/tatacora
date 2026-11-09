<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI moteur de synchronisation du serveur, ce qu'un POSTE peut écrire des
| réglages de la facturation normalisée, de la forme juridique et des documents commerciaux
| (09/11/2026, décision du PO : « le poste fait ce que le web fait »). Le serveur est l'ancrage
| des règles et des PHRASES que le poste réplique (`EnregistrerParametres`) : jamais des textes
| recopiés. Le test `reglages_facturation_contre_serveur_test.dart` compare cas par cas.
|
| Entrée (stdin, JSON) :
|   { "cas": [ { "nom": "...", "auteur": "admin|comptable", "prealable": {cle: valeur},
|                "valeurs": {cle: valeur|null}, "affectation": false } ] }
|   `admin` : rôle administrateur. `comptable` : rôle PARAM=C SANS être administrateur.
|   `prealable` : valeurs posées en base avant l'opération. `affectation` : une affectation du
|   résultat ACTIVE est passée (services réels) avant l'opération.
| Sortie (stdout, JSON) :
|   { "resultats": { nom: { "statut", "motif", "code_motif", "stockees": {cle: valeur|null} } },
|     "cles_administrateur": [...], "phrases": {...}, "libelles_mode": {...} }
|
| La base N'EST PAS un double : le script travaille sur `tatacora_test` (il REFUSE toute autre base,
| sauf une base d'essai PRIVÉE `tatacora_<nom>_test` donnée par `TATACORA_BASE_ESSAI`), et ANNULE
| chaque cas (rollback).
| Usage : php tool/parametres/rejouer_reglages_facturation.php < scenario.json
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

if (! is_array($scenario) || ! isset($scenario['cas'])) {
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

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\AffectationResultatService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Models\User;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use App\Shared\Sync\Gestionnaires\GestionnaireParametres;
use App\Shared\Sync\Services\SynchronisationService;
use Database\Seeders\ComptabiliteReferentielSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow('2026-11-09 10:00:00');

$resultats = [];
DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    $role = app(RolePermissionService::class)->creerRole('comptable_essai', null);
    app(RolePermissionService::class)->definirNiveau($role, 'PARAM', 'C');

    $creer = static fn (string $libelleRole): User => User::create([
        'login' => 'regl.' . Str::random(8),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', $libelleRole)->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    $comptes = ['admin' => $creer('administrateur'), 'comptable' => $creer('comptable_essai')];
    $service = $app->make(SynchronisationService::class);

    foreach ($scenario['cas'] as $cas) {
        DB::beginTransaction();

        try {
            foreach (($cas['prealable'] ?? []) as $cle => $valeur) {
                ParametreSysteme::create(['cle' => $cle, 'valeur' => (string) $valeur]);
            }

            if (($cas['affectation'] ?? false) === true) {
                (new ComptabiliteReferentielSeeder())->run();
                $passeur = $creer('comptable');
                Auth::login($passeur);
                $centre = static fn (string $l): string => (string) CentreCout::query()->where('libelle', $l)->value('id');
                $passer = app(PasserEcritureService::class);
                $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-10', 'libelle' => 'Ventes bar', 'lignes' => [
                    ['compte' => '5711', 'debit' => '100000.00'],
                    ['compte' => '7011', 'credit' => '100000.00', 'centre_id' => $centre('Bar')],
                ]]);
                $passer->passerEtValider(['journal' => 'CAI', 'date' => '2026-03-11', 'libelle' => 'Achats', 'lignes' => [
                    ['compte' => '6011', 'debit' => '30000.00', 'centre_id' => $centre('Restaurant')],
                    ['compte' => '5711', 'credit' => '30000.00'],
                ]]);
                $exercice = ExerciceComptable::query()->where('annee', 2026)->firstOrFail();
                $cloture = app(ClotureExerciceService::class);
                $cloture->demarrer($exercice, $passeur);
                $cloture->cloturer($exercice->refresh(), $passeur);
                app(AffectationResultatService::class)->affecter($exercice->refresh(), [
                    'reserve_legale' => '0', 'autres_reserves' => '0', 'dividendes' => '0',
                    'report_a_nouveau' => '0', 'imputation_report_crediteur' => '0', 'compte_exploitant' => '70000',
                ], '2027-04-30', $passeur);
            }

            $auteur = $comptes[$cas['auteur']];
            Auth::login($auteur);
            $lot = [[
                'uuid_operation' => (string) Str::uuid(), 'table' => 'parametres_systeme', 'type' => 'creation',
                'entite_id' => (string) Str::uuid(), 'payload' => ['valeurs' => $cas['valeurs']],
                'horodatage_client' => '2026-11-09T10:00:00+00:00',
            ]];
            $r = $service->traiterLot('poste-essai', $lot, (string) $auteur->id)['resultats'][0];

            $resultats[$cas['nom']] = [
                'statut' => $r['statut'],
                'motif' => $r['motif'] ?? null,
                'code_motif' => $r['code_motif'] ?? null,
                'stockees' => array_combine(
                    array_keys($cas['valeurs']),
                    array_map(static fn (string $cle): ?string => ParametreSysteme::where('cle', $cle)->value('valeur'), array_keys($cas['valeurs'])),
                ),
            ];
        } finally {
            Auth::logout();
            DB::rollBack();
        }
    }

    $langue = static fn (string $cle, array $args = []): string => (string) __('parametres.' . $cle, $args);
    $sortie = [
        'resultats' => $resultats,
        'cles_administrateur' => GestionnaireParametres::CLES_ADMINISTRATEUR,
        'libelles_mode' => array_combine(
            array_map(static fn (ModeFacturation $m): string => $m->value, ModeFacturation::cases()),
            array_map(static fn (ModeFacturation $m): string => $m->libelle(), ModeFacturation::cases()),
        ),
        'phrases' => [
            'mecef_reserve' => $langue('mecef_reserve_administrateur'),
            'forme_reservee' => $langue('forme_juridique_reservee_administrateur'),
            'forme_affectation_active' => $langue('forme_juridique_affectation_active'),
            'forme_inconnue' => $langue('forme_juridique_inconnue', ['valeur' => 'VALEUR', 'admises' => 'ADMISES']),
            'manque_ifu' => $langue('mecef_manque_ifu'),
            'manque_operateur' => $langue('mecef_manque_operateur'),
            'manque_jeton' => $langue('mecef_manque_jeton'),
            'mode_refuse' => $langue('mecef_mode_refuse', ['mode' => 'MODE', 'manques' => 'MANQUES']),
        ],
    ];
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
